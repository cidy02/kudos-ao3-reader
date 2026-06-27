# TASKS.md — Kudos task board

Shared, lightweight task board for all AIs + the human. **Read [`AGENTS.md`](AGENTS.md) first.**
Update this file whenever you start, finish, or hand off work — it is the primary
handoff channel between sessions and between agents.

## How to use it (30 seconds)

- **Claim** a task → move it to **In Progress**; set `Owner`, `Branch`, status `🔄`.
- **Finish** → move it to **Completed** with the commit SHA(s) + date.
- **Hand off / block** → leave it in **In Progress** with `✋ HANDOFF` or `⛔ BLOCKED`
  and a clear **Next step** / **Blocker**.
- Keep entries short; link to `docs/…` or `READIUM_MIGRATION_NOTES.md` for detail.
- Task IDs are `T-NN` (just for cross-reference; pick the next free number).

**Status:** 🔄 in progress · ✋ handoff (ready for pickup) · ⛔ blocked · ✅ done · 🅿️ backlog

---

## 🔄 In Progress

| ID | Task | Owner | Branch | Status | Next step / notes |
|----|------|-------|--------|--------|-------------------|
| T-55 | **Android Port Phase 0 — contract/docs preparation**: add the approved Android port plan, contract skeletons, branch policy, current Apple v1 backup facts, v2 backup additions, AO3 sort/concurrency notes, and Codex handoff. No Android implementation/scaffold yet. | Codex | `kudos-ao3-reader-android` | ✋ HANDOFF | Phase 0 docs added; no Android implementation. **Next:** Codex/Claude review `docs/android/ANDROID_PORT_PLAN.md`, `docs/contracts/`, and `docs/ai/HANDOFF.md`; if accepted, Claude may start Phase 1 scaffold only. **Open:** human still needs to confirm Android `minSdk`/`targetSdk`, desugaring policy, and first release channel. |
| T-54 | **UI / Navigation / AO3-Parity Refinement** (large product-structure overhaul): 4 core tabs **Home / Library / Browse / Account** + a **global floating Search**; native **Browse** (Category→Fandom→Works, WebView demoted to fallback); **Account** absorbs the Bookmarks + Settings tabs; card consistency; work-level AO3 actions; privacy screen; saved searches; error states. | Claude | `feature/ui-refinement`→`main` | ✅ MERGED | **Plan APPROVED (phases back-to-back, pause at UI audit gate).** ✅ Prereq: merged `test/home-tab-overhaul`→`main` (`679b8cc`, pushed). ✅ **Phase 1 DONE** (`825db64`): 4 tabs Home/Library/Browse/Account + global Search (search-role slot); new `AccountView` absorbs Bookmarks+Settings (AO3 Account · My AO3 · On-AO3 web fallbacks · Local History/Favorites · App/Settings · Help); retired `BookmarksView`/`AO3AccountSection`; Links dropped. iOS+macOS build; sim-verified. ✅ **Phase 2 DONE** (`6f9de55`): local-first Global Search in `SearchView` — typing shows on-device matches live (Library works via `WorkRow`, fandoms, tags, collections) + explicit "Search AO3" action; no per-keystroke scraping; fandom browser still idle-state. Also: Global Search matches the **cached AO3 fandom catalog** (`18baad0`) — instant, no per-keystroke scraping; real search on tap corrects. ✅ **Phase 3 DONE** (`8893692`): native **Browse** — `MediaBrowserView` categories root → `FandomListView` (w/ filter) → `FandomWorksView` (native AO3 results, reuses `AO3WorkRow`/pagination/search); old web `BrowseView`→`AO3WebBrowserView` fallback ("Open AO3 Website" + `router.open`); Search idle now a prompt. Verified end-to-end in sim. ✅ **Phase 4 DONE** (`ee15e9a`): card/shelf consistency — shared `WorkStatLabel` (DRY'd `WorkRow`+`AO3WorkRow`) + `CoverStatsLine` adds a consistent rating+chapters line to the Home/Library cover cards (e.g. "T · 2/7"). ✅ **Phase 5 DONE** (`05222c0`): work-level AO3 actions — shared `AO3WorkActionsMenu` ("More actions" overflow on WorkDetail + Reader): Give Kudos / Comment / AO3 Bookmark / Mark for Later / Subscribe / Open on AO3, under an "On AO3 (opens website)" section. **Honest web fallbacks** (router.open → web view); native writes gated (CSRF, Part 16) — NOT implemented/faked. Local actions stay separate. ✅ **Phase 6 DONE** (`b50166e`): **Privacy & Local Data** screen (Account→App) — what's stored locally + Remove AO3 Session, Clear Browse Cache (`FandomCatalog.clearCache`), Clear Reading History. Error/stale states already covered (per-surface `ContentUnavailableView` + Retry-After). Also fixed the Library toolbar (tight icon cluster, Select→icon: `61d2a48`,`3376e21`). ✅ **All 6 phases complete.** **Post-phase work on branch:** skeleton loading across remote first-loads; Browse fandom-works filter button (shared `AO3FilterPanel`); Subscriptions fixed (`parseSubscriptionsPage` for the `dl`/`dt` page — was wrongly using `li.work.blurb`); **unified Work Detail** (`1875849` — one canonical `WorkDetailView` for local+remote, `Read`→Reader not a 2nd detail, lazy import-on-action, floating tab/search hidden on pushed screens) + **warnings/category/status/stats parity for local works** (`84bdaf7`, added `comments`/`hits` to `SavedWork`); ✅ **Saved Searches** (`bfd6b3d`, owner-approved `SavedSearch` model — full `AO3SearchFilters` made Codable, "Save Search…" in the filter panel, listed/re-run/swipe-delete on the Search idle screen). **Remaining:** local History/Favorites still to relocate to Library. ✅ **MERGED to `main` (`1c0c0d7`, pushed) 2026-06-24** after a no-regression check vs `readium-migration` (every non-reader feature present on both; only the in-progress Readium reader migration is intentionally legacy-excluded). iOS+macOS build + full test suite green on `main` (fresh DerivedData). See [[ui-nav-ao3-parity-refinement]]. |

---

## 🅿️ Backlog (prioritized)

### P1 — remaining
- **T-07 · Lazy / on-demand chapter extraction** 🅿️ *deferred.* Legacy/macOS reader
  only (the iOS Readium reader is already lazy); correctness-risky (WKWebView must
  resolve each chapter's CSS/image/font resources). Low ROI — do only if large-work
  perf becomes a real problem. Target: legacy `EPUBDocument.open` upfront-unzip.

### P2 — features (roadmap "Later" list; ID assigned on pickup)
- **Automatic CloudKit backup/sync** — portable file Export / Import completed
  in T-42; automatic background sync remains a later phase.
- **Highlights / notes / annotations** — large; a reader annotation system.
- **Text-to-Speech (TTS)** — large; `AVSpeechSynthesizer` in the reader.

### Phase 3 — native AO3 writes (most fragile; needs the per-page CSRF token)
- **Leave kudos · comment · subscribe · AO3-side bookmark** — fetch the work/page,
  extract its `authenticity_token`, POST the form, detect a login redirect. Build on
  `AO3AuthService.authenticatedRequest`. See [[native-ao3-roadmap]] Phase 3 +
  [`docs/AO3Authentication.md`](docs/AO3Authentication.md).

### UI-refinement & maintainability pass (user-planned — *after* the feature backlog)
- Polish the AO3 account sub-picker (the "Subs" label, 4-segment layout, "AO3
  History" vs the local "History"); a dedup / clarity sweep over the Phase-2 +
  download-queue / bulk-actions code; general maintainability pass.

### Readium reader — Phase-4 polish (now on `main`, iOS reader; see `READIUM_MIGRATION_NOTES.md`)
- **T-20 · Phase-4 interaction polish** — auto-hide chrome on scroll, custom
  page-turn animation, safe-area inset tuning. (Notes ▸ Migration status, Phase 4 = partial.)

### ⚠️ Verification & housekeeping debts (clear before trusting the new features)
- **🔴 Live AO3 verification (HIGH).** Every scraping feature shipped 2026-06-20
  (auth login; Marked-for-Later / Bookmarks / History / Subscriptions selectors +
  URLs; the series-page scrape for the download queue) is **build + unit-test
  verified only — never run with a real AO3 session.** Selector/URL assumptions are
  encoded in `KudosTests` fixtures; some may need a one-line fix once tested logged
  in. A single live login test validates the whole Phase-2 batch at once.
- **🔴 Visual verification (HIGH).** The simulator's display surfaces were
  unavailable for the entire 2026-06-20 session, so nothing new was screenshotted
  (AO3 sub-picker, Library bulk-select, download-queue banner, About page, Continue
  Reading shelf). All build/test-verified and the app boots clean, but unseen.
- **Keychain on a signed device build.** Confirm the session actually persists to
  Keychain on real hardware (the WebKit-store fallback is meant to be the
  Simulator/dev backstop only). See [`docs/AO3Authentication.md`](docs/AO3Authentication.md).
- **Single-branch consolidation (2026-06-24).** The `main` (legacy) / `readium-migration`
  split was merged into a **single `main` branch**; all other branches were deleted
  (local + remote). The old cross-branch hazards once listed here no longer apply — no
  scratch worktrees, no "pollution stashed on main", and `main` now *legitimately*
  includes Readium (iOS), so a `readiumLocator` reference is correct, **not** a stale
  build artifact. The legacy WKWebView reader is now `#if os(macOS)`-guarded (iOS uses
  the Readium navigator). Still: build **both** iOS (Readium) and macOS (legacy) before
  claiming a cross-platform change is done.

### Bugs
- _No active bugs._ ↳ see the **🐛 Bugs registry** below.

---

## ✅ Completed (recent — newest first)

| ID | Task | Owner | Branch(es) | SHA (main / readium-migration) | Date |
|----|------|-------|------------|--------------------------------|------|
| T-70 | Android UI refinement pass: added canonical Android interface guidance docs (`KUDOS_ANDROID_INTERFACE_GUIDELINES.md`, `ANDROID_MATERIAL_HIG_TRANSLATION.md`, `CROSS_PLATFORM_UI_BRIDGE.md`); added shared Material UI components for screen/section headers, metadata chips, status badges, and loading/error/empty cards; tightened AO3/saved-work cards across Home, Library, Search, Browse, Account lists, and Work Detail; made Home shelves horizontal; replaced remaining loose loading/error/empty copy on major non-reader screens; removed unused scaffold placeholder components. No functional AO3/auth/backup/reader/Room/DataStore/parsing behavior changed. Deferred: device screenshots, TalkBack/font-scale/tablet audit, Home Subscriptions/Recently Updated, advanced Search filter UI, Backup SAF UI, raw AO3 URL hydration, live AO3 verification. Verified `:app:compileDebugKotlin`; clean `:app:clean :app:assembleDebug :app:testDebugUnitTest` (235 JVM tests, 0 failures); `:app:lintDebug`. A non-clean assemble first hit stale duplicate generated class files with `" 2.class"` suffixes and was resolved by `:app:clean`. | Codex | `kudos-ao3-reader-android` | _see git log_ | 2026-06-27 |
| T-69 | Android Port Phase 12 final UI polish/accessibility/release-readiness pass: verified Phase 10 (`c167ef0`) and Phase 11 (`21ffa1f`, `2aed965`) are present; replaced the Phase 1 Home placeholder with an offline, privacy-aware dashboard backed by existing Library state (Continue Reading, Favorites, Recently Opened, Recently Added) and canonical Work Detail/Reader routing; added a Material adaptive app shell with bottom navigation on phones and navigation rail on wider screens; replaced Settings/Backup placeholder copy with real settings summary/reset and backup compatibility/privacy status; removed stale Search/Account/Work Detail implementation copy; aligned the Android launcher mark to AO3 red `#990000`; fixed Claude-flagged Phase 8 privacy/progress issues (obscured works excluded from free-text search, chapter-ratio progress preferred over in-chapter offset); landed the Phase 11 Browse parser parity fix for featureless media categories; updated `UI_PARITY_CHECKLIST.md` for Phase 12 statuses; added Home dashboard, route-contract, Library privacy/progress, and Browse parser tests. Deferred/needs review: device/TalkBack/dynamic-font/tablet screenshots, Home AO3 Subscriptions/Recently Updated, advanced Search filter UI, backup SAF import/export UI, direct raw AO3 URL hydration, live AO3 login/write verification, and final distribution/license policy review. Verified `:app:compileDebugKotlin`; focused new test slices; full `:app:assembleDebug :app:testDebugUnitTest :app:lintDebug :app:assembleRelease` (235 JVM tests, 0 failures). Non-fatal release warnings remain for bundled native strip fallback and existing Readium experimental API opt-ins. | Codex | `kudos-ao3-reader-android` | _see git log_ | 2026-06-27 |
| T-68 | Android Port Phase 11 Browse + AO3 WebView fallback (Claude): native Browse — `/media` category list → per-category fandom index (`/media/<name>/fandoms`, counts, local filter) → fandom work list (reuses the Phase 5 search path `work_search[fandom_names]`, pagination, read-only Saved/Downloaded/Favorite/Finished indicators) → canonical Work Detail; never auto-saves. Added a read-only AO3-only WebView fallback (AO3 in-app, externalize other http(s), block non-web schemes; back/loading/error). New packages `network/ao3/browse`, `browse`, `web`; ported Apple `mediaCategories()`/`fandoms()` selectors. Built in an isolated worktree on the clean `1d9a7c9` base parallel to Phase 10, then merged into `kudos-ao3-reader-android` (`21ffa1f`); only additive `AppNavHost.kt` conflicts. Tests for URL safety, WebView policy, category/fandom parsing (overload/empty/changed-markup), repository behavior, and local indicators (complete≠finished). Deferred: device/manual verification, count scraping, recently-visited fandoms, native `/tags/` page parsing (WebView covers it), UI polish. Verified clean `:app:clean :app:assembleDebug :app:testDebugUnitTest` (226 JVM tests, 0 failures). See [`docs/ai/PHASE_11_BROWSE_HANDOFF.md`](docs/ai/PHASE_11_BROWSE_HANDOFF.md). | Claude | `kudos-ao3-reader-android` | `21ffa1f` | 2026-06-27 |
| T-67 | Android Port Phase 10 Authenticated AO3 Writes and Comments: added explicit authenticated form POST support on `OkHttpAO3Client` with coordinator usage, centralized User-Agent, AO3-only cookies via Phase 9 auth, raw form encoding matching Apple, no GET coalescing and no auto-retry for POSTs. Added CSRF/authenticity parsing from hidden inputs and meta tags, pseud parsing, write validation error parsing, subscription-state parsing, and conservative repositories for kudos, subscribe/unsubscribe, Mark for Later, basic native AO3 bookmark creation, and work-level comment submission. Added public comment-thread loading, work/chapter comment target models, comment form parsing, and a functional Comments screen. Work Detail now exposes real AO3 actions; Reader exposes a Comments entry when a saved work has a canonical AO3 work URL. Deferred: live AO3 verification, native bookmark edit/update, true Readium end-of-work trigger/chapter-context routing, and broad UI polish. Verified `:app:compileDebugKotlin`, Phase 10 test slice, and full `:app:testDebugUnitTest` (201 JVM tests, 0 failures). | Codex | `kudos-ao3-reader-android` | _see git log_ | 2026-06-27 |
| T-66 | Android Port Phase 0-5 verification + Phase 7 follow-ups (Claude): verified Codex's committed Phases 0-5 the same way as Phase 6 (build + tests + multi-agent code review vs plan/contracts/Apple). Confirmed parity for coordinator concurrency (3), reader numeric defaults (18/1.65/28), `SavedSearch.dateAdded`, `WorkCollection` fields, AO3 rating/warning/category IDs, `sort_column` mapping, and ZIP-slip protection. Fixed 9 confirmed findings: **HIGH** `WorkDao` `@Insert(REPLACE)`→`@Upsert` (REPLACE cascade-deleted a work's user tags + collections on every favorite/finished/progress update) + regression test; AO3 red accent `#8B1E1E`→`#990000`; Sepia theme now uses Apple's warm-brown `#9A6732` tint instead of red/green; `isLoginUrl` exact-match→`.contains` (Apple parity); search word-count now passes raw values through like Apple (no longer drops `10,000`) + test; `SETTINGS_CONTRACT` appTheme default doc corrected; `AO3OverloadDetector` tightened to specific phrases (was false-flagging normal pages containing "capacity"/"try again later") + regression test; Phase 7 reader `ReaderProgressSaver` now also flushes on `Lifecycle.ON_STOP` (backgrounding) via `lifecycle-runtime-compose`. Reported-not-changed (match Apple): coalescer caller-cancellation, collection/saved-search last-write-wins on UUID match, deferred font-merge dedup. Verified `:app:assembleDebug` + `:app:testDebugUnitTest` (177 JVM tests, 0 failures). | Claude | `kudos-ao3-reader-android` | _see git log_ | 2026-06-27 |
| T-65 | Android Port Phase 9 Authentication and Account: added visible AO3 WebView login using AO3's real login page, CookieManager session capture/restore, app-private no-backup session persistence, AO3-only cookie-header generation for authenticated GET requests, Account signed-in/signed-out/expired UI, logout, and read-only account lists for Marked for Later, AO3 Bookmarks, AO3 History, Subscriptions (`/users/<username>/subscriptions?type=works`), and My Works. Account list items use `AO3WorkSummary` and open canonical Work Detail without auto-saving to Library. Added account URL builders, username/login-required detection, bookmarks parser support over `li.bookmark.blurb`, sparse subscriptions parser over `dl.subscription dt`, sanitized account fixtures, and tests for session store, cookie parsing/scoping, authenticated headers, login-page detection, account URLs, account parsers, pagination, session expiry, and logout. Added Android `INTERNET` permission. Deferred: encrypted Keystore/Tink session-at-rest implementation, hidden/automatic login, account collections, authenticated writes/comments/kudos/subscribe/bookmark/Mark-for-Later mutations, WebView/device manual verification. Verified clean `:app:clean :app:assembleDebug :app:testDebugUnitTest :app:lintDebug` (175 JVM tests, 0 failures). | Codex | `kudos-ao3-reader-android` | _see git log_ | 2026-06-27 |
| T-64 | Android Port Phase 8 Library UX: replaced the basic saved-work list with an offline Library dashboard backed by `LibraryViewModel`/`LibraryRepository`/pure `LibraryQuery` state. Implemented Continue Reading, Reading History, Recently Added, Favorites, All Saved Works, local search across saved-work metadata/user tags/collections, deterministic sorts (recently added, last read, title, author, word count, kudos), core filters (favorite, finished/unfinished, downloaded/not downloaded, user tag, collection) plus query support for AO3 metadata facets, and a privacy classifier that hides Mature/Explicit works in Hide mode or masks card details in Obscure mode. Library cards remain information-dense and navigate to canonical Work Detail; downloaded visible works also expose a direct Read action using the existing Phase 7 reader route. Added Room-backed Library snapshot coverage and pure query tests for filters, combined filters, sorts, local search, sections, privacy, missing-EPUB state, and non-mutating behavior. Deferred: AO3 update checking/Recently Updated, biometric reveal UI, full tag/collection management screens, bulk actions, advanced Library facet panel, Home dashboard data wiring, and device visual verification. Verified clean `:app:clean :app:assembleDebug :app:testDebugUnitTest :app:lintDebug` (155 JVM tests, 0 failures). | Codex | `kudos-ao3-reader-android` | _see git log_ | 2026-06-27 |
| T-63 | Android Port Phase 7 Readium Reader integration (Claude + Codex takeover): added Readium Kotlin Toolkit 3.3.0 (`readium-shared`/`streamer`/`navigator`) + core-library desugaring (`desugar_jdk_libs` 2.1.5, required by Readium metadata) + `fragment-ktx` 1.8.9; `MainActivity` is now a `FragmentActivity` to host Readium's Fragment-based EPUB navigator inside Compose (`ReadiumNavigatorHost` via `FragmentContainerView`/`AndroidView`). Built an engine-agnostic reader layer (`ReaderProgress`/`ReaderProgressMapper`/`ReaderLocatorCodec`/`ReaderRestoreTarget`/`ReaderRepository`/`ReaderViewModel`/`ReaderUiState`/`ReaderProgressSaver`/`ReaderLinkHandler`/`EndOfWorkActions` + `settings/ReaderSettingsMapper`/`ReaderPreferences`) and a Readium adapter (`ReadiumPublicationOpener`/`ReadiumProgressAdapter`/`ReadiumSettingsAdapter`). Real `ReaderScreen` replaces the placeholder (loading/error/reading states); Work Detail **Read** opens the reader when `hasEpub`. Progress restore prefers a version-gated platform-tagged locator envelope, else `lastSpineIndex`/`lastScrollFraction`, else start; saves always refresh both fallback fields + `lastReadDate` and never touch local user state. Light/Dark/Sepia + font size/line-height/margins/scroll-vs-paged/justify mapped to `EpubPreferences`; bold + custom fonts deferred (value-class/import). Codex finalization tightened locator version compatibility, made Android fallback progress use per-spine progression before whole-book progression, hardened AO3 reader-link host detection, and routes reader work links into the native Work Detail path (hydration still deferred). Deferred: live-render device verification, guaranteed save-on-process-death, full reader chrome, custom-font import, deep tag routing/full work-link hydration, auth/comments. Verified clean `:app:clean :app:assembleDebug :app:testDebugUnitTest :app:lintDebug` (135 JVM tests, 0 failures). | Claude/Codex | `kudos-ao3-reader-android` | _see git log_ | 2026-06-26 |
| T-62 | Android Port Phase 6 takeover review (Claude): reviewed and verified Codex's committed Phase 6 work without rewriting it — confirmed canonical Work Detail, save/download lifecycle, app-private `files/works/<UUID>.epub` storage, file-store path safety, metadata merge, canonical tag fetch, and Room-backed Library all build and pass. Fixed one contract bug: `WorkImporter.persistDownloadedEpub` was force-clearing `isFinished` on every download, which would silently wipe the user's Finished marker on re-download; now preserves local user state. Added `downloadPreservesExistingFinishedState` regression test. Verified clean `:app:assembleDebug` and `:app:testDebugUnitTest` (100 JVM tests, 0 failures). | Claude | `kudos-ao3-reader-android` | _see git log_ | 2026-06-26 |
| T-61 | Android Port Phase 6 Work Detail save/download lifecycle: added shared Android app container/Room database wiring, canonical Work Detail source model for remote summaries and local saved works, Room-backed `WorkRepository`, metadata merge that preserves local user state/progress, AO3 canonical work metadata/tag fetch from `/works/<id>?view_adult=true`, EPUB download from `/downloads/<id>/work.epub`, app-private UUID file storage at `files/works/<UUID>.epub`, metadata-only save, download/redownload, favorite/finished toggles, local user tags, local collections, delete local EPUB, remove from Library, and basic Library list backed by Room. Readium reader opening, auth/WebView, authenticated AO3 writes/comments/account lists, EPUB metadata parsing, full Library filters/sorts, and advanced download queue remain deferred. Verified clean `:app:assembleDebug`, `:app:testDebugUnitTest` (99 JVM tests), and `:app:lintDebug`. | Codex | `kudos-ao3-reader-android` | _see git log_ | 2026-06-26 |
| T-60 | Android Port Phase 5 AO3 search and parsing: added Apple-compatible AO3 search filter enums/models, folded query behavior for excluded tags/warnings/categories and rating exact/plus/minus/not-rated combinations, one-based URL generation with `page=1`, current sort enum mappings, word-count normalization, Jsoup search-result parser, typed search repository on the Phase 4 client, sanitized parser fixtures, functional native Search screen with loading/error/empty/results/sort/pagination states, AO3 result cards, and metadata-aware Work Detail placeholder. Auth, EPUB import/download, Readium, comments/writes, advanced filter UI, saved searches, account lists, and production Library wiring remain deferred. Verified `:app:assembleDebug`, `:app:testDebugUnitTest` (81 JVM tests), and `:app:lintDebug`. | Codex | `kudos-ao3-reader-android` | _see git log_ | 2026-06-26 |
| T-59 | Android Port Phase 4 AO3 networking core: added OkHttp-based raw GET client, centralized AO3 constants and Safari-like User-Agent, 3-slot request coordinator with configurable 500 ms spacing, GET request coalescing, retry/backoff policy, Retry-After seconds/HTTP-date parsing, explicit AO3 result/error/status mapping, conservative overload/capacity detection, and MockWebServer/coroutines tests. Search/query building, HTML parsing, auth/WebView, Readium, EPUB download/import, writes/comments, production Library, Apple source, and Xcode changes remain deferred. Verified with clean `:app:assembleDebug`, `:app:testDebugUnitTest`, and `:app:lintDebug`; 59 JVM tests passed. | Codex | `kudos-ao3-reader-android` | _see git log_ | 2026-06-26 |
| T-58 | Android Port Phase 3 backup compatibility foundation: Kotlin serialization backup manifest DTOs for Apple v1 and Android v2; Apple v1 directory manifest/package import where accessible; deterministic v2 ZIP `.kudosbackup` export/import; validation for versions, dates, UUIDs, safe paths, malformed filenames, duplicate entries, missing manifests, invalid JSON, truncated ZIPs, and size limits; pure non-destructive merge service for works, EPUB file decisions, tags, collections, bookmarks, fonts, saved searches, settings, and reader progress. Backup placeholder copy updated; SAF/production restore UI intentionally deferred. Added 24 backup JVM tests (35 total project JVM tests). Verified `:app:assembleDebug`, `:app:testDebugUnitTest`, and `:app:lintDebug`. No AO3 networking/parsing/auth/Readium/EPUB download/account/comment/production Library implementation. | Codex | `kudos-ao3-reader-android` | _see git log_ | 2026-06-26 |
| T-57 | Android Port Phase 2 core models/settings foundation: Kotlin domain models for saved works, tags, bookmarks, collections, fonts, saved searches, settings, and backup-compatible settings; Room schema v1 with works/user tags/tag refs/collections/collection refs/bookmarks/custom fonts/saved searches; DataStore Preferences settings repository with Apple-matching defaults; placeholder Settings screen now displays defaults. Added 11 JVM unit tests for settings defaults, enum mappings, DataStore, Room creation, DAO insert/read, collection relationships, SavedSearch `dateAdded`, and portable reader progress fields. No AO3/network/auth/backups/Readium/EPUB/account/comment/production Library implementation. Verified `:app:assembleDebug`, `:app:testDebugUnitTest`, and `:app:lintDebug`. | Codex | `kudos-ao3-reader-android` | _see git log_ | 2026-06-26 |
| T-56 | Android Port Phase 1 scaffold: compileable Android project under `android/` using Gradle Kotlin DSL, AGP 9.2.0, Gradle 9.4.1 wrapper, Kotlin/Compose compiler 2.3.21, Compose BOM 2026.06.00, Material 3, and placeholder Compose navigation for Home/Library/Browse/Account plus Search, Work Detail, Reader, Settings, and Backup. No AO3 networking/parsing/auth/backups/Readium/Room/DataStore implementation. Verified `:app:assembleDebug`, `:app:testDebugUnitTest`, and `:app:lintDebug` with Android Studio JBR + `ANDROID_HOME=$HOME/Library/Android/sdk`. | Codex | `kudos-ao3-reader-android` | _see git log_ | 2026-06-26 |
| T-53 | Library **real Collections** (user-named shelves): `WorkCollection` SwiftData model (many-to-many w/ `SavedWork`; registered in the container); Collections dashboard section (leading "New Collection" card + per-collection cards); `CollectionDetailView` (list/remove works, rename/delete); `AddToCollectionView` sheet from a work's detail page (toggle membership, create). Builds iOS+macOS; section + New card sim-verified. | Claude | `test/home-tab-overhaul`→`main` | `2570f8e` | 2026-06-22 |
| T-52 | Library **top-fandom quick-filter chips** on the dashboard (data-driven `All` + most-common fandoms, reuse `TagChip`; tap → filter all sections incl. AO3 Marked-for-Later; trailing Reset; replaces the plain "Filters active" banner). Chip UI sim-verified. | Claude | `test/home-tab-overhaul`→`main` | `73d7e84` | 2026-06-21 |
| T-51 | **Master prompt Phase B** — networking politeness/local-first (`main` + `readium-migration`). (1) `AO3RequestCoordinator` — polite bounded-concurrency gate (3) complementing `AO3Client`; `FandomCatalog` loads Browse-by-category prefetches concurrently-but-bounded. (2) **Local-first disk cache** (`FandomCatalogCache`, stale-while-revalidate). (3) **Request coalescing** (`RequestCoalescer` in `AO3Client.fetchData`). 10 tests; sim-verified. **Proposed/deferred:** formalize `DownloadQueue`→DownloadCoordinator + `WorkImporter`→ImportCoordinator; wider cache/coalesce rollout. | Claude | both | `ae22b2f`, `aec3554`, `5e28a4c` | 2026-06-21 |
| T-50 | **Master prompt Phase A**: new app icon (red book + heart cutout + black bookmark, vector source `Design/AppIcon.svg`); first-launch **WelcomeView** (`hasCompletedOnboarding`, theme-aware, accessible); **shake-to-report** (`ShakeDetector` + `BugReportView` → prefilled GitHub issue) reachable by shake or About; `AppLinks`. Verified in sim. | Claude | `main` + `readium-migration` | `e56e97b`, `b1d23a2` | 2026-06-21 |
| T-49 | Add canonical **`docs/PROJECT_PHILOSOPHY.md`** (master prompt Part 3); linked from README + AGENTS. On all branches. | Claude | all | `7aa3d26` | 2026-06-21 |
| T-48 | **Security:** scrub the Apple `DEVELOPMENT_TEAM` ID from `project.pbxproj` → `""` (repo is public). All branches. Still in git **history** — purge needs a force-push rewrite (deferred, owner's call). | Claude | all | `e36dda5` | 2026-06-21 |
| T-46 | Layout overhaul — **Library** rebuilt as a 5-section carousel dashboard (Reading Now, Saved for Later, Finished, Collections, Downloaded) via shared `WorkCarouselSection`; collapsible, `>` See-all → full list, per-section empty states; Saved for Later merges AO3 Marked for Later; filters/insights/privacy/tag-routing/iOS bulk-select preserved. Verified in sim. | Claude | `test/home-tab-overhaul`→`main` | `3fc9c98` | 2026-06-21 |
| T-45 | Consolidate the `docs/Bugs.md` + `Feature_Ideas.md` + `UI_Polish_Todo.md` trackers into single BUG-N / FI-N / UI-N registries in `TASKS.md`; remove the three files; update README + AGENTS.md. | Claude | `test/home-tab-overhaul`→`main` | `bb0b224` | 2026-06-21 |
| T-44 | Layout overhaul — **Home** tab rebuilt as a Books-style dashboard: collapsible horizontal carousels (Reading Now, Recently Updated, Subscriptions, Favorites, Recently Opened) with `>` See-all, per-section empty states, reading-progress bars, and AO3 update detection (`WorkUpdateChecker`, `SavedWork.knownChapterCount`). Added the `Home` tab + `Kudos_Layout_Structure.md`. Verified in sim. | Claude | `test/home-tab-overhaul`→`main` | `5286dda` (+ `5ffa33f`, `306ac6f`) | 2026-06-21 |
| T-43 | Fix **BUG-4**: Library bulk-select `EditMode` is iOS-only → macOS build broke. Multi-select state guarded `#if os(iOS)`; macOS uses a plain `libraryList`. macOS + iOS both build, all tests pass. | Claude | both | _see git log_ | 2026-06-21 |
| T-42 | Portable `.kudosbackup` export/import for Library records, EPUBs, User Tags, bookmarks, custom fonts, and app/reader settings; merge-only restore through the system document picker (FI-19) | Codex | both | `6048684` / `5cd9394` | 2026-06-20 |
| T-41 | Local Reading Insights dashboard: works/words read, activity, completion, and top fandoms (FI-18) | Codex | both | `1cfe4b0` / `be74d8f` | 2026-06-20 |
| T-40 | Continue Reading shelf at the top of the Library (in-progress works, most-recently-read first → one-tap resume into the reader); added `SavedWork.lastReadDate` (FI-17) | Claude | both | _see git log_ | 2026-06-20 |
| T-39 | Settings → About / Sources & Licenses sheet (version, GPL-3.0, SwiftSoup/Readium/ao3_api credits, AO3/OTW disclaimer) (FI-16) | Claude | both | _see git log_ | 2026-06-20 |
| T-38 | Download queue (`DownloadQueue` + root progress banner) — "Download Whole Series" scrapes the series page (`AO3Client.seriesWorks`) and downloads/imports serially via the polite AO3Client; second half of "Download queue / bulk actions" (FI-15) | Claude | both | _see git log_ | 2026-06-20 |
| T-37 | Library bulk-select + bulk actions (delete / save / favorite) via EditMode + `List(selection:)`; first half of "Download queue / bulk actions" (FI-15) | Claude | both | _see git log_ | 2026-06-20 |
| T-36 | Phase-2: native AO3 work Subscriptions (4th "AO3" sub-tab) — reuses worksPage/parseSearchPage; only `li.work.blurb` items surface, so work subs only (FI-14). Completes the Phase-2 read backlog. | Claude | both | _see git log_ | 2026-06-20 |
| T-35 | Phase-2: native AO3 reading History + consolidate the account lists into one "AO3" segment with a sub-picker (`AO3AccountSection`) to avoid section-bar overflow (FI-13) | Claude | both | _see git log_ | 2026-06-20 |
| T-34 | Phase-2: native AO3 Bookmarks list — generalized the MfL view into `AO3AccountWorksList(kind:)`; `parseBookmarksPage` (`li.bookmark.blurb`, work id from `/works/` link, skips series/external) (FI-12) | Claude | both | _see git log_ | 2026-06-20 |
| T-33 | Phase-2 first authenticated feature: native "Marked for Later" reading list — Bookmarks "Later" segment, authenticated reads via AO3AuthService, reuses parseSearchPage + AO3WorkRow + pagination (FI-11) | Claude | both | _see git log_ | 2026-06-20 |
| T-21 | Calibrate Readium theme colors, typography units, margins, weight, built-in fallbacks, and imported custom-font rendering | Codex | `readium-migration` | — / `6fb3322` | 2026-06-20 |
| T-17 | Document EPUB ZIP/OPF/spine/TOC/metadata assumptions, import failures, security boundaries, tests, and Readium platform differences | Codex | both | `208df0c` / `a3f70ba` | 2026-06-20 |
| T-29 | Readium reader routes EPUB HTTP/HTTPS links to the in-app Browse tab while preserving system handling for non-web schemes | Codex | `readium-migration` | — / `6cb7525` | 2026-06-20 |
| T-32 | AO3 auth review follow-ups: off-screen login WebView gets a window, one silent hidden-login retry, calmer fallback copy, sign-up/reset links, AO3 HTML-fixture parser tests, doc + code clarifications | Claude | both | _see git log_ | 2026-06-20 |
| T-31 | Preserve successful AO3 login when Keychain is unavailable by recovering from WebKit's persistent app-scoped cookie store (BUG-3) | Codex | both | `3a3363d` / `39556be` | 2026-06-20 |
| T-30 | AO3 authentication foundation: native login, hidden WebView session capture, automatic visible fallback, Keychain persistence, session lifecycle, authenticated requests (FI-10) | Codex | both | `a5775d5` / `811a784` | 2026-06-20 |
| T-28 | EPUB web links (AO3 work/author/tag) open in the Browse tab, not inside the legacy reader's web view — verified in simulator (BUG) | Claude | both | _see git log_ | 2026-06-19 |
| T-15 | Sync in-app AO3 browser with app theme (FI-5) | Codex | both | `58663da` / `2f48e95` | 2026-06-19 |
| T-27 | Search Back returns to Browse (then the previous tab) after a fandom/typed search, instead of skipping straight to the tab (BUG) | Claude | both | _see git log_ | 2026-06-19 |
| T-26 | Toolbar "expand/collapse all" toggle for Search result cards | Claude | both | _see git log_ | 2026-06-19 |
| T-25 | Calm Search pagination layout (UI-1 follow-up) | Codex | both | `9374053` / `491b195` | 2026-06-19 |
| T-14 | Refine the Search pagination card (UI-1) | Codex | both | `024af77` / `1ab6781` | 2026-06-19 |
| T-24 | Enrich Browse-by-fandom cards: fandom/work counts, saved count, recently-read chips, regular text weight, section dividers (+ Search/Library card dividers) (FI-9) | Claude | both | _see git log_ | 2026-06-19 |
| T-16 | P2 AO3-red default accent + accent color picker (FI-6) | Claude | both | _see git log_ | 2026-06-19 |
| T-23 | Extend Include → Exclude → Clear cycling to Warnings/Categories (FI-3) | Codex | both | `ff4f93a` / `8373068` | 2026-06-19 |
| T-22 | Fix T-09 tag cycling UI + restore top picker search field (BUG-2) | Codex | both | _see git log_ | 2026-06-18 |
| T-09 | P2 Advanced rating + cycling include/exclude Search tags (FI-2, FI-3) | Codex | both | _see git log_ | 2026-06-18 |
| T-10 | P2 Expandable search result cards (FI-4) | Codex | both | _see git log_ | 2026-06-18 |
| T-11 | P2 Tap a tag (work/My) → filter the Library (FI-8) | Claude | both | _see git log_ | 2026-06-18 |
| T-12 | P2 Long-press Filters → Clear All Filters (FI-1) | Claude | both | _see git log_ | 2026-06-18 |
| T-13 | P2 Hide privacy eye button when no hidden works (FI-7) — *already implemented; verified* | Claude | n/a | — | 2026-06-18 |
| —    | docs: stable IDs + status across trackers | Claude | both | `2a8696d` / `1c3c8a4` | 2026-06-18 |
| —    | Collaboration system (`AGENTS.md` + `TASKS.md`) | Claude | both | `458dfd4` / `170d381` | 2026-06-18 |
| T-08 | P1 Sepia consistency verified (Settings); bug closed | Claude | both | `30f3e9a` / `746273a` | 2026-06-18 |
| T-06 | P1 Structured OSLog logging | Claude | both | `23392f0` / `d6b8c9f`+`b0ea6ff` | 2026-06-18 |
| T-05 | P1 Split `EPUB.swift` into focused files | Claude | both | `daa8422` / `edc07f4` | 2026-06-18 |
| —    | GitHub repo setup (GPL-3.0 LICENSE, README, docs/, topics) | Claude | both | `22ce718` / `20d7550` | 2026-06-18 |
| —    | P0-1 `KudosTests` target + 20 pure-logic tests | Claude | both | `7eac358`+`1012d53` / `8f6c7cc`+`aebe4ba` | 2026-06-18 |
| —    | P0-3 Typed `EPUBError`, AO3Client retry/backoff, surfaced failures | Claude | both | `362d5c0` / `cea2eb1` | 2026-06-18 |
| —    | P0-2 SwiftLint + SwiftFormat + pre-commit hook + CI | Claude | both | `f59a1bb` / `c5d9c1e` | 2026-06-18 |

_Older UI / reader / Library work predates this board — see `git log`._

---

## 🐛 Bugs (BUG-N registry)

_Consolidated from the former `docs/Bugs.md`._ **Status:** Open · In Progress · Fixed. Detail for each is in the Completed table / `git log` under its board task.

**Active:** _none._

**Fixed & verified:**
- **BUG-4** — Library bulk-select `EditMode` broke the macOS build; guarded `#if os(iOS)`, macOS uses a plain list (T-43, 2026-06-21).
- **BUG-3** — AO3 login was discarded when Keychain was unavailable; now falls back to WebKit's app-scoped cookie store (T-31, 2026-06-20).
- **BUG-2** — T-09 tag-cycling UI + tag-picker search-field placement regression (T-22, 2026-06-18).
- **BUG-1** — Sepia theme not applying app-wide; fixed via `.appThemedScroll()`/`.appThemedRows()` (T-08, 2026-06-18).

---

## 💡 Feature Ideas (FI-N registry)

_Consolidated from the former `docs/Feature_Ideas.md`._ **Status:** Idea · Planned · In Progress · Done · Parked. All current FI items are **Done** (board task in parens).

- **Search & Filters:** FI-1 long-press clear filters (T-12) · FI-2 advanced rating (T-09) · FI-3 cycling include/exclude multi-select (T-09/T-23) · FI-4 expandable result cards (T-10).
- **Browse / Web:** FI-5 sync browser theme (T-15) · FI-9 enrich browse-by-fandom cards (T-24).
- **AO3 account (auth + Phase-2 reads):** FI-10 auth foundation (T-30) · FI-11 Marked for Later (T-33) · FI-12 AO3 Bookmarks (T-34) · FI-13 Reading History + grouped AO3 section (T-35) · FI-14 work Subscriptions (T-36).
- **Library:** FI-7 hide privacy eye when nothing hidden (T-13) · FI-8 tap tag → filter Library (T-11) · FI-15 download queue & bulk actions (T-37/T-38) · FI-17 Continue Reading shelf (T-40) · FI-18 reading statistics (T-41).
- **App:** FI-16 About / Sources & Licenses (T-39) · FI-19 portable Library backup (T-42).
- **Theming:** FI-6 AO3-red accent + color picker (T-16).

---

## ✨ UI Polish (UI-N registry)

_Consolidated from the former `docs/UI_Polish_Todo.md`._
- **UI-1** — Refined the Search pagination pill: elevated card, tightly grouped page pills, long-press arrows jump to first/last, nearby-page fallback on narrow cards (Done; T-14/T-25).

---

## 🧭 Key decisions & open questions

- **macOS reader — decided:** iOS/iPadOS use Readium; **macOS keeps the legacy
  reader** (Readium navigator is UIKit-only). Readium SPM is scoped `platformFilter = ios;`.
- **Workflow — decided:** **single `main` branch** (the `main`/`readium-migration`
  split was consolidated 2026-06-24). Just commit to `main`; no cross-branch porting.
- **AO3 authentication — decided:** native account UI drives AO3's real form in
  a hidden WebView; mechanism failures reveal the same WebView as a fallback.
  Sessions, never passwords, are stored device-only in Keychain.
- **Open — before going public:** scrub the Apple `DEVELOPMENT_TEAM` ID from
  `project.pbxproj`.
- **Open — migration (`READIUM_MIGRATION_NOTES.md` §6):** consolidate Library
  metadata on Readium vs keep the custom OPF layer?
- **Cleanup — done:** `test/card-lists` (abandoned/polluted) was deleted in the
  2026-06-24 single-branch consolidation, along with all other non-`main` branches.
- **Layout overhaul (`test/home-tab-overhaul`) — decided:** Home & Library both use
  the shared `WorkCarouselSection`. **Library cards open the work's *detail* page**
  (the management surface), not straight into the reader as on Home — by design.
  **Saved for Later = local saved + AO3 Marked for Later** merged; **Collections =
  placeholder** (no model yet); **no Synced/Local badges yet**. (Branch long since
  merged to `main` and deleted in the single-branch consolidation.)
- **Open — layout follow-ups (deferred):** (1) light filter *quick-chips* on the
  Library dashboard — only the active-filter banner + full Filters inspector exist
  so far; (2) a `Collection` model to make Collections real; (3) confirm whether
  Library cards should offer a reader-direct affordance.

---

## ↩️ Context for the next session

- **Done & pushed (`main`, in sync with `origin`):** the full AO3 auth
  foundation + **Phase-2 reads** (Marked for Later, Bookmarks, History,
  Subscriptions — all under the Bookmarks tab's "AO3" segment), plus the
  missing-features batch — **download queue & bulk actions, About page, Continue
  Reading shelf, Reading Insights, and portable Library backups** (T-30…T-42,
  FI-10…19).
- **Natural next pickup:** fix **BUG-4** to restore the promised macOS build,
  then start **Highlights / notes / annotations**. Automatic CloudKit backup/sync
  remains a later phase. The **live AO3 verification** debt still needs a real
  signed-in session.
- **Single branch:** the project is now just `main` (consolidated 2026-06-24) — no
  porting, no worktrees. Build **both** iOS (Readium) and macOS (legacy reader).
- Quick commands — Build/Test: `xcodebuild … CODE_SIGNING_ALLOWED=NO` ·
  `Scripts/test.sh` · Lint: `Scripts/lint.sh`.

## UI Consistency & Density Audit (Required Before Merge)

### Purpose
Ensure new UI work remains consistent with the established Kudos design language and does not regress information density, scanability, or theme behavior.

### Human Verification Required
The following items require screenshots and human review before completion:

- AO3 account sub-picker
- Library bulk-select mode
- Download queue banner
- About page
- Continue Reading shelf
- Search result cards
- Library cards

### Information Density Review
For every new or modified card:

- Verify title visibility is unchanged or improved
- Verify author visibility is unchanged or improved
- Verify fandom visibility is unchanged or improved
- Verify reading progress visibility is unchanged or improved
- Verify chapter/word count visibility is unchanged or improved
- Verify download status visibility is unchanged or improved
- Verify no critical metadata has been hidden behind additional taps

### Theme Consistency Review
Verify all new UI components:

- Use ThemeManager/AppThemeSurface
- Support Light, Dark, and Sepia themes
- Avoid hardcoded colors
- Avoid hardcoded corner radius values
- Avoid hardcoded shadows
- Follow existing spacing scale

### Card Family Consistency
Compare against existing Library/Search cards:

- Typography hierarchy
- Metadata presentation
- Badge styling
- Progress indicators
- Padding and spacing
- Corner radius treatment

### Approval Gate
Before merging UI changes:

1. Screenshot review completed
2. Density review completed
3. Theme review completed
4. Human approval received

Do not mark UI tasks complete until all four requirements are satisfied.
  
