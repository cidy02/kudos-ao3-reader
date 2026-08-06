# AO3 Networking Audit

**Audited tree:** worktree `tasklist-reports-impl-429b9e`, branch `claude/tasklist-reports-impl-429b9e`, HEAD `72267fea`.
**Date:** 2026-08-06.
**Method:** static reading of the full networking surface, plus live comparison against `archiveofourown.org` (search form DOM, option values, pagination markup, and four executed search queries), plus the official OTW Archive `WorkQuery` source.
**Scope note:** the task named branch `hig-review`; this worktree is the one the current session has been working in and is the tree actually audited. Findings should be re-checked if `hig-review` has diverged.

**No source code was modified. This report contains no patches.**

---

## Executive Summary

### Overall health

**Good, with a well-defined feature gap.** The core networking layer is unusually disciplined for an HTML-scraping client: a single actor owns pacing, retry, coalescing, and status→error mapping; politeness is real rather than aspirational; and the security posture around cookies is deliberate and documented. Every AO3 tag/rating/warning/category ID hardcoded in the filter model matches live AO3 exactly (verified today, see [Compatibility](#ao3-compatibility-analysis)). The exclusion strategy — folding what AO3's structured form cannot express into its Elasticsearch query syntax — is not a hack; it is verified working against the live site.

The weaknesses are concentrated in **search feature coverage** (7 of AO3's 22 work-search fields are unimplemented) and in **request lifecycle** (superseded requests are discarded but never cancelled). Neither is a correctness bug in what is implemented; both are gaps between the app and AO3's actual capability.

### Major strengths

1. **Centralized, testable politeness.** `AO3Client.pace()` claims slots synchronously so request *starts* are ≥0.6 s apart regardless of caller concurrency, and the arithmetic is extracted into a pure, unit-tested `paceStep`. The actor-reentrancy trap that would defeat a naive "one at a time" assumption is explicitly called out in the code and designed around.
2. **Correct, conservative retry policy.** Transient-only retry (5xx, 429 honouring `Retry-After`, a curated `URLError` set), exponential backoff, and `CancellationError` rethrown before the retry logic can swallow it. 403 is deliberately *not* retried.
3. **Deliberate cookie isolation.** An `.ephemeral` per-process jar keeps Cloudflare's `cf_clearance`/`__cf_bm` warm while the AO3 auth cookie is structurally purged after every anonymous fetch, with the invariant made unit-testable. The rationale (and the prior regression it fixes) is documented inline.
4. **Verified filter constants.** All 5 rating IDs, 6 warning IDs, and 6 category IDs match live AO3.
5. **Strong parser-level test coverage** with real HTML fixtures.

### Major weaknesses

1. **Seven AO3 search fields are not implemented** — `title`, `creators`, `hits`, `kudos_count`, `comments_count`, `bookmarks_count`, `sort_direction` (Finding 1, Finding 2).
2. **Search results can only ever be sorted descending**, and two of AO3's ten sort columns are unreachable (Finding 2).
3. **Superseded searches are not cancelled**, only ignored — so rapid paging queues real, paced network requests and delays the one the user actually wants (Finding 3).
4. **Zero test coverage of search URL construction** — the single highest-risk surface, and the one whose correctness this audit had to establish by hand (Finding 5).
5. **No response caching layer**; coalescing only helps genuinely concurrent callers (Finding 8).

### Highest-priority improvements

| # | Improvement | Finding | Effort |
|---|---|---|---|
| 1 | Add search-URL construction tests pinning every `work_search[...]` parameter | F5 | Small |
| 2 | Cancel superseded search tasks instead of only discarding results | F3 | Small |
| 3 | Add `sort_direction` + the two missing sort columns | F2 | Small |
| 4 | Add the four stat-range fields and `title`/`creators` | F1 | Medium |
| 5 | Escape user text interpolated into query syntax | F6 | Small |

---

## Architecture Overview

### Components

| Component | File | LOC | Role |
|---|---|---:|---|
| `AO3Client` (actor) | `Services/AO3Client.swift` | 1292 | Single owner of fetch, pace, retry, coalesce, status→error. Search + work/series/listing parsing. |
| `AO3Client+Authors` | `Services/AO3Client+Authors.swift` | 653 | Author/series parsing; also hosts the **shared** `paginationTotal` and `statInt` helpers. |
| `AO3Client+Comments` / `+Inbox` / `+Preferences` | — | 445 / 386 / 480 | Feature extensions; all route through `getHTML` rather than opening a second pipeline. |
| `AO3RequestCoordinator` (actor) | `Services/AO3RequestCoordinator.swift` | 90 | Fair FIFO concurrency gate (default 3), cancellation-aware. |
| `RequestCoalescer` (actor) | `Services/RequestCoalescer.swift` | 24 | De-duplicates concurrent identical in-flight requests. |
| `AO3AuthService` / `AO3SessionVault` | — | 988 / 365 | Per-account session, authenticated request construction. |
| `AO3RedirectCookieRelay` | — | 122 | Redirect-time cookie handling. |
| `AO3URLResolver` | — | 44 | Relative→absolute AO3 URL resolution. |
| `AO3SearchFilters` | `Models/AO3Models.swift` | 870 (file) | Filter model + query synthesis + `Codable` persistence for `SavedSearch`. |
| `SearchView` | `Features/Search/SearchView.swift` | 760 | UI state machine, paging, token-based staleness. |

### Request lifecycle (anonymous GET)

```
caller
  └─ AO3Client.getHTML(url)
       └─ fetchData(url)
            └─ RequestCoalescer.shared(url)          ← dedupe concurrent identical GETs
                 └─ performFetch(url)
                      └─ withRetry(maxRetries: 2)    ← transient-only, exponential backoff
                           ├─ pace()                 ← claim next ≥0.6s slot, then sleep
                           ├─ session.data(from:)
                           ├─ defer purgeSessionCookie(...)   ← runs even on non-2xx
                           └─ check(response)        ← HTTP status → typed AO3Error
       └─ String(decoding:as: UTF8.self)             ← lossy by design
```

Two independent throttles compose here, and the interaction is worth stating explicitly because it is easy to misread:

- `AO3RequestCoordinator` bounds **how many** operations run at once (3).
- `AO3Client.pace()` bounds **how often** a request may *start* (one per 0.6 s).

So the coordinator does permit three requests to be in flight simultaneously, but their *starts* are still serialized 0.6 s apart. Steady-state throughput is therefore ≈1.67 req/s no matter how the coordinator is tuned. This is not a defect — it is the politeness budget — but anyone tuning `limit` expecting a throughput change will be surprised. It should be documented at the coordinator.

### Error taxonomy

`AO3Error` (`Models/AO3Models.swift:628`): `rateLimited(retryAfter:)`, `notFound`, `forbidden`, `server(status:)`, `http(status:)`, `network(String)`, `parse`, `authenticationRequired`. This is a well-shaped taxonomy — it distinguishes retryable from terminal, and separates "AO3 bounced us to login" from generic 4xx, which the UI needs in order to prompt re-authentication rather than showing a dead end.

---

## Search Pipeline

```
SearchView.filters (AO3SearchFilters)
   │  runSearch() / loadPage(n)
   ▼
load(page:)  ── loadToken += 1 ──►  Task { … }        ← NOT cancelled (F3)
   ▼
AO3Client.search(filters:page:)                        ← AO3Client.swift:267
   │   builds URLComponents("<base>/works/search")
   │   add(...) skips nil/blank values
   ▼
getHTML(url)  → [lifecycle above]
   ▼
AO3Client.parseSearchPage(html, page:)                 ← AO3Client.swift:1141
   └─ parseWorksList(blurbSelector: "li.work.blurb")
        ├─ parseBlurb(el) per blurb, `try?` — a malformed blurb is skipped, not fatal
        └─ paginationTotal(in: doc, currentPage:)
   ▼
AO3SearchPage(works:currentPage:totalPages:)
   ▼
SearchView: guard token == loadToken  → results / phase
```

**Assessment.** The shape is right: pure URL construction, one network primitive, static parsing that is independently testable. `add()` correctly refuses to emit blank parameters, so an untouched filter contributes nothing to the URL — confirmed by the `defaultsDoNotAlterTheQuery` test.

Three observations:

- `parseBlurb` failures are swallowed per-blurb (`compactMap { try? ... }`). Correct for resilience, but it means a site-wide markup change degrades to *silently empty result pages* rather than a surfaced error. There is no floor check (e.g. "blurb elements existed but none parsed") that would distinguish "no results" from "parser broke". See Finding 9.
- `search()` does not send `view_adult=true`, while `worksPage(at:)` explicitly does (`AO3Client.swift:681`). See Finding 7.
- Staleness is handled by a monotonic token, not cancellation. See Finding 3.

---

## Filtering Pipeline

`AO3SearchFilters` splits its work across two channels, which is the central design decision of this subsystem:

**Channel A — AO3's structured form fields.** Emitted directly as `work_search[...]` query items.

**Channel B — AO3's Elasticsearch query syntax**, synthesized into `work_search[query]` for everything the structured form cannot express (`AO3Models.swift:238`):

```swift
clauses += excludedTags.map { "-\"\($0)\"" }
clauses += Warning.allCases.filter(excludedWarnings.contains)
              .map { "-archive_warning_ids:\($0.ao3ID)" }
clauses += Category.allCases.filter(excludedCategories.contains)
              .map { "-category_ids:\($0.ao3ID)" }
if let ratingSearchClause { clauses.append(ratingSearchClause) }
```

This exists because AO3's structured form has exactly one rating select and no exclusion inputs at all, while the app offers Include→Exclude→Clear cycling and Rating+/Rating− semantics.

**I verified Channel B against live AO3 rather than assuming it:**

| Synthesized clause | Live test | Result |
|---|---|---|
| `rating_ids:13` | `?work_search[query]=rating_ids:13&…fandom_names=Naruto` | 20/20 results Explicit ✅ |
| `-archive_warning_ids:14` | `?work_search[query]=-archive_warning_ids:14&…fandom_names=Naruto` | 0/20 results carried "Creator Chose Not To Use" ✅ |

So the approach is sound and the field names are right. The rating fallback is also internally consistent: `structuredRatingID` returns a value only when exactly one rating is selected, and `ratingSearchClause` produces the `OR` expression only when more than one is — the two are mutually exclusive by construction, so a rating can never be double-specified.

The one defect in this channel is **unescaped interpolation of user text** into query syntax (Finding 6).

---

## Parsing Pipeline

| Page kind | Entry point | Selector |
|---|---|---|
| Search / readings / series / tag listings | `parseSearchPage` | `li.work.blurb` |
| Bookmarks | `parseBookmarksPage` | `li.bookmark.blurb` |
| Subscriptions | `parseSubscriptionsPage` | `dl.subscription dt` |

`parseSearchPage` and `parseBookmarksPage` share `parseWorksList`, differing only by selector — good factoring, since bookmark blurbs carry `id="bookmark_<n>"` and `parseBlurb` already falls back to reading the work id out of the `/works/<id>` title link.

`parseBlurb` (`AO3Client.swift:1201`) extracts id, title, authors (+ verified identities, with an `Anonymous` fallback), fandoms, rating, warnings, categories, WIP state, date, and tag groups. The "Additional Tags" handling is notably careful: rather than selecting `li.freeforms`, it takes *all* tags and subtracts the categorized ones, so a tag in an unexpected group still surfaces instead of vanishing.

Stat extraction is centralized in `statInt` (`AO3Client+Authors.swift:515`), which reads `dl.stats dd.<kind>` and filters to digits — so `"24,180"` → `24180` correctly, and AO3's `<a>`-wrapped counts (comments, kudos, bookmarks) parse fine since `.text()` unwraps them.

**Confirmed against live AO3 today** — the blurb `dl.stats` order and classes are exactly: `language, words, chapters, comments, kudos, bookmarks, hits`, with `comments`/`kudos`/`bookmarks` wrapped in anchors and AO3 **omitting the `<dd>` entirely when a count is zero**. The parser's `Int?` return correctly represents that absence.

---

## Pagination & Sorting Pipeline

### Pagination

`paginationTotal` (`AO3Client+Authors.swift:503`) takes the maximum parseable integer among `ol.pagination li, nav.pagination a, .pagination li`, defaulting to `currentPage`.

**Live-verified.** AO3's search pagination for a large result set renders:

```
← Previous | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | … | 4999 | 5000 | Next →
```

Because AO3 always renders the **last** page number, taking the max is correct, and non-numeric items (`← Previous`, `…`, `Next →`) parse to `nil` and are skipped. AO3 caps search pagination at **5000 pages**. Small result sets render no pagination element, and the `currentPage` default correctly yields 1.

This is correct but structurally fragile — it infers a total from presentational markup. See Finding 9.

### Sorting

`Sort` (`AO3Models.swift:586`) maps to `work_search[sort_column]`, with `.relevance` → `nil` (omit, letting AO3 default to `_score`). Verified live: `sort_column=kudos_count` returned 41565 / 27594 / 26811 kudos in order.

The gap is that **`sort_direction` is never sent**. otwarchive's `WorkQuery` confirms it defaults to `'desc'`. See Finding 2.

---

## AO3 Compatibility Analysis

### Field coverage

Ground truth: the live `/works/search` form, enumerated in-browser (38 input elements, 22 distinct parameter names).

| AO3 parameter | Implemented | Where | Notes |
|---|:--:|---|---|
| `work_search[query]` | ✅ | `AO3Client.swift:278` | Also carries synthesized exclusion/rating clauses |
| `work_search[title]` | ❌ | — | **Missing** (F1) |
| `work_search[creators]` | ❌ | — | **Missing** (F1) |
| `work_search[fandom_names]` | ✅ | `:280` | |
| `work_search[character_names]` | ✅ | `:281` | |
| `work_search[relationship_names]` | ✅ | `:282` | |
| `work_search[freeform_names]` | ✅ | `:283` | |
| `work_search[rating_ids]` | ✅ | `:285` | Single-value; multi handled via query syntax |
| `work_search[archive_warning_ids][]` | ✅ | `:287` | Correct `[]` multi-value form |
| `work_search[category_ids][]` | ✅ | `:290` | Correct `[]` multi-value form |
| `work_search[crossover]` | ✅ | `:292` | |
| `work_search[complete]` | ✅ | `:293` | |
| `work_search[single_chapter]` | ✅ | `:294` | |
| `work_search[word_count]` | ✅ | `:295` | Expression form; see F4 |
| `work_search[revised_at]` | ✅ | `:296` | |
| `work_search[language_id]` | ✅ | `:297` | Full 168-entry list |
| `work_search[hits]` | ❌ | — | **Missing** (F1) |
| `work_search[kudos_count]` | ❌ | — | **Missing** (F1) |
| `work_search[comments_count]` | ❌ | — | **Missing** (F1) |
| `work_search[bookmarks_count]` | ❌ | — | **Missing** (F1) |
| `work_search[sort_column]` | ✅ | `:298` | 8 of 10 columns |
| `work_search[sort_direction]` | ❌ | — | **Missing** (F2) |
| `page` | ✅ | `:300` | 1-based, always sent |

**Coverage: 15 / 22 (68%).**

otwarchive's `WorkQuery` additionally accepts `words_from`, `words_to`, `date_from`, `date_to`, `series_titles`, `collection_ids`, and `work_types`, which are not all exposed on the public form. `words_from`/`words_to` are directly relevant (F4).

### Constant-value verification

All verified against the live form's option values today.

| Set | App values | Live AO3 | Match |
|---|---|---|:--:|
| Ratings | 9, 10, 11, 12, 13 | 9=Not Rated, 10=General, 11=Teen, 12=Mature, 13=Explicit | ✅ |
| Warnings | 14, 16, 17, 18, 19, 20 | 14, 16, 17, 18, 19, 20 | ✅ |
| Categories | 116, 22, 21, 23, 2246, 24 | 116=F/F, 22=F/M, 21=Gen, 23=M/M, 2246=Multi, 24=Other | ✅ |
| `complete` | `T` / `F` / omit | `T`, `F`, `""` | ✅ |
| `crossover` | `T` / `F` / omit | `T`, `F`, `""` | ✅ |
| `single_chapter` | `1` / omit | `1` (checkbox), `0` (hidden) | ✅ |
| Sort columns | 8 values | 10 values | ⚠️ missing `authors_to_sort_on`, `title_to_sort_on` |

**No incorrect constant was found anywhere in the filter model.**

---

## Findings

### Finding 1 — Six AO3 search fields are unimplemented

- **Severity**: High
- **Location**: `Services/AO3Client.swift:267–306` (`search(filters:page:)`); `Models/AO3Models.swift` (`AO3SearchFilters`); `Features/Search/AO3FilterPanel.swift`
- **Description**: AO3's work-search form exposes `title`, `creators`, `hits`, `kudos_count`, `comments_count`, and `bookmarks_count`. None are modelled or emitted.
- **Evidence**: Live DOM enumeration of `/works/search` returned 22 distinct `work_search[...]` names; the six above have no corresponding `add(...)` call in `search()` and no property on `AO3SearchFilters`. otwarchive's `WorkQuery` confirms all six are honoured server-side.
- **Impact**: Users cannot search by title or author, nor filter by popularity thresholds ("kudos > 1000"), which are among the most-used AO3 search behaviours. Searching for an author currently requires typing the name into free-text `query`, which matches body text and tags too and therefore returns materially different (noisier) results than `creators` would.
- **Root Cause**: Incremental feature scope — the filter panel was built around tags/ratings/warnings, and the numeric and identity fields were never added.
- **Recommended Fix**: Add six properties to `AO3SearchFilters` and six `add(...)` calls. The four stat fields accept the *same* range-expression grammar as `word_count`, so extract the existing `wordCountExpression` into a reusable `rangeExpression(from:to:)` and apply it to all five. Reuse the existing `wordsFrom`/`wordsTo` two-field UI idiom for each.
  - *Alternative considered*: expressing these through `query` syntax (`kudos_count:>1000`). Rejected — the structured fields exist, are documented, and avoid the escaping hazard in Finding 6.
- **Scope**: Medium (model + URL + UI + persistence migration for `SavedSearch`)
- **Risk**: Low-Medium. `AO3SearchFilters` is `Codable`-persisted by `SavedSearch`; new properties **must** be added to the explicit `CodingKeys` (`AO3Models.swift:144`) *and* decoded with the established `decodeIfPresent(...) ?? default` pattern already applied to `chapterCount` (`AO3Models.swift:208`), or every previously saved search will fail to decode. Swift's synthesized `Decodable` treats a missing key as an error even when the property has a default — this is why the custom `init(from:)` exists.
- **Dependencies**: None
- **Priority**: P1
- **Confidence**: High — field names and acceptance verified live.
- **Verification method**: Live DOM enumeration + otwarchive source cross-check.

### Finding 2 — Results can only be sorted descending; two sort columns unreachable

- **Severity**: High
- **Location**: `Models/AO3Models.swift:586–616` (`Sort`); `Services/AO3Client.swift:298`
- **Description**: `work_search[sort_direction]` is never sent, and the `Sort` enum omits `authors_to_sort_on` (Creator) and `title_to_sort_on` (Title).
- **Evidence**: `search()` emits only `sort_column`. Live form exposes a `sort_direction` select with `asc`/`desc`. otwarchive `WorkQuery`: *"`sort_direction` defaults to `'desc'`"*.
- **Impact**: Ascending sorts are impossible. This is most visible for the two missing columns — alphabetical-by-title and by-creator are inherently ascending operations — but it also blocks legitimate uses of the columns that *are* present, such as finding the shortest works (`word_count` ascending) or the oldest (`created_at` ascending).
- **Root Cause**: `Sort` was modelled as a flat list of columns rather than a (column, direction) pair.
- **Recommended Fix**: Add a `SortDirection` enum (`.ascending`/`.descending`) to `AO3SearchFilters`, emit `work_search[sort_direction]`, and add the two missing columns. Default to `.descending` to preserve current behaviour exactly.
  - *Alternative considered*: a per-column implicit direction (title→asc, kudos→desc). Rejected — it removes user control and surprises anyone who wants the non-default.
- **Scope**: Small
- **Risk**: Low. Same `Codable` migration caveat as Finding 1.
- **Dependencies**: None
- **Priority**: P1
- **Confidence**: High — verified live and against otwarchive.
- **Verification method**: Live DOM + otwarchive source.

### Finding 3 — Superseded search requests are never cancelled

- **Severity**: High
- **Location**: `Features/Search/SearchView.swift:714–736` (`load(page:)`), `:738–759` (`refreshCurrentResults()`)
- **Description**: Staleness is handled by incrementing `loadToken` and discarding results whose token no longer matches. The `Task` is never retained and never cancelled, so a superseded request still performs its full network round-trip.
- **Evidence**:
  ```swift
  private func load(page: Int) {
      loadToken += 1
      let token = loadToken
      let current = filters
      Task {                                   // ← not stored, never cancelled
          let result = try await AO3Client.shared.search(filters: current, page: page)
          guard token == loadToken else { return }   // ← result discarded, work already done
  ```
  No `Task` handle is stored anywhere in `SearchView` (`grep` for `searchTask` returns nothing).
- **Impact**: Compounded by the 0.6 s pacer, this directly delays the user. Tapping through pages 2→3→4→5 issues four real requests; because `pace()` serializes *starts*, the page-5 request the user is actually waiting for must wait out the pacing slots of three requests whose results will be thrown away — roughly 1.8 s of avoidable latency. It also spends AO3 request budget on work that is discarded, which is contrary to the politeness posture the rest of the layer maintains so carefully.
- **Root Cause**: Token-based staleness is a correctness mechanism; it was not paired with a lifecycle mechanism.
- **Recommended Fix**: Store the in-flight `Task` in `@State` and `cancel()` it at the top of `load(page:)`/`refreshCurrentResults()`. Keep the token check as a second line of defence (cancellation is cooperative and can lose a race). Add a `catch is CancellationError { return }` arm so a cancelled load does not render an error phase.
  - *Note*: this fix is only fully effective together with Finding 4 — `RequestCoalescer` currently will not propagate the cancellation into the actual fetch.
  - *Alternative considered*: SwiftUI `.task(id:)`, which cancels automatically on id change. Cleaner, but paging is imperative here (triggered by taps, not by a derived identity), so it would require restructuring page state into a single identity value. Reasonable as a follow-up, not required.
- **Scope**: Small
- **Risk**: Low
- **Dependencies**: Finding 4 for full benefit
- **Priority**: P1
- **Confidence**: High — verified by reading the complete call path; no cancellation exists anywhere in it.
- **Verification method**: Static analysis.

### Finding 4 — `RequestCoalescer` does not propagate cancellation

- **Severity**: Medium
- **Location**: `Services/RequestCoalescer.swift:15–23`
- **Description**: The shared work runs in an unstructured `Task { }`. Unstructured tasks do not inherit cancellation from the context that awaits them, so cancelling a caller does not cancel the underlying fetch.
- **Evidence**:
  ```swift
  let task = Task { try await operation() }   // unstructured — no cancellation inheritance
  inFlight[key] = task
  defer { inFlight[key] = nil }
  return try await task.value
  ```
- **Impact**: Cancellation stops at the coalescer boundary. Once Finding 3 is fixed, cancelling a search would still leave the HTTP request running to completion. Today the impact is latent (nothing cancels), which is why this is Medium rather than High.
- **Root Cause**: Unstructured `Task` is required here — the whole point is that the work outlives any single caller so others can join it. But that also means cancellation semantics must be handled deliberately, and they were not.
- **Recommended Fix**: Reference-count the waiters and cancel the shared `Task` only when the last waiter goes away, via `withTaskCancellationHandler`. This preserves the coalescing guarantee (one caller leaving must not cancel work another still needs) while making cancellation effective when *all* callers have gone.
  - *Alternative considered*: cancelling on the first waiter's cancellation. Rejected outright — it would let one caller's cancellation break an unrelated caller's request, which is worse than the current behaviour.
  - *Alternative considered*: leaving as-is and accepting that fetches always run to completion. Defensible given the small page sizes, but it forfeits the latency win from Finding 3.
- **Scope**: Small-Medium
- **Risk**: Medium — reference-counting a shared task is genuinely easy to get subtly wrong; this needs its own tests, including the "second waiter joins while first is cancelling" race.
- **Dependencies**: Pairs with Finding 3
- **Priority**: P2
- **Confidence**: High on the mechanism (documented Swift concurrency semantics); Medium on real-world impact magnitude, which depends on how often users abandon searches mid-flight — not measured.
- **Verification method**: Static analysis against Swift concurrency semantics.

### Finding 5 — No test asserts any search URL parameter

- **Severity**: Medium (High as a *risk multiplier*)
- **Location**: `KudosTests/` — absence
- **Description**: `grep -rl "work_search\[" KudosTests/` returns **nothing**. No test exercises `AO3Client.search(filters:page:)`'s URL construction.
- **Evidence**: `SearchFiltersTests` covers `searchQuery` *synthesis* thoroughly (11 tests, including exclusion syntax and rating expressions) and `AO3ClientTests` covers parsing and the other URL builders (`markedForLaterURL`, `historyURL`, `subscriptionsURL`, `seriesPageURL`, bookmarks). The mapping from `AO3SearchFilters` → `work_search[...]` query items is the one link in the chain with no coverage at all.
- **Impact**: Every parameter name, every rating/warning/category ID, and the `[]` multi-value convention are load-bearing constants that this audit had to verify by hand against the live site. A typo or a refactor could break search silently — and because `parseBlurb` failures are swallowed per-blurb (Finding 9), the symptom would be "no results", not an error.
- **Root Cause**: `search()` interleaves URL construction with the network call, so there is no pure seam to assert against without hitting the network.
- **Recommended Fix**: Extract the URL construction into a static pure function — `static func searchURL(filters:page:) -> URL?` — and have `search()` call it. Then assert the full query-item set for: defaults (only `page` present), each filter in isolation, multi-value warnings/categories, and the rating structured/expression split.
  - *Alternative considered*: snapshot-testing the whole URL string. Rejected — query-item order would make it brittle; assert on a parsed `[name: [value]]` dictionary instead.
- **Scope**: Small
- **Risk**: Very low — pure extraction, no behaviour change.
- **Dependencies**: Should land *before* Findings 1 and 2, so those additions are covered as they are written.
- **Priority**: P1 (do first)
- **Confidence**: High
- **Verification method**: Static analysis (`grep` over the test target).

### Finding 6 — User text is interpolated into query syntax unescaped

- **Severity**: Medium
- **Location**: `Models/AO3Models.swift:242` (`searchQuery`)
- **Description**: Excluded tag names are wrapped in double quotes by string interpolation with no escaping: `"-\"\($0)\""`.
- **Evidence**:
  ```swift
  clauses += excludedTags.map { "-\"\($0)\"" }
  ```
  A tag containing a double quote — legal on AO3, e.g. a title-style freeform tag — produces `-"He said "hello""`, which terminates the quoted phrase early and injects stray tokens into the Elasticsearch query.
- **Impact**: Malformed queries for affected tags: silently wrong result sets, or an AO3-side parse error. Not a security issue in the usual sense — the input is the user's own and the blast radius is their own search — but it is a correctness bug and a search-syntax injection.
- **Root Cause**: Query-syntax construction by string interpolation with no escaping helper.
- **Recommended Fix**: Add a small `escapedPhrase(_:)` helper that backslash-escapes `"` (and `\`) before wrapping, and route every quoted interpolation through it. Add a test with a quote-containing tag.
  - *Alternative considered*: stripping quotes from user input. Rejected — it silently changes what the user asked for.
- **Scope**: Small
- **Risk**: Low
- **Dependencies**: None
- **Priority**: P2
- **Confidence**: High on the code path. **Medium on AO3's exact escaping grammar** — I did not empirically confirm how AO3's Elasticsearch layer handles an escaped quote, so the specific escape sequence should be validated against the live site before shipping.
- **Verification method**: Static analysis. Live validation of the escape sequence still required.

### Finding 7 — `search()` omits `view_adult` while sibling listing paths send it

- **Severity**: Low
- **Location**: `Services/AO3Client.swift:267–306` vs `:678–686`
- **Description**: `worksPage(at:)` explicitly appends `view_adult=true` "so paging and adult works resolve like search" — but `search()`, the path that comment refers to, does not send it.
- **Evidence**: `grep view_adult` shows it in `worksPage(at:)`, work/chapter detail fetches, comments, and write actions — but not in `search()`.
- **Impact**: Believed nil in practice: AO3's adult interstitial gates *work* pages, not listing pages, and live search results returned Explicit works without it. But the comment in `worksPage(at:)` asserts parity with a behaviour `search()` does not actually have, so the codebase is self-inconsistent and the next reader will be misled.
- **Root Cause**: Divergent evolution of two listing paths.
- **Recommended Fix**: Either add `view_adult=true` to `search()` for genuine parity (harmless, one line), or correct the `worksPage(at:)` comment to stop claiming it. Prefer the former for uniformity.
- **Scope**: Small
- **Risk**: Very low
- **Dependencies**: None
- **Priority**: P3
- **Confidence**: High that the divergence exists; **Medium** that it has no functional effect — I did not test a logged-out request for an Explicit work through the search path specifically.
- **Verification method**: Static analysis + partial live observation.

### Finding 8 — No response caching

- **Severity**: Medium
- **Location**: `Services/AO3Client.swift:51–61` (`makeAnonymousSessionConfiguration`)
- **Description**: No `URLCache` is configured and no `cachePolicy` is set anywhere in the codebase (`grep` for `URLCache|requestCachePolicy|cachePolicy` returns no hits). The session is `.ephemeral`, whose default cache is small and in-memory only.
- **Evidence**: The configuration sets `httpAdditionalHeaders`, `timeoutIntervalForRequest`, `httpShouldSetCookies`, `httpCookieAcceptPolicy` — and nothing cache-related.
- **Impact**: `RequestCoalescer` only helps *concurrent* identical requests. Sequential repeats — paging 1→2→1, or revisiting a work — re-fetch in full, each paying a 0.6 s pacing slot. This is the single largest remaining politeness win available.
- **Root Cause**: Caching was layered onto callers ad hoc (`FandomCatalog.warmCache()`) rather than at the transport.
- **Recommended Fix**: Configure an explicit `URLCache` (a few MB memory, modest disk) on the session. Because it is `.ephemeral`, a disk cache must be attached deliberately. Then decide per-call whether to honour AO3's headers or apply a short app-level TTL for listing pages.
  - *Alternative considered*: an app-level `[URL: (Data, Date)]` cache in `AO3Client`. Rejected — reimplements `URLCache` and re-derives HTTP caching semantics by hand, exactly the kind of thing the existing layer has been careful to avoid.
  - **Caveat**: AO3's own `Cache-Control` headers were not inspected. If AO3 sends `no-store`, `URLCache` will honour it and the win evaporates — measure before building.
- **Scope**: Small (config) to Medium (with a TTL policy)
- **Risk**: Medium — caching search results risks showing stale pages; needs an explicit invalidation story for pull-to-refresh.
- **Dependencies**: None
- **Priority**: P2
- **Confidence**: High that no caching exists. **Low-Medium on the achievable benefit**, pending inspection of AO3's response headers.
- **Verification method**: Static analysis. Header inspection outstanding.

### Finding 9 — Parse failures are indistinguishable from empty results

- **Severity**: Medium
- **Location**: `Services/AO3Client.swift:1190` (`parseWorksList`); `AO3Client+Authors.swift:503` (`paginationTotal`)
- **Description**: Two independent degradation paths both fail silently:
  1. `blurbs.compactMap { try? Self.parseBlurb($0) }` — if AO3 changes blurb markup, every blurb fails, and the page returns zero works with no error.
  2. `paginationTotal` infers the total from presentational pagination markup; if AO3 moved to a `Next`-only pager, totals would silently collapse to `currentPage`, capping the app at one page.
- **Evidence**: Both are `try?`/max-based with `currentPage` as the floor, and neither has a "we saw elements but parsed none" check.
- **Impact**: A future AO3 markup change degrades to a confusing, un-actionable empty state rather than a diagnosable failure. Given the app is entirely scraping-based, markup change is a *when*, not an *if*.
- **Root Cause**: Resilience (don't fail a page for one bad blurb) was implemented without an accompanying health signal.
- **Recommended Fix**: In `parseWorksList`, if `!blurbs.isEmpty && works.isEmpty`, log at error level and throw `AO3Error.parse`. That distinction is precise: blurb elements present but none parseable is unambiguously a parser break, never a legitimate empty result — a genuinely empty page has no blurb elements at all.
  - *Alternative considered*: a partial-failure ratio threshold. Rejected as over-fitted; the all-or-nothing case is the one that matters and is unambiguous.
- **Scope**: Small
- **Risk**: Low
- **Dependencies**: None
- **Priority**: P2
- **Confidence**: High on the code path; the markup-change scenario is an informed hypothesis, not an observed failure.
- **Verification method**: Static analysis.

### Finding 10 — `word_count` uses an expression where AO3 offers native bounds

- **Severity**: Low
- **Location**: `Services/AO3Client.swift:699–708` (`wordCountExpression`)
- **Description**: Two UI fields (`wordsFrom`, `wordsTo`) are collapsed into a single expression string (`"1000-5000"`, `"> 1000"`, `"< 5000"`). otwarchive's `WorkQuery` accepts `words_from` and `words_to` directly.
- **Evidence**: otwarchive `WorkQuery` reads `words_from`/`words_to` alongside `word_count`. **Live-verified that the current expression form works**: `work_search[word_count]=> 1000` (space included) returned only works above 1000 words.
- **Impact**: None today — this is working code. It is a robustness note: the app parses two numbers, formats them into a string, and relies on AO3 re-parsing that string, when a lossless two-field path exists. otwarchive strips commas/periods/underscores before conversion, so user-typed `"1,000"` also survives.
- **Root Cause**: Modelled on the public form's single visible field rather than the underlying query API.
- **Recommended Fix**: Low priority. If Finding 1's shared `rangeExpression(from:to:)` helper is built, keep the expression form for uniformity across all five range fields — that consistency is worth more than the marginal robustness of the native pair.
  - *Alternative considered*: switching to `words_from`/`words_to`. Rejected precisely because the other four stat fields have no such native pair, so it would make word count the odd one out.
- **Scope**: Small
- **Risk**: Low
- **Dependencies**: Finding 1
- **Priority**: P4 — document, do not change
- **Confidence**: High — both forms verified.
- **Verification method**: Live query + otwarchive source.

### Finding 11 — `Retry-After` date parsing allocates a `DateFormatter` per call

- **Severity**: Low
- **Location**: `Services/AO3Client.swift:205–215` (`retryAfter(from:)`)
- **Description**: A `DateFormatter` is constructed on every call that reaches the HTTP-date branch.
- **Evidence**: `let formatter = DateFormatter()` inside the function body.
- **Impact**: Negligible — only on 429 responses, and only when AO3 sends a date rather than an integer. Noted for completeness, not because it matters.
- **Root Cause**: Convenience.
- **Recommended Fix**: Hoist to a `static let`, matching the cached-formatter pattern already used in `WorkStat` (`UIComponents/WorkStatLabel.swift`).
- **Scope**: Small
- **Risk**: Very low
- **Dependencies**: None
- **Priority**: P4
- **Confidence**: High
- **Verification method**: Static analysis.

---

## Consistency Report

| Concern | Consistent? | Notes |
|---|:--:|---|
| One networking primitive | ✅ | Every feature extension routes through `getHTML`/`fetchData`. No second pipeline exists — verified by grep across all `AO3Client+*` files. |
| Pagination parsing | ✅ | Single shared `paginationTotal` used by search, bookmarks, subscriptions, authors. |
| Stat parsing | ✅ | Single shared `statInt`. |
| Page-number URL convention | ⚠️ | `search()` always sends `page`; `markedForLaterURL`, `historyURL`, `seriesPageURL`, `worksPage(at:)` send it only when `page > 1`. Both are valid; the inconsistency is cosmetic but invites confusion. |
| `view_adult` | ❌ | Sent by work/chapter/comment/tag-listing paths, not by `search()` (Finding 7). |
| Error surfacing | ⚠️ | `AO3Error` is well-shaped, but `CancellationError` has no dedicated arm in `SearchView`'s catch — it would render as a generic failure once Finding 3 lands. |
| Filter constants | ✅ | All IDs match live AO3. |
| Dead code | ✅ | No abandoned/duplicate networking path found. |

---

## Technical Debt

1. **`AO3Client.swift` is 1292 lines** and carries two `swiftlint:disable` escapes (`file_length`, `type_body_length`). It mixes transport, URL construction, and static parsing. The extensions (`+Authors`, `+Comments`, `+Inbox`, `+Preferences`) show the intended direction; transport-vs-parsing has not yet been split.
2. **Search URL construction is untestable in place** (Finding 5) — the direct cause of the coverage gap.
3. **Shared helpers live in a feature extension**: `paginationTotal` and `statInt` are used by every parser but are defined in `AO3Client+Authors.swift`, which is not where a reader would look.
4. **Two throttles with non-obvious interaction** — `AO3RequestCoordinator(limit: 3)` and `pace(0.6s)` (see Architecture). Undocumented at the coordinator.
5. **Ad hoc caching** (`FandomCatalog.warmCache()`) in place of a transport-level policy (Finding 8).

---

## Refactoring Opportunities

Ordered by value-to-risk.

1. **Extract `static func searchURL(filters:page:) -> URL?`** — unblocks Finding 5, zero behaviour change, prerequisite for Findings 1–2. *Do this first.*
2. **Extract a shared `rangeExpression(from:to:)`** — makes Finding 1's four stat fields nearly free once `searchURL` is pure.
3. **Split `AO3Client` into transport and parsing** — `AO3Client` (actor: pace/retry/coalesce/fetch) and `AO3Parsing` (an enum of static parsers). Removes both lint escapes and makes the entire parsing surface testable without touching the actor. Medium effort, low risk, mechanical.
4. **Move `paginationTotal`/`statInt` into the parsing type** — naturally resolved by (3).
5. **Model sort as `(column, direction)`** — Finding 2, and prevents the same flattening recurring.

---

## Unknowns & Residual Risk

Stated explicitly rather than guessed at.

1. **AO3's `Cache-Control` headers were not inspected.** Finding 8's benefit is unquantified and could be near-zero if AO3 sends `no-store`. **Measure before implementing.**
2. **AO3's Elasticsearch escaping grammar was not empirically tested.** Finding 6's specific escape sequence is a recommendation, not a verified fix.
3. **No load or rate-limit testing was performed.** Whether 0.6 s + 3 concurrent actually stays under AO3's limits in sustained use is unverified; no observed 429 was available to study.
4. **Authenticated paths were spot-checked only** (Tier 2). `AO3AuthService` (988 lines) and `AO3SessionVault` (365) were not audited line-by-line. The cookie-isolation *invariant* was verified by reading `makeAnonymousSessionConfiguration` and `purgeSessionCookie` and confirming unit tests exist; the broader auth flow was not.
5. **`hig-review` divergence.** This audit is of `72267fea` in the current worktree. If `hig-review` differs, re-verify.
6. **AO3 may change at any time.** Every live-verified fact here has today's date on it. This is the standing risk of a scraping client and the reason Finding 5 matters more than its severity suggests.

---

## Prioritized Action Plan

### Immediate (Critical)

*Nothing in this audit is production-breaking.* No incorrect parameter, no wrong constant, no data-loss path was found. The list below is ordered by value, not urgency.

### High Priority

1. **Extract `searchURL(filters:page:)` and test it exhaustively** (F5). Do this before anything else — it is the safety net for items 2–4 and pins the constants this audit verified by hand.
2. **Cancel superseded search tasks** (F3). Small, immediately felt by users while paging.
3. **Add `sort_direction` and the two missing sort columns** (F2). Small, unlocks alphabetical and ascending sorts.
4. **Add `title`, `creators`, and the four stat-range fields** (F1). The largest functional gain; lands cheaply once (1) and the shared range helper exist. Remember the `decodeIfPresent` migration for `SavedSearch`.

### Medium Priority

5. **Throw on total blurb-parse failure** (F9). Converts a future silent breakage into a diagnosable one.
6. **Escape quoted user text in query synthesis** (F6). Validate the escape against live AO3 first.
7. **Reference-counted cancellation in `RequestCoalescer`** (F4). Needs its own race tests; pairs with (2).
8. **Investigate transport-level caching** (F8) — *measure AO3's headers first*, then decide.

### Nice to Have

9. Split `AO3Client` into transport + parsing; drop both lint escapes (Debt 1, 3).
10. Resolve the `view_adult` inconsistency (F7) — one line, or fix the misleading comment.
11. Document the pace/coordinator interaction at `AO3RequestCoordinator` (Debt 4).
12. Normalize the `page`-parameter convention across URL builders (Consistency).
13. Hoist the `Retry-After` `DateFormatter` (F11).

### Recommended order of work

```
F5 (extract + test)  →  F3 (cancel)  →  F2 (sort)  →  F1 (fields)
                                   ↘  F4 (coalescer cancellation)
F9 (parse signal)  →  F6 (escaping)  →  F8 (measure, then cache)
                                   →  Refactor 3 (split client)
```

`F5` first is the load-bearing decision: it converts the highest-risk untested surface into a tested one *and* creates the pure seam that makes `F1`/`F2` cheap and safe. Everything else can proceed in parallel afterwards.

---

## Appendix — Live Verification Log

All performed 2026-08-06 against `archiveofourown.org`.

| # | Check | Method | Result |
|---|---|---|---|
| 1 | Work-search field inventory | DOM enumeration of `/works/search` | 38 elements, 22 distinct names |
| 2 | Rating / warning / category / sort / complete / crossover option values | DOM option extraction | All app constants match |
| 3 | Pagination markup, large result set | `ol.pagination` on `?query=love&page=2` | `← Previous 1…9 … 4999 5000 Next →`; cap 5000 |
| 4 | Space-padded word-count expression | `word_count=> 1000` + `sort_column=kudos_count` | Accepted; sorted desc (41565/27594/26811) |
| 5 | Field-scoped query syntax | `query=rating_ids:13` | 20/20 Explicit |
| 6 | Negated field-scoped syntax | `query=-archive_warning_ids:14` | 0/20 "Chose Not To Use" |
| 7 | Blurb `dl.stats` structure | DOM inspection of a work blurb | `language, words, chapters, comments, kudos, bookmarks, hits`; zero-count `<dd>` omitted |
| 8 | otwarchive `WorkQuery` parameters + sort defaults | Source fetch | Confirms `words_from`/`words_to`, `date_from`/`date_to`, `sort_direction` default `desc` |
