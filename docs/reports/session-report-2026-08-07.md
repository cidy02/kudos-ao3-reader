# Session Report — 2026-08-06/07

**Branches (neither pushed):**

| Platform | Branch | Worktree | Commits | Verify |
|---|---|---|---|---|
| iOS | `claude/ao3-networking-review-3377ae` | `ao3-networking-review-3377ae` | 16 | `Scripts/verify.sh` ALL GREEN — 968 tests, 86 suites |
| Android | `android/exclusion-parity` (off `kudos-ao3-reader-android`) | `android-exclusion-parity` | 7 | `android/Scripts/verify.sh` ALL GREEN |

Started from `docs/reports/ao3-networking-review-2.md` (a second-pass adversarial
review) and ran through its action plan, then a series of feature and design
requests, then an adversarial review of everything above.

Test count: **917 → 968** on iOS. Android gained 5 new test classes.

---

## 1. What the review asked for, and what happened

### The defect neither review pass found

**Saved searches did not persist. At all.** Saving a search wrote a row and the
search was silently gone — from the list, from every fetch, permanently.

`Language` carried a custom `encode(to:)` writing a `singleValueContainer` (the
bare id, matching the old raw-value-enum wire format). SwiftData makes **one
SQLite column per stored property** for a composite attribute, but fills those
columns from the `Encodable` conformance. One value for two columns left `title`
`NULL`, and CoreData then rejected the whole row:

```
CoreData: error: Row (pk = 1) for entity 'SavedSearch' is missing mandatory
                 text data for property 'title'
```

Dumped from a real (non-in-memory) store written by the app's own schema:

```
before: ZID: ''   ZTITLE1: NULL            ← typeof() = null, not empty string
after : ZID: ''   ZTITLE1: 'Any language'
```

Found by implementing the review's own S5 recommendation ("add one round-trip test
that opens a real `ModelContainer`"). The test failed on its first run, for default
filters.

**Fixed twice.** The first fix stopped new saves being destroyed. The second — after
being told the first was incomplete — redesigned `Language` to store only `id` and
derive `title`, which drops the column count from two to one. That recovers rows
already written by the broken build: a store written by `67850e41`'s model, which
that build itself read back as **0 rows**, now reads as 1 row intact, language
included. Verified by writing a store with the old model and reopening it with the new.

`5f071776` and `0c71a730` are **not on `main`** (`git merge-base --is-ancestor`), so
no released build was affected.

### The other action-plan items

| # | Item | Outcome |
|---|---|---|
| S1 | Invalidation missing from 4 refresh surfaces | Fixed. Media/fandom lists take it at the `.refreshable` closure, not inside `refresh()` — that doubles as their initial loader and would have evicted on first load. |
| S2 | `dateBoundFormatter` pinned to UTC | Fixed with `.autoupdatingCurrent` (not `.current`: the instance is a `static let` that outlives a time-zone change). Its test was rebuilt to assert the contract — bounds at **00:30 and 23:30** so it fails on any non-UTC machine in either offset direction. |
| S3 | `.reloadIgnoringLocalCacheData` stops reads, not writes | Comment corrected; `evictFromSharedCache` added for the write half. **The review's suggested fix does not work** — see corrections below. |
| S4 | Refresh no longer cancellable by the gesture | `withTaskCancellationHandler` bound to a local (`Task` is `Sendable`, the view is not), plus `.cancelRefreshOnTabChange` for the tab-switch case SwiftUI does *not* cancel. |
| S5 | Persistence tested through the wrong mechanism | Real `ModelContainer` round-trip test; found the defect above. |
| S6/S7 | Exclusion mechanism and case-sensitivity mis-described | Documented, including the `filter_ids` vs `match_filter` split. |
| S8/S9/S10 | Mechanism choice, race, header stability | Decisions and measurements recorded in the doc comments. |
| item 6 | `invalidateCachedResponses` had zero coverage | Test added against the *live* client's cache via a new internal seam. Mutation-confirmed. |

### Two corrections to the review itself

**S3's recommended fix is not implementable on this code path.** "Add a
`URLSessionDataDelegate` returning `nil` from `willCacheResponse`" — measured
against a local server, that callback is **never delivered** under
`await session.data(for:delegate:)`:

```
async data(for:delegate:)  + task delegate     : called=false  stored=true
async data(for:delegate:)  + session delegate  : called=false  stored=true
dataTask(with:)            + session delegate  : called=true   stored=false
```

So the choice was never "comment vs. delegate" but "comment vs. rewriting the
authenticated fetch out of async/await *and* attaching a session-wide delegate to a
session whose anonymous traffic we want cached". Neither was taken; an eviction after
each authenticated fetch was, with the residual window documented rather than papered
over.

**S7's premise is false.** The review says the app has "four free-text tag fields with
no autocomplete". It doesn't — `TagSelectField`/`TagPickerView` have offered
AO3-autocomplete-backed pickers for all four tag kinds, with no free-text entry
anywhere. Building autocomplete again would have duplicated working code. What was
actually missing was **coverage**: `autocompleteTags` had none, and its five endpoint
paths are load-bearing (a wrong one 404s into an empty suggestion list that reads as
"no such tag"). Pure `autocompleteURL`/`parseAutocomplete` seams were split out and
pinned.

---

## 2. Features built

### Results card

AO3's own result-count heading, above search and browse results:

```
📄 Naruto (Anime & Manga)                    1–20
   142,327 works
   [Sort: Date Updated] [English] [Complete]
```

The total is the one fact a page of blurbs cannot supply. Three live heading shapes,
read from the site rather than guessed:

```
/works/search      h3.heading   92,495 Found
/tags/<t>/works    h2.heading   1 - 20 of 142,322 Works in Naruto (Anime & Manga)
/users/<n>/works   h2.heading   1 - 20 of 535 Works by astolat
```

Four traps that only measuring exposed:

1. **A zero-result search omits the heading entirely** — it renders only "Search
   Results". So `nil` is the normal path and the summary is parsed with `try?`: a
   decorative count must never fail a page whose works parsed fine.
2. **The search heading's text is `"92,495 Found  ?"`** — the `?` is its help link.
   "Everything after the noun" would put a bare **?** on the card.
3. **With a query active AO3 says "Works *found* in \<tag\>"**, not "Works in". Browse
   sends a query for every excluded warning, so that is its *normal* heading — the
   card would have silently lost its title exactly when a filter was active.
4. **The count is anchored to the noun**, never "the first number": `1 - 20 of 142,322`
   otherwise reads as **1 work**, and a fandom named `5 - 10 Years Later` otherwise
   produces a page range.

The chips are the other half — until now nothing on screen said what was filtering a
list once the panel was dismissed, only a filter button that changed colour. Only
non-default settings appear; the sort always does, which is what keeps the card from
looking empty. Tapping opens the filter panel.

### Browse reads AO3's tag listing

`/tags/<fandom>/works` instead of `/works/search?work_search[fandom_names]=`. Same
works (142,327 both ways) and the **same filters** — the tag page's visible sidebar is
smaller, but it is the same `WorkSearchForm` and honours everything the panel emits.
Verified live against a 142,327 baseline:

| Filter | Result |
|---|---|
| `rating_ids=10` | 33,009 |
| `word_count=1000-5000` | 61,895 |
| `single_chapter=1` | 85,978 |
| `revised_at=< 1 week ago` | 1,357 |
| `hits=> 1000` | 78,553 |
| `character_names=Sasuke Uchiha` | 364 |
| `title` / `creators` (nonsense) | 0 |
| `query=-archive_warning_ids:14` | 88,698 |

One query-item builder serves both endpoints, with a test asserting they emit
identical parameters, so the two screens cannot drift into answering different
questions about the same fandom.

**Trade-off, stated deliberately:** AO3 serves tag lists `no-cache` where it serves
`/works/search` `max-age=600`, so paging back and forth on Browse re-fetches. `pace()`
still bounds the rate; the cache only ever saved a repeat.

### Everything else

- **Per-category tag glyphs** — fandom `books.vertical`, character `person`,
  relationship `figure.2`, additional `tag`, warning `exclamationmark.triangle`.
  Chosen against the stat row's vocabulary, which shares the screen (`heart` is kudos,
  `person.2.fill` is the AO3 category). The card's heading carries its subject's own
  glyph, derived **for free** from the works already on the page — every work there
  carries the subject tag, and the blurb parser has already sorted each work's tags by
  AO3's markup classes.
- **Work-card status chips** — rating, category, warnings, completion as capsules,
  separated from the counts below. Android had none of these at all; that gap is closed.
- **Subscription cards fill in** — AO3's subscriptions page lists only title, id and
  author. Metadata is fetched per row as it appears, never as a batch: 20 works would
  be 20 paced requests before anything rendered.
- **Carousel shelf bands** on Home/Library, Apple Books style. Every shelf, not
  alternating: alternation needs each section's ordinal and breaks the moment one is
  conditional.
- **Filter sheet** — Apply top right, Reset top left, drag handle between.
- **Pagination redesigned** — see below.
- **Android exclusion parity** — `excluded_tag_names` instead of `-"tag"` phrase
  syntax, which over-excluded, skipped canonical resolution, and interpolated user text
  into query syntax **with no escaping at all**.
- **Android was discarding imported filters** — an iOS saved search's `language` is an
  object where Android declared a `String`; the type mismatch made `decode()` return
  *default filters*, silently throwing away query, fandom, ratings, everything.

### Pagination — the design argument

The old control was AO3's web bar (`1 … 5 6 7 … 142`) ported verbatim. Numbered bars
answer a problem the web has and iOS doesn't: no gesture layer, no sheets, and a mouse
that can hit a 20px target. On a phone it spent a full row on ten tap targets, eight of
which are wrong, and still couldn't reach page 2,731 of 5,000.

Split along the line first-party apps split on:

- **Common — one page at a time.** Two chevrons, and that is the whole visible control
  (Books' chapter navigation, Photos' day stepper).
- **Rare — somewhere far away.** The centre reads `Page 3 of 5,000` and opens a
  scrubber (Books' "Go to Page", the Music scrubber). A thumb crossing 300pt addresses
  5,000 pages; a rail of pills does not.

The bar now states position in words — which the numbered version only implied — and
spends no chrome on a jump made once a session.

**The slider does not load while you drag.** Pagination is a network fetch; a
live-bound slider would fire a request per tick and rate-limit the reader out of AO3 in
one gesture. The sheet holds a draft, previews it, commits once. That constraint is
what makes a slider affordable here at all.

Native throughout: `.disabled` rather than hand-rolled disabled colours,
`.regularMaterial`, `.contentTransition(.numericText())` so digits roll rather than
cut, `.sensoryFeedback(.selection)` on the page *actually changing* so a tap on a
disabled edge stays silent, and an `accessibilityAdjustableAction` so VoiceOver can
page with a swipe. Animations gated on Reduce Motion. The pagination *logic* —
`navigationPage`, `compactPageWindow`, `abbreviate` — is unchanged and still
unit-tested; `compactPageWindow` now drives the scrubber's fine-adjust row, the same
"current page and its neighbours" question it always answered.

---

## 3. Adversarial review — bugs found in my own work

Five defects, all fixed. Four were in code written this session.

### A. Android's `browseBaseline()` was dead code — the iOS fix never landed there
**Severity: high.** I put Date Updated in the *repository*, behind a
`filters ?: browseBaseline()` fallback. But `FandomWorksScreen` holds its own filter
state, initialises it to `AO3SearchFilters()` and always passes it — so the fallback
never fired. RELEVANCE sends no `sort_column`, AO3's tag listing sorts by `revised_at`
regardless, and the sheet claimed "Best Match" over date-ordered results. Exactly the
regression the iOS change fixed, still live on Android because the baseline sat one
layer too low.
**Fix:** the screen seeds and resets from it, and its sheet no longer offers Best Match.

### B. The filter-button badge would light with no filters set
**Severity: medium. Caught by an existing test**, which is the reason it is listed as
caught rather than shipped. `summaryLabels` always ends with the sort so the card is
never empty — but `activeFilterChips` fed Android's badge, so reusing it would have
reported "1 filter" on a screen with none.
**Fix:** badge counting is its own function with its own meaning — what the user
actually changed.

### C. The enricher's in-flight path returned the wrong value
**Severity: medium.** A second row asking for a work already being fetched awaited the
shared task and returned its **raw** result, skipping the merge that restores the
listing's title and author, and never caching. Two rows showing one work could
disagree about its title.
**Fix:** await the shared task, then fall through to the same merge and cache.

### D. A stepped Material slider would draw ~5,000 tick marks
**Severity: medium.** `steps = totalPages - 2` is 4,998 ticks for a full AO3 list — a
solid smear, and a lot of them to lay out.
**Fix:** continuous slider, readout rounds.

### E. The card advertised a sort that isn't applied
**Severity: low.** `TagWorksView` refines the loaded page in place and its panel
deliberately hides Sort (re-ordering needs a fresh query) — yet the card showed
"Sort: Best Match", naming a control the user cannot reach.
**Fix:** `summaryLabels(includesSort:)` now matches the panel.

### Checked and found correct
- iOS `FandomWorksView`'s filter button uses `hasExtraFilters` (compares to the
  baseline), so seeding the sort did **not** make it read permanently active — the
  same bug as (A) in a place where it happened not to apply.
- `isSparse` cannot fire on a normal list: rating, chapters *and* fandoms blank
  together is a subscription blurb, never a parsed search blurb.
- The enricher's actor state is safe under concurrent rows; the post-await re-check is
  load-bearing.
- Carousel banding survives a hidden section, which alternation would not.

---

## 4. Environment issue worth knowing

`android/app/build` accumulates macOS-style duplicate files (`WorkStatIcons 2.class`) —
847 of them at one point — which fails `dexBuilderDebug` with "Type … is defined
multiple times". **The source tree is clean**; only build output is affected. Deleting
`find app/build -name "* [0-9].*" -delete` fixes it, and it recurred across the
session, so something is duplicating files under `~/Documents`. Worth chasing
separately — it will keep biting Android builds.

Also: `PDFWorkConverterTests.extractsProseAndRejoinsHardWrappedLines()` failed **once**
and passed on re-run and in every clean verify since. Nothing in this batch touches PDF
code. Flagged as a possible flake, not investigated.

---

## 5. Still open

1. **Nothing is pushed.** 16 iOS commits, 7 Android.
2. **The signed-in header check** — nobody has fetched `/users/<n>/bookmarks` while
   genuinely signed in. If it stays `public` there, S3's residual eviction window is
   worth closing properly.
3. **No UI was driven.** Everything visual is verified by build, tests and live
   transport measurements; the iOS build is installed on the paired iPhone but no
   screen was watched. Android is **not** installed anywhere.
4. **Android's `AO3WorkMetadata` has no `isComplete`**, so an enriched subscription
   card shows "Unknown" completion where iOS shows the real state.
5. **The exclusion *semantics*** still have no test on either platform — only that the
   parameter is emitted.
