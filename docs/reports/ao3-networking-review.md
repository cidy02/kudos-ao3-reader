# AO3 Networking Change Review

**Reviewed range:** `29cd9158..b9d70515` (7 commits, 35 files, ~2 900 insertions).
**Reviewed tree:** worktree `ao3-networking-review-3377ae`, branch `claude/ao3-networking-review-3377ae`, HEAD `b9d70515`.
**Date:** 2026-08-06. All live checks below were run today against `archiveofourown.org`.
**Method:** static reading of the full range; re-execution of every live check the
prior audit's appendix depends on, plus ~30 new live queries; four purpose-built
Swift probes against live AO3 (response caching, cancellation propagation, URL
determinism, ephemeral-session disk behaviour); otwarchive source cross-check
(`work_query.rb`, `query.rb`, `work_search_form.rb`, `bookmarks_helper.rb`, the
bookmark blurb templates); a full `Scripts/verify.sh` run; and hand
mutation-testing of the new test suite, one full 911-test run per mutation.

**The review itself changed no code.** The findings were then fixed in separate
follow-up commits at the maintainer's request — see
[Remediation status](#remediation-status) at the end for what landed, what
changed on contact with a compiler, and the two items deliberately left alone.

---

## Executive Summary

### Is this change safe to keep on the branch?

**Yes, with three fixes first.** The implementation is competent and most of it
is genuinely correct — I verified the parts that were easiest to get wrong
(AO3's parameter contract, the `Language` wire format, the backup format's
two-way compatibility, the cancellation chain reaching `URLSession`) and they
hold up. The one item the implementing agent flagged as knowingly unvalidated,
F6's Elasticsearch escaping, **is correct**; I confirmed it live and it fixes a
real, demonstrable query-corruption bug.

The problems are concentrated in the caching change (F8) and in one
over-broad parse guard (F9), and they share a cause: both were validated against
a model of AO3 rather than against the requests the app actually sends.

### What must be fixed before it goes further

1. **[R1, High] `view_adult=true` makes AO3's responses uncacheable, so F8's
   caching win does not exist on the search path.** F7 and F8 landed in the same
   commit and cancel each other out. AO3 serves `/works/search` as
   `max-age=600, public` — but add `view_adult=true` and it becomes
   `private, max-age=0, no-store, no-cache, must-revalidate`. Search results are
   byte-identical either way, so F7 bought nothing and cost everything F8 was for.
2. **[R2, High] Pull-to-refresh now returns a cached page with no network round
   trip** on every surface whose URL *is* cacheable — series pages,
   `/users/*/works`, `/users/*/bookmarks`, `/collections` (measured per
   endpoint). The app even has an explicit `bypassCache` flag for refresh; the
   new `URLCache` sits underneath it, un-bypassed. Note R1 and R2 must be fixed
   **together**: fixing R1 alone makes search and browse stale-refresh surfaces too.
3. **[R3, High] F9's new `AO3Error.parse` throw breaks bookmarks pages** whose
   bookmarks are all series, external works, or deleted items. That is an
   ordinary user state, and I reproduced the exact page shape on live AO3.

### Confidence in the previous agent's audit, and in its implementation

| | Assessment |
|---|---|
| **The audit (`2af2985e`)** | **High.** Its 11 findings are all real; none invented or overstated. Its constant-by-constant verification against live AO3 was accurate and I could reproduce it. Its caveats were placed correctly — it explicitly gated F8 on measuring headers and explicitly marked F6's escape sequence unverified, and both cautions turned out to be the right ones. Its blind spot is exactly the one the task predicted: auditing a snapshot that already contained its own three prior commits, it never questioned `Language`, `bookmarks`, or the reader KVO. |
| **The implementation (`5f071776`, `b9d70515`)** | **Medium.** Seven of the eleven fixes land cleanly (F1, F2, F4, F5, F6, F10, F11). One is only partly effective (F3 — the round trips really are cancelled, the latency saving isn't). Three need rework (F7, F8, F9), and the first two only because they interact: each is defensible alone and they cancel out together. The pattern is consistent — every fix that stayed inside the code is right; the three that depended on a claim about AO3's *behaviour* are the three that went wrong, because that claim was measured on the wrong request shape (F7/F8) or reasoned from one caller of two (F9). Separately, three code comments state as fact things that are demonstrably false (R1, R5, R11) — the code is mostly right, the stated reasons are not, and on this codebase the comments are load-bearing documentation. |

The un-audited commits came out **better than expected**. `Language`'s wire
format really is unchanged, the backup format really is compatible both ways,
and the KVO has no retain cycle. The genuine defects found there are minor
(R9) or are test-coverage gaps (R8) rather than data-safety problems.

---

## Review of the Previously Un-Audited Commits

`0c71a730`, `cd8f8a32`, `30322553`, `72267fea` — reviewed here for the first time.

### `0c71a730` — `Language` enum → struct, `ChapterCount`, cross-platform fixes

**The persistence claim checks out.** The pre-change type
(`29cd9158:AO3Models.swift:397`) was `enum Language: String` whose raw values
were AO3's own `language_id` codes (`case english = "en"`, `case portuguese =
"ptBR"`, `case any = ""`). The replacement
([AO3Models.swift:650](kudos-ao3-reader/Models/AO3Models.swift:650)) encodes and
decodes through a `singleValueContainer` carrying the bare `id` string. Old
payload `"en"` → new `Language(id: "en", title: "English")`; old `""` → `.any`.
**The wire format is byte-identical**, and the new type is strictly *more*
lenient than the old one: an unrecognised code now decodes to
`Language(id: code, title: code)` where the old enum would have thrown.

I checked the list itself against AO3 rather than trusting the count. The live
`/works/search` form's `language_id` select has **163 options (1 blank + 162
languages)**; the app has 162 `rawList` entries plus `.any` = 163, no duplicate
ids, no duplicate titles, and the first entry matches AO3's first entry exactly
(`("so", "af Soomaali")`). The list is complete and correct. The "168-entry"
figure repeated in the audit and in the code comment is wrong — it is 162 — see
[R11](#r11--factual-errors-in-the-audit-and-in-code-comments).

`ChapterCount` is new, decoded with `decodeIfPresent(...) ?? .any`
([AO3Models.swift:240](kudos-ao3-reader/Models/AO3Models.swift:240)), and its
`single_chapter=1` value matches the live form. Correct.

### `cd8f8a32` + `72267fea` — reader scrollbar KVO

No retain cycle: the observation closure captures only its parameters, and
`NSKeyValueObservation` holds its observed object weakly, so nothing here keeps
a dead spread view alive. The `72267fea` swap from `ObjectIdentifier` keys to
`NSMapTable.weakToStrongObjects()` is a real improvement and its stated
rationale (address reuse after a spread deallocates) is sound.

Two residual notes, both minor: `weakToStrongObjects` is the one configuration
Apple explicitly cautions against, because the strong values for zeroed weak
keys survive until the table resizes ([R9](#r9--weak-to-strong-nsmaptable-retains-dead-kvo-tokens-until-it-resizes));
and `restoreNativeScrollIndicators` walks the whole view hierarchy on every
SwiftUI update. Neither is a correctness problem. **Neither commit added a
single test** (`@Test` count is 885 at both `30322553` and `72267fea`), so this
UIKit workaround is entirely uncovered — but it is also not practically
unit-testable, so I do not raise it as a finding.

### `30322553` — `bookmarks` added end-to-end

**Both persistence directions verified.**
`KudosBackupManifest.currentVersion` was already `8` at the base commit
(`29cd9158:KudosBackup.swift:224`) and is still `8`, and
`supportedVersions = [1...8]`. So:

- *Old archive → new build*: `bookmarks = try container.decodeIfPresent(Int.self, forKey: .bookmarks) ?? 0`
  ([KudosBackup.swift:541](kudos-ao3-reader/Services/KudosBackup.swift:541)). ✅
- *New archive → old build*: version `8` is in the old build's whitelist, and
  `KudosBackupWork.init(from:)` reads only its declared `CodingKeys`, so the
  unknown `bookmarks` key is silently ignored. ✅

The decision not to bump the version is therefore **correct**, and the reasoning
given for it is correct. This was the single most likely place for a data-loss
bug in the whole range and it is clean.

The merge path is also right: `mergedPositive`
([KudosBackup.swift:2005](kudos-ao3-reader/Services/KudosBackup.swift:2005))
returns `current` whenever `incoming <= 0`, so restoring a pre-`bookmarks`
archive over a work with a known count cannot zero it.

`SavedWork.bookmarks` is a new non-optional `Int` with a default on a SwiftData
`@Model`. The app uses `ModelContainer(for: schema)` with no
`SchemaMigrationPlan` ([MyApp.swift:23](kudos-ao3-reader/App/MyApp.swift:23)),
so this relies on automatic lightweight migration — which handles an added
attribute with a default. `comments` and `hits` were added the same way
earlier, so there is precedent in this store. Acceptable.

What is missing is coverage: nothing asserts that `parseBlurb` actually extracts
`dd.bookmarks`, and nothing round-trips `KudosBackupWork.bookmarks`. See
[R8](#r8--the-bookmarks-addition-has-no-parsing-or-round-trip-test).

### Did auditing its own snapshot cause the audit to miss things?

Yes, but less than feared. The audit's field-coverage table
(`ao3-networking-audit.md:228`) lists `work_search[language_id]` as ✅ with the
note "Full 168-entry list" — accepting its own prior commit's work as
pre-existing fact, including the wrong count. It never asked whether the
`Language` rewrite was wire-compatible; that question only appears because this
review asked it. The answer happened to be "yes".

The more consequential miss is **structural, not per-commit**: the audit reasoned
about `parseWorksList` as if `parseSearchPage` were its only caller, which is
what produced F9's over-broad remedy ([R3](#r3--f9s-parse-failure-throw-breaks-legitimate-bookmarks-pages)).

---

## Verification of the Original Audit

Were the 11 findings real? **All 11 were real.** None invented, none overstated.
Two were understated, and one contained a claim I could refute.

| # | Real? | Notes from this review |
|---|---|---|
| F1 | ✅ Real | 6 fields genuinely missing. Denominator of 22 confirmed live (see below). |
| F2 | ✅ Real | `sort_direction` absent, 2 columns missing. Confirmed against the live form and otwarchive. |
| F3 | ✅ Real | …but its **impact estimate is wrong**. See [R7](#r7--f3s-headline-benefit-the-18-s-latency-saving-is-not-achievable-because-pace-never-releases-a-claimed-slot). |
| F4 | ✅ Real | Unstructured `Task` genuinely does not inherit cancellation. |
| F5 | ✅ Real | Zero coverage confirmed at the base commit. |
| F6 | ✅ Real | **Confirmed live**: the unescaped form corrupts the query badly (see below). |
| F7 | ✅ Real (divergence) | The divergence existed. But the audit's preferred remedy was the wrong one — see [R1](#r1--view_adulttrue-makes-ao3s-responses-uncacheable-nullifying-the-caching-change). |
| F8 | ⚠️ Real but mis-premised | "No `URLCache` is configured" — the report already self-corrects this. The deeper problem is that the header measurement was taken on a URL shape the app never sends. |
| F9 | ✅ Real | The silent-degradation risk is real. The proposed remedy is unsound for one of the two callers. |
| F10 | ✅ Real | Correctly assessed as "document, do not change". |
| F11 | ✅ Real | Trivial, correctly prioritised P4. |

**Was anything missed?** Yes — four things, none of which the audit's method
would have surfaced, because all four require running the code or the request:

- The `view_adult` × `Cache-Control` interaction (R1) — needs a live header
  measurement of the *post-fix* URL.
- The refresh-vs-cache interaction (R2) — the audit *did* flag it as a risk
  ("needs an explicit invalidation story for pull-to-refresh") and then the
  implementation shipped without one.
- `parseWorksList`'s second caller (R3) — needs a caller census.
- Query-item order instability (R6) — needs to be run more than once.

**A claim I can refute.** The audit and the shipped comment both assert that on
relevance sort "a direction is meaningless". AO3 honours it:

| Request | First three work ids |
|---|---|
| no sort params (what the app sends for `.relevance`) | `89979316, 89976191, 89975466` |
| `sort_direction=asc` alone, no column | `7499, 7507, 8480` |
| `sort_column=_score&sort_direction=asc` | `7499, 7507, 8480` |
| `sort_column=_score&sort_direction=desc` | `89979316, 89976191, 89975466` |

So `sort_direction` on `_score` is honoured and reverses the result set.
otwarchive explains why: `sort` applies `direction` to both the sort column and
the `id` tiebreaker (`work_query.rb:277-286`). **The code's behaviour is still
correct** — omitting the direction is the right call, and the comment's *stated
consequence* ("sending one would pin `_score` ascending — worst match first") is
exactly right. Only the word "meaningless" is wrong. Filed under [R11](#r11--factual-errors-in-the-audit-and-in-code-comments).

---

## Verification of the Fixes

| # | Claimed | Verdict | Evidence |
|---|---|---|---|
| F1 | 6 fields added, 15/22 → 22/22 | **Fixed** | All 22 live `work_search[...]` names are emitted by `searchURL`; enumerated in-browser today. |
| F2 | `SortDirection` + 2 columns | **Fixed** | All 10 live `sort_column` values and both `sort_direction` values are reachable and match. |
| F3 | Superseded searches cancelled | **Partially fixed** | Cancellation does reach `URLSession` (proved below). The pacing slot is not released, so the latency saving the finding was justified by does not materialise — [R7](#r7--f3s-headline-benefit-the-18-s-latency-saving-is-not-achievable-because-pace-never-releases-a-claimed-slot). `refreshCurrentResults` is also not itself cancellable — [R10](#r10--refreshcurrentresults-cancels-but-is-not-cancellable). |
| F4 | Reference-counted coalescer cancellation | **Fixed** (over-built) | Works. The identity set is unnecessary and its justification is wrong — [R5](#r5--the-requestcoalescer-identity-set-is-justified-by-a-failure-that-cannot-occur). |
| F5 | `searchURL` extracted + 14 tests | **Fixed** (15 tests, not 14) | Real pure seam, well-shaped assertions. Coverage gaps in [R4](#r4--ten-of-the-seventeen-ao3-ids-are-asserted-nowhere). |
| F6 | `quotedPhrase` escaping | **Fixed — and now live-validated** | See below. This closes the audit's one open assumption. |
| F7 | `view_adult` added to `search()` | **Fixed, and should be reverted** | It achieves parity and breaks caching — [R1](#r1--view_adulttrue-makes-ao3s-responses-uncacheable-nullifying-the-caching-change). |
| F8 | Memory-only `URLCache`, after measuring | **Regressed** | The measurement was of the wrong URL shape ([R1](#r1--view_adulttrue-makes-ao3s-responses-uncacheable-nullifying-the-caching-change)); the cache breaks refresh ([R2](#r2--pull-to-refresh-returns-a-cached-page-with-no-network-round-trip)) and is not identity-partitioned ([R12](#r12--the-urlcache-is-not-partitioned-by-identity)). |
| F9 | Throw on total blurb-parse failure | **Regressed** | Correct for `parseSearchPage`, wrong for `parseBookmarksPage` — [R3](#r3--f9s-parse-failure-throw-breaks-legitimate-bookmarks-pages). |
| F10 | Deliberately unchanged | **Correct** | Range grammar re-verified live. |
| F11 | `DateFormatter` hoisted | **Fixed** | `static let` with `en_US_POSIX` + GMT + IMF-fixdate format; `DateFormatter` parsing is thread-safe and nothing mutates it post-init. |

### F6 — the one flagged unknown, now resolved

The implementing agent named this "the most likely place to find a real, shipped
bug". It isn't — the fix is right. Measured against a fixed corpus
(`work_search[fandom_names]=Naruto`, total **92,493** works):

| `work_search[query]` | Result count | Reading |
|---|---:|---|
| *(none)* | 92,493 | baseline |
| `-"Time Travel"` | 89,676 | control: excludes 2,817 works ✅ |
| `-"He said "hello""` — **the old, unescaped code** | **2,431** | query corrupted; wrongly excludes ~90,000 works |
| `-"He said \"hello\""` — **the new, escaped code** | **92,493** | parsed as one literal phrase matching nothing ✅ |
| `-"Time \"Travel\""` | 89,676 | escaped quotes survive as one phrase (Elasticsearch's analyzer normalises the punctuation, as expected) |
| `-"back\\slash"` | 92,493 | backslash escaping also parses as one phrase ✅ |

Two conclusions: F6 described a **real** bug (the unescaped form is
catastrophically wrong, not marginally wrong), and `\"` is the **correct**
escape for AO3's query parser. The audit's Medium-confidence caveat can be
closed. Backslash-first ordering in `quotedPhrase`
([AO3Models.swift:355](kudos-ao3-reader/Models/AO3Models.swift:355)) is also correct.

---

### The eleven specific claims, adjudicated

| # | Claim | Verdict |
|---|---|---|
| 1 | "Coverage 15/22 → 22/22"; is 22 the right denominator; was skipping the rest right? | **Upheld.** 22 confirmed live (27 form fields − 5 login/CSRF); all 22 emitted. Skipping `series_titles`/`work_types` was right — they are *not* in `WorkSearchForm::ATTRIBUTES` and AO3 silently ignores them (measured). But `excluded_tag_names` and `date_from`/`date_to` **are** accepted and unused — [R14](#r14--ao3-accepts-excluded_tag_names-and-date_fromdate_to-which-the-app-does-not-use). |
| 2 | "AO3 defaults `sort_direction` to `desc`, so `.descending` preserves prior behaviour exactly" | **Upheld.** Confirmed live (identical top-3 with and without) and at source (`work_query.rb:278`). The default is global, so it held for every column. |
| 3 | "`sort_direction` is only sent with an explicit column, because on relevance a direction is meaningless" | **Behaviour upheld, rationale refuted.** AO3 *does* honour a direction on `_score` and reverses the results. Omitting it is still correct, and the comment's stated consequence is right — only "meaningless" is wrong. [R11](#r11--factual-errors-in-the-audit-and-in-code-comments). |
| 4 | "Superseded searches are now cancelled" — prove it reaches `URLSession` | **Upheld, with a caveat.** Proved: a real `LocalDataTask` is cancelled (`-999`). But the pacing slot is not released, so the 1.8 s latency saving claimed in F3 does not materialise — [R7](#r7--f3s-headline-benefit-the-18-s-latency-saving-is-not-achievable-because-pace-never-releases-a-claimed-slot). |
| 5 | "Memory-only cache, because a disk cache would write mature AO3 HTML out in the clear" | **Upheld, and stronger than it looks.** See below. |
| 6 | "Every new persisted field decodes leniently" | **Upheld.** All 13 checked individually, including the 8 without tests. |
| 7 | The `b9d70515` coalescer change, unsupported by a failing test | **Code fine, justification false.** [R5](#r5--the-requestcoalescer-identity-set-is-justified-by-a-failure-that-cannot-occur). I recommend keeping it and rewriting the comment, not reverting. |
| 8 | "`verify.sh`: ALL GREEN (911 tests)" | **Upheld.** 911/911, 82 suites, 0 skipped/quarantined — but not reproducible in a clean worktree ([R13](#r13--verifysh-cannot-run-in-a-clean-worktree)), and the audit's separate "+22" count is wrong ([R11](#r11--factual-errors-in-the-audit-and-in-code-comments)). |
| 9 | `Language` "encodes/decodes as the bare id string, so the old wire format is unchanged" | **Upheld.** Verified against the actual pre-change enum (`29cd9158:AO3Models.swift:397`), whose raw values were AO3's own codes. Identical wire format, and strictly more lenient on unknown codes. |
| 10 | Adding `bookmarks` to the archive "needs no manifest version bump" | **Upheld.** `currentVersion` was already `8` before the change, so `8` is in the *old* build's whitelist too; and `init(from:)` reads only declared keys, so the extra field is ignored downgrade-wards. Correct in both directions. |
| 11 | Reader scrollbar KVO — retain cycle, leak, fighting Readium | **Upheld.** No retain cycle (the closure captures nothing), no unbounded growth, and the self-set is genuinely self-limiting via the `== false` guard. One cosmetic caveat: [R9](#r9--weak-to-strong-nsmaptable-retains-dead-kvo-tokens-until-it-resizes). |

**Claim 5 in detail**, because the brief asks four separate questions and the
answers are not all the obvious ones:

- *Is the privacy reasoning sound?* **Yes.**
- *Does `.ephemeral` already bound this?* **No — I assumed it would and was
  wrong.** I handed an ephemeral configuration an explicit `URLCache` with
  `diskCapacity: 50 MB` and a real directory, fetched one cacheable AO3 page,
  and **168,924 bytes were written to disk** (`currentDiskUsage: 172376`).
  `.ephemeral` does *not* veto an explicitly-assigned disk cache. So
  `diskCapacity: 0` is **load-bearing**, not decorative, and the reasoning
  behind it is correct. This is the single best-judged line in the caching change.
- *Was there a pre-existing default cache the audit missed?* **Nominally yes,
  functionally no — and this corrects both the audit and my own first answer
  here.** `.ephemeral` does report a default `urlCache` of
  `memory = 512 000, disk = 0`, which is what the audit's self-correction rests
  on. But it is inert: measured, a repeat GET through a stock ephemeral session
  is a full network load and `currentMemoryUsage` stays **0**. Assigning a cache
  is what switches caching *on*, so the change really is 0 → 8 MB. This matters
  practically — it means reverting F8 would genuinely eliminate R2 and R12,
  rather than merely shrinking them.
- *Is 8 MB sensible?* **Yes.** AO3 listing pages measure 33–90 KB, so 8 MB holds
  roughly 90–240 pages — comfortably more than a session's working set, and
  trivial against an iOS app's memory budget.
- One redundancy: `requestCachePolicy = .useProtocolCachePolicy` is a **no-op**.
  Measured, that is already the default on `.ephemeral` (rawValue `0`). Harmless
  and arguably worth keeping as documentation of intent, but it is not doing
  anything.

## Live AO3 Compatibility Re-check

Every check the audit's appendix lists that a finding depends on was re-run
today. AO3 has **not** changed in any way that invalidates the work.

| # | Check | Result | Matches audit? |
|---|---|---|---|
| 1 | `/works/search` distinct `work_search[...]` names | **22** (27 form fields − 5 login/CSRF) | ✅ denominator confirmed |
| 2 | All 22 names emitted by `searchURL` | 22/22 | ✅ coverage claim confirmed |
| 3 | `sort_column` option values | `_score, authors_to_sort_on, title_to_sort_on, created_at, revised_at, word_count, hits, kudos_count, comments_count, bookmarks_count` | ✅ all 10 reachable |
| 4 | `sort_direction` option values | `asc`, `desc` | ✅ |
| 5 | AO3 defaults `sort_direction` to `desc` | `sort_column=kudos_count` alone ≡ `…&sort_direction=desc` (identical top-3); `asc` differs | ✅ **claim 2 confirmed**, and confirmed at source (`work_query.rb:278`) |
| 6 | `language_id` options | 163 (1 blank + 162) — app has 163 | ✅ exact match |
| 7 | Range grammar `> 1000` / `1000-5000` / `< 50` | accepted | ✅ |
| 8 | Field-scoped + negated query syntax | accepted | ✅ |
| 9 | Elasticsearch quote escaping | `\"` correct (table above) | 🆕 **the audit could not check this; now verified** |
| 10 | `Cache-Control` on the URL the app **actually sends** | `private, max-age=0, no-store, no-cache, must-revalidate` | ❌ **contradicts the audit's `max-age=600, public`** — see R1 |
| 11 | `view_adult` changes search results? | No — same 20 work ids, including Explicit works, with and without | 🆕 F7 buys nothing |
| 12 | Bookmarks page can contain zero parseable works | Yes — reproduced a live page with 20/20 series bookmarks | 🆕 see R3 |

Full header matrix for check 10:

```
GET /works/search?…&view_adult=true    → private, max-age=0, no-store, no-cache, must-revalidate
GET /works/search?…                    → max-age=600, public   (+ x-ao3-caching-backend: unicorn_cache_bot)
GET /works/<id>?view_adult=true        → max-age=0, private, must-revalidate
GET /works/<id>                        → max-age=600, public
GET /series/<id>                       → max-age=600, public
GET /users/<name>/works                → max-age=600, public
GET /users/<name>/works?view_adult=true→ max-age=600, public   ← unaffected
GET /tags/<tag>/works                  → no-cache, public      (never cacheable, either way)
GET /tags/<tag>/works?view_adult=true  → no-cache, public      ← unaffected
```

**The `view_adult` penalty does not generalize.** It applies to `/works/search`
and `/works/<id>`, and *not* to `/users/<n>/works` or `/tags/<t>/works` — so
`worksPage(at:)` can keep sending it for free, and only `searchURL` needed the
change. This was measured after the fix landed, because the first version of
that comment speculated the opposite.

---

## Concurrency Review

### Does cancellation actually reach `URLSession`? — Yes. Proved, not read.

I copied `RequestCoalescer` and `pace()` verbatim out of HEAD into a standalone
harness, ran a real AO3 fetch through them, and cancelled the caller 250 ms in.
The caller's error:

```
NSURLErrorDomain Code=-999 "cancelled"
  _NSURLErrorFailingURLSessionTaskErrorKey = LocalDataTask <1B0A4C24-…>.<1>
```

`-999` carrying a failing `LocalDataTask` can only be produced by the
`URLSessionTask` itself being cancelled. So the chain
`SearchView.loadTask.cancel()` → `withTaskCancellationHandler.onCancel` →
`release(cancelled: true)` → `entry.task.cancel()` → `session.data` →
`URLSessionTask.cancel()` is **real and complete**. Claim 4 in the task brief is
verified.

Note the raw error reaching the caller as `URLError`, not `CancellationError` —
this is exactly what `withRetry`'s normalisation
([AO3Client.swift:250](kudos-ao3-reader/Services/AO3Client.swift:250)) exists to
fix, and independently justifies that part of the change.

### Is the `Task.isCancelled` gate correct? — Yes.

`withRetry` runs *inside* the coalescer's shared task, so `Task.isCancelled`
there refers to the shared task — which is precisely the thing `release` cancels.
Ordering is safe: the shared task is cancelled *before* `URLSession` reports
`-999`, so the flag is already true when the gate is evaluated. A `URLError
.cancelled` arriving without `Task.isCancelled` would fall through to the generic
`catch`, where `retryDelay` returns `nil` (`.cancelled` is deliberately absent
from `transientURLErrorCodes`) and the error is rethrown — the right behaviour,
and it has a test.

### Coalescer race analysis

I worked through the races the brief names. None of them bite:

- **Double release.** A cancelled waiter does reach `release` twice. Harmless —
  see [R5](#r5--the-requestcoalescer-identity-set-is-justified-by-a-failure-that-cannot-occur) for why, and why the stated justification for the fix is wrong.
- **Late release evicting a newer round.** Guarded by `entry.task == task`
  ([RequestCoalescer.swift:67](kudos-ao3-reader/Services/RequestCoalescer.swift:67)). Correct and necessary.
- **New waiter joining while another cancels.** `release` runs entirely inside
  the actor, and it clears `inFlight[key]` *before* calling `cancel()`, so a
  caller arriving after cancellation always starts a fresh task. Correct.
- **Pre-cancelled caller.** The shared `Task` is unstructured and does not
  inherit cancellation, so it starts; `withTaskCancellationHandler` then fires
  `onCancel` immediately and the sole-waiter path cancels it. Self-correcting.
- **Entries leaking in `inFlight`.** Every exit path releases. No leak found.
- **A cancelled waiter hanging.** `Task.value` is not resumed by the *waiter's*
  cancellation, so a cancelled waiter stays suspended until the shared task
  finishes. In the sole-waiter case that is guaranteed to happen, because the
  `onCancel` release cancels it. With other waiters present, it waits for the
  real result — which is the intended coalescing semantics.

### Ordering of the `Task {}` inside `defer` vs `onCancel`

The brief asks whether these can be reordered harmfully. They cannot, and the
reason is worth recording because it is not obvious: the `defer`'s release can
only be scheduled *after* `try await task.value` returns, i.e. after the shared
task has completed. So in the sole-waiter cancellation case the `onCancel`
release necessarily runs first — it is what causes the completion the `defer`
is waiting on.

---

## Persistence & Migration Review

Three formats changed; all three are safe. Verified individually rather than as
a group.

### 1. `AO3SearchFilters` inside `SavedSearch` (SwiftData, `Codable`)

Every field added across the whole range decodes leniently. I checked all
thirteen, not just the ones with tests
([AO3Models.swift:221-260](kudos-ao3-reader/Models/AO3Models.swift:221)):

| Field | Added in | Decode | OK |
|---|---|---|:--:|
| `chapterCount` | `0c71a730` | `decodeIfPresent ?? .any` | ✅ |
| `title`, `creators` | `5f071776` | `decodeIfPresent ?? ""` | ✅ |
| `hitsFrom/To`, `kudosFrom/To`, `commentsFrom/To`, `bookmarksFrom/To` | `5f071776` | `decodeIfPresent ?? ""` | ✅ (8/8) |
| `sortDirection` | `5f071776` | `decodeIfPresent ?? .descending` | ✅ |
| `language` (type changed) | `0c71a730` | strict `decode`, but wire format unchanged | ✅ |
| `sort` (cases added) | `5f071776` | strict `decode`; `String` raw values, existing cases untouched | ✅ |

`Sort` gained `creator` and `workTitle` *in the middle* of the case list, which
would matter for an integer-raw-value enum but does not here: the raw values are
the case names, so `"dateUpdated"` still decodes to `.dateUpdated`. Checked.

`hasActiveFilters` and the reset path (`AO3SearchFilters(query:)`) both cover
every new field, so the new fields persist, reset, and round-trip correctly.

### 2. `SavedWork.bookmarks` (SwiftData `@Model`)

Additive non-optional attribute with a default, no `SchemaMigrationPlan`,
handled by automatic lightweight migration. Precedent exists in the same model
(`comments`, `hits`). Acceptable, untested, unchanged risk profile.

### 3. `KudosBackup`'s `ArchivedWork`

Verified in both directions — see the `30322553` section above. **The decision
not to bump the manifest version is correct.** Claim 10 in the task brief is
confirmed, including the `supportedVersions` whitelist reasoning: `8` was
already `currentVersion` before the change, so an old build accepts a new
archive and ignores the unknown key.

### Round-trip lossiness and downgrade

Nothing round-trips lossily. Downgrade *is* a real scenario for this app —
`KudosBackup` archives are explicitly portable across devices and installs, and
the sync directory carries manifests between builds — which is why the two-way
check mattered. It passes.

---

## Test Quality Assessment

`Scripts/verify.sh` — **ALL GREEN, 911 tests in 82 suites, 0 skipped, 0
quarantined.** Reproduced today (log in the scratchpad). Claim 8 confirmed.

Two caveats on that:

- **It does not run in a fresh worktree.** `Vendor/MuPDF.xcframework` is
  gitignored and must be built with `Scripts/build-mupdf.sh`; without it the run
  dies at stage 3/5 with `There is no XCFramework found at …`. I had to symlink
  it from a sibling worktree. Not caused by this change, but "ALL GREEN" is not
  reproducible from a clean checkout — see [R13](#r13--verifysh-cannot-run-in-a-clean-worktree).
- The audit reports "885 → 907 (+22)". Actual: 885 → **910** at `5f071776` →
  **911** at `b9d70515`. Undercounted; see R11.

**No test file was clobbered.** I compared `@Test` counts per file at
`29cd9158` vs HEAD: every file gained or held. Nothing was deleted. The
implementing agent's self-reported `Write`-clobber incident left no trace.

### Do the tests assert AO3's contract, or just what the code emits?

Mostly the contract — `SearchURLTests` pins literal parameter names and literal
AO3 ids, and asserts against a parsed `[name: [value]]` dictionary rather than a
URL string, which is the right shape. But **the id coverage is partial**, and
that is exactly the failure mode the brief asked about.

Hand mutation-testing — one deliberate break at a time, **full 911-test suite run
per mutation**, source restored after each (worktree verified clean afterwards):

| # | Mutation | Result | Caught by |
|---|---|---|---|
| M1 | `Category.multi` id `"2246"` → `"246"` | 🔴 **SUITE STILL GREEN** | *nothing* |
| M2 | `work_search[freeform_names]` → `work_search[freeform_name]` | ✅ caught | `tagFieldsUseAO3sNameParameters` |
| M3 | `SortDirection.descending.value` `"desc"` → `"asc"` | ✅ caught | `sortSendsColumnAndDirectionTogether` |
| M4 | `Warning.violence` id `"17"` → `"117"` | ✅ caught | `warningsAndCategoriesUseBracketedMultiValueParameters` |
| M5 | `rangeExpression` `"> \(lower)"` → `">\(lower)"` (drops AO3's space) | ✅ caught | `rangeExpressionCoversBothBoundsAndNeither` |
| M6 | Disable F9's parse-failure throw | ✅ caught | `blurbsPresentButNoneParseableThrowsInsteadOfLookingEmpty` |

**5 of 6 caught.** The tests are genuinely load-bearing — every parameter name,
every *asserted* id, the range grammar's easily-lost space, and F9's new throw
are all pinned, and each failure named exactly the right test. M4 is the useful
control: it is the same *kind* of mutation as M1 and it was caught, which shows
the test style works and that M1's survival is purely a breadth gap, not a
design flaw.

M1 is the brief's own hypothetical and it survives untouched — see
[R4](#r4--ten-of-the-seventeen-ao3-ids-are-asserted-nowhere).

### Is anything asserted only through its own helper?

`SearchURLTests.params(_:page:)` is a thin adapter over
`URLComponents.queryItems` — it cannot mask a bug in `searchURL` because it does
no interpretation. `SearchFiltersTests` asserts `searchQuery` as a literal
string. No self-referential assertions found.

### What is not covered

1. **Ten of the seventeen AO3 ids** — [R4](#r4--ten-of-the-seventeen-ao3-ids-are-asserted-nowhere).
2. **The `bookmarks` stat** — no parse test, no backup round-trip test — [R8](#r8--the-bookmarks-addition-has-no-parsing-or-round-trip-test).
3. **`parseBookmarksPage` with non-work bookmarks** — the gap that let R3 through.
   `AO3ClientTests.bookmarksHTML` contains one bookmarked *work* only.
4. **Cache behaviour** — the two new `AO3ClientPolicyTests` assert the
   *configuration* (`diskCapacity == 0`, `requestCachePolicy`). Nothing asserts
   what the configuration *does*, which is why R1 and R2 shipped.
5. **URL stability** — the tests deliberately assert order-independently, so
   R6 is invisible to them.
6. **The reader KVO** — zero tests, from either commit that touched it.

The coalescer tests deserve specific credit: `coalescingSurvivesAMidFlightCancellationByAnotherWaiter`
carries an inline "Honest note" admitting it passes against the implementation
it was written to replace. That is the right thing to write down, and my
independent analysis agrees with it ([R5](#r5--the-requestcoalescer-identity-set-is-justified-by-a-failure-that-cannot-occur)).

---

## New Findings

### R1 — `view_adult=true` makes AO3's responses uncacheable, nullifying the caching change

- **Severity**: High
- **Location**: [AO3Client.swift:367](kudos-ao3-reader/Services/AO3Client.swift:367) (`searchURL`, F7's fix); [AO3Client.swift:60-73](kudos-ao3-reader/Services/AO3Client.swift:60) (`makeAnonymousSessionConfiguration`, F8's fix)
- **Description**: F7 and F8 landed in the same commit and cancel each other
  out. F8's entire justification is that AO3 serves listing pages
  `Cache-Control: max-age=600, public`. That is true — but only for a request
  *without* `view_adult`. F7 added `view_adult=true` to every search URL, which
  flips AO3 to a no-store response. The comment at
  [AO3Client.swift:60](kudos-ao3-reader/Services/AO3Client.swift:60) states the
  cacheable header as present-tense fact and cites the exact scenario ("paging
  back and forth — 1 → 2 → 1 — into one round trip instead of three") that the
  code sitting five lines away makes impossible.
- **Evidence** (live, 2026-08-06, app User-Agent, `GET`):

  ```
  /works/search?work_search[fandom_names]=Naruto&view_adult=true&page=1
    → cache-control: private, max-age=0, no-store, no-cache, must-revalidate, post-check=0, pre-check=0

  /works/search?work_search[fandom_names]=Naruto&page=1
    → cache-control: max-age=600, public
      potential_upstream: unicorn_cache_bot
      x-ao3-caching-backend: unicorn_elastic_bot, unicorn_cache_tmpfs
  ```

  Reproduced with a second, unrelated query (`work_search[query]=love`) — same
  flip. The same applies to work pages: `/works/<id>` is `max-age=600, public`,
  `/works/<id>?view_adult=true` is `max-age=0, private, must-revalidate`.
  A Swift probe using the app's exact session config confirms the end result:
  two identical search GETs both report `resourceFetchType == .networkLoad`.

  And `view_adult` **changes nothing** about the results — same 20 work ids in
  the same order, including Explicit-rated works, with and without it (query:
  `fandom_names=Naruto&rating_ids=13`).
- **Impact**: The 8 MB cache delivers zero benefit on the search path — the path
  its own comment names — and on work/chapter pages. It still helps `/series/`,
  `/users/*/works` and author profiles, which is where R2's damage lands. The
  net effect of the two fixes together is: no latency win, plus a broken refresh.
- **Root Cause**: The header was measured before F7 was written, and never
  re-measured after. Neither fix's test exercises a real request.
- **Recommended Fix**: **Revert F7** — drop `view_adult=true` from `searchURL`,
  and instead correct the misleading comment in `worksPage(at:)`, which was the
  audit's own stated alternative. It restores the cacheable header, costs
  nothing (the results are identical), and makes F8's comment true.
  - *Alternative considered*: keep `view_adult` and delete the `URLCache`. Also
    coherent, but throws away a real win on the paths that do cache, and
    `view_adult` demonstrably buys nothing on a listing page.
  - *Alternative considered*: keep both and accept the dead cache. Rejected —
    it leaves a comment that is actively false and an 8 MB allocation doing
    nothing on the hot path.
  - Whichever is chosen, **R2 must be fixed too** — reverting F7 makes search
    results cacheable, which makes R2 worse, not better.
- **Scope**: Small (one line + one comment)
- **Risk**: Low. The behavioural equivalence is measured, not assumed. Worth one
  live check against a work that is *restricted to registered users* before
  committing, since that is the one page class `view_adult` might genuinely gate.
- **Dependencies**: Must land together with R2.
- **Priority**: P1
- **Confidence**: **High** — reproduced four times across two query shapes and
  two endpoint types.
- **Verification method**: Live `GET` header inspection + result-set comparison + Swift `URLSessionTaskMetrics` probe.

### R2 — Pull-to-refresh returns a cached page with no network round trip

- **Severity**: High
- **Location**: [AO3Client.swift:72-73](kudos-ao3-reader/Services/AO3Client.swift:72); every `.refreshable` that reaches a cacheable AO3 URL. Measured per-endpoint rather than assumed:

  | Surface | URL | `Cache-Control` today | Affected? |
  |---|---|---|:--:|
  | [AO3SeriesDetailView.swift:74](kudos-ao3-reader/Features/Authors/AO3SeriesDetailView.swift:74) | `/series/<id>` | `max-age=600, public` | **yes** |
  | [AO3AccountWorksList.swift:299](kudos-ao3-reader/Features/Bookmarks/AO3AccountWorksList.swift:299) | `/users/<n>/works`, `/users/<n>/bookmarks` | `max-age=600, public` | **yes** |
  | [AO3CollectionsList.swift:78](kudos-ao3-reader/Features/Account/AO3CollectionsList.swift:78) | `/collections` | `max-age=600, public` | **yes** |
  | [AuthorProfileView.swift:190](kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:190) | `/users/<n>/profile` | `private, max-age=0, no-store, …` | no |
  | [NativeBrowseView.swift:107](kudos-ao3-reader/Features/Browse/NativeBrowseView.swift:107) | `search()` / `worksPage(at:)` — both force `view_adult` | uncacheable | **not yet** — see below |
  | [SearchView.swift:243](kudos-ao3-reader/Features/Search/SearchView.swift:243) | `/works/search` — forces `view_adult` | uncacheable | **not yet** — see below |

  The last two are protected only by the very bug R1 describes. **Fixing R1
  without fixing R2 turns search and browse into stale-refresh surfaces too** —
  which is why the two must land together.

  (`/users/<n>/bookmarks` was measured anonymously; the app fetches it
  authenticated, and AO3 may well downgrade it to `private` for a signed-in
  viewer. I could not test that without credentials — see *Unknowns*.)
- **Description**: With `requestCachePolicy = .useProtocolCachePolicy` and a
  live `URLCache`, any AO3 URL answered `max-age=600, public` is served from
  memory for ten minutes. Pull-to-refresh does nothing during that window. No
  call site anywhere sets `.reloadIgnoringLocalCacheData` (`grep` returns
  nothing). The audit named this exact risk — "caching search results risks
  showing stale pages; needs an explicit invalidation story for pull-to-refresh"
  — and the implementation shipped without one.
- **Evidence**: Swift probe using `makeAnonymousSessionConfiguration()` verbatim,
  against `/series/1234`:

  ```
  [initial load  ] NETWORK   200 33389 bytes  CC=max-age=600, public  csrf=33uBLF-_pfpEIC9gqrsX
  [pull-to-refresh] CACHE-HIT 200 33389 bytes  CC=max-age=600, public  csrf=33uBLF-_pfpEIC9gqrsX
  >> identical CSRF token: the refresh returned the cached body, no round trip.
  ```

  The CSRF token is regenerated on every genuine render, so an identical token
  is proof the body was not re-fetched. `URLSessionTaskMetrics.resourceFetchType
  == .localCache` confirms it independently.

  **The app already tries to prevent this and is defeated one layer down.**
  `AO3SeriesDetailView`'s refresh calls `load(page: 1, replace: true,
  bypassCache: true)`, and `bypassCache` skips `AO3AuthorPageCache`
  ([AO3AuthorProfileService.swift:39](kudos-ao3-reader/Services/AO3AuthorProfileService.swift:39))
  — then falls straight into the new `URLCache` beneath it.
- **Impact**: A user who pulls to refresh a series, an author's works, their own
  bookmarks list, or the collections list sees the same content and has no way to
  force a re-fetch short of waiting ten minutes or restarting. This is a silent
  failure of an explicit user gesture — worse than no caching at all, because the
  user's action visibly does nothing. Fixing R1 extends it to search and browse.
- **Root Cause**: A transport-level cache was added without giving the
  refresh gesture a way through it. The existing app-level `bypassCache` flag
  stops at the wrong layer.
- **Recommended Fix**: Thread the existing bypass down to the transport. Add
  `AO3Client.getHTML(_:bypassCache:)` that builds a `URLRequest` with
  `cachePolicy = .reloadIgnoringLocalCacheData` when set, and pass `true` from
  every `.refreshable` path (the call sites already carry the flag; they just
  stop short). The probe confirms this policy forces `NETWORK`.
  - *Alternative considered*: `URLCache.shared.removeAllCachedResponses()` on
    refresh. Rejected — it evicts unrelated entries and is a blunt instrument.
  - *Alternative considered*: drop the cache entirely. Simpler and defensible,
    but forfeits a measured win on the paths that do cache.
- **Scope**: Small-Medium (one new parameter, ~6 call sites)
- **Risk**: Low
- **Dependencies**: Pairs with R1
- **Priority**: P1
- **Confidence**: **High** — reproduced with the app's exact session configuration.
- **Verification method**: Swift probe against live AO3 with `URLSessionTaskMetrics` + CSRF-token fingerprinting.

### R3 — F9's parse-failure throw breaks legitimate bookmarks pages

- **Severity**: High
- **Location**: [AO3Client.swift:1249](kudos-ao3-reader/Services/AO3Client.swift:1249) (`parseWorksList`), reached via `parseBookmarksPage` → [AO3Client.swift:755](kudos-ao3-reader/Services/AO3Client.swift:755) (`bookmarksPage(for:page:)`) → [AO3AccountWorksList.swift:88](kudos-ao3-reader/Features/Bookmarks/AO3AccountWorksList.swift:88)
- **Description**: The new guard infers "blurb elements present but none parsed
  ⇒ the parser broke". That inference is sound for `parseSearchPage`
  (`li.work.blurb`, where AO3 always emits `id="work_<n>"`). It is **false** for
  `parseBookmarksPage` (`li.bookmark.blurb`), where AO3 legitimately renders
  bookmarks of things that are not works. `parseBlurb` cannot parse those and
  throws, so a page of them now fails the whole request instead of returning an
  empty page.
- **Evidence**: otwarchive's own templates settle the mechanism.
  `bookmarks/_bookmark_blurb.html.erb` wraps *every* bookmark in
  `<li id="bookmark_<id>" class="bookmark blurb group …">` and delegates to
  `_bookmark_item_module.html.erb`, which branches four ways:

  | Bookmarkable | Heading link | `parseBlurb` |
  |---|---|---|
  | `Work` | `/works/<id>` | ✅ parses |
  | `Series` | `/series/<id>` | ❌ throws |
  | `ExternalWork` | `/external_works/<id>` | ❌ throws |
  | deleted | *(no heading — `<p class="message">`)* | ❌ throws |

  `parseBlurb` needs either `id="work_<n>"` (never true here — the id is
  `bookmark_<n>`) or `h4.heading a[href^="/works/"]` (absent for the last three).

  Live confirmation, in-browser on AO3 today
  (`/bookmarks/search?bookmark_search[bookmarkable_type]=Series&bookmark_search[bookmarkable_query]=Naruto`):

  ```json
  { "total": 20, "kinds": { "/series": 20 }, "withWorksLink": 0,
    "liIdStartsWithBookmark": 20,
    "sample": [{ "id": "bookmark_2125873087",
                 "cls": "bookmark blurb group series-980460 user-3914382 user-16379482",
                 "href": "/series/980460", "hasWorksLink": false }] }
  ```

  20 `li.bookmark.blurb` elements, zero parseable ⇒ `blurbs.isEmpty == false &&
  works.isEmpty == true` ⇒ **throw**.

  The app fetches `/users/<name>/bookmarks` with no type filter
  ([AO3Client.swift:416](kudos-ao3-reader/Services/AO3Client.swift:416)), so any
  page of a user's bookmarks that happens to hold only series/external/deleted
  entries hits this.
- **Impact**: A user whose bookmarks are series-heavy — or simply whose last page
  of bookmarks happens to be all series — gets a hard error instead of a list,
  and pagination stops there. Before this change they got an empty page (also
  wrong, but recoverable and non-blocking). The regression is real even though
  the pre-existing behaviour was imperfect.
- **Root Cause**: The remedy was designed against one caller. `parseWorksList`
  is shared by two selectors with materially different contracts, and only
  `li.work.blurb` guarantees a parseable work per element.
- **Recommended Fix**: Make the guard the caller's decision rather than the
  shared helper's. Add a `requireParseableBlurbs: Bool` parameter to
  `parseWorksList`, `true` from `parseSearchPage` and `false` from
  `parseBookmarksPage`. Two lines, keeps F9's real benefit exactly where the
  inference holds.
  - *Alternative considered (better, larger)*: teach `parseBlurb` to recognise
    series and external-work bookmarks and skip them explicitly, so "unparsed"
    once again means "broken". This is the right long-term shape and would also
    let the bookmarks screen show series bookmarks instead of dropping them —
    but it is a feature, not a fix, and should not gate this branch.
  - *Alternative considered*: revert F9 entirely. Rejected — the finding is real
    and the guard is correct for search.
- **Scope**: Small
- **Risk**: Low
- **Dependencies**: None
- **Priority**: P1
- **Confidence**: **High** — mechanism confirmed in otwarchive source, page shape
  reproduced live.
- **Verification method**: otwarchive template reading + live DOM enumeration.

### R4 — Ten of the seventeen AO3 ids are asserted nowhere

- **Severity**: Medium
- **Location**: `KudosTests/SearchURLTests.swift`; ids in [AO3Models.swift:425](kudos-ao3-reader/Models/AO3Models.swift:425) (`Warning`), [:453](kudos-ao3-reader/Models/AO3Models.swift:453) (`Category`), and `Rating.ao3ID`
- **Description**: F5's stated purpose is to "pin every parameter name, id and
  multi-value convention" the audit verified by hand. It pins the names and the
  conventions, but only 7 of the 17 ids.

  | Set | Asserted | Unasserted |
  |---|---|---|
  | Ratings | `13`, `11` | `9`, `10`, `12` |
  | Warnings | `14`, `17`, `18` | `16`, `19`, `20` |
  | Categories | `21`, `23` | `116`, `22`, `2246`, `24` |

  The brief's own hypothetical — category `Multi` as `2246` vs `24` — lands
  exactly in the gap.
- **Evidence**: `grep -rn "2246\|\"116\"" KudosTests/` returns nothing. Direct
  demonstration: mutating `Category.multi` from `"2246"` to `"246"` and running
  the **full 911-test suite** leaves it **green**. The control mutation on an
  *asserted* id (`Warning.violence` `"17"` → `"117"`) is caught immediately, so
  this is a coverage-breadth gap, not a weakness in how the tests are written.
- **Impact**: A transcription error in any of ten AO3 ids ships green. Because
  `Category`/`Warning` use the AO3 id as the enum's raw value, such an error is
  also silently persisted into every `SavedSearch` that uses the affected facet.
  The symptom would be "this filter returns the wrong works", which is precisely
  the class of breakage F5 was created to prevent.
- **Root Cause**: The tests were written per-behaviour (multi-value convention,
  exclusion syntax) rather than per-constant.
- **Recommended Fix**: One table-driven test that walks `Rating.allCases`,
  `Warning.allCases` and `Category.allCases` and asserts each `ao3ID` against a
  literal expected map. ~15 lines, closes all ten at once, and gives the next
  AO3 change one obvious place to update.
- **Scope**: Small
- **Risk**: None
- **Dependencies**: None
- **Priority**: P2
- **Confidence**: High
- **Verification method**: `grep` over the test target + full-suite mutation run.

### R5 — The `RequestCoalescer` identity set is justified by a failure that cannot occur

- **Severity**: Medium (documentation correctness; the code is safe)
- **Location**: [RequestCoalescer.swift:20-29](kudos-ao3-reader/Services/RequestCoalescer.swift:20) (`Entry.waiters` doc), [:66-75](kudos-ao3-reader/Services/RequestCoalescer.swift:66) (`release`), and the `b9d70515` commit message
- **Description**: The comment claims a plain counter "would therefore drop by
  two, evicting the entry while another waiter was still registered and silently
  letting the next caller start a duplicate fetch." **That sequence is not
  reachable.** A cancelled waiter's second release comes from the `defer` inside
  the `withTaskCancellationHandler` body — and that `defer` can only run once
  `try await task.value` has returned, i.e. once the shared task has *already
  completed*. At that moment the entry has no value left: any new caller would
  correctly start a fresh fetch anyway, because the coalescer is a de-duplicator,
  not a cache. So the over-decrement can only ever evict a spent entry.
- **Evidence**: The control flow is in the file. `shared` returns
  `try await withTaskCancellationHandler { defer { … }; return try await task.value }`
  — there is no path on which the `defer` fires before `task.value` resolves.
  `Task.value` is not resumed by the *awaiting* task's cancellation. The change's
  own test says as much in an inline "Honest note", and the commit message
  concedes the bug could not be demonstrated.
- **Impact**: None at runtime. The cost is a wrong explanation attached to the
  trickiest code in the file, in a codebase whose comments are otherwise reliable
  enough to be treated as documentation. The next reader will take it at face
  value.
- **Root Cause**: A hazard identified by reasoning about `release` in isolation,
  without the constraint that the two calls cannot interleave arbitrarily.
- **Recommended Fix**: **Keep the identity set, rewrite the comment.** The set is
  five lines longer than a counter and is obviously correct without needing the
  above argument — that is genuine value, just not the value claimed. Replace the
  fabricated failure scenario with the true one: *"A cancelled waiter releases
  twice. With a counter that is provably harmless — the second release cannot run
  until the shared task has finished — but proving it requires an argument about
  `Task.value` resumption. A set makes the second release idempotent by
  construction, so no argument is needed."*
  - *Alternative considered*: revert to the counter (`b9d70515` reverted whole).
    Legitimate and slightly smaller. I do not recommend it: the set costs almost
    nothing and removes a subtle proof obligation from a concurrency path.
- **Scope**: Small (comment only)
- **Risk**: None
- **Dependencies**: None
- **Priority**: P3
- **Confidence**: **High** on the analysis; the code is correct either way.
- **Verification method**: Static analysis against Swift structured-concurrency semantics; corroborated by the change's own test comment.

### R6 — The search URL is not stable for a fixed filter set

- **Severity**: Medium
- **Location**: [AO3Client.swift:332-337](kudos-ao3-reader/Services/AO3Client.swift:332) (`for warning in filters.warnings`, `for category in filters.categories`)
- **Description**: Warnings and categories are emitted by iterating a `Set`.
  Swift's `Set` iteration order is not stable across equal sets — it depends on
  the storage layout, which depends on insertion history and capacity — so the
  same logical filter produces different query-item orders. AO3 does not care.
  `RequestCoalescer` (keyed on the `URL`) and `URLCache` (keyed on the URL) both
  do.
- **Evidence**: Three logically identical `Set`s of the same three enum cases —
  one from an array literal, one built by `insert`, one built by `remove` from a
  larger set — emitted 2 or 3 *distinct* URLs, varying between process runs:

  ```
  run 1: …ids][]=19&…=18&…=17   …ids][]=17&…=18&…=19   …ids][]=17&…=19&…=18   → 3 distinct
  run 2: …ids][]=18&…=19&…=17   …ids][]=17&…=19&…=18   …ids][]=18&…=19&…=17   → 2 distinct
  ```
- **Impact**: Two screens issuing the same filtered search concurrently may not
  coalesce, and a repeated identical search may miss the response cache. Both are
  the exact wins F4 and F8 were built for. The magnitude is bounded — it only
  bites when warnings or categories are selected — but it is invisible, and it
  silently erodes the politeness posture the rest of the layer maintains
  carefully.
- **Root Cause**: Pre-existing (the loops predate this range), but newly
  consequential now that a URL-keyed cache exists.
- **Recommended Fix**: Sort before emitting —
  `for warning in filters.warnings.sorted(by: { $0.ao3ID < $1.ao3ID })`, same for
  categories. Two lines, no behaviour change against AO3, and it makes the
  emitted URL a pure function of the filter set.
  - *Alternative considered*: change the model to `[Warning]`. Rejected — a set
    is the right type for the semantics; only the *emission* needs an order.
  - Add one test asserting that two differently-constructed equal filter sets
    produce identical URLs. The existing tests sort the values before comparing,
    so they are structurally unable to catch this.
- **Scope**: Small
- **Risk**: None
- **Dependencies**: None
- **Priority**: P2
- **Confidence**: **High** on the mechanism (demonstrated directly); Medium on
  how often real users have multiple warnings/categories selected — not measured.
- **Verification method**: Standalone Swift probe, repeated across processes.

### R7 — F3's headline benefit (the 1.8 s latency saving) is not achievable, because `pace()` never releases a claimed slot

- **Severity**: Medium
- **Location**: [AO3Client.swift:127-133](kudos-ao3-reader/Services/AO3Client.swift:127) (`pace()`); `ao3-networking-audit.md` Finding 3 "Impact"
- **Description**: F3 was prioritised P1 on a quantified user-facing claim:
  paging 2→3→4→5 makes the page-5 request "wait out the pacing slots of three
  requests whose results will be thrown away — roughly 1.8 s of avoidable
  latency." Cancelling those requests does not recover that time. `pace()`
  advances `nextAllowedRequestAt` **synchronously, before** it sleeps, and
  nothing rolls it back on cancellation. The slot stays spent.
- **Evidence**: Standalone replication of `pace()` — three claims with one
  cancelled mid-sleep leaves the next free slot **1.10 s away**, i.e. all three
  0.6 s slots consumed. Confirmed in the source: `nextAllowedRequestAt =
  max(now, nextAllowed).addingTimeInterval(minRequestInterval)` runs
  unconditionally, then `Task.sleep` may throw.
- **Impact**: The fix delivers its *politeness* benefit in full — the discarded
  HTTP round trips really are cancelled (proved in the Concurrency Review), so
  AO3 is spared the work and the user's bandwidth is spared. It does not deliver
  the latency benefit that justified its priority. Not a regression; a corrected
  expectation, and worth recording so nobody re-derives the 1.8 s figure later.
- **Root Cause**: The pacer models a reservation, and cancellation was added to
  the request lifecycle without a matching release in the reservation.
- **Recommended Fix**: **Do nothing to `pace()`** unless the latency actually
  matters. Releasing a slot correctly means either rolling `nextAllowedRequestAt`
  back (racy — another caller may have already claimed past it) or maintaining a
  free-list of slots, and both add real complexity to the one piece of this layer
  that is currently simple and provably correct. Amend F3's impact paragraph in
  the audit instead.
  - *Alternative, if measured to matter*: claim the slot *after* the sleep rather
    than before. That reintroduces exactly the actor-reentrancy hazard the
    slot-claiming design exists to avoid. Not recommended.
- **Scope**: Small (documentation) / Large (if actually implemented)
- **Risk**: Low as documentation
- **Dependencies**: None
- **Priority**: P3
- **Confidence**: **High** — reproduced with the pacer's own arithmetic.
- **Verification method**: Standalone Swift replication of `pace()`.

### R8 — The `bookmarks` addition has no parsing or round-trip test

- **Severity**: Medium
- **Location**: [AO3Client.swift:1007](kudos-ao3-reader/Services/AO3Client.swift:1007) and [:1340](kudos-ao3-reader/Services/AO3Client.swift:1340) (`statInt("bookmarks")`); [KudosBackup.swift:365](kudos-ao3-reader/Services/KudosBackup.swift:365), [:541](kudos-ao3-reader/Services/KudosBackup.swift:541)
- **Description**: `30322553` added `bookmarks` through the blurb parser, the
  work-metadata parser, `AO3WorkSummary`, `AO3WorkMetadata`, `AO3WorkTagGroups`,
  `SavedWork`, `KudosBackupWork`, the tag-merge, refresh and queue-import paths,
  and the backup archive format — and added ten tests, none of which touch
  `bookmarks`. `grep` for a `bookmarks` assertion in the parser or backup tests
  returns only unrelated `KudosBackupManifest.bookmarks` (the saved-bookmark
  list, a different concept sharing the name).
- **Evidence**: `grep -rn "\.bookmarks ==" KudosTests/` — no hit against a parsed
  stat or an archived work.
- **Impact**: The two things most worth pinning are unpinned: that
  `dd.bookmarks` is the right selector, and that a `bookmarks` value survives a
  backup export/import cycle.

  The first is worse than it looks. I confirmed live that AO3 emits the blurb's
  `dl.stats` as `language, words, chapters, [comments], [kudos], [bookmarks],
  hits` and **omits the `<dd>` entirely when a count is zero** — only 5 of 20
  blurbs on a sample page carried `dd.bookmarks`. `statInt` selects by class, so
  the omission is handled correctly; but it also means a *wrong class name*
  (`dd.bookmark`, say) would return `nil` on every work, which is
  indistinguishable from AO3's own legitimate absence. The stat would silently
  read as "unknown" forever, with nothing failing.
- **Root Cause**: Coverage was added for the visible UI change (14 new
  `WorkStatLabelTests`, all formatting) rather than the data path underneath it.
- **Recommended Fix**: Extend the existing blurb fixture in `AO3ClientTests` with
  a `<dd class="bookmarks">` and assert the parsed value; add `bookmarks` to one
  existing `KudosBackupTests` round-trip assertion. Both are one-line additions
  to tests that already exist.
- **Scope**: Small
- **Risk**: None
- **Dependencies**: None
- **Priority**: P2
- **Confidence**: High
- **Verification method**: `grep` over the test target; live confirmation of AO3's blurb stat order.

### R9 — Weak-to-strong `NSMapTable` retains dead KVO tokens until it resizes

- **Severity**: Low
- **Location**: [ReadiumNavigatorContainer.swift:430-431](kudos-ao3-reader/Features/ReaderReadium/ReadiumNavigatorContainer.swift:430)
- **Description**: `NSMapTable.weakToStrongObjects()` is the one configuration
  Apple's own documentation cautions against: *"the strong values for weak keys
  which get zeroed out remain until the map table resizes itself."* So each
  destroyed spread's `NSKeyValueObservation` is retained past its scroll view's
  death, and is not invalidated at that point either.
- **Evidence**: Apple's `NSMapTable` class reference; the code holds
  `NSKeyValueObservation` as a strong value against a weak `UIScrollView` key.
- **Impact**: Negligible in size — an `NSKeyValueObservation` is small and the
  table self-drains on resize. Lookups are still *correct*: a zeroed weak key
  cannot match a new object at a reused address, so the address-reuse hazard that
  `72267fea` was written to fix really is fixed. This is a cleanliness note on an
  otherwise well-reasoned change, not a defect.
- **Root Cause**: Inherent to the chosen collection.
- **Recommended Fix**: Leave it. If it ever matters, invalidate explicitly on
  teardown by draining the table in the coordinator's `deinit`. Do not switch to
  `weakToWeakObjects` — the observation would then be deallocated immediately and
  observation would silently stop, which is the bug the map table exists to avoid.
- **Scope**: Small
- **Risk**: Low
- **Dependencies**: None
- **Priority**: P4 — document, do not change
- **Confidence**: High on the mechanism; **Low** that it is worth acting on.
- **Verification method**: Static analysis + Apple documentation.

### R10 — `refreshCurrentResults` cancels, but is not cancellable

- **Severity**: Low
- **Location**: [SearchView.swift:749-751](kudos-ao3-reader/Features/Search/SearchView.swift:749)
- **Description**: `refreshCurrentResults()` calls `loadTask?.cancel()` but never
  assigns itself to `loadTask`. A `load(page:)` started while a refresh is in
  flight therefore cancels only the *previous, already-finished* load — the
  refresh runs to completion and spends a full pacing slot ahead of the request
  the user is waiting for. This is the same defect F3 was written to remove, on
  the one path F3 did not cover.
- **Evidence**: `loadTask` is assigned only at
  [SearchView.swift:724](kudos-ao3-reader/Features/Search/SearchView.swift:724),
  inside `load(page:)`.
- **Impact**: Small. `.refreshable`'s task is still cancelled by SwiftUI on
  disappear, so the unbounded case is covered; the gap is only "user refreshes,
  then immediately taps a page". The token check keeps the result correct.
- **Root Cause**: `refreshCurrentResults` is `async` and driven by
  `.refreshable`, so it has no `Task` of its own to store — the fix for
  `load(page:)` did not transfer.
- **Recommended Fix**: Wrap the body in a stored task —
  `loadTask = Task { … }; await loadTask?.value` — so both paths share one
  cancellation slot. Roughly four lines.
  - *Alternative considered*: leave it. Defensible; the impact is genuinely small.
- **Scope**: Small
- **Risk**: Low
- **Dependencies**: None
- **Priority**: P3
- **Confidence**: High
- **Verification method**: Static analysis of the complete call path.

### R11 — Factual errors in the audit and in code comments

- **Severity**: Low
- **Location**: `docs/reports/ao3-networking-audit.md` (field table, verification section); [AO3Client.swift:357-359](kudos-ao3-reader/Services/AO3Client.swift:357) (`sort_direction` comment)
- **Description**: Four claims that are wrong, none behaviourally consequential
  but all in prose a maintainer would reasonably trust:
  1. **"168-entry" language list** (`ao3-networking-audit.md:228`) — it is
     **162** (163 including "Any"). AO3's live form has 163 options including
     the blank, so the list is *exactly* right; only the number is wrong. The
     figure appears in the audit only — the `Language` doc comment itself
     ([AO3Models.swift:574](kudos-ao3-reader/Models/AO3Models.swift:574)) sensibly
     quotes no count.
  2. **"Test count 885 → 907 (+22)"** — actual `@Test` counts are 885 at the
     audit baseline, **910** at `5f071776`, **911** at `b9d70515`.
  3. **"on AO3's default relevance sort a direction is meaningless"** — refuted
     live (see the table in *Verification of the Original Audit*). AO3 honours
     `sort_direction` on `_score` and reverses the results. The *decision* to
     omit it and the comment's stated consequence are both still correct.
  4. **"AO3 serves listing pages with `Cache-Control: max-age=600, public`
     (measured 2026-08-06)"** at
     [AO3Client.swift:60](kudos-ao3-reader/Services/AO3Client.swift:60) — true of
     a URL the app never sends. Covered by R1.
- **Evidence**: Live DOM enumeration (163 options); `git grep -c "@Test"` per
  commit; the sort-direction result table; the header matrix.
- **Impact**: On a scraping client, these comments *are* the specification.
  (2) and (3) are also the kind of claim a future reader would build on.
- **Root Cause**: Numbers written from recollection rather than recount; (3)
  reasoned from first principles rather than tested.
- **Recommended Fix**: Correct all four in place. For (3), keep the code and
  rewrite the reason: *"AO3 does honour a direction on `_score` — it reverses the
  ranking — which is exactly why we don't send one: it would pin worst-match-first."*
- **Scope**: Small
- **Risk**: None
- **Dependencies**: R1 for (4)
- **Priority**: P3
- **Confidence**: High
- **Verification method**: Live DOM enumeration, `git grep`, live query comparison.

### R12 — The `URLCache` is not partitioned by identity

- **Severity**: Medium
- **Location**: [AO3Client.swift:72](kudos-ao3-reader/Services/AO3Client.swift:72); the shared `session` at [AO3Client.swift:25](kudos-ao3-reader/Services/AO3Client.swift:25), used by `performFetch`, `performAuthenticatedFetch` and `submitWrite` alike
- **Description**: One `URLSession`, and therefore one `URLCache`, serves
  anonymous GETs, authenticated GETs and write POSTs. `URLCache` keys on the URL
  and method — **not** on the `Cookie` header. So a response fetched under one
  identity can be served to another.

  This matters specifically here because the layer immediately above it was built
  to prevent exactly this: `authCoalescingKey(url:cookieHeader:)`
  ([AO3Client.swift:528](kudos-ao3-reader/Services/AO3Client.swift:528)) keys the
  authenticated coalescer by URL *and* cookie header, with a comment explaining
  that "a mid-flight account switch can never hand one session's response to
  another (A5-F1)". The new cache reintroduces the same hazard one layer down,
  unguarded and undiscussed.
- **Evidence**: Swift probe with the app's exact configuration — a request
  carrying `Cookie: _otwarchive_session=…` was served the **anonymous** cached
  copy of `/series/1234`:

  ```
  [with Cookie] CACHE-HIT 200 33389 bytes CC=max-age=600, public csrf=33uBLF-_pfpEIC9gqrsX
  >> identical CSRF token to the earlier anonymous fetch.
  ```
- **Impact**: **Bounded today, by AO3 rather than by the app.** AO3 marks
  personalized pages `private, max-age=0, must-revalidate` and sends no
  `ETag`/`Last-Modified`, so those are re-fetched in full every time and never
  served across identities. The pages that *do* cross the boundary
  (`/series/`, `/users/*/works`) are ones AO3 itself marks `public`, so the data
  is not private. The finding is that the invariant is now enforced by a third
  party's headers instead of by the app, on a code path whose sibling has an
  explicit comment promising otherwise. A future AO3 header change, or a new
  authenticated fetch of a `public` URL whose content differs by viewer, turns
  this into a real leak with no test and no guard to catch it.
- **Root Cause**: The cache was attached to the shared session configuration
  without considering that the session is not identity-scoped.
- **Recommended Fix**: Set `request.cachePolicy = .reloadIgnoringLocalCacheData`
  on every authenticated request in `authenticatedRequest(for:method:)`
  ([AO3AuthService.swift:629](kudos-ao3-reader/Services/AO3AuthService.swift:629)).
  One line, keeps the cache exactly where it is safe (anonymous reads), and makes
  the identity boundary explicit in code rather than implicit in AO3's headers.
  - *Alternative considered*: a second `URLSession` for authenticated traffic.
    Cleaner in principle, but it would split the Cloudflare cookie jar that
    `challengeCookieHeader` deliberately shares — a real regression.
  - *Alternative considered*: rely on AO3's `private` headers. That is the
    status quo; it is not written down anywhere and has no test.
- **Scope**: Small
- **Risk**: Low — authenticated pages are already effectively uncached, so this
  mostly makes existing behaviour explicit.
- **Dependencies**: Related to R1/R2
- **Priority**: P2
- **Confidence**: **High** that the cache is unpartitioned (demonstrated);
  **Medium** on present-day exploitability — I found no URL that is both
  `public`-cacheable and viewer-dependent, but I did not enumerate every
  authenticated fetch in the app.
- **Verification method**: Swift probe against live AO3 with CSRF-token fingerprinting.

### R13 — `verify.sh` cannot run in a clean worktree

- **Severity**: Low
- **Location**: `Scripts/verify.sh`, `Scripts/test.sh`; `.gitignore:48` (`Vendor/`)
- **Description**: `Vendor/MuPDF.xcframework` is gitignored (built by
  `Scripts/build-mupdf.sh`, ~48 MB) and is not present in a fresh worktree, so
  `verify.sh` — "the project's definition of done" — dies at stage 3/5 with
  `error: There is no XCFramework found at …/Vendor/MuPDF.xcframework` and
  `Testing cancelled because the build failed`. This is not caused by the change
  under review, but it means the "ALL GREEN (911 tests)" claim is not
  reproducible by anyone who checks the branch out fresh.
- **Evidence**: First `verify.sh` run in this worktree: exit 65 at stage 3. After
  symlinking the framework from a sibling worktree, the same command produced
  `Test run with 911 tests in 82 suites passed after 17.465 seconds` and
  `verify: ALL GREEN`.
- **Impact**: Every new worktree or clone silently fails its own definition of
  done, with an error that reads like a project misconfiguration rather than a
  missing prerequisite.
- **Root Cause**: A required, deliberately-uncommitted build artefact with no
  bootstrap step in the verification script.
- **Recommended Fix**: Have `verify.sh` (or `test.sh`) check for
  `Vendor/MuPDF.xcframework` and either invoke `Scripts/build-mupdf.sh` or fail
  early with that instruction. Three lines.
- **Scope**: Small
- **Risk**: None
- **Dependencies**: None
- **Priority**: P3
- **Confidence**: High
- **Verification method**: Ran it, twice.

### R14 — AO3 accepts `excluded_tag_names` and `date_from`/`date_to`, which the app does not use

- **Severity**: Low (opportunity, not a defect)
- **Location**: [AO3Client.swift:308](kudos-ao3-reader/Services/AO3Client.swift:308) (`searchURL`); [AO3Models.swift:287-297](kudos-ao3-reader/Models/AO3Models.swift:287) (`searchQuery`'s exclusion synthesis)
- **Description**: The brief asks whether skipping `words_from`, `date_from`,
  `series_titles`, `collection_ids` and `work_types` was right. Mostly yes — but
  the answer is not the one the audit gave, and it uncovers something that bears
  directly on F6.

  The authority is `WorkSearchForm::ATTRIBUTES` (`work_search_form.rb:7-47`), a
  40-entry allowlist; `process_options` discards anything outside it. The public
  `/works/search` form exposes 22 of those 40. Three of the remaining 18 are
  interesting:

  | Parameter | In `ATTRIBUTES`? | Live result vs 92,493 baseline | Verdict |
  |---|:--:|---|---|
  | `excluded_tag_names` | ✅ | **89,853** — works | 🆕 a *structured* replacement for the app's `-"tag"` query synthesis |
  | `date_from` | ✅ | **5,171** (`=2024-01-01`) — works | 🆕 genuine capability gap |
  | `date_to` | ✅ | **7,664** (`=2015-01-01`) — works | 🆕 genuine capability gap |
  | `words_from` / `words_to` | ✅ | — | correctly skipped (F10; the expression form is verified working) |
  | `collection_ids` | ✅ | — | correctly skipped — needs AO3 collection ids the app has no lookup for |
  | `series_titles` | ❌ | **92,493** — *ignored* | correctly skipped |
  | `work_types` | ❌ | **92,493** — *ignored* | correctly skipped |

  So the audit's note that `series_titles` and `work_types` are "additionally
  accepted" by `WorkQuery` is misleading: they are read *inside* `WorkQuery`
  (`work_query.rb:159, 266`) but never survive `WorkSearchForm`, so they are
  unreachable from `/works/search`. Skipping them was right, for a reason the
  audit did not state.
- **Evidence**: `work_search_form.rb:7-47` (the allowlist) and `:63`
  (`@options.delete_if`); live counts today against
  `work_search[fandom_names]=Naruto`, all shown in the table above. The two
  unpermitted controls returning the exact baseline is what proves the allowlist
  is enforced.
- **Impact**:
  1. **`excluded_tag_names` would make F6's escaping unnecessary.** The app folds
     exclusions into `work_search[query]` as `-"tag"` purely because "AO3's
     structured form has exactly one rating select and **no exclusion inputs at
     all**" (the audit's words, and the code's). The *form* has none; the
     *endpoint* does. Routing exclusions through it removes the entire
     query-syntax injection surface that F6 had to patch — and gives *better*
     results, because tag-name exclusion resolves canonical tags and their
     synonyms, where a `-"phrase"` match does not. That is what the 89,853 vs
     89,676 difference is.
  2. **`date_from`/`date_to` are a real gap.** The app can only express relative
     windows (`revised_at` = "< 1 month ago"). "Posted in 2024" is not
     expressible at all. So "22/22 coverage" is accurate for the *form* and
     complete as a claim, but it is not the ceiling of what `/works/search` accepts.
- **Root Cause**: Both the audit and the implementation took the public form's
  DOM as the definition of the endpoint's contract. It is a subset of it.
- **Recommended Fix**: Two separate pieces of work, neither urgent:
  - Move `excludedFandoms`/`excludedCharacters`/`excludedRelationships`/
    `excludedAdditionalTags` from `searchQuery` synthesis to
    `work_search[excluded_tag_names]` (comma-joined). Keep `quotedPhrase` — the
    excluded *warnings* and *categories* still go through query syntax as
    `-archive_warning_ids:` / `-category_ids:`, and the rating expression still
    needs it. Verify against live AO3 before switching; the result sets differ
    slightly by design, so this is a behaviour change, not a refactor.
  - Add `dateFrom`/`dateTo` alongside the existing `updated` window if absolute
    date filtering is wanted. Straightforward now that the range plumbing exists.
  - *Alternative considered*: leave both. Entirely defensible — the current
    exclusion path is verified working and F6's escaping is now proven correct.
    This is an improvement, not a repair.
- **Scope**: Small (dates) / Medium (exclusions — it changes result sets)
- **Risk**: Medium for the exclusion switch, because it alters what users get
  back. Low for the dates.
- **Dependencies**: None
- **Priority**: P3
- **Confidence**: **High** that both parameters work and that the two controls
  are ignored — measured. **Medium** on whether the exclusion switch is
  desirable; canonical-tag exclusion is arguably more correct but it is a
  product decision, not a bug fix.
- **Verification method**: otwarchive `work_search_form.rb` allowlist + six live queries with counts.

---

## What I Checked and Found Correct

Listed so the maintainer knows what was actually examined, not only what broke.

**AO3 contract**
- All 22 live `work_search[...]` parameter names are emitted; 22 is the correct
  denominator (27 form fields minus 5 login/CSRF). Coverage claim confirmed.
- All 10 `sort_column` values and both `sort_direction` values match the live
  form exactly; `.relevance → nil` correctly lets AO3 pick its own default
  (`work_query.rb:289`: `_score`, or `revised_at` when faceting).
- AO3 defaults `sort_direction` to `desc` — confirmed live *and* at source
  (`work_query.rb:278`), so `.descending` genuinely preserves prior behaviour.
- The `[]` multi-value convention, the `T`/`F` flag values, `single_chapter=1`,
  and the `revised_at` age strings all match.
- The range grammar (`> 1000`, `1000-5000`, `< 50`) is accepted, including the
  space, on all five numeric fields.
- **F6's escape sequence is correct** — the one item shipped unvalidated. Proved
  with result-count arithmetic against a fixed corpus.
- The `Language` list is complete and exact: 162 entries + "Any" = 163, matching
  AO3's 163 options; no duplicate ids or titles; first entry matches AO3's.
- `+` in a search field is *not* percent-encoded by `URLComponents`, so
  `work_search[title]=C++` reaches Rails as `C  `. **Checked live and it is
  harmless**: AO3's analyser strips punctuation, so `C++`, `C` and `C  ` all
  return the same 4,462 works. Not a finding.

**Persistence**
- `Language`'s old wire format (a bare `"en"` / `""` string) is preserved
  exactly; the new type is strictly more lenient on unknown codes.
- All 13 fields added across the range decode leniently — checked individually,
  including the eight without tests.
- `Sort`'s new cases are inserted safely (String raw values).
- `KudosBackup` is compatible in both directions with no version bump, because
  `currentVersion` was already 8; the reasoning behind the decision is sound.
- `mergedPositive` cannot zero a known count when restoring an older archive.
- `hasActiveFilters` and the reset path both cover every new field.

**Concurrency**
- Cancellation reaches `URLSession` — demonstrated with a real cancelled
  `LocalDataTask`, not inferred.
- The `Task.isCancelled` gate on `URLError.cancelled` is correctly placed and
  cannot misreport a server-side failure; `.cancelled` is correctly absent from
  `transientURLErrorCodes`, with a test.
- `release`'s task-identity guard is necessary and correct.
- No leaked `inFlight` entries, no lost wakeups, no hanging waiter, no harmful
  reordering between the `defer` and `onCancel` releases.

**UI**
- The `naturalDirection` re-seed does **not** clobber a saved search's direction.
  I traced the reachable paths: `runSaved` is invoked from `idleScreen`, not from
  inside the filter panel, so `.onChange(of: filters.sort)` is not live when a
  saved search loads; and the only other whole-struct replacement reachable with
  the panel open is Reset, which lands on the same default anyway. The re-seed
  only fires when the user operates the Sort picker — which is the documented
  intent. **No finding.**
- New filter fields persist, reset and round-trip.
- The `.textInputAutocapitalization(.never)` chain attaches to the Creator field
  only, not Title. That matches the stated intent (pseuds, not titles); only the
  comment's placement above both fields is misleading.

**Caching configuration** (the parts that are right — the parts that aren't are R1/R2/R12)
- **`diskCapacity: 0` is load-bearing and correctly reasoned.** Contrary to what
  I expected, `.ephemeral` does *not* refuse an explicitly-assigned disk cache:
  handed one with `diskCapacity: 50 MB`, it wrote 168,924 bytes of AO3 HTML to
  disk on a single page fetch. The comment's rationale — that this would quietly
  undo the app's own mature-content gating — is sound, and the line is doing real
  work.
- **8 MB is a sensible size** for 33–90 KB pages (~90–240 of them).
- **`.ephemeral`'s nominal 512 KB default cache is inert** — measured, a repeat
  GET through a stock ephemeral session is a full network load and
  `currentMemoryUsage` stays 0. So assigning the cache is what turned caching on
  (0 → 8 MB), and R2/R12 are genuinely introduced by this change rather than
  pre-existing. This corrects the audit's self-correction, and my own first
  reading of it.

**Other**
- `verify.sh` genuinely green: 911/911, 82 suites, **0 skipped, 0 quarantined, 0
  `withKnownIssue`, 0 `XCTSkip`**.
- No test file was clobbered or lost tests anywhere in the range.
- No unguarded iOS-only API — the macOS build stage passes, which is the real
  check for the implementing agent's flagged concern.
- No `try!`, `as!`, force-unwrap, or unchecked index access in ~2 900 added lines.
- The hoisted `DateFormatter` is correct (`en_US_POSIX`, GMT, IMF-fixdate) and
  safe to share (`DateFormatter` parsing is thread-safe; nothing mutates it).
- No retain cycle in the reader KVO; the observation closure captures nothing.

---

## Unknowns & Residual Risk

1. **I did not enumerate every authenticated fetch in the app** against R12, and
   **I have no AO3 credentials**, so every header in this report was measured
   anonymously. AO3 may well downgrade a page to `private` for a signed-in
   viewer — `/users/<n>/profile` already is `private` even anonymously, which
   suggests AO3 does mark personalized views correctly. But `/users/<n>/bookmarks`
   measures `max-age=600, public` anonymously, and that is exactly the URL the app
   fetches *authenticated*. **Re-measure that one request while signed in** before
   concluding R12 is theoretical; it is the single check most likely to change a
   verdict here.
2. ~~**`view_adult` on registered-users-only works.**~~ **Closed.** Compared full
   corpus totals rather than page 1: `fandom_names=Naruto` returns **92,493 Found
   with and without** `view_adult`. If the parameter gated any work class the
   totals would differ. Nothing is filtered.
3. **`NSKeyValueObservation` outliving its observed object** (R9) — I reasoned
   about it from Apple's documented semantics but did not instrument the reader
   to confirm no KVO-dealloc warning is logged in practice.
4. **AO3's `Cache-Control` behaviour is a live-service detail**, not a contract.
   Everything in R1/R2/R12 is dated 2026-08-06 and could change.
5. ~~**SwiftData migration is untested** for `SavedWork.bookmarks`.~~ **Closed —
   run against a real pre-change store.** The booted simulator still held a
   `default.store` written 2026-08-05 19:22, before `30322553` added the column
   (confirmed by schema: `ZKUDOS`/`ZCOMMENTS`/`ZHITS` present, no `ZBOOKMARKS`),
   holding 2 `SavedWork` rows. Building HEAD and launching against it: the app
   started and stayed up, `ZBOOKMARKS` was added by automatic lightweight
   migration, and both rows survived byte-identical (kudos 483/620, comments
   367/54, hits 25964/9939) with the new column defaulted to 0. No crash report.
   *Caveat:* that store had 0 `SavedSearch` rows, so the `AO3SearchFilters`
   `Codable` path was not exercised against real persisted data — but its wire
   format is unchanged and its decode is unit-tested against legacy payloads.
6. ~~**`hig-review` divergence**, carried forward from the audit.~~ **Closed —
   it never diverged.** `origin/hig-review` is `29cd9158ebd3525d6d63ff6fddeab30e591a0b93`,
   which *is* this review's base commit, and there are zero commits on it that
   this branch does not contain. So every finding applies to `hig-review`
   directly and this branch is a clean fast-forward from it. This also retires
   the same caveat in the audit's scope note and its Unknown #5.
7. **R6's real-world magnitude is unmeasured** — I proved the URLs differ, not
   how often users select multiple warnings or categories.

---

## Prioritized Action Plan

### Immediate (Critical)

*Nothing is data-destroying or ships a wrong AO3 constant.* The three P1 items
below are user-visible regressions introduced by this range, not emergencies.

### High Priority

1. **R3 — scope F9's throw to `parseSearchPage`.** Two lines. Fixes a hard error
   on an ordinary bookmarks page. Do this first: smallest diff, clearest
   regression, no dependencies.
2. **R1 + R2 together — decide the caching story and make it coherent.**
   These must land as one change; fixing either alone makes the other worse.
   Recommended: revert `view_adult=true` from `searchURL` (restoring the
   cacheable header and the win F8 was for), correct the `worksPage(at:)`
   comment instead, and thread `bypassCache` down to
   `cachePolicy = .reloadIgnoringLocalCacheData` at every `.refreshable` call
   site. Re-measure the headers afterwards and paste the result into the comment.
3. **R12 — set `.reloadIgnoringLocalCacheData` on authenticated requests.** One
   line, and it belongs in the same change as (2) while the caching model is
   being reasoned about.

### Medium Priority

4. **R4 — table-driven id test** over `Rating`/`Warning`/`Category`. ~15 lines,
   closes ten unasserted constants at once.
5. **R6 — sort warnings and categories before emitting**, plus one test that two
   differently-built equal filter sets produce identical URLs.
6. **R8 — assert the `bookmarks` stat**: one line in the existing blurb fixture,
   one line in an existing backup round-trip test.

### Nice to Have

7. **R5 — rewrite the `Entry.waiters` comment** to state the true reason. Keep
   the code.
8. **R11 — correct the four factual errors** (162 not 168; 911 not 907; the
   `sort_direction`-on-`_score` rationale; the cache-header claim, which R1
   already forces).
9. **R7 — amend F3's impact paragraph** in the audit to drop the 1.8 s figure.
   Do not touch `pace()`.
10. **R10 — give `refreshCurrentResults` its own cancellable task.**
11. **R13 — have `verify.sh` check for `Vendor/MuPDF.xcframework`** and fail with
    the bootstrap instruction.
12. **R14 — consider `date_from`/`date_to`** (small, purely additive) and, as a
    separate product decision, whether exclusions should move to
    `excluded_tag_names`. The latter changes result sets, so it is not a refactor.
13. **R9 — leave alone**; documented here so the next reader does not re-derive it.

### Recommended order of work

```
R3 (scope the throw)  ──►  R1 + R2 + R12 (one coherent caching change)  ──►  re-run verify.sh
                                                   │
R4 ─┬─ R6 ─┬─ R8   (test hardening, independent, parallelisable) ◄──────────┘
    │      │
    └──────┴──►  R5, R11, R7 (documentation truth-up)  ──►  R10, R13
```

`R3` first because it is the smallest fix for the clearest regression and blocks
nothing. `R1/R2/R12` must be one change — they are three views of the same
decision about what this app caches and for whom, and splitting them leaves the
cache in a worse state than either endpoint. The test hardening is genuinely
independent and can proceed in parallel. The documentation items are last but
should not be dropped: on a scraping client with no API contract, the comments
are the specification, and four of them currently say things that are not true.

---

## Remediation status

Twelve of the fourteen findings were fixed in follow-up commits. Two were
deliberately left alone. One fix changed shape once a test was written against
it — recorded below, because the discarded version looked better on paper.

| # | Finding | Status | What landed |
|---|---|---|---|
| R1 | `view_adult` defeats the cache | ✅ Fixed | `searchURL` no longer sends `view_adult`. Three comments that asserted the opposite were rewritten against measurements, including the `worksPage(at:)` one the audit originally wanted corrected. |
| R2 | Pull-to-refresh serves a cached page | ✅ Fixed | `AO3Client.invalidateCachedResponses()`, called from the anonymous refresh paths (search, browse ×2, series detail). Authenticated surfaces need no call — R12 takes them out of the cache entirely. |
| R3 | Parse throw breaks bookmarks pages | ✅ Fixed | `parseWorksList(requireParseableBlurbs:)`, false from `parseBookmarksPage`. + 1 regression test. |
| R4 | Ten facet ids asserted nowhere | ✅ Fixed | `everyFacetIDMatchesAO3sOwnForm` pins all 17 ids in one table. |
| R5 | Coalescer comment describes an impossible bug | ✅ Fixed (comment) | Code kept — it is correct by construction, which is worth the few extra lines. The `Entry.waiters` doc now explains why the counter would *also* have been safe instead of implying it wasn't. |
| R6 | Search URL not stable for a fixed filter set | ✅ Fixed | Warnings/categories emitted in sorted id order. + `equalFilterSetsAlwaysProduceTheSameURL`, which builds the same filter three ways. |
| R7 | F3's 1.8 s latency claim is unachievable | ✅ Fixed (doc) | The audit's F3 impact paragraph now carries the correction and the measurement. `pace()` untouched — releasing a claimed slot correctly is real complexity for a benefit nobody has measured wanting. |
| R8 | `bookmarks` had no parsing or round-trip test | ✅ Fixed | Blurb fixture gained `dd.bookmarks` (in AO3's real position, `<a>`-wrapped); present, absent, round-trip and pre-`bookmarks`-archive cases all asserted. |
| R9 | Weak-to-strong `NSMapTable` retains dead tokens | ⏭️ **Not changed, as recommended** | Lookups are correct and the table self-drains. Switching to weak-to-weak would silently stop observation — the exact bug the map table exists to prevent. |
| R10 | `refreshCurrentResults` cancels but isn't cancellable | ✅ Fixed | It now reuses `load(page:)` rather than repeating it, so the refresh lives in the same `loadTask` slot. Net −16 lines. |
| R11 | Four factual errors | ✅ Fixed | 168 → 162 languages; 885 → 907 → the real 910/911; the `sort_direction`-on-`_score` rationale replaced with the measured behaviour; the cache-header comment rewritten (R1). |
| R12 | `URLCache` not partitioned by identity | ✅ Fixed | `authenticatedRequest` sets `.reloadIgnoringLocalCacheData`. + assertion in the existing `authenticatedRequest` test. |
| R13 | `verify.sh` can't run in a clean worktree | ✅ Fixed | Preflight check for `Vendor/MuPDF.xcframework` that names `Scripts/build-mupdf.sh`, instead of dying four minutes later at the test build. |
| R14 | `excluded_tag_names`, `date_from`/`date_to` unused | ⏭️ **Not changed — maintainer's call** | Both verified to work, but neither is a defect. Moving exclusions to `excluded_tag_names` changes what users get back (canonical-tag exclusion resolves synonyms; the current `-"phrase"` match does not — that is the 89,853 vs 89,676 gap), so it is a product decision, not a repair. `date_from`/`date_to` are a new feature. Left for you. |

### One fix that changed shape

R3's first implementation was the "better, larger" option this report recommends
in that finding: extract the id resolution into a shared `blurbWorkID`, then gate
the throw on *blurbs that name a work* rather than on the caller. It reads
better, keeps the health signal on both pages, and is **wrong** —
`blurbWorkID` returns nil in exactly the cases `parseBlurb` throws, so the
"identifiable" set is always equal to the parsed set and the guard becomes
unsatisfiable. It would have silently deleted F9 outright.

That only surfaced when the existing test was run against it. Worth recording
for whoever picks up the larger version later: making the signal sound for
bookmarks needs *positive* recognition of series/external/deleted blurbs, not a
smarter negative.

### Verification

`Scripts/verify.sh` — invariants, lint, full iOS suite, macOS build, whitespace.
Test count **911 → 915** (+4). The live measurements these fixes rest on are in
the finding bodies above, each with the date it was taken.
