# Phase 11 — Android Browse + WebView Fallback (Claude)

Dedicated handoff for parallel work. Phase 10 (authenticated AO3 writes/comments)
was being implemented by Codex on `kudos-ao3-reader-android` at the same time, so
this phase is isolated and avoids editing shared write/comment/auth files.

## Branch / base

- Branch: `kudos-ao3-reader-android-phase-11-browse` (separate `git worktree` at
  `../kudos-ao3-reader-android-phase-11-browse`).
- Base commit: `1d9a7c9` (tip of `kudos-ao3-reader-android` at start; the T-66
  verification commit).
- Phase 10 was running in parallel in the main worktree (uncommitted at the time:
  `AO3Client.kt`, new `network/ao3/writes/`, `network/ao3/comments/`, evolved
  `AppNavHost.kt` / `WorkDetailScreen.kt` / `KudosAppContainer.kt`). None of that
  is in this branch — it builds on the clean `1d9a7c9` base.

## What you found from prior handoffs

- Phase 5 search infra (`AO3SearchParser`, `AO3WorkSummary`, `AO3SearchRepository`,
  `AO3SearchFilters` with a `fandom` field, `AO3WorkCard`) is reusable for fandom
  work lists.
- Phase 4 polite client (`OkHttpAO3Client` + coordinator/retry/coalescing) is the
  GET path; `AO3OverloadDetector` flags capacity pages.
- Navigation uses module-level `remember` state in `AppNavHost` keyed by `Routes`
  constants; Work Detail is canonical via `WorkDetailSource.RemoteSummary`.
- Apple reference: `AO3Client.mediaCategories()` parses `/media`
  (`ul.media.fandom.index.group li.medium.listbox.group`), and `fandoms(atPath:)`
  parses `/media/<name>/fandoms` (`ol.fandom.index li a.tag` + work count). Ported
  selectors faithfully.

## Design decisions

- **Fandom work lists reuse Phase 5 search** (`work_search[fandom_names]=<fandom>`)
  rather than building/escaping `/tags/<name>/works` URLs. AO3 tag-URL escaping
  (`/`→`*s*` etc.) is error-prone; the search path is correct, already encoded, and
  reuses the existing parser/pagination/overload handling. The fandom name from the
  catalog is AO3's canonical tag name, so the filter is exact.
- **WebView fallback is read-only** and AO3-only; it is NOT the Phase 9 auth
  WebView (left untouched).

## Files changed

New (`network/ao3/browse/`): `AO3BrowseModels.kt`, `AO3BrowseUrls.kt`,
`AO3BrowseParser.kt`, `AO3BrowseRepository.kt`.
New (`browse/`): `BrowseLocalIndicators.kt`, `BrowseUi.kt`, `FandomListScreen.kt`,
`FandomWorksScreen.kt`; replaced placeholder `BrowseScreen.kt`.
New (`web/`): `AO3WebUrlPolicy.kt`, `AO3WebViewFallbackScreen.kt`.
Edited (additive, shared — expect merge conflicts after Phase 10): `app/Routes.kt`,
`app/AppNavHost.kt`, `app/KudosAppContainer.kt`.
New tests: `network/ao3/browse/AO3BrowseUrlsTest`, `AO3BrowseParserTest`,
`AO3BrowseRepositoryTest`; `web/AO3WebUrlPolicyTest`; `browse/BrowseLocalIndicatorsTest`.
New fixtures: `src/test/resources/ao3/browse/{categories,fandom_list,empty_category,overload,parser_changed}.html`.

## Dependencies added

None. (Android `WebView` + the existing `INTERNET` permission from Phase 9 cover
the WebView fallback; no new Gradle deps.)

## Browse behavior implemented

- Top-level Browse fetches AO3's `/media` categories natively (loading / error +
  Retry + "Open on AO3" / empty states).
- Category → `FandomListScreen`: fetches `/media/<name>/fandoms`, parses fandoms +
  work counts, dedupes first-seen, supports a local in-list filter, and a WebView
  fallback ("Open on AO3").
- Fandom → `FandomWorksScreen`: fetches works via the Phase 5 search path, reuses
  `AO3WorkCard`, supports pagination, overlays local indicators (Saved /
  Downloaded / Favorite / Finished) from a single `observeSavedWorks()` snapshot.
- Tapping a work opens the canonical Work Detail (`WorkDetailSource.RemoteSummary`).
- Browse never auto-saves: `AO3BrowseRepository` has no `WorkRepository`/DB handle;
  indicators are a pure read-only mapping (`BrowseLocalIndicators`).

## WebView fallback behavior

- `AO3WebViewFallbackScreen` hosts a `WebView` via `AndroidView`. Policy
  (`AO3WebUrlPolicy`): AO3 https stays in-app; other http(s) is externalized via
  `ACTION_VIEW`; non-web schemes (`javascript:`, `intent:`, `file:`) are blocked.
- Android back walks WebView history first (`BackHandler` + top-bar Back), loading
  progress bar, main-frame error state with Retry + "Browser", and an "Open in
  browser" action. No JS bridge/injection (JS + DOM storage enabled only for
  rendering).

## URL safety policy

- `AO3BrowseUrls.resolveAo3Url` resolves relative hrefs against the AO3 base and
  returns null for non-AO3 hosts (open-redirect protection); preserves existing
  percent-encoding (no double-encoding).
- `isAo3Url` requires https + apex/subdomain of `archiveofourown.org` (rejects
  `notarchiveofourown.org`, `archiveofourown.org.evil.com`, plain http).

## Local indicator behavior

- `BrowseLocalIndicators.index()` keys saved works by `sourceUrl`; `forWork()`
  matches `AO3WorkSummary.workUrl`. `isFinished` is local reading state and is
  never derived from the AO3 `isComplete` completion flag (explicitly tested).

## Tests added & results

- `AO3BrowseUrlsTest`, `AO3WebUrlPolicyTest` (URL building/safety + WebView policy),
  `AO3BrowseParserTest` (categories/fandoms/overload/empty/changed-markup),
  `AO3BrowseRepositoryTest` (categories/fandoms/works via fake client, no-network
  guards, search-filter URL), `BrowseLocalIndicatorsTest` (mapping +
  complete≠finished + no-mutation by construction).
- Commands: `./gradlew :app:assembleDebug :app:testDebugUnitTest` → **BUILD
  SUCCESSFUL, 202 JVM tests, 0 failures** (was 177 on the base; +25 from new
  browse/web tests).

## Manual verification

NOT performed — no emulator/device in this environment. The repository/parser/URL/
policy layers are unit-tested; the actual Browse screens and the WebView fallback
(rendering, back-stack, external-intent handoff) need device verification. The
prompt's manual checklist applies.

## Parallel-work / merge notes

- I did NOT edit `TASKS.md` or `docs/ai/HANDOFF.md` to avoid clobbering Codex's
  Phase 10 edits. **Post-Phase-10 follow-up:** add a Phase 11 row to `TASKS.md` and
  a pointer in `docs/ai/HANDOFF.md`.
- **Expected merge conflicts** when rebasing onto post-Phase-10
  `kudos-ao3-reader-android` (Phase 10 touched the same shared files):
  - `app/AppNavHost.kt` — both add routes/state; my Browse additions are additive
    blocks (Browse/BrowseFandoms/BrowseWorks/WebFallback). Resolve by keeping both.
  - `app/KudosAppContainer.kt` — my `browseRepository` is appended at the end;
    Phase 10 added `writeRepository`/`commentRepository`. Keep both.
  - `app/Routes.kt` — both add route constants + `titleFor` arms. Keep both.
  - No overlap expected in `network/ao3/browse/`, `browse/`, `web/` (new packages).
- Recommended merge order:
  1. Finish + merge Phase 10 into `kudos-ao3-reader-android`.
  2. Rebase this branch onto updated `kudos-ao3-reader-android`.
  3. Resolve the three shared-file conflicts above (additive — keep both sides).
  4. Run `:app:assembleDebug :app:testDebugUnitTest`.

## Known gaps / deferred

- No device/manual verification (no emulator here).
- Category/fandom counts beyond what the index exposes are not scraped (no
  background crawling, per the politeness rules).
- Fandom work lists use default RELEVANCE sort; per-fandom sort/filters UI deferred.
- Recently-visited fandoms (local history) not implemented (no local browse-history
  store yet).
- Direct `/tags/<name>/works` native page parsing not added (search path used
  instead); the WebView fallback covers any AO3 page we don't render natively.
- No final HIG/Material UI polish (explicitly out of scope for this phase).

## Recommended next step after Phase 10 merges

Rebase, resolve the three additive shared-file conflicts, re-run the build/tests,
then (optionally) a device pass over Browse + the WebView fallback before the final
UI-polish phase.
