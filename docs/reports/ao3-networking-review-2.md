# AO3 Networking Review — Second Pass

**Reviewed range:** `b9d70515..67850e41` (8 commits, 16 files, ~1 890 insertions).
**Reviewed tree:** worktree `ao3-networking-review-3377ae`, branch `claude/ao3-networking-review-3377ae`, HEAD `67850e41`.
**Date:** 2026-08-06. Every live check below was run today against `archiveofourown.org`, anonymously (no credentials available).
**Method:** full static read of the range; four purpose-built Swift probes against live AO3 using `makeAnonymousSessionConfiguration()` verbatim (cache invalidation, authenticated cache-write, refresh call-site census, timezone); ~35 live AO3 requests (header matrix ×3 repeats, result-count arithmetic); otwarchive source cross-check (`work_query.rb`, `work_search_form.rb`, `query.rb`, `taggable_query.rb`); direct SQLite inspection of nine real SwiftData stores; a full `Scripts/verify.sh` run; and five hand mutations, each a full 917-test run.

**This review changed no code.** Everything below is reported, not fixed. Where a
fix is small and obvious I have written it out, but nothing has been applied and
nothing has been committed.

---

## Executive Summary

### Is this change safe to keep on the branch?

**Yes.** Nothing in this range is data-destroying, ships a wrong AO3 constant, or
leaks one account's page to another. The eight commits do what they say, the
suite is genuinely green (917/917, verified below), and the two highest-risk
claims in the batch — that `invalidateCachedResponses()` works, and that
`date_from`/`date_to` filter `revised_at` — are **both correct**. The item the
implementing agent flagged as its single knowingly-unvalidated fix turns out to
be right.

### Is it safe to push?

**Not yet — three things first.** None is an emergency; all three are things a
user will actually hit.

1. **[S1, High] R2 is only half fixed.** Four more `.refreshable` surfaces reach
   `max-age=600, public` AO3 URLs and never call the invalidation. I measured
   cache hits on all of them: an author's Works tab, an author's Bookmarks tab,
   the comments thread (signed out), and the media index. Pull-to-refresh on
   those still returns the same bytes for ten minutes. The agent's own admission
   that "the call-site list may be incomplete" is correct, and the gap is larger
   than the three surfaces it guessed at.
2. **[S2, High] The timezone defect is real, is worse than flagged, and the new
   test locks it in.** `dateBoundFormatter` is pinned to UTC while `DatePicker`
   produces a local `Date`. 4 of 9 realistic timezone/time-of-day combinations
   emit a **different calendar day than the user picked**, in *both* directions —
   not just "east of UTC gets the previous day". Worse: applying the correct fix
   makes `absoluteDateBoundsUseAO3sISOFormat` **fail**, because that test builds
   its input in the same UTC calendar the formatter uses. The test asserts the
   implementation, not the contract.
3. **[S3, Medium] R12 stops reads but not writes.** `.reloadIgnoringLocalCacheData`
   does not keep a response *out* of the cache — I measured an authenticated-shaped
   request storing 33 389 bytes into the shared `URLCache`. The shipped comment
   says "Never serve an authenticated page from (**or into**) the shared response
   cache". The "or into" half is false, and the identity invariant is therefore
   still enforced by AO3's headers rather than by the app — which is the exact
   thing R12 was written to stop.

### Confidence in the previous agent's *review*, and in its *implementation*

| | Assessment |
|---|---|
| **The review (`c15bcb6d`)** | **High.** All 14 findings are real. I re-derived R1, R3, R4, R6, R7, R13 and R14 independently and reproduced the numbers, including the 74 261 / 73 419 exclusion arithmetic to within corpus drift. Its live measurements were honest and its confidence markers were placed correctly. Two blind spots, both structural rather than careless: it reasoned about caching from *which surfaces it had already looked at* rather than from a census (S1), and it treated `AO3SearchFilters` persistence as a `Codable` problem when for `SavedSearch` it is a SwiftData **column-schema** problem (S5). |
| **The implementation (`0c69a04a`..`67850e41`)** | **Medium-High.** Eleven of the fourteen fixes are complete and correct, and I confirmed three of them by mutation (the facet-id table, the URL-stability sort, and R3's scoping all die when broken). Two are partial (R2 → S1, R12 → S3). One traded one defect for another (R10 → S4). The pattern from the first review repeats one level down and in the same place: **every fix that stayed inside the code is right; the fixes that rest on a claim about a system the code doesn't own — AO3's headers, `URLSession`'s caching contract, SwiftData's storage model, the user's calendar — are the ones with a gap.** |

The agent's self-reported "notes" were accurate on every point I could check,
including the admissions. It said the call-site list might be incomplete; it is.
It said it suspected a timezone defect; there is one. That candour is worth
saying out loud, because it is what made this pass efficient.

---

## Verification of the Review's Findings

Were the 14 findings real? **Yes, all 14.** None invented. None overstated. I
re-verified the seven that a second pass can actually re-derive:

| # | Re-checked? | Result |
|---|---|---|
| R1 | ✅ live, ×3 | `/works/search` plain → `max-age=600, public` on all three runs; `+view_adult=true` → `max-age=0, private, must-revalidate`. Real. |
| R2 | ✅ probe | Reproduced a `CACHE-HIT` with identical CSRF on `/series/1234` using the app's config. Real — and **wider than reported** (S1). |
| R3 | ✅ source + mutation | otwarchive's four-way bookmark branch confirmed; removing the fix turns the new regression test red. Real. |
| R4 | ✅ mutation | `Category.multi` `"2246"` → `"246"` — the mutation that survived the previous suite — is now **caught** by `everyFacetIDMatchesAO3sOwnForm`. Genuinely closed. |
| R6 | ✅ mutation | Dropping `.sorted()` produces **3 distinct URLs** from 3 equal filter sets and the new test fails. Real, and now covered. |
| R7 | ✅ source | `pace()` claims its slot before sleeping, unconditionally. Real. |
| R13 | ✅ ran it | Copied `verify.sh` into a Vendor-less root: exits 1 with the bootstrap instruction. Real, and fixed. |
| R14 | ✅ source + live | `excluded_tag_names`, `date_from`, `date_to` are all in `WorkSearchForm::ATTRIBUTES` (lines 26, 41, 42). All three work live. Real. |

**Was anything missed?** Two things, both of which required a method the review
did not use:

- **A census, not a sample.** R2's surface table lists six `.refreshable` sites.
  There are **twenty**. The four the fix missed (S1) are all in the fourteen the
  table never enumerated. `AuthorProfileView` *is* in the table — marked "no",
  correctly, for `/users/<n>/profile` — but the screen's Works and Bookmarks
  tabs fetch different URLs that are `max-age=600, public`.
- **The actual storage engine.** The review verified `AO3SearchFilters`
  persistence by reading its `Codable` conformance. SwiftData does not use that
  conformance (S5). Nine real stores on this machine prove it: the composite
  attribute is **flattened into one SQLite column per stored property**.

**Did reviewing a snapshot and then implementing it cause blind spots?** Yes, one,
and it is visible in the artefact: the review recommended the *surgical* fix for
R2 (per-request `.reloadIgnoringLocalCacheData`) and explicitly rejected
`removeAllCachedResponses()` as "a blunt instrument… it evicts unrelated
entries". The implementation then shipped the rejected option, and no commit
message, comment, or report line says the trade-off was reconsidered — the
`invalidateCachedResponses` doc-comment simply argues the blunt approach is fine,
as if the earlier rejection had not been written by the same agent four commits
earlier (S8). The *surgical* option was shipped too, for authenticated requests
(R12). Both mechanisms now coexist and the codebase does not say which is the
house style.

---

## Verification of the Fixes

| # | Claimed status | My verdict | Basis |
|---|---|---|---|
| R1 | ✅ Fixed | **Fixed** | `searchURL` emits no `view_adult`; `searchNeverSendsViewAdult` pins it. Live: identical 92 495 totals with and without. |
| R2 | ✅ Fixed | **Partially fixed** | The mechanism works (proved). Four cacheable refresh surfaces still lack the call — **S1**. |
| R3 | ✅ Fixed | **Fixed** | Mutation-confirmed. The surviving shape is sound — see *R3's fix, re-examined*. |
| R4 | ✅ Fixed | **Fixed** | Mutation-confirmed; the previously-surviving mutation now dies. |
| R5 | ✅ Fixed (comment) | **Fixed** | New `Entry.waiters` comment states the true reason and no longer implies an unreachable bug. Analysis matches mine. |
| R6 | ✅ Fixed | **Fixed** | Mutation-confirmed. String sort, not numeric — correct, see *Tier 3*. |
| R7 | ✅ Fixed (doc) | **Fixed** | Audit's F3 impact paragraph carries the correction and the 1.10 s measurement. `pace()` untouched, as recommended. |
| R8 | ✅ Fixed | **Fixed** | Present/absent/round-trip/pre-`bookmarks`-archive all asserted, including `dd.bookmarks` `<a>`-wrapped in AO3's real position. |
| R9 | ⏭️ Not changed | **Correct** | Agreed; leaving it is right. |
| R10 | ✅ Fixed | **Fixed, with a new defect** | It is now cancellable by a subsequent `load`. It is **no longer cancellable by the `.refreshable` gesture itself** — **S4**. |
| R11 | ✅ Fixed | **Fixed** | 162 languages; 911/917 counts; the `sort_direction`-on-`_score` rationale now states the measured behaviour; the cache-header comment rewritten. All four corrected in place, and I found no stale copy elsewhere. |
| R12 | ✅ Fixed | **Partially fixed** | Reads are prevented (measured). Writes are not — **S3**. |
| R13 | ✅ Fixed | **Fixed** | Ran the preflight in a Vendor-less root; exits 1 with the right message. |
| R14 | ✅ Both adopted | **Adopted; one correct, one defective** | `excluded_tag_names` is correct and reproducible. `date_from`/`date_to` reach the right axis but emit the wrong **day** — **S2**. |

---

## The Caching Change

This was the highest-risk commit and it holds up better than expected. Taking
the brief's six questions in order.

### 1. Does `invalidateCachedResponses()` actually work? — **Yes. Proved.**

This was the single least-evidenced claim in the batch and it is **correct**.

The mechanism people expect to fail here is `URLSession.configuration` returning
a *copy* of the configuration, so that `session.configuration.urlCache` would be
a different object from the one assigned and clearing it would do nothing. It is
a copy — but a **shallow** one, and the `URLCache` reference survives it:

```
assigned URLCache identity : ObjectIdentifier(0x0000000110479d20)
session.configuration cache: ObjectIdentifier(0x0000000110479d20)
SAME OBJECT?               : true
config object identity     : assigned=0x…11046c000  viaSession=0x…110477f70   ← config IS copied
```

End to end, against live AO3 with `makeAnonymousSessionConfiguration()` verbatim:

```
[initial   ] NETWORK    200  33376 bytes  CC=max-age=600, public  csrf=UH3BIMeR3Lti5dNzAQvjkkLc
             cache currentMemoryUsage after load: 33376
[repeat    ] CACHE-HIT  200  33376 bytes  CC=max-age=600, public  csrf=UH3BIMeR3Lti5dNzAQvjkkLc
  >> session.configuration.urlCache?.removeAllCachedResponses()
             originalCache.currentMemoryUsage: 0
[post-inval] NETWORK    200  33382 bytes  CC=max-age=600, public  csrf=2WR0ggRCsRROPlU40riYOSv6
```

Memory usage drops to zero, the next fetch is a real network load, and the CSRF
token changes — which it only does on a genuine render. **Claim 1 is verified.**
No finding.

### 2. Is the call-site list complete? — **No. Four gaps, all measured.** (S1)

Twenty `.refreshable` modifiers exist. Here is the whole census, with what each
actually fetches and today's header for that URL:

| Surface | Fetches | `Cache-Control` today | Invalidates? | Verdict |
|---|---|---|---|---|
| `SearchView:243` | `/works/search` | `max-age=600, public` | ✅ | correct |
| `NativeBrowseView:107` (fandom) | `search()` | `max-age=600, public` | ✅ | correct |
| `NativeBrowseView:286` (tag) | `worksPage(at:)` → `/tags/<t>/works` | `no-cache, public` | ✅ | correct (belt-and-braces) |
| `AO3SeriesDetailView:74` | `/series/<id>` | `max-age=600, public` | ✅ | correct |
| **`AuthorProfileView:190` → Works tab** | `/users/<n>/works` | **`max-age=600, public`** | ❌ | **GAP — measured CACHE-HIT** |
| **`AuthorProfileView:190` → Bookmarks tab** | `/users/<n>/bookmarks` | **`max-age=600, public`** | ❌ | **GAP — measured CACHE-HIT** |
| **`CommentsView:153` (signed out)** | `/works/<id>?show_comments=true&view_full_work=true` | **`max-age=600, public`** | ❌ | **GAP** |
| **`MediaBrowserView:103`** | `/media` | **`max-age=600, public`** | ❌ | **GAP — measured CACHE-HIT** |
| `FandomListView:52` | `/media/<x>/fandoms` | `max-age=600, public` | ❌ | **latent** — 2.5 MB body exceeds `URLCache`'s per-entry ceiling, so it is not stored *by accident of size* |
| `AuthorProfileView:190` → About tab | `/users/<n>/profile` | `max-age=0, private` | ❌ | safe (AO3's header) |
| `AuthorProfileView:190` → Series tab | `/users/<n>/series` | `max-age=0, private` | ❌ | safe (AO3's header) |
| `AO3AccountWorksList:299` | authenticated works/bookmarks/subscriptions | — | ❌ | safe — R12's request policy |
| `AO3CollectionsList:78` | authenticated `/collections` | — | ❌ | safe — R12's request policy |
| `AccountView:208`, `:248` | `refreshCurrentTab`, guarded by `auth.isLoggedIn` | — | ❌ | safe — always authenticated |
| `WorkDetailView:145` | `/works/<id>` | `no-cache, public` | ❌ | safe (AO3's header) |
| `HomeView:117`, `HomeSectionListView:98`, `LibraryView:241`/`:638`, `LibrarySectionListView:228`, `Collections.swift:182`, `ReadingQueues:225` | local SwiftData / `WorkMetadataRefresh` on `/works/<id>` | `no-cache` | ❌ | safe |

Direct measurement of the four gaps, app config verbatim:

```
AuthorProfileView works tab      /users/astolat/works
  [first ]           NETWORK   186478B  CC=max-age=600, public  csrf=j5cU325TYr-5XBZs0mYy
  [pull-to-refresh]  CACHE-HIT 186478B  CC=max-age=600, public  csrf=j5cU325TYr-5XBZs0mYy
AuthorProfileView bookmarks tab  /users/astolat/bookmarks
  [first ]           NETWORK   196815B  ...  csrf=dcIlQl-hYdQVFa0bTcGD
  [pull-to-refresh]  CACHE-HIT 196815B  ...  csrf=dcIlQl-hYdQVFa0bTcGD
MediaBrowserView                 /media
  [first ]           NETWORK    30840B  ...  csrf=xh_GMJXs1ngQkvO2kuB7
  [pull-to-refresh]  CACHE-HIT  30840B  ...  csrf=xh_GMJXs1ngQkvO2kuB7
FandomListView                   /media/Movies/fandoms
  [first ]           NETWORK  2529031B  ...  csrf=tzOEwiMmYiozPcDeur3I
  [pull-to-refresh]  NETWORK  2529031B  ...  csrf=tzOEwiMmYiozPcDeur3I   ← size, not design
```

`AuthorProfileView` is the sharpest of these: it passes `bypassCache: true`
into `AO3AuthorProfileService.refresh`, which skips `AO3AuthorPageCache` and then
falls into the new `URLCache` underneath — **the exact defeat R2 described, still
live, on a surface R2's own table marked safe.** It is also the surface where
the gesture means the most: "has this author posted anything since I last
looked?"

### 3. Is the invalidate-then-fetch sequence atomic? — **No, and I reproduced the race.** (S9)

They are two separate `await`s on an actor, so anything can interleave. Modelled
directly:

```
== invalidate mid-flight, then fetch again ==
    -> invalidated mid-flight; memoryUsage=0
[inflight ] NETWORK    200 33382B  csrf=2WR0ggRCsRROPlU40riYOSv6
    -> after in-flight response landed: memoryUsage=33382  entryStoredForURL=true
[post-race] CACHE-HIT  200 33382B  csrf=2WR0ggRCsRROPlU40riYOSv6   ← pre-refresh body
```

An in-flight response that lands *after* the invalidation repopulates the cache,
and the next fetch reads it. Reachability in the app is narrow but not
theoretical: the natural trigger is pulling to refresh while the initial `.task`
load is still running. In practice `RequestCoalescer` usually gets there first —
it will merge the refresh's fetch into the in-flight identical request and return
the pre-gesture body directly, without the cache being involved at all — which is
the same user-visible outcome by a different route, and is at most a few seconds
stale. **Low severity, worth writing down, not worth a lock.**

### 4. Is `removeAllCachedResponses()` the right blunt instrument? — **It works, but the choice is undocumented.** (S8)

It is defensible: 8 MB, memory-only, ten-minute lifetime, on an explicit user
gesture. The cost is that pulling to refresh Search evicts the series page, the
author page and the media index too, and each of those then costs a fresh
`pace()` slot when next visited.

What is missing is the reasoning. The review had **already rejected this option
in writing** ("Rejected — it evicts unrelated entries and is a blunt instrument")
and recommended per-request `.reloadIgnoringLocalCacheData`, which it then
shipped *for authenticated requests only*. The `invalidateCachedResponses`
doc-comment argues the blunt approach is fine but never mentions that the other
approach was preferred four commits earlier. The claim "the caller is a view that
knows it wants fresh data, not which URLs its loader is about to build" is also
not quite true for the largest caller: `SearchView` can build its exact URL with
the static, pure `AO3Client.searchURL(filters:page:)`.

Not a defect. But if the fix for S1 adds four more call sites, that is the moment
to pick one mechanism and say why.

### 5. The undocumented coupling in `worksPage(at:)` — **the premise is false, and the real coupling is elsewhere.**

The brief asks whether browse is "currently harmless partly because
`worksPage(at:)` still sends `view_adult`, which makes its responses
uncacheable". **It does not.** Measured, ×3:

- `/tags/<t>/works` is `no-cache, public` **with or without** `view_adult` — it
  was never cacheable, so `view_adult` is not what protects it.
- `/users/<n>/works` is `max-age=600, public` **with or without** `view_adult` —
  so on that path `worksPage(at:)` responses are cacheable *right now*.

So the hypothesised trap does not exist, and the shipped comment on
`worksPage(at:)` is accurate on both endpoints. Browse is safe for the plain
reason that both its call sites invalidate.

The coupling that *does* exist and is not written down is the opposite one:
`/users/<n>/works` is cacheable, and `worksPage(at:)`'s only caller is browse —
but `AuthorProfileService` reaches the same URL by a different route
(`getHTML`) and does not invalidate. That is S1, and it is a real instance of
"one URL, two callers, one of them guarded".

### 6. Does the authenticated bypass work end-to-end? — **Reads yes; writes no.** (S3)

Reads are genuinely bypassed. Every authenticated fetch in the app routes
through the single `AO3AuthService.authenticatedRequest(for:method:)`
(`AO3AuthService.swift:615`) — I enumerated every `URLRequest(url:)` in the
target and the only other two are the WebKit login flow and `about:blank`. The
policy assignment is unit-asserted, and measured: an authenticated-shaped request
is `NETWORK` every time, even with a warm cache entry present.

Nothing else broke. `authCoalescingKey` still keys on URL + cookie;
`redirectCookieRelay` is unaffected by a cache policy; `purgeSessionCookie` runs
only on the anonymous path and is untouched; setting the policy on the `"POST"`
variant used by `AO3WriteActions` is harmless.

**But the comment's parenthesis is wrong.** `.reloadIgnoringLocalCacheData` means
"don't *read* the cache". It says nothing about storing. Measured:

```
== A: authenticated-shaped request (.reloadIgnoringLocalCacheData + Cookie) ==
[auth-1 ] NETWORK    200 33389B  policy=1
    -> after authenticated fetch: memoryUsage=33389  entryStoredForURL=true   ← STORED
```

So an authenticated response **is** written into the shared cache. Today that is
harmless, and for a reason the app does not own: AO3 downgrades any
cookie-bearing request to `private, max-age=0, must-revalidate` with no
validator, so the stored entry is born stale and every later read re-fetches.
I confirmed that directly —

```
/series/1234        (no cookie)  → max-age=600, public
/series/1234        + Cookie     → max-age=0, private, must-revalidate
/users/astolat/works + Cookie    → max-age=0, private, must-revalidate
```

— and the subsequent anonymous read did go to the network. **The invariant holds;
the code does not hold it.** That is precisely what R12 set out to change, so the
fix is half-landed and its comment overstates what it achieved.

---

## The Exclusion & Date Change (user-visible behaviour)

### The exclusion switch is correct, and the reported arithmetic reproduces

Live today, corpus `work_search[fandom_names]=Naruto`:

| Query | Found | Reading |
|---|---:|---|
| baseline | 92,495 | (report: 92,493 — two days' growth) |
| `excluded_tag_names=Time Travel` | 89,855 | excludes 2,640 ✅ |
| `excluded_tag_names=Time Travel,Fluff` | **74,261** | **exactly the report's figure** |
| `work_search[query]=-"Time Travel" -"Fluff"` (the old path) | **73,419** | **exactly the report's figure** |
| `excluded_tag_names=Time Travel,Fluff,Angst` | 65,055 | three names work ✅ |
| `excluded_tag_names=Tmie Travle` (misspelt) | 92,495 | excludes nothing |
| `excluded_tag_names=time travel` (lowercase) | 89,741 | excludes **more**, not less |
| `excluded_tag_names=TIME TRAVEL` | 89,741 | identical to lowercase |

The 74 261 / 73 419 difference is reproducible to the digit and the explanation
is right: the old phrase route also matched summary and title text.

**Case sensitivity behaves the opposite way to the worry.** A lowercase name does
not silently stop filtering — it filters *harder*. `taggable_query.rb` explains
why, and it is worth recording because it is genuinely counter-intuitive:

```ruby
found = Tag.where(name: names).pluck(:id, :name)
{ ids: found.map(&:first), missing: (names - found.map(&:second)).uniq }
```

The DB lookup is case-insensitive, so `"time travel"` **finds** the canonical tag
and its id lands in `exclusion_ids`. But `names - found.map(&:second)` is a
**case-sensitive Ruby array difference**, so `"time travel"` is *also* reported
missing — and `named_tag_exclusion_filter` adds a `match` filter for it on top.
Both filters fire. Hence 89 741 < 89 855.

A misspelling excludes nothing, which is correct — excluding a tag nobody used
removes no works — and is not a regression: `-"Tmie Travle"` behaved the same.

**Commas cannot corrupt anything.** `AO3SearchFilters.commaSeparatedValues`
splits the user's input on commas and trims; `all_tag_names` does
`options[field].split(",").map(&:squish)`. Both sides use the identical
convention, so a tag name containing a comma is split the same way at both ends.
Such a tag is simply **inexpressible** — and was equally inexpressible before the
change, since the old path split on commas first too. No finding.

**`quotedPhrase(_:)` was safe to delete.** At `b9d70515`, `git grep` returns
exactly two hits: the definition (`AO3Models.swift:347`) and one caller
(`:292`). "Only caller" was true. And no remaining path interpolates *synthesized*
user text into query syntax — what `searchQuery` now joins is the user's own raw
free-text query plus enum-derived `-archive_warning_ids:`/`-category_ids:`/
`-rating_ids:` clauses built from `ao3ID` constants. The raw `query` field is
unescaped by design: it is AO3's free-text field and users are meant to be able
to type AO3 query syntax into it.

One pre-existing wrinkle, noted rather than filed: an unbalanced quote in that
free-text field can swallow the clauses appended after it. Live,
`query=he said "hi -category_ids:21` returns a page with no result heading at
all, where the balanced form returns 60. Unchanged by this range and it is the
user's own typing; mentioned so nobody rediscovers it and blames the exclusion
switch.

**The one thing that is a genuine product risk, already known:** every saved
search containing an exclusion now returns a different result set, with no
migration and no notice. The report says so plainly and the maintainer adopted it
anyway. I am not re-litigating it — only noting that no test pins the *semantics*
(only that the parameter is emitted), so a future refactor could silently revert
to phrase exclusion with the suite green.

### The date fields reach the right axis — but emit the wrong day (S2)

**Claim 6 is correct.** `work_query.rb:220-227`:

```ruby
def date_range_filter
  return unless options[:date_from].present? || options[:date_to].present?
  range[:gte] = clamp_search_date(options[:date_from].to_date) if …
  range[:lte] = clamp_search_date(options[:date_to].to_date) if …
  { range: { revised_at: range } }
```

`revised_at` — *updated*, not posted. The agent's mid-implementation correction is
right, and live arithmetic agrees: `date_from=2025-08-06` → 1,985 and
`revised_at=< 1 year ago` → 1,978 (the report measured 1,979 yesterday), a drift
of hours, not of axis. The AND claim in the panel footer is also right:
`date_from=2025-08-06` **+** `revised_at=< 1 week ago` → 105, identical to
`< 1 week ago` alone.

The defect is the **day**. `dateBoundFormatter` is pinned to UTC;
`DatePicker(displayedComponents: .date)` edits only y/m/d and preserves the bound
`Date`'s time-of-day, which `dateBound(_:date:)` seeds with `Date()` — the local
wall-clock moment the toggle was switched on. So whenever that time-of-day
crosses a UTC boundary, the emitted day is not the day on screen. User picks
**31 January 2026**:

```
zone                 toggled-on   emitted      user picked
Asia/Tokyo           08:30        2026-01-30   2026-01-31   *** OFF BY ONE ***
Asia/Tokyo           20:30        2026-01-31   2026-01-31   ok
Europe/Berlin        01:30        2026-01-31   2026-01-31   ok
UTC                  12:30        2026-01-31   2026-01-31   ok
America/New_York     09:30        2026-01-31   2026-01-31   ok
America/New_York     21:30        2026-02-01   2026-01-31   *** OFF BY ONE ***
Pacific/Auckland     09:30        2026-01-30   2026-01-31   *** OFF BY ONE ***
Pacific/Honolulu     20:30        2026-02-01   2026-01-31   *** OFF BY ONE ***

4/9 cases emit a different day than the user picked.
```

Two things the agent's own flag understated: it is **both directions** (UTC−
users get the *next* day), and it depends on the hour the toggle was flipped,
which then sticks — so the same user gets a correct bound one day and an off-by-one
bound the next, from the same picker, with nothing on screen to indicate it.

---

## Live AO3 Compatibility Re-check

Every behavioural claim the range rests on, re-measured today.

| # | Claim | Result | Verdict |
|---|---|---|---|
| 1 | `/works/search` plain is `max-age=600, public` | `max-age=600, public` ×3 runs | ✅ stable |
| 2 | `+view_adult=true` flips it to uncacheable | `max-age=0, private, must-revalidate` | ✅ (wording differs from the report's longer no-store string; both uncacheable) |
| 3 | `view_adult` changes no results | 92,495 Found **with and without** | ✅ upheld |
| 4 | `/users/<n>/works` unaffected by `view_adult` | `max-age=600, public` both ways | ✅ upheld |
| 5 | `/tags/<t>/works` unaffected by `view_adult` | `no-cache, public` both ways (one run of three returned `private, max-age=0, no-store`) | ⚠️ upheld, but not deterministic |
| 6 | `/works/<id>` is `max-age=600, public` | **`no-cache, public`** on all three runs | ❌ **does not reproduce** |
| 7 | `excluded_tag_names` takes a comma list | 1, 2 and 3 names all work; spaces fine | ✅ upheld and extended |
| 8 | `date_from`/`date_to` work and hit `revised_at` | 1,985 / 7,664; AND-ed correctly | ✅ upheld |

**On claim 3 and restricted works.** The corpus totals are byte-identical with and
without `view_adult` — 92,495 both ways. If the parameter gated *any* class of
work, including registered-users-only works, the totals would differ. It gates
nothing on a listing page. (Works restricted to registered users are excluded
from anonymous results by AO3's own visibility rules, which `view_adult` does not
touch; that is unchanged by this range either way.)

**On claim 4 — the drift matters more than the individual values.** (S10) The
report presents its header matrix as a per-endpoint fact. It is not: `/works/<id>`
does not reproduce at all for me, and `/tags/<t>/works` returned two different
answers in three consecutive requests. AO3's headers vary with its own caching
backend (`x-ao3-caching-backend: unicorn_cache_bot` appears on some responses and
not others), so a single measurement is a sample, not a contract.

This does not change any code decision in the range — `/works/<id>` being
`no-cache` makes `view_adult` free there either way, and `worksPage(at:)`'s
comment is correct on the two endpoints that actually matter. But the shipped
comments state these as measured facts with a date, and two of them are already
stale one day later. That is worth knowing before someone treats a comment as a
contract.

---

## Concurrency Review

### `refreshCurrentResults` — correct on the paths it was rewritten for

```swift
await AO3Client.shared.invalidateCachedResponses()
if results.isEmpty { phase = .loading }
load(page: currentPage)
await loadTask?.value
```

- **No lost wakeup.** `load(page:)` is synchronous and assigns `loadTask` before
  returning; there is no suspension point between the assignment and the read in
  `await loadTask?.value`, so the await always targets the task just created.
- **No swallowed throw.** `load` catches every error inside the task body, so
  `loadTask` is `Task<Void, Never>` and `.value` cannot throw. Confirmed by the
  declaration at `SearchView.swift:42`.
- **No stuck spinner.** If the user taps a page mid-refresh, `load(page:)`
  cancels the refresh's task; the body catches `CancellationError` and returns, so
  the task completes and the awaiting `.refreshable` closure resumes.
- **Token check retained** as a second line of defence. Correct.

### But the gesture is no longer cancellable (S4)

Before the fix, `refreshCurrentResults` awaited `AO3Client.shared.search(...)`
**directly**, so it inherited the `.refreshable` task's cancellation: swiping away
mid-refresh cancelled the AO3 request. Now the fetch lives in an unstructured
`loadTask`, and `loadTask?.cancel()` appears at exactly one place —
`SearchView.swift:723`, inside `load(page:)`. There is no `onDisappear`, no
`.task(id:)` teardown, and no `.cancelRefreshOnTabChange`.

So cancelling the refresh gesture no longer stops the request. R10's stated
impact — "the refresh runs to completion and spends a full pacing slot ahead of
the request the user is actually waiting for" — is now true of the *disappear*
path instead of the *tap-a-page* path. The report's claim that "`.refreshable`'s
task is still cancelled by SwiftUI on disappear, so the unbounded case is
covered" was true of the old code and is no longer true of the new.

The codebase already has the idiom: `UIComponents/CancellableRefresh.swift`'s
`.cancelRefreshOnTabChange($refreshTask)`, used by `LibraryView`,
`HomeSectionListView` and `LibrarySectionListView`. `SearchView` does not use it.

### `RequestCoalescer` — unchanged behaviour, better comment

The `b9d70515..HEAD` change is comment-only. I re-derived the argument
independently and it is correct: the `defer` release can only be scheduled after
`try await task.value` returns, so the second release always lands on a spent
entry; the set is correct by construction rather than by that argument. The new
comment says exactly that. No finding.

---

## Persistence & Migration Review

### `SavedSearch` is not persisted through `Codable` (S5)

`SavedSearch.filters` is a plain `var filters: AO3SearchFilters` on a `@Model`.
SwiftData stores that composite attribute by **flattening one SQLite column per
stored property** — not as an archived `Codable` blob. Nine real stores on this
machine show it. Two schema generations, side by side:

```
older store                       HEAD-schema store
  ZQUERY      VARCHAR               ZQUERY        VARCHAR
  ZFANDOM     VARCHAR               ZTITLE        VARCHAR    ← filters.title
  ZWORDSFROM  VARCHAR               ZFANDOM       VARCHAR
  ZUPDATED    VARCHAR               ZWORDSFROM    VARCHAR
  ZLANGUAGE   VARCHAR   ←──┐        ZDATEFROM     TIMESTAMP  ← new
  ZSORT       VARCHAR      │        ZDATETO       TIMESTAMP  ← new
  ZNAME       VARCHAR      │        ZUPDATED      VARCHAR
  ZID         BLOB (uuid)  │        ZID           VARCHAR    ←─┐ language.id
  ZWARNINGS   BLOB         └──────► ZTITLE1       VARCHAR    ←─┘ language.title
                                    ZSORT         VARCHAR
                                    ZSORTDIRECTION VARCHAR
                                    ZNAME         VARCHAR
                                    ZID1          BLOB (uuid)
```

**For this range the answer is: safe.** `dateFrom`/`dateTo` become two nullable
`TIMESTAMP` columns — a textbook additive lightweight migration, and one store on
this machine already carries them. A `SavedSearch` written before this range
migrates cleanly.

**But the verification method that certified it does not describe the mechanism.**
The previous review checked "all 13 fields decode leniently" by reading
`init(from:)`, and the new tests add a `JSONEncoder` round-trip. I confirmed the
`Codable` path itself is fine (`{"updated":"any"}` decodes with `dateFrom == nil`;
a populated struct round-trips equal). It is simply not the path SwiftData takes,
and `AO3SearchFilters`'s `Codable` conformance has **no other production
consumer** — `grep` finds no `JSONEncoder`/`JSONDecoder` touching it anywhere in
`kudos-ao3-reader/`. So those tests guard a mechanism nothing in the app uses,
while the mechanism that *is* used has no test.

The proof that SwiftData ignores the conformance is in the schema above:
`Language` has a **custom** `encode(to:)` using a `singleValueContainer` that
emits one bare string. Had SwiftData used it, `Language` would be one column. It
is two — `ZID` + `ZTITLE1`, its two stored properties.

**The consequence, which is outside this range but was cleared by the previous
review:** commit `0c71a730` turned `Language` from `enum Language: String` into a
two-property struct, which drops `ZLANGUAGE` and adds `ZID`/`ZTITLE1`. The
review's claim 9 — *"encodes/decodes as the bare id string, so the old wire
format is unchanged"* — is right about JSON and does not cover this. I have not
been able to observe the migration outcome, because every store on this machine
holds **zero** `SavedSearch` rows, so I am flagging the mechanism (High
confidence) and not the user-visible result (see S5's confidence note).

### `SavedWork.bookmarks` and `KudosBackup`

Both re-checked and unchanged by this range. The `bookmarks` round-trip and
pre-`bookmarks`-archive cases now have real assertions (R8), including the
`decodeIfPresent ?? 0` downgrade path. No finding.

---

## Test Quality Assessment

`Scripts/verify.sh` — **ALL GREEN, exit 0. 917 tests in 82 suites.** Reproduced
in this worktree today. `@Test` count in `KudosTests` is exactly 917, so the
report's "911 → 917 (+6)" is accurate. Zero skips: every `skipped` /
`withKnownIssue` / `XCTSkip` hit in the log is a test *name* or a library log
line, not a skip directive. **Claim 10 upheld.**

Per-commit `@Test` counts rise monotonically — 911, 911, 912, 915, 915, 915, 915,
917 — and the only deleted tests are the two `quotedPhrase` ones plus three
renames. Nothing else vanished from the test target, and the only production
deletion is `quotedPhrase` itself plus locals from the `SearchView` rewrite.
**Claim 9 and the deletion audit both check out.**

### Hand mutation testing — five mutations, one full 917-test run each

| # | Mutation | Result | Caught by |
|---|---|---|---|
| M1 | `Category.multi` `"2246"` → `"246"` (the previous survivor) | ✅ **caught** | `everyFacetIDMatchesAO3sOwnForm` |
| M2 | drop `.sorted()` from the warning/category emission | ✅ caught (3 distinct URLs) | `equalFilterSetsAlwaysProduceTheSameURL` |
| M3 | drop `requireParseableBlurbs: false` from `parseBookmarksPage` | ✅ caught | `aBookmarksPageOfOnlySeriesIsEmptyRatherThanAParseError` |
| M4 | empty the body of `invalidateCachedResponses()` | 🔴 **SUITE STILL GREEN** | *nothing* |
| M5 | apply the *correct* timezone fix (`UTC` → `TimeZone.current`) | 🔴 **SUITE GOES RED** | `absoluteDateBoundsUseAO3sISOFormat` |

M1 is the headline: R4 genuinely closed the gap the previous review demonstrated.
M2 and M3 confirm R6 and R3 are load-bearing.

**M4 is the coverage hole the brief predicted**, and it is total: the function can
be emptied and 917 tests still pass. So can the three call sites (nothing asserts
them either). The whole pull-to-refresh cache story rests on prose.

**M5 is the more interesting result.** `absoluteDateBoundsUseAO3sISOFormat` builds
its input with a **UTC calendar** and asserts the UTC-formatted output. That makes
it structurally unable to catch the defect — and worse, actively hostile to the
fix: on this machine (EDT, UTC−4) applying `TimeZone.current` produces

```
✘ Expectation failed: (values["work_search[date_from]"] → ["2024-01-30"]) == ["2024-01-31"]
✘ Expectation failed: (values["work_search[date_to]"]   → ["2025-12-24"]) == ["2025-12-25"]
```

The test does not merely miss the bug. **It pins it.** This is the clearest
example in the batch of asserting what the code emits rather than what the
contract requires: the contract is "the calendar day the user selected", and the
test never expresses a user-facing day at all.

### What is asserted against AO3's contract, and what isn't

Genuinely contract-shaped: every `work_search[...]` name is a literal; all 17
facet ids are now pinned against the live form with a comment naming the
verification date; the range grammar's space is pinned; `excluded_tag_names`'s
comma convention is pinned; assertions run against a parsed `[name: [value]]`
dictionary rather than a URL string.

Asserting the implementation instead of the contract:

1. **`absoluteDateBoundsUseAO3sISOFormat`** — as above. The single worst one.
2. **`everyFacetIDMatchesAO3sOwnForm` pins `allCases` order as well as ids.**
   Mildly brittle — reordering the Rating picker for presentation reasons breaks a
   test about AO3 ids. Defensible (the array *is* the picker order) but it makes
   the test fail for a reason its name does not describe. Low priority; if it ever
   annoys someone, compare as a dictionary keyed by case.
3. **`equalFilterSetsAlwaysProduceTheSameURL` is probabilistic.** It relies on
   three differently-built `Set`s actually iterating differently. It caught M2
   cleanly here (3 distinct URLs) and with six-element sets built three ways a
   false green is unlikely — but it is not guaranteed, and a green result is not
   proof the sort is present.

### The load-bearing behaviour with no assertion behind it

The equivalent of the previous review's "10 of 17 ids" gap is now:

1. **`invalidateCachedResponses()` and its call sites** — zero coverage,
   demonstrated by M4.
2. **The exclusion *semantics*** — `excludedTagNames` is asserted to produce
   `"Naruto,Star Wars,Alice/Bob"`, but nothing pins that exclusions must not also
   appear in `work_search[query]` for a filter set that has *both* excluded tags
   and excluded warnings… actually
   `exclusionsSplitBetweenTheTagFieldAndQuerySyntax` does assert
   `!query.contains("Bleach")`, so this one is covered. Withdrawn.
3. **`AO3SearchFilters` persistence through SwiftData** — the tests exercise
   `Codable`, which SwiftData does not use (S5). No test opens a store.
4. **`.reloadIgnoringLocalCacheData`'s actual effect** — the test asserts the
   property is set, which is right and cheap. Nothing asserts what it does, which
   is how the "or into" half of the comment went unchallenged (S3).

---

## New Findings

### S1 — `invalidateCachedResponses()` is missing from four refreshable surfaces that reach cacheable AO3 URLs

- **Severity**: High
- **Location**: [AuthorProfileView.swift:190](kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:190) → [AO3AuthorProfileService.swift:296](kudos-ao3-reader/Services/AO3AuthorProfileService.swift:296) → [:54](kudos-ao3-reader/Services/AO3AuthorProfileService.swift:54) (`getHTML`); [CommentsView.swift:153](kudos-ao3-reader/Features/Comments/CommentsView.swift:153) → [AO3Client+Comments.swift:66](kudos-ao3-reader/Services/AO3Client+Comments.swift:66); [MediaBrowserView.swift:103](kudos-ao3-reader/Features/Search/MediaBrowserView.swift:103) → [AO3Client.swift:1141](kudos-ao3-reader/Services/AO3Client.swift:1141); [FandomListView.swift:52](kudos-ao3-reader/Features/Search/FandomListView.swift:52) → [AO3Client.swift:1170](kudos-ao3-reader/Services/AO3Client.swift:1170)
- **Description**: R2's fix added `await AO3Client.shared.invalidateCachedResponses()`
  to four call sites (search, browse ×2, series detail). Twenty `.refreshable`
  modifiers exist. Four more reach AO3 URLs that are `max-age=600, public` today
  and go through the anonymous `getHTML` pipeline, so pull-to-refresh on them
  still re-renders the cached body for ten minutes. `AuthorProfileView` is the
  sharpest case: it explicitly passes `bypassCache: true` to skip
  `AO3AuthorPageCache` and then falls straight into the `URLCache` beneath —
  the exact defeat R2 described, on a surface R2's own table marked safe (it
  measured `/users/<n>/profile`, but the screen's Works and Bookmarks tabs fetch
  different URLs).
- **Evidence**: Swift probe using `makeAnonymousSessionConfiguration()` verbatim
  against live AO3. Identical byte counts and identical CSRF tokens — the token
  is regenerated on every genuine render, so an unchanged one proves the body was
  not re-fetched:

  ```
  /users/astolat/works       [first] NETWORK 186478B csrf=j5cU325TYr-5XBZs0mYy
                             [again] CACHE-HIT 186478B csrf=j5cU325TYr-5XBZs0mYy
  /users/astolat/bookmarks   [first] NETWORK 196815B csrf=dcIlQl-hYdQVFa0bTcGD
                             [again] CACHE-HIT 196815B csrf=dcIlQl-hYdQVFa0bTcGD
  /media                     [first] NETWORK  30840B csrf=xh_GMJXs1ngQkvO2kuB7
                             [again] CACHE-HIT  30840B csrf=xh_GMJXs1ngQkvO2kuB7
  ```

  Headers measured today: `/users/<n>/works`, `/users/<n>/bookmarks`, `/media`,
  `/media/<x>/fandoms` and `/works/<id>?show_comments=true&view_full_work=true`
  are all `max-age=600, public`. `FandomListView` is *latently* affected only:
  its 2 529 031-byte body exceeds `URLCache`'s per-entry ceiling for an 8 MB
  memory cache, so it is not stored — protection by accident of size, which a
  smaller fandom index or a larger cache would remove.
  `CommentsModel.authenticatedRequest` returns `nil` when signed out
  ([CommentsModel.swift:268](kudos-ao3-reader/Features/Comments/CommentsModel.swift:268)),
  and `commentsPage` then takes the `getHTML` branch — so the comments gap
  applies to signed-out readers.
- **Impact**: Pull-to-refresh silently does nothing on four screens, including the
  two where the gesture is most meaningful — "has this author posted since I last
  looked?" and "are there new replies on this thread?". This is worse than no
  caching: an explicit user action visibly succeeds and changes nothing, with no
  way to force a re-fetch short of waiting out ten minutes or restarting.
- **Root Cause**: The fix was scoped by reasoning about "which surfaces are
  anonymous *and* cacheable" from the set of surfaces already in R2's table,
  rather than by enumerating the twenty `.refreshable` sites and resolving the URL
  each one actually fetches. The agent flagged this risk itself.
- **Recommended Fix**: Add the invalidation to `AuthorProfileService.refresh`,
  `CommentsModel.load(forceRefresh: true)`, `MediaBrowserView.refresh` and
  `FandomListView.refresh` — four one-line additions matching the existing
  pattern, ~15 minutes.
  - *Alternative (preferred if the fix is being made anyway)*: thread the
    intent to the transport instead. `AO3Client.getHTML(_:bypassCache:)` building
    a `URLRequest` with `.reloadIgnoringLocalCacheData` when set — which is what
    the review originally recommended for R2 and what R12 already shipped for
    authenticated requests. It removes the need for a call-site census entirely
    (the flag travels with the request), it stops evicting other screens' entries,
    and it makes the two halves of the caching model use one mechanism instead of
    two. Larger diff (~6 call sites plus a parameter) but it is the version that
    does not have to be re-audited the next time a `.refreshable` is added.
  - *Alternative considered*: leave `FandomListView` alone since its body is too
    large to cache. Rejected — that is an invariant of AO3's current page size,
    not of the app.
- **Scope**: Small (four call sites) / Small-Medium (transport parameter)
- **Risk**: Low
- **Dependencies**: Decide alongside S8 (which mechanism is the house style)
- **Priority**: P1
- **Confidence**: **High** — cache hits measured directly on three of the four;
  the fourth (comments) is established by header measurement plus reading the
  signed-out branch, not by an end-to-end probe.
- **Verification method**: `grep` census of all 20 `.refreshable` sites → call-path
  trace to the fetching function → live `Cache-Control` per URL → Swift probe with
  `URLSessionTaskMetrics` and CSRF fingerprinting.

### S2 — `dateBoundFormatter` emits a different calendar day than the user picked, and the new test locks the defect in

- **Severity**: High
- **Location**: [AO3Models.swift:374-381](kudos-ao3-reader/Models/AO3Models.swift:376) (`dateBoundFormatter`); [AO3FilterPanel.swift:237-249](kudos-ao3-reader/Features/Search/AO3FilterPanel.swift:241) (`dateBound(_:date:)`); `KudosTests/SearchURLTests.swift` (`absoluteDateBoundsUseAO3sISOFormat`)
- **Description**: The formatter is pinned to `TimeZone(identifier: "UTC")`.
  `DatePicker(displayedComponents: .date)` edits only the year/month/day of the
  bound `Date` and preserves its time-of-day, which `dateBound` seeds with
  `Date()` — the local wall-clock instant the toggle was switched on. Formatting
  that instant in UTC yields the previous day for users east of UTC who toggled
  in their morning, and the *next* day for users west of UTC who toggled in their
  evening. The agent flagged this as a suspicion and deliberately did not resolve
  it; it is real, and it is not one-directional.
- **Evidence**: Swift probe reproducing the shipped formatter verbatim, over nine
  realistic zone/hour pairs, for a user picking 31 January 2026:

  ```
  Asia/Tokyo       08:30 → 2026-01-30   (picked 2026-01-31)  OFF BY ONE
  Asia/Tokyo       20:30 → 2026-01-31                        ok
  America/New_York 21:30 → 2026-02-01   (picked 2026-01-31)  OFF BY ONE
  America/New_York 09:30 → 2026-01-31                        ok
  Pacific/Auckland 09:30 → 2026-01-30                        OFF BY ONE
  Pacific/Honolulu 20:30 → 2026-02-01                        OFF BY ONE
  4/9 cases emit a different day than the user picked.
  ```

  And the test actively defends the defect. Applying the fix
  (`TimeZone.current`) and running the full suite on this machine (EDT):

  ```
  ✘ absoluteDateBoundsUseAO3sISOFormat: (values["work_search[date_from]"] → ["2024-01-30"]) == ["2024-01-31"]
  ✘ absoluteDateBoundsUseAO3sISOFormat: (values["work_search[date_to]"]   → ["2025-12-24"]) == ["2025-12-25"]
  ✘ Test run with 917 tests in 82 suites failed after 17.8 seconds with 2 issues.
  ```

  The test builds its input with `Calendar` pinned to UTC and asserts the
  UTC-formatted output — a tautology with respect to this defect.
- **Impact**: An absolute date bound silently filters by the wrong day. Because
  the offset depends on the hour the toggle was flipped and that time-of-day then
  sticks in the persisted `Date`, the same user can get a correct bound one day
  and an off-by-one bound the next from the same control, with nothing on screen
  to indicate which. A saved search carries the wrong bound forever. Magnitude is
  one day of `revised_at` — small per query, invisible, and wrong.
- **Root Cause**: Two calendars. The formatter was modelled on
  `retryAfterDateFormatter`, where pinning to GMT is correct because the input is
  an HTTP-date in GMT. Here the input is a user-picked *local* calendar day, and
  the parameter AO3 wants is a calendar day, not an instant — so no conversion
  should happen at all.
- **Recommended Fix**: Format in the calendar the picker presented — set
  `formatter.timeZone = TimeZone.current` (or, more explicitly,
  `Calendar.current.timeZone`), and update `absoluteDateBoundsUseAO3sISOFormat` to
  build its input in that same calendar so it asserts "the day the user picked"
  rather than "UTC midnight". One line of production code plus the test.
  - *Alternative considered*: normalise to local midnight at capture time —
    `dateBound`'s setter seeds `Calendar.current.startOfDay(for: Date())` instead
    of `Date()`. This also fixes the symptom and has the nice property of making
    the persisted value mean "a day" rather than "an instant". It does **not** fix
    it alone: a local-midnight `Date` formatted in UTC still shifts for every
    UTC+ user. Best used *together* with the timezone change, not instead of it.
  - *Alternative considered*: keep UTC and document it. Rejected — AO3's
    `date_range_filter` compares against `revised_at` timestamps and the user is
    picking a day off a calendar; there is no reading under which the intended
    day is a different day.
  - *Not recommended*: pinning the formatter to `en_US_POSIX` is correct and
    should stay — that is about digit shapes and month names, not about the zone.
- **Scope**: Small
- **Risk**: Low. Changes emitted values by at most one day, in the direction that
  matches what the user selected.
- **Dependencies**: None
- **Priority**: P1
- **Confidence**: **High** — reproduced across nine zone/hour pairs; the
  test-locks-in-the-bug half was demonstrated with a full suite run.
- **Verification method**: Swift probe reproducing the shipped formatter and the
  `DatePicker` semantics; full 917-test mutation run.

### S3 — `.reloadIgnoringLocalCacheData` stops authenticated *reads*, not authenticated *writes*, so the shipped comment is false

- **Severity**: Medium
- **Location**: [AO3AuthService.swift:631-641](kudos-ao3-reader/Services/AO3AuthService.swift:641) (the comment and `request.cachePolicy`); [AO3Client.swift:85-86](kudos-ao3-reader/Services/AO3Client.swift:85) (the rule it references)
- **Description**: The comment says *"Never serve an authenticated page from (or
  into) the shared response cache."* `.reloadIgnoringLocalCacheData` is defined as
  "ignore the local cache, load from the originating source" — it governs reads
  only. Nothing here prevents the response being **stored**, and it is stored.
  So R12's stated goal — "makes the identity boundary explicit in code rather
  than implicit in AO3's headers" — is only half achieved: the read half is
  explicit in code, the write half is still AO3's headers.
- **Evidence**: Swift probe, app configuration verbatim:

  ```
  == A: authenticated-shaped request (.reloadIgnoringLocalCacheData + Cookie) ==
  [auth-1 ] NETWORK   200 33389B  policy=1
      -> after authenticated fetch: memoryUsage=33389  entryStoredForURL=true
  == D: authenticated again ==
  [auth-2 ] NETWORK   200 33382B  policy=1      ← reads correctly bypassed
  ```

  `cache.cachedResponse(for:)` on a plain `URLRequest` for that URL returns the
  entry, so it is retrievable by an anonymous request. What stops it being
  *served* is AO3, not the app — measured today:

  ```
  /series/1234           (no cookie) → max-age=600, public
  /series/1234           + Cookie    → max-age=0, private, must-revalidate
  /users/astolat/works   + Cookie    → max-age=0, private, must-revalidate
  ```

  A `max-age=0, must-revalidate` entry with no `ETag`/`Last-Modified` must
  revalidate and has nothing to revalidate with, so it always re-fetches. Probe
  step B confirms the subsequent anonymous read went to the network.
- **Impact**: No leak today. The finding is that a comment asserting an app-owned
  invariant describes something the app does not do, on the one code path whose
  sibling (`authCoalescingKey`) carries an explicit promise about exactly this
  hazard. A future AO3 header change — or any authenticated fetch of a URL AO3
  marks `public` whose content varies by viewer — turns it into a real
  cross-identity leak, with no guard and no test to catch it. On this codebase the
  comments are treated as the specification, which is what makes a false one cost
  something.
- **Root Cause**: `URLRequest.cachePolicy` was assumed to be symmetric. The
  symmetric control is the storage decision, which lives in
  `URLSessionDataDelegate.urlSession(_:dataTask:willCacheResponse:)`.
- **Recommended Fix**: Two options; I recommend the first.
  1. **Correct the comment** to state what is actually enforced and by whom:
     authenticated requests never *read* the cache (in code, and asserted), and
     never end up *served* to another identity because AO3 marks cookie-bearing
     responses `private, max-age=0` (measured, dated, and not ours). One
     sentence, and it makes the residual risk legible.
  2. **Make it true.** Add a `URLSessionDataDelegate` on the authenticated fetch
     path returning `nil` from `willCacheResponse`, so the response is never
     stored. This genuinely moves the invariant into the app. It costs a delegate
     on `performAuthenticatedFetch` (which already passes
     `redirectCookieRelay`, so the seam exists) and one test asserting
     `cache.cachedResponse(for:) == nil` after an authenticated fetch.
  - *Alternative considered*: a second `URLSession` for authenticated traffic.
    Still rejected for the reason the review gave — it splits the Cloudflare
    cookie jar `challengeCookieHeader` deliberately shares.
- **Scope**: Small (comment) / Small-Medium (delegate + test)
- **Risk**: None for (1); Low for (2)
- **Dependencies**: None
- **Priority**: P2
- **Confidence**: **High** that the write happens and the comment is wrong
  (measured). **Medium** on present-day exploitability — I have no credentials, so
  I could not check a genuinely signed-in `public` page; my cookie was a
  well-formed fake, which is enough to show AO3 branches on cookie presence but
  not to prove it branches identically for a real session.
- **Verification method**: Swift probe with `URLCache.cachedResponse(for:)` and
  `URLSessionTaskMetrics`; live header comparison with and without a `Cookie`
  header.

### S4 — R10's fix made the refresh cancellable by the next load, and uncancellable by the gesture

- **Severity**: Medium
- **Location**: [SearchView.swift:749-762](kudos-ao3-reader/Features/Search/SearchView.swift:749) (`refreshCurrentResults`); [SearchView.swift:243](kudos-ao3-reader/Features/Search/SearchView.swift:243) (`.refreshable`); [SearchView.swift:723](kudos-ao3-reader/Features/Search/SearchView.swift:723) (the only `loadTask?.cancel()`)
- **Description**: Before the fix, `refreshCurrentResults` awaited
  `AO3Client.shared.search(...)` directly inside the `async` function driven by
  `.refreshable`, so it was a structured child of SwiftUI's refresh task and
  inherited its cancellation — swiping away or switching tabs mid-refresh
  cancelled the AO3 request. The fix moved the work into the unstructured
  `loadTask`. `loadTask` is cancelled in exactly one place, `load(page:)`. There
  is no `onDisappear`, no `.task(id:)` teardown, and no
  `.cancelRefreshOnTabChange`. So the gesture's own cancellation no longer
  reaches the request.
- **Evidence**: `grep -n "loadTask\|onDisappear\|\.task(\|cancelRefreshOnTabChange"`
  over `SearchView.swift` returns the `@State` declaration (`:42`), the
  `.task(id: localMatchKey)` for local matches only (`:110`), the single
  `cancel()` (`:723`), the assignment (`:724`), and the `await` (`:761`).
  Nothing else. The report's own text asserts the opposite — *"`.refreshable`'s
  task is still cancelled by SwiftUI on disappear, so the unbounded case is
  covered"* — which was true of the code R10 replaced.
- **Impact**: Small but real, and it is the same politeness cost F3/R10 exist to
  remove, relocated rather than removed: a user who pulls to refresh and
  immediately leaves the tab leaves a full AO3 request running to completion,
  spending a `pace()` slot ahead of whatever they navigated to. The net change
  from R10 is a swap of which cancellation path works, not a strict improvement —
  and the report records it as a clean fix (`Net −16 lines`).
- **Root Cause**: Moving work out of a structured task to gain one cancellation
  edge silently drops the structured one.
- **Recommended Fix**: Use the idiom the codebase already has. Wrap the
  `.refreshable` closure with
  `UIComponents/CancellableRefresh.swift`'s `.cancelRefreshOnTabChange`, as
  `LibraryView:638`, `HomeSectionListView:98` and `LibrarySectionListView:228`
  already do — but note that helper cancels the *refresh* task, so it needs to
  reach `loadTask`. The smallest correct version is to add
  `withTaskCancellationHandler { await loadTask?.value } onCancel: { loadTask?.cancel() }`
  around the final await, which restores the structured edge without giving up
  the shared-slot behaviour R10 wanted. Roughly four lines.
  - *Alternative considered*: revert R10 and keep the refresh structured. That
    reinstates the defect R10 fixed (a refresh finishing ahead of a tapped page).
    Not recommended — the two edges are not exclusive.
  - *Alternative considered*: leave it. Defensible; the impact is one wasted
    request per abandoned refresh. But the report claims this path *is* covered,
    so at minimum that sentence should stop saying so.
- **Scope**: Small
- **Risk**: Low
- **Dependencies**: None
- **Priority**: P2
- **Confidence**: **High** on the mechanism (complete call-path read; the
  cancellation site census is exhaustive for this file). Not exercised at runtime.
- **Verification method**: Static analysis of the full `SearchView` task
  lifecycle, cross-checked against the pre-fix implementation in the diff.

### S5 — `SavedSearch` persistence is SwiftData column-flattening, not `Codable`, so the tests certify the wrong mechanism

- **Severity**: Medium
- **Location**: [SavedSearch.swift:11](kudos-ao3-reader/Models/SavedSearch.swift:11) (`var filters: AO3SearchFilters`); [AO3Models.swift:229-267](kudos-ao3-reader/Models/AO3Models.swift:229) (`init(from:)`); `KudosTests/SearchFiltersTests.swift`
- **Description**: `AO3SearchFilters` is stored as a SwiftData composite
  attribute, which is persisted as **one SQLite column per stored property**, not
  as an archived `Codable` payload. Both the previous review's persistence
  argument ("all 13 fields decode leniently") and this range's new coverage
  (`JSONEncoder` round-trip, legacy-payload decode) exercise the `Codable`
  conformance — which has **no production consumer at all**: `grep` finds no
  `JSONEncoder`/`JSONDecoder` touching `AO3SearchFilters` anywhere in
  `kudos-ao3-reader/`. The real mechanism has no test.
- **Evidence**: `PRAGMA table_info(ZSAVEDSEARCH)` across nine simulator stores.
  Older stores carry `ZQUERY`, `ZFANDOM`, `ZWORDSFROM`, `ZUPDATED`, `ZLANGUAGE`,
  `ZSORT`… ; a HEAD-schema store carries `ZDATEFROM TIMESTAMP` and
  `ZDATETO TIMESTAMP` (the new fields, correctly nullable) and — instead of
  `ZLANGUAGE` — the pair `ZID VARCHAR` + `ZTITLE1 VARCHAR`, in the same ordinal
  position.

  That pair is the proof. `Language` has a **custom** `encode(to:)` using a
  `singleValueContainer` that emits one bare string
  ([AO3Models.swift:610](kudos-ao3-reader/Models/AO3Models.swift:610)). If
  SwiftData used the `Codable` conformance, `Language` would occupy one column.
  It occupies two — its two stored properties. SwiftData is reflecting over
  stored properties and ignoring the custom coder.
- **Impact**: Two parts, of different weight.
  - **For this range: none.** `dateFrom`/`dateTo` become two nullable `TIMESTAMP`
    columns, which is a textbook additive lightweight migration, and one store on
    this machine already carries them. A `SavedSearch` written before this range
    migrates fine. That conclusion is now *evidenced*, where before it rested on
    an argument about a code path SwiftData does not execute.
  - **For the previous range: an open question the review closed too early.**
    Commit `0c71a730` turned `Language` from `enum Language: String` into a
    two-property struct. On the SwiftData side that drops `ZLANGUAGE` and adds
    `ZID`/`ZTITLE1` — a restructure, not an addition. The review's claim 9 ("the
    old wire format is unchanged") is correct about JSON and silent about this.
    The plausible outcome is that saved searches lose their language selection on
    upgrade; the worse outcome is a migration failure on two non-optional `String`
    attributes arriving without defaults.
- **Root Cause**: `Codable` conformance on a SwiftData composite attribute reads
  like the persistence contract. It is a *requirement* for the attribute, not the
  serialization SwiftData performs.
- **Recommended Fix**: In priority order —
  1. **Settle the `Language` question empirically** before this branch ships to a
     device that has ever run a pre-`0c71a730` build: create a `SavedSearch` with a
     non-default language on an old build, then launch HEAD against that store and
     check the value survives. This is the same method the agent used for
     `SavedWork.bookmarks` and it is the only way to answer it. If it does not
     survive, a `SchemaMigrationPlan` with a custom stage is the fix.
  2. **Add one round-trip test that opens a real `ModelContainer`** (in-memory is
     fine) and saves/reloads a fully-populated `SavedSearch`. It would not have
     caught the `Language` restructure, but it pins the mechanism that is actually
     used and costs ~15 lines.
  3. **Correct the persistence section** of `ao3-networking-review.md`, which
     currently presents the `Codable` analysis as covering `SavedSearch`.
  - *Alternative considered*: store `filters` as `Data` and own the encoding
    explicitly. That *would* make the `Codable` analysis correct and make future
    field changes free — but it is a schema migration of its own and gives up
    queryability. Not worth it for this.
- **Scope**: Small (test + doc) / Medium (if a migration stage turns out to be needed)
- **Risk**: Low for the test; the `Language` question is unquantified until run.
- **Dependencies**: None
- **Priority**: P2
- **Confidence**: **High** that SwiftData flattens and ignores the custom coder
  (proved by the column layout across two schema generations). **High** that the
  new date columns are safe. **Low** on the `Language` user-visible outcome — I
  could not observe it, because every store on this machine holds zero
  `SavedSearch` rows, which is the same wall the previous agent hit.
- **Verification method**: `sqlite3 PRAGMA table_info` over nine real
  `default.store` files; source reading of `Language`'s custom `Codable`;
  `JSONEncoder` round-trip probe to confirm the `Codable` path itself is sound.

### S6 — The exclusion comment (and the report's own correction) misdescribe otwarchive's mechanism

- **Severity**: Low
- **Location**: [AO3Models.swift:323-341](kudos-ao3-reader/Models/AO3Models.swift:335) (`excludedTagNames` doc comment); `docs/reports/ao3-networking-review.md` — *"R14, and one thing this report got wrong"*, item 2
- **Description**: Both texts state that "otwarchive turns each excluded name into
  its own `match` filter on the `tag` field". That is what happens to names AO3
  **cannot find in its tag database**. Names it *can* find — the common case, and
  the whole point of the change — take a different route: their ids go into
  `exclusion_ids` and become `term_filter(:filter_ids, id)`.
- **Evidence**: `work_query.rb:191-217` has **two** exclusion filters, both
  active:

  ```ruby
  def tag_exclusion_filter          # ids found in the DB
    exclusion_ids.map { |id| term_filter(:filter_ids, id) }
  def named_tag_exclusion_filter    # names NOT found in the DB
    excluded_tag_names.map { |n| match_filter(:tag, n) }
  ```

  and `taggable_query.rb` shows `excluded_tag_names` returning only
  `parsed_excluded_tags[:missing]`. `match_filter` uses `operator: "and"`
  (`query.rb:154-156`), so a multi-word missing name requires all its tokens —
  it does not over-exclude.
- **Impact**: The comment understates the change in the user's favour and, in
  doing so, over-corrects R14's original wording. `filter_ids` on an AO3 work are
  its **canonical filter tags**, so excluding by a found id does resolve synonyms
  and meta-tags — which is what R14 first said and the remediation note then
  retracted as "phrase-vs-tag, not synonym resolution". The truth is both: the
  841-work difference is phrase-vs-tag, *and* the tag route additionally resolves
  canonical tags. It also explains the case-sensitivity result, which is otherwise
  inexplicable.
- **Root Cause**: `named_tag_exclusion_filter` is the more visible of the two
  methods and is the one whose name matches the parameter.
- **Recommended Fix**: One sentence in the doc comment: names AO3 recognises are
  excluded by canonical filter id (so synonyms and sub-tags go too); names it does
  not recognise fall back to an AND-ed text match on the tag field, and therefore
  exclude nothing when the name is a typo. Amend the report's correction #2 the
  same way.
- **Scope**: Small (comment only)
- **Risk**: None
- **Dependencies**: None
- **Priority**: P3
- **Confidence**: High
- **Verification method**: otwarchive `work_query.rb`, `taggable_query.rb`,
  `query.rb` read directly; corroborated by the measured case-sensitivity
  arithmetic (89,855 exact-case vs 89,741 lowercase).

### S7 — Excluded tag names are case-sensitive in a way nothing normalises or documents

- **Severity**: Low
- **Location**: [AO3Models.swift:323-341](kudos-ao3-reader/Models/AO3Models.swift:335) (`excludedTagNames`); [AO3FilterPanel.swift](kudos-ao3-reader/Features/Search/AO3FilterPanel.swift) (the four free-text exclusion fields)
- **Description**: The app passes the user's typed text through verbatim. AO3's
  DB lookup is case-insensitive but its "missing" computation is a case-sensitive
  Ruby array difference, so a name typed in the wrong case is treated as **both**
  found and missing, and gets both filters. The result is a *different* (larger)
  exclusion set than the canonically-cased name.
- **Evidence**: Live, same corpus (92,495):
  `Time Travel` → 89,855; `time travel` → 89,741; `TIME TRAVEL` → 89,741.
  Mechanism at `taggable_query.rb`: `missing: (names - found.map(&:second)).uniq`.
- **Impact**: Minor and in the "excludes slightly more" direction, so no user is
  shown something they asked to exclude. But the app has four free-text tag fields
  with no autocomplete, so wrong-case input is the *normal* case, and two users
  typing the same tag differently get different result counts with no explanation.
  A typo excludes nothing at all — correct behaviour, but equally silent.
- **Root Cause**: AO3-side asymmetry between a case-insensitive DB lookup and a
  case-sensitive set difference. Nothing the app can fix at source.
- **Recommended Fix**: Do nothing to the wire format. If it is ever worth
  addressing, the useful version is UI: the panel could note that excluded tags
  match AO3 tag names, and a tag-name autocomplete (AO3 has an autocomplete
  endpoint) would fix input quality at the source rather than guessing at case.
  Recording the behaviour here is most of the value.
- **Scope**: Small (doc) / Medium (autocomplete)
- **Risk**: None
- **Dependencies**: None
- **Priority**: P4 — document, do not change
- **Confidence**: High on the measurement and the mechanism.
- **Verification method**: Six live queries with counts; otwarchive source.

### S8 — Two different cache-bypass mechanisms now coexist, and the one the review rejected is the one that shipped

- **Severity**: Low
- **Location**: [AO3Client.swift:88-101](kudos-ao3-reader/Services/AO3Client.swift:99) (`invalidateCachedResponses`); [AO3AuthService.swift:641](kudos-ao3-reader/Services/AO3AuthService.swift:641) (`request.cachePolicy`); `docs/reports/ao3-networking-review.md` — R2's *Recommended Fix*
- **Description**: R2's recommended fix was per-request
  `.reloadIgnoringLocalCacheData`, with `removeAllCachedResponses()` explicitly
  rejected: *"it evicts unrelated entries and is a blunt instrument."* The
  implementation shipped the rejected option for anonymous refreshes and the
  recommended option for authenticated requests. No commit message or comment
  records the reversal; the `invalidateCachedResponses` doc-comment argues the
  blunt approach is costless without mentioning that the same author had
  preferred the other one four commits earlier.
- **Evidence**: The two code sites above, plus R2's *Recommended Fix* and its
  first *Alternative considered* in the report.
- **Impact**: No runtime defect — I proved the shipped mechanism works. The cost
  is that the codebase now has two answers to "how does a caller get fresh data?"
  with nothing saying which to use, on a layer whose comments are otherwise the
  specification. That directly raises the cost of fixing S1: a maintainer adding
  four call sites has to guess.
  One stated justification is also not quite true: *"the caller is a view that
  knows it wants fresh data, not which URLs its loader is about to build"* — the
  largest caller, `SearchView`, can build its exact URL with the static, pure
  `AO3Client.searchURL(filters:page:)`.
- **Root Cause**: The choice was made during implementation and the earlier
  written analysis was not revisited.
- **Recommended Fix**: Fold into S1. Pick one mechanism — I recommend the
  per-request policy, because it is the one that scales to a call-site list nobody
  has to keep complete — and state the decision in `invalidateCachedResponses`'s
  doc-comment (or delete the function if the policy approach wins everywhere).
- **Scope**: Small
- **Risk**: None
- **Dependencies**: S1
- **Priority**: P3
- **Confidence**: High
- **Verification method**: Source and report comparison.

### S9 — Invalidate-then-fetch is not atomic; an in-flight response repopulates the cache

- **Severity**: Low
- **Location**: [SearchView.swift:753-761](kudos-ao3-reader/Features/Search/SearchView.swift:753); [NativeBrowseView.swift:107-110](kudos-ao3-reader/Features/Browse/NativeBrowseView.swift:108) and [:286-289](kudos-ao3-reader/Features/Browse/NativeBrowseView.swift:287); [AO3SeriesDetailView.swift:74-79](kudos-ao3-reader/Features/Authors/AO3SeriesDetailView.swift:77)
- **Description**: `await invalidateCachedResponses()` and the load that follows
  are separate `await`s. A response already in flight when the invalidation runs
  writes itself into the cache afterwards, and the refresh's own fetch can then be
  served from it.
- **Evidence**: Reproduced directly (invalidate 40 ms into a live fetch):

  ```
  -> invalidated mid-flight; memoryUsage=0
  [inflight ] NETWORK   200 33382B  csrf=2WR0ggRCsRROPlU40riYOSv6
  -> after in-flight response landed: memoryUsage=33382  entryStoredForURL=true
  [post-race] CACHE-HIT 200 33382B  csrf=2WR0ggRCsRROPlU40riYOSv6   ← pre-refresh body
  ```
- **Impact**: Very small. The trigger is pulling to refresh while an identical
  request is already in flight — realistically, refreshing during a slow initial
  load. In that scenario `RequestCoalescer` will usually intercept first and hand
  the refresh the in-flight (pre-gesture) body anyway, so the user-visible outcome
  is the same by a simpler route, and the data is seconds old rather than minutes.
- **Root Cause**: A global mutable cache plus a two-step protocol.
- **Recommended Fix**: Do nothing. Fixing it properly means holding the actor
  across the fetch — serialising every refresh against every other request — which
  is far more expensive than the defect. If S1 is fixed with the per-request
  policy instead, this disappears on its own, because there is no window: the
  request itself carries "do not read the cache". That is a further argument for
  that mechanism.
- **Scope**: Small (none, if S1 takes the policy route)
- **Risk**: None
- **Dependencies**: S1, S8
- **Priority**: P4 — document, do not change
- **Confidence**: **High** on the mechanism (demonstrated); **Medium** on
  reachability in the app — I reasoned about the trigger rather than instrumenting
  the UI.
- **Verification method**: Swift probe with a deliberately-timed invalidation.

### S10 — AO3's `Cache-Control` is not stable per endpoint, and two of the shipped comments' measurements no longer reproduce

- **Severity**: Low
- **Location**: [AO3Client.swift:789-808](kudos-ao3-reader/Services/AO3Client.swift:799) (`worksPage(at:)` doc comment); `docs/reports/ao3-networking-review.md` — the full header matrix
- **Description**: The header matrix is presented as a per-endpoint fact, dated.
  Repeat measurement shows AO3's answer varies with its own caching backend.
- **Evidence**: Three consecutive runs today:

  ```
  run1  /tags/Naruto/works : private, max-age=0, no-store, no-cache, must-revalidate, …
  run2  /tags/Naruto/works : no-cache, public
  run3  /tags/Naruto/works : no-cache, public
  run1-3 /works/259626     : no-cache, public       (report claims max-age=600, public)
  run1-3 /works/search     : max-age=600, public    (stable — the one that matters)
  ```
- **Impact**: None on the code. `/works/search` — the measurement every decision
  in the range rests on — was stable across all three runs, and `/users/<n>/works`
  was `max-age=600, public` with and without `view_adult`, so the
  `worksPage(at:)` comment's operative claim holds. What does not hold is the
  `/works/<id>` line, and the implication that these values are properties of the
  endpoint rather than samples. Because the code comments state them as measured
  facts with a date, a future reader may treat a single value as a contract.
- **Root Cause**: One measurement per URL.
- **Recommended Fix**: Soften the two comments that enumerate per-endpoint
  headers to say these were sampled and that AO3 varies them by caching backend
  (`x-ao3-caching-backend` is present on some responses and absent on others).
  Keep the dates. Do not remove the measurements — they are still the best
  evidence available; they just are not invariants.
- **Scope**: Small (comment only)
- **Risk**: None
- **Dependencies**: None
- **Priority**: P4
- **Confidence**: High — repeated measurement.
- **Verification method**: `curl -I` ×3 per endpoint with a browser User-Agent.

---

## R3's fix, re-examined

The brief asks specifically about this one, because the agent's first attempt was
wrong. The version that survived is sound.

`requireParseableBlurbs: Bool = true` on `parseWorksList`, `false` from
`parseBookmarksPage` only. `parseSearchPage` relies on the **default**
(`AO3Client.swift:1251` passes no argument), which means the default is
load-bearing and is exercised: flipping it to `false` turns
`blurbsPresentButNoneParseableThrowsInsteadOfLookingEmpty` red, and removing the
`false` at the bookmarks call site turns the new regression test red. Both
directions are covered.

**Is default-`true` the right shape for future callers?** Yes. The default is the
strict, noisy behaviour, so a new caller that forgets to think about it gets the
parser-health signal rather than silence — failing loud is the correct default
for a scraper. Opting out is a deliberate act with a comment attached.

**Is losing the signal on bookmarks the right trade?** Yes, for now. There is no
sound negative test for that page: `blurbWorkID` returning nil is exactly what
`parseBlurb` throwing means, which is why the first attempt was unsatisfiable.
The report's note that a proper fix needs *positive* recognition of
series/external/deleted blurbs is right, and that is a feature (it would also let
the screen show series bookmarks instead of dropping them), not a fix. The
residual risk — an AO3 markup change to `li.bookmark.blurb` degrading into a
silent empty page — is the pre-change behaviour, so this is not a regression.
No finding.

---

## Tier 3 spot-checks

- **`verify.sh` preflight** — works. Copied into a Vendor-less root: exits 1 with
  the `Scripts/build-mupdf.sh` instruction and the symlink alternative. R13 fixed.
- **Sorted query-item emission is a *string* sort**, so the order is
  `116, 21, 22, 2246, 23, 24` rather than numeric. **Deliberate and correct** —
  the requirement is determinism, not ordering, and the comment says so ("AO3
  doesn't care about the order; those two do"). A numeric sort would be no better
  and would need the ids to stay numeric. Not a finding.
- **The four corrected comments** — I checked each against reality. 162 languages
  (matches AO3's 163 options including the blank); 911 → 917 (matches the
  `@Test` count and the suite output); the `sort_direction`-on-`_score` rationale
  now states the measured behaviour rather than "meaningless"; the cache-header
  comment rewritten and no longer contradicted by the code five lines away. No
  stale copy of any of the four survives elsewhere in the two reports or the
  source.
- **Anything else calling the changed APIs** — `worksPage(at:)` has exactly one
  caller (`NativeBrowseView:383`). `invalidateCachedResponses` has three call
  sites in four places. `AO3SearchFilters.excludedTagNames` has one consumer
  (`searchURL`). `quotedPhrase` has none, because it no longer exists. No orphans.

---

## What I Checked and Found Correct

Listed so the maintainer knows what was examined, not only what broke.

**The caching change**
- `invalidateCachedResponses()` **works** — `session.configuration` is a shallow
  copy, the `URLCache` reference survives it, memory usage drops to 0, and the
  next fetch is a real network load with a fresh CSRF token. The one knowingly
  unvalidated item in the batch is correct.
- Authenticated **reads** are genuinely bypassed, every time, measured.
- `AO3AuthService.authenticatedRequest` really is the single builder for
  authenticated requests — I enumerated every `URLRequest(url:)` in the target;
  the only others are the WebKit login flow and `about:blank`.
- The bypass broke nothing else: `authCoalescingKey` still keys on URL + cookie,
  `redirectCookieRelay` is unaffected, `purgeSessionCookie` runs only on the
  anonymous path, and setting the policy on the POST variant is harmless.
- `worksPage(at:)`'s comment is accurate on both endpoints it names.
- Browse's two refresh paths are correct, and for the right reason (they
  invalidate) rather than the hypothesised one.

**AO3 contract**
- `view_adult` filters nothing on a listing page: **92,495 Found with and
  without**, so no work class — including registered-users-only works — is gated
  by it. Claim 3 upheld.
- `excluded_tag_names` accepts one, two and three names, names containing spaces,
  and is split on commas by AO3 using the identical convention the app uses.
- `date_from`/`date_to` filter `revised_at`, confirmed in
  `work_query.rb:220-227` **and** live (1,985 vs 1,978 against the relative
  window). AO3 ANDs them with `revised_at` — 105 either way. Claim 6 upheld.
- `excluded_tag_names`, `date_from` and `date_to` are all in
  `WorkSearchForm::ATTRIBUTES` (lines 26, 41, 42).
- The 74,261 / 73,419 exclusion arithmetic reproduces to the digit.
- `/works/search` served `max-age=600, public` on all three runs — the one
  measurement everything else depends on is stable.

**Code and tests**
- `quotedPhrase` had exactly one caller at `b9d70515`; deleting it was safe, and
  no path now interpolates *synthesized* user text into query syntax. Claim 9
  upheld.
- No test file was clobbered: `@Test` counts rise monotonically 911 → 917 across
  the eight commits, and the only deletions are the two `quotedPhrase` tests plus
  three renames.
- `verify.sh` is genuinely green — 917 tests, 82 suites, exit 0, **zero** real
  skips (every `skipped`/`withKnownIssue` string in the log is a test name or a
  library log line). Claim 10 upheld, including the count.
- Three mutations die in the right test: the facet-id table (R4), the URL-stability
  sort (R6), and R3's scoping. These fixes are load-bearing, not decorative.
- `refreshCurrentResults`'s rewrite has no lost wakeup, no swallowed throw, no
  stuck spinner, and no task-replacement race — the `loadTask` read cannot see a
  different task than the one `load(page:)` just created.
- The `RequestCoalescer` comment rewrite is correct; I re-derived the argument
  independently and agree the set is correct by construction.
- `AO3SearchFilters`'s `Codable` path itself is sound: a legacy `{"updated":"any"}`
  payload decodes with `dateFrom == nil`, and a populated struct round-trips equal.
- `dateFrom`/`dateTo` land as nullable `TIMESTAMP` columns — a safe additive
  SwiftData migration, now confirmed against a real migrated store rather than
  argued.
- The `AND` semantics the filter panel's footer promises are real.
- The date-bound UI shape (`Toggle` carries the optionality, seeds `Date()`
  rather than a silent 2001 default) is a good call; the defect is in the
  formatter, not the control.

---

## Unknowns & Residual Risk

1. **No AO3 credentials.** Every header in this report was measured anonymously,
   or with a well-formed *fake* session cookie. That is enough to show AO3
   branches on cookie presence (`/series/1234` goes `public` → `private`), but not
   to prove it branches identically for a real signed-in session. The single
   check most likely to change a verdict here is still the one the previous report
   named: **fetch `/users/<n>/bookmarks` while genuinely signed in and read its
   `Cache-Control`.** If it stays `public`, S3 stops being a documentation defect
   and becomes a real one.
2. **I did not run the app.** Everything behavioural was proved with standalone
   probes reproducing the app's configuration and call shapes verbatim, not by
   driving the UI. S1's four gaps are proved at the transport layer; I did not
   watch a pull-to-refresh fail on screen.
3. **The `Language` SwiftData question (S5) is open.** Every store on this machine
   holds zero `SavedSearch` rows, so I could not observe what happens to a saved
   search's language across the `0c71a730` schema change. The mechanism is
   certain; the outcome is not. It needs a populated old store and a launch.
4. **AO3's headers are a live-service detail, and demonstrably not stable** (S10).
   Everything in the caching sections is dated 2026-08-06 and two of the previous
   report's values already fail to reproduce one day later.
5. **S4 is a static finding.** I read the complete task lifecycle and the
   cancellation-site census for `SearchView` is exhaustive, but I did not observe
   an abandoned refresh completing.
6. **S9's reachability is reasoned, not instrumented.** The race is demonstrated;
   how often a user hits it in the app is not measured.
7. **`FandomListView` is protected by page size, not by design** (S1). I measured
   2.5 MB today against an 8 MB memory cache. A smaller fandom index — or a larger
   cache — makes it a real gap with no code change.

---

## Prioritized Action Plan

### Immediate (Critical)

*Nothing.* No data loss, no wrong AO3 constant, no cross-identity leak. The branch
is safe to keep.

### High Priority — before pushing

1. **S2 — fix the date timezone, and fix the test with it.** Smallest diff,
   clearest user-visible wrongness, and it must be done *with* the test or the
   suite blocks it. Do this first: it is the only item where the existing tests
   actively resist the correct behaviour.
2. **S1 — close the four refresh gaps.** Decide the mechanism first (S8): I
   recommend the per-request `.reloadIgnoringLocalCacheData` the review
   originally preferred, because it also dissolves S9 and removes the need to keep
   a call-site census correct forever. If the blunt invalidation stays, add four
   one-line calls and say in the doc-comment why it is the house style.
3. **S3 — correct the `authenticatedRequest` comment** (one sentence), or make it
   true with a `willCacheResponse` delegate. Correcting it is the minimum; the
   comment currently asserts an invariant the app does not enforce.

### Medium Priority

4. **S4 — restore gesture cancellation on `SearchView`'s refresh** (~4 lines), or
   at minimum stop the report claiming that path is covered.
5. **S5 — settle the `Language` migration question** against a populated
   pre-`0c71a730` store, and add one `ModelContainer` round-trip test so
   `SavedSearch` persistence is covered by the mechanism it actually uses.
6. **Add one test for the invalidation.** M4 shows the whole mechanism can be
   emptied with the suite green. A test that fetches a stubbed URL twice, calls
   `invalidateCachedResponses()`, and asserts `urlCache.currentMemoryUsage == 0`
   costs a few lines and would have caught a genuinely broken implementation.

### Nice to Have

7. **S6** — one sentence correcting the exclusion mechanism in the code comment
   and the report's correction #2.
8. **S8** — record the cache-bypass decision wherever it lands.
9. **S10** — soften the two per-endpoint header comments to say "sampled", keeping
   the dates and values.
10. **S7, S9** — documented above; no change recommended.

### Recommended order of work

```
S2 (date + its test)  ──►  decide mechanism (S8)  ──►  S1 (four gaps)  ──►  re-run verify.sh
                                                          │
S3 (comment or delegate) ─────────────────────────────────┤
                                                          │
S4 (cancellation) ─┬─ S5 (Language check + container test) ┴─►  S6, S8, S10 (comment truth-up)
                   └─ invalidation test (item 6)
```

**S2 first** because it is the only item the test suite currently blocks, and
because it is a wrong answer given to the user rather than a missing optimisation.
**S8 before S1**, because choosing the mechanism changes what the S1 fix looks
like — four one-line calls versus one parameter — and doing S1 twice is the
avoidable outcome. **S3 in the same change as S1**, while the caching model is
being reasoned about, exactly as the previous report argued for R1/R2/R12. The
test items are independent and can proceed in parallel.

The pattern worth carrying forward from both passes: on this codebase, fixes that
stay inside the code have been right every time. The ones that go wrong are the
ones resting on a claim about a system the app does not own — AO3's headers,
`URLSession`'s caching contract, SwiftData's storage model, the user's calendar.
Those are the four places to spend verification effort, and in each case the
verification is cheap: measure it, twice.
