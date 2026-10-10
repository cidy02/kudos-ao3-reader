# 3ce result — cached AO3 pages

## iOS reference (read from code)

`AO3AuthorPageCache.Key` is the full URL (including query/page) plus `authenticationScope`. The default scope is `signed-in:<username>` or `anonymous`; the private scope appends `#session-<sessionGeneration>`. Inbox and dashboard-only Account use that private scope; ordinary author profiles and series use the default. Fresh lifetime: 5 minutes; fallback lifetime: 24 hours from insertion, not from last access. Both boundaries are strict (`> now`). Capacity: 128, evicting the earliest stale deadline, not least recently used. Reinsertion replaces both deadlines. Expired entries are pruned on insertion/access. It is a process-local actor singleton, with no disk/backup representation.

`page` checks `isCurrent`, uses a fresh entry unless `bypassCache`, constructs the authenticated request before awaiting, reads through the coordinator/client, then inserts HTML. Parsing happens afterwards: parser errors invalidate the exact URL. A bypass skips only the fresh hit; it still permits fallback. Its exact failure handling is:

```swift
} catch is CancellationError {
    throw CancellationError()
} catch AO3Error.authenticationRequired {
    // Never hide an expired session behind cached authenticated markup.
    guard isCurrent() else { throw CancellationError() }
    throw AO3Error.authenticationRequired
} catch {
    guard isCurrent() else { throw CancellationError() }
    if let stale = await AO3AuthorPageCache.shared.staleValue(for: key) {
        guard isCurrent() else { throw CancellationError() }
        return Page(html: stale, isStale: true)
    }
    throw error
}
```

Android deliberately narrows that last catch: transport failures, 5xx and AO3 busy only; never authentication, 403, 404, other 4xx, validation or parser drift. Android also uses session generation for every viewer, including signed-out, as required by this brief (stricter than ordinary iOS author/series scope).

## Policy

The Author profiles row permits “a 5-minute TTL keyed by full URL and authentication scope” and “at most 24 hours of same-scope stale fallback”; it says “stale data never crosses accounts or hides session expiry” and caps the cache at 128. These permit the HTML, deadlines, capacity and viewer isolation here. Account Dashboard “loads only its dashboard page” and its “private HTML cache and activation use the session-generation scope”: no speculative account list read is added. Inbox metadata is isolated by “account **and session generation**” and must “Never prefetch Inbox from Overview, follow pagination, or poll in the background”: this cache adds no enrichment, crawl or polling. The must-not list says “No background or bulk scraping of logged-in pages” and “no bypassing `AO3Client`”: all reads below use existing clients and repositories.

## Implementation / verification

Implemented in this worktree, uncommitted. No Gradle/Xcode execution, sign-in or network access; build, unit tests and visual verification remain for Claude.

## Decided without asking

- One `network/ao3/AO3PageCache.kt`, shared by the relevant repositories; HTML/response data only in memory.
- Page-kind discriminator in addition to URL and viewer scope prevents a different parser/page kind sharing a slot (A22-2).
- Use existing fixtures and fake clients; no extra fixture archive or disk cache.

## Open questions

- iOS allows more fallback errors and weaker scope for public author/series pages. Follow the explicit stricter Android requirements above; no additional reads.

## iOS: complete read/write and banner trace

Read-through callers found by searching all `AO3AuthorProfileFetcher.page` calls:

- `AO3AuthorProfileModel`: dashboard header; Works (ordinary, Collected Works and Gifts, including sort/filter/fandom URLs and every requested page); Series index and pages; Bookmarks index and pages; About; optional **own account only** `/stats`; block/mute confirmation pages (always bypassed). Dashboard-only activation skips the selected index but still calls the own-stats path when it owns the route. Ordinary author activation waits for a usable header before the selected index. Stats are silent, once per model until reset, never someone else's stats.
- `AO3InboxModel`: the visible Inbox page, with its exact filter query and pagination, under account + session generation.
- `AO3SeriesDetailView`: the requested series page, then additional pages on demand; import/preservation is a separate path.
- `AccountWorksInlineSection` in `AccountComponents.swift`: its opened account-list URL under the private generation scope (including the subscription-specific parser).
- `AuthorNewestWorkStore`: one first works page per registered author, **only** when the approved Favorites → Authors destination is explicitly opened; private generation scope and current-session fence.

Reads that do **not** use this singleton: the underlying `getHTML`/`authenticatedPageHTML` calls except when invoked by the fetcher; normal search/tag/browse, work metadata/pages/EPUBs; `AO3AuthService.accountWorks` / `accountSubscriptions` and other account list services; comments and chapter indexes (their own screen-owned caches); write form/token reads outside the author moderation confirm path; login/session validation; series import/preservation `seriesWorks`. Referencing the fetcher's scope helper in those callers is not a cache read. No new anonymous fallback read follows an authenticated refusal in this port.

The only network insertion is `page` after a successful client read and current-context check. Parsing failure in the author model and series view removes the exact key. `removeValue` also handles expired access, eviction and explicit invalidation. `insert` prunes entries past the fallback deadline, evicts the earliest deadline if adding entry 129, and replaces an existing entry's HTML and both deadlines.

Writes and explicit removals in iOS:

1. Successful user subscribe/unsubscribe: `toggleSubscription` → `invalidateAuthorDashboards`: all dashboard/pseud-dashboard URLs for that target username, under the action's captured authentication scope; leaves indexes and other viewers alone. Reloads header with bypass.
2. Successful block/unblock/mute/unmute: `confirmPendingModeration` performs the same dashboard removal and bypassed header reload. Beginning moderation reads its confirmation page with bypass; it is not a write/removal.
3. Successful Inbox Mark Read / Mark Unread / Delete: `AO3InboxModel.performAction` removes **all query/page variants** at that account's Inbox path in its captured generation scope. If action URL differs from referer it also removes that exact action URL key. Reloads visible page with bypass.
4. Parser invalidation removes only the failed URL/scope. No series-edit/reorder removal of this singleton was found in the reference; it is not invented here.

`bypassCache` means “skip fresh memory”, not “disable saving or offline fallback”. Author retry bypasses the header only if not loaded and always the selected tab; pull refresh bypasses header and selected tab, after also clearing iOS's underlying HTTP cache. Author post-write header reload and moderation confirmation bypass. Inbox retry, pull refresh, filter application and post-write reload bypass; ordinary pagination does not. Series retry and pull refresh bypass (refresh starts page one and clears the HTTP cache); initial page/pagination do not. Account refresh delegates to the profile model for Overview/Works/Series/Bookmarks; other account-list tabs use their separate reload paths.

**Reference-code disagreement with the summary:** `AO3InboxModel.authContext` is a sentinel (`scope: "", generation: -1`). Its comment explicitly says the first `activate()` “always resets and bypasses the cache”. `activate` passes `bypassCache: didTransition`. Thus a **new** Inbox model on reopening makes a page request even inside five minutes. Reopening an already-loaded model makes none (`phase != .idle`). Android follows the real code: `AccountInboxViewModel` initial load and session-transition load bypass; ordinary page reads can hit fresh cache. Filter application now also bypasses, matching the reference.

Every banner says **“Showing cached AO3 data”**, symbol **`wifi.slash`**:

| Place | Flag and placement | Clearing |
|---|---|---|
| Inbox | A parsed page assigns `isShowingStaleCache = fetched.isStale`; first segment of the comments panel, above notifications (including empty-page case). | A non-stale parse assigns false; `reset()` clears it on account/session change/sign-out. |
| Account tab's profile lists | Uses `profileModel.isShowingStaleCache`, only in loaded profile content, ahead of Works/Series/Bookmarks. List gets a section/card row; compact gets a horizontal-gutter label. | Model dashboard success replaces the flag with the header's `isStale`; selected-page parses OR their stale flags into it; auth reset clears. |
| Author profile | Same model flag; section after scope/tab controls and before dashboard/content. | Same dashboard-replacement/tab-OR/reset rules. A fresh *tab alone* need not clear an older model flag; a successful full refresh does. |
| Series | Section between series summary and Works. Replacing a load assigns the page's stale flag; appending pages ORs it. | Fresh replacement clears; the auth-scope task resets it before loading, including on sign-out. |

No shared cache `clear` is called on iOS sign-out/session change. The private generation key makes those entries inaccessible to the new private scope, though they remain in memory until expiry/eviction. Ordinary author/series keys are only username/anonymous: a same-username relogin or a later anonymous view can reuse that same scope in the reference. Android is intentionally stricter per the brief: generation on all keys **and physical clearing** at every auth-generation transition. Relaunch loses the singleton on both platforms. Counts cache conventions are memory-only, scoped, TTL-based and never fetch on their own; its own 30-minute count TTL is unrelated to HTML deadlines.

## Android implementation and request accounting

`AO3PageCache.shared` owns immutable page responses/HTML, stripping response headers (including Set-Cookie) before keeping a copy. It has no `Context`, file path, serializer, Room entity or backup field. Key = full requested URL + (`username?`, session generation) + page kind. Anonymous uses a null username **and the real client's generation**. Full URLs distinguish pages, filter/sort/scope/fandom query variants; kind distinguishes incompatible consumers. Cache and invalidation operations are synchronized. A revision and viewer fence prevent suspended reads from reinstalling a copy after invalidation/session change. Cancellation never becomes fallback. Only a correctly parsed page is stored; parser drift discards the matching old copy.

Production `DefaultAO3AuthenticatedClient.sessionChanges` exposes the existing generation StateFlow. Screens collect it with StateFlow's current initial value, so a synthetic initial zero does not trigger a duplicate first read. Author and series display state is keyed to that collected generation; Account's combined state masks a header whose generation differs; its refresh also checks the current username before dispatch so logout cannot queue an anonymous read of the former account; Inbox cancels/reset/reloads on the generation signal. `advanceSessionGenerationLocked` clears the shared cache before publishing the next generation (restore, login, sign-out, expiry, successful verification refresh; debug demo restore too).

Repository entry points cached here: `AO3AuthorRepository.loadDashboard/loadAbout/loadWorks/loadFandomWorks/loadSeries/loadBookmarks`, `AO3InboxRepository.load`, `AO3SeriesRepository.detailPage`. `seriesPage/seriesWorks`, search-based `AO3AuthorWorksRepository`, work/form/comment/chapter/account-list clients are left on their existing paths. No read-ahead, refresh timer, background refresh or second HTTP transport is added.

Per-page client-call increments, starting empty and with success:

| Visible read | First | Reopen <5 min | Reopen ≥5 min, <24 h | Pull refresh |
|---|---:|---:|---:|---:|
| Author dashboard/header | 1 | 0 | 1 | 1 |
| Author selected Works (or explicitly selected Series/Bookmarks/About) | 1 | 0 | 1 | 1 |
| Own profile route (header + selected index) | 2 | 0 | 2 | 2 |
| Account hub's existing header | 1 | 0 | 1 | 1 |
| Series detail, current page | 1 | 0 | 1 | 1 (page one) |
| Inbox, **new model** each opening | 1 | 1 | 1 | 1 |
| Inbox, loaded same model reactivated | 1 | 0 | 0 | 1 |
| Inbox repository same-session page revisited | 1 | 0 | 1 | 1 |

These are **client calls for these HTML pages**, not individual internal retry attempts. The same fresh-hit/bypass rules apply in iOS. Unreachable reads still make the normal foreground attempt before fallback, even within the fresh lifetime when bypassed. After 24 hours there is no fallback. Refusals remove the matching copy immediately and return the existing typed error; a later offline retry cannot resurrect it.

**Existing full-screen request differences (kept sparingly, not hidden):** current iOS's ordinary own-profile/Account model also reads optional own `/stats` once on activation, and Account Overview activates its selected Works index even though the visible identity card uses the header. Android has no own-stats loader and its hub currently reads only the header (and may already load Subscriptions for existing counts). This brief adds no stats feature or speculative Works/Subscriptions read to the hub. Thus total whole-screen counts for those existing ancillary paths are not equal to iOS: the table isolates the implemented HTML reads. No own-stats or count traffic is claimed tested here. Inbox work-context hydration is another separate existing client path; stale fallback skips new hydration, failures are remembered before attempts, and a systemic failure stops the batch. This is deliberately more sparing than iOS's per-revision enrichment of a stale page.

Banners use `CachedAO3DataRow` in `ui/components/` (no edits under `ui/subject/` or `settings/`). `WifiOff` is the native equivalent of `wifi.slash`; its tint is `tokens.scopePalette.accent`, label `tokens.secondaryInk`, explicit 20sp line height. A weighted, unbounded-height text label wraps at accessibility font scale rather than clipping/ellipsizing. Ordinary size is one line. Inbox attaches it as the first segment of its existing lazy notification panel and removes top rounding from the following row. Author/own profile places it after profile/tab controls before content; Account hub after identity; series after header before Works. All use the existing theme tokens for Light/Dark/Sepia/OLED. No stock chip/card/snackbar or new shared-component metrics.

A successful full refresh clears the author/own-profile aggregate flag via fresh header + selected content. Inbox, hub and series directly assign the returned `isStale`. A stale loaded screen retains the same forms, rows, metadata and navigation afforded by its copy. Existing writes from those screens:

- Inbox: parsed bulk form still supports Mark Read, Mark Unread and Delete, same-session, single-shot POST, no token re-GET. Only a confirmed success invalidates all Inbox variants plus the exact differing action URL. Unconfirmed/refused writes keep their verdict and do not invalidate. Post-write reload bypasses fresh cache. Busy flag has `finally`; a departed viewer cannot receive a late action verdict.
- Author: Subscribe and block/mute currently hand off to the existing web route; no Android native author POST equivalent exists. They continue that handoff from the loaded copy. Therefore no native Android subscribe/block/mute write was invented. Cache has the corresponding dashboard-removal operation with tests, ready for the native action port; web changes can be re-read with pull refresh. This is an existing product difference from iOS, not a claim that web writes now notify native cache.
- Own profile / hub: existing destinations and session controls remain usable; the own-profile route keeps the same existing author web handoffs. No native write is synthesized from profile HTML.
- Series: Edit/Reorder still fetch their fresh forms through existing repositories; stored listing HTML is not a write form. Reloading listing never clears a writer's in-progress text/target. No extra invalidation absent from the iOS reference is added.

## Local demo

Debug builds only, existing demo fixture mode required. Start the demo normally (the existing **local** fake session is `--ez kudosDemoSignedIn true` alongside `--ez kudosDemoLibrary true`; this is not a live login). Open Inbox, own profile, Avery's profile, and/or Dawn Cycle once successfully. Then send a new intent to the **same process**:

```sh
adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoCachedPagesOffline true
```

This calls the existing demo interceptor before its fixture dispatch; selected page GETs throw a local `UnknownHostException`, never contacting AO3. Pull to refresh any opened screen to bypass fresh memory immediately; it shows the banner and its saved rows. A newly opened Inbox bypasses immediately as iOS does. Ordinary author/series reopening inside five minutes is correctly answered from fresh memory without a banner; pull refresh or wait five minutes to demonstrate fallback. Flip back using the same command with `false`, then pull refresh; the successful fixture removes the banner. Do not force-stop between these taps: memory must survive. The switch does not expire the cache, forge a stale flag, change production behavior, affect POSTs or fail edit/reorder form GETs.

Fixture selectors checked against actual demo routes/data:

- Inbox: `/users/AO3_Reader/inbox` → `ao3_inbox_manage`, notifications 9001/9002/9003 and its parsed bulk/filter forms.
- Account hub/own profile: `/users/AO3_Reader` → `ao3_author_dashboard_demo`; own profile Works → `ao3_author_works`.
- Author: `/users/Avery_Archive` → the same dashboard fixture; Works → `ao3_author_works` (includes **Two Voices at Dawn**); other tabs retain their existing profile/series/bookmark fixtures.
- Series: `/series/321` → `ao3_demo_dawn_series`, **The Dawn Cycle**, **First Light**, **A Lamp at the Crossing**, creators from series metadata.

The failure selector accepts user/pseud dashboards and exactly `/inbox`, `/profile`, `/works`, `/works/collected`, `/gifts`, `/series`, `/bookmarks`, plus numeric series show pages. It excludes `/profile/edit`, `/series/321/edit`, `/series/321/manage` and POSTs. No new fixture files.

## Verification and handoff

Written, **not executed** (no Gradle/Xcode allowed):

- `AO3PageCacheTest`: exact fresh/fallback boundaries with controlled time; 128-entry eviction; full URL, page-kind and two-session/anonymous isolation; all-Inbox-variant and pseud-dashboard removals; cancellation fence after clearing; parser failure; empty temporary directory and new-cache emptiness.
- `CachedAO3PagesRepositoryTest`: every cached screen/page's first/fresh/expired/bypass counts; combined author header+Works counts; iOS Inbox first-activation bypass; offline, timeout, transport drop, 500/503/502 and typed/HTML busy fallback; authentication/403/404/other HTTP/rate-limit/parse/validation refusal, followed by offline to prove no resurrection; banner metadata clearing on success; session/anonymous isolation; every confirmed Inbox action's removals and unconfirmed retention.
- `CachedAO3SessionTest`: real auth repository logout and same-username verification refresh physically remove a key even if the old key is retained by the test. All session storage/cookies/validation are local fakes, not login/network.
- `CachedAO3PagesScreenTest`: actual Inbox, own/other author profile, series and hub show/clear the banner, author pull refresh, refusal followed by offline reopening on Inbox/author/series, and tokenized banner layout in all four themes at 2× font scale. Native Robolectric graphics, tall 2400dp window, real-time waits for off-main parse effects, no database/client shutdown in `@After`.
- Existing author/repository/screen suites clear the process singleton before each test to avoid cross-test fresh hits.

Performed here: read real Kotlin constructors/interfaces/parser exceptions/palette fields/theme enum and all changed call sites; static whitespace check `git diff --check` and delimiter scan of changed Kotlin files (neither is compilation); checked demo selector against its actual fixture rows/URLs; inspected only this worktree plus the read-only iOS reference. No runtime/build/test pass or visual correctness is claimed. Claude must compile Android and run the new suites plus existing author sort/profile, Inbox, session generation, series/write and Account regression suites; verify pull gestures/cancellation and Light/Dark/Sepia/OLED screenshots with normal and accessibility text before landing. No branch switch, commit, push, AO3 contact, `TASKS.md`, Room schema or backup-format edit.

## Additional decisions without asking

- iOS's actual new-Inbox-model bypass wins over the brief's initial summary. Recorded the separate loaded-model and new-model counts above.
- Kept Android's existing whole-screen read set: no ancillary stats port or speculative hub index read. Differences are listed rather than adding unseen requests.
- Stale Inbox fallback does not retry optional metadata; fresh explicit refresh may retry failed attempts, while already resolved metadata wins. Systemic failure stops at that attempted work.
- Kept series import/preservation uncached; only detail-page reads use this shared cache.
- Existing captured HTML fixtures and test-local fake clients; source/test file names describe cached pages, and none contains the forbidden filename word.

## Additional open questions (sparing decisions applied)

- Full Account/own-profile ancillary `/stats` and selected-index parity is a separate port decision; no additional requests sent here. The cache's per-page counts match the reference, while the pre-existing whole-screen differences above remain explicit.
- Native author subscribe/block/mute has not landed on Android. Existing web handoff remains; no new native write or background invalidation probe.
- iOS's author banner is sticky across fresh tab-only loads and resets via dashboard refresh; Android follows that model. Series's existing Android pagination replaces a page rather than appending iOS's accumulated pages; banner follows the displayed replacement. No paging redesign in this brief.

## Landing note (Claude, 2026-10-09)

Landed after a hand merge with brief 3cd in `author/AuthorProfileScreen.kt` (six regions:
3cd's own-works state and bar, this brief's pull to refresh and cache). Gate: 2,510 tests.
**Not yet seen on the emulator.**

- **After the writer's own delete or edit the page is read again from AO3**, not from the
  cache: 3cd's reloads now pass `bypassCache = true`. This brief did not know those writes
  and removes nothing for them, so the reload would have shown the list as it was.
- `loadHeader` takes both changes' parameters (`bypassCache`, then 3cd's callback, which
  runs where it did: after a successful load of the route still on screen).
- The list sits in the refresh box, the box takes the column's free height, and 3cd's
  selection bar stays under it.
- One test repaired: `AO3SeriesRepositoryTest` built two repositories for one address and
  the second was answered from the first's fresh copy in the shared cache. Each now has its
  own cache. **Any test that builds a repository with the default cache shares it with every
  other test in the run**: pass `pageCache = AO3PageCache()` in new tests.
- Read line by line: `network/ao3/AO3PageCache.kt` (keyed by address, viewer name and
  session; an old copy only after no connection, a timeout, "AO3 is busy" or a 5xx, never
  after a refusal; nothing kept when the session moved on meanwhile) and the clearing in
  `auth/AO3AuthRepository.kt` (every step of the session clears everything).
- Not read line by line: the four screens' banner wiring and the Inbox's removals. Gemini's
  index is `audits/A34-result.md` (unread). A Codex review of the landed code is owed.

### Seen on the emulator (Claude, 2026-10-10, airplane mode, the demo's local answers)

**The command under "Local demo" does not work as written.** Without
`--activity-single-top` the running activity never receives the extra, and the reads go on
succeeding. Use:
`adb shell am start -n io.github.cidy02.kudos/.MainActivity --activity-single-top --ez kudosDemoCachedPagesOffline true`
(and `false` to turn it back).

- Own profile, Light: with reads failing, a pull shows "Showing cached AO3 data" above the kept
  rows; a tab never read says "Couldn't load series", "You're offline. Try again when you're
  back online." with Retry; with reads working again a pull removes the banner and the failed
  tab loads.
- A series, Dark: the banner above the kept works.
- The Inbox, Dark: **the first pull after opening shows "Couldn't load your inbox", not the
  kept page.** The opening reads the plain Inbox address and a refresh reads the address the
  filter form gives, so no copy is kept under the second until one refresh has succeeded;
  after that a failing pull shows the banner and the kept rows. iOS builds the address the
  same way (`AO3InboxModel.inboxURL`), so both apps do this. P3, not changed.
- Not seen: another author's profile; Sepia, OLED and twice the text size.
