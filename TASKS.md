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
| T-64 | **Carousel selection refinements** — allow direct select/deselect from carousel cards using the existing parent selection state and fix the detailed card select bubble so it sits cleanly inside the card edge. | Codex | `ui-select-refinement` | ✅ DONE | Implemented against Library's existing `selection`/`EditMode` model: carousel cards toggle selection in place, detailed select list stays available from the toolbar, and edit-mode card rows gain leading room for the system select bubble. Follow-up `afc1a6e` tags detailed select-list rows with `SavedWork.id`, so carousel selections remain selected when switching to the detailed card list. Verified: `Scripts/lint.sh` (warnings only, pre-existing), iPhone simulator build/install. Earlier full verification: iPhone test suite, iPad simulator build, macOS build. |
| T-65 | **Lint cleanup** — fixed the pre-existing SwiftLint warning set without intentional behavior changes: safe naming/line-wrap/optional-init/style fixes, tiny tuple-to-struct cleanup, centralized AO3 HTML decoding to preserve existing lossy UTF-8 behavior, and documented local lint exceptions for large behavior-sensitive screens/services. | Codex, Claude | `claude/lint-cleanup-review-q9x71g` | ✅ DONE | Commit `71b16c3`. Codex verified (their environment): `Scripts/lint.sh` clean, `git diff --check`, iPhone 17/iOS 26.5 test suite, macOS build with `CODE_SIGNING_ALLOWED=NO`. **Claude adversarial review pass:** inspected the full diff line-by-line against every listed risk (Codable/persistence keys, tuple→struct field access, string-token formatting used for cache invalidation, decode/parse behavior, disable-comment scope); found it minimal, behavior-preserving, and correctly scoped (no file crossed a lint threshold without a disable, no file under-threshold got one; all `swiftlint:disable` are `:this`/`:next` except two justified file-scope `file_length` disables on files already over the 700-line threshold). Could not independently re-run `Scripts/lint.sh`/build/tests in this session's Linux sandbox (no Swift toolchain, network egress to install one denied by org policy) — re-run before merge. **Mac verification pass (Claude):** re-ran everything the Linux sandbox couldn't. Found two real compiler errors invisible without a Swift toolchain — `Log.epub.info(...)`/`Log.library.info(...)` string interpolations referencing `toc`/`finishedCount`/`failedCount` inside closures where an earlier redundant-`self` cleanup had stripped a `self.` that `OSLogMessage`'s interpolation actually requires for capture-semantics clarity — fixed by restoring `self.` at those three sites (`ReadiumReaderView.swift`, `DownloadQueue.swift`). Also fixed one remaining `line_length` warning (`SettingsView.swift:163`). After those two fixes: `Scripts/lint.sh` clean (0 warnings), `git diff --check` clean, full iOS test suite green (`iPhone 17`/iOS 26.5), iOS + macOS builds both succeed. Ready to merge. |
| T-63 | **Native pull-to-refresh across Home / Library / Browse / Search / Work Detail** — add native refresh affordances that refresh only visible/current-context AO3 data, merge metadata on successful parses, preserve filters/navigation, and never delete or purge local works on AO3/network/rate-limit/unavailable failures. New `WorkMetadataRefresh` service, deliberately separate from background tag sync, with field-level merge guards and save-only-after-successful-parse. **Review pass (Claude, `aaad490`):** adversarial multi-agent review confirmed data-safety/merge/scope properties hold across all screens; fixed a real cancellation-type-mismatch bug (`URLError(.cancelled)` vs `CancellationError`, so the refresh loop's own cancellation guard was silently dead code) and a work-completion-status selector bug (`dt.status` doesn't exist on real AO3 markup — only the sibling `dd.status` is classed — and the test fixture had been hand-written to match the bug). **Gap-closure pass (Claude):** closed the three items flagged as follow-ups — (1) added `cancelRefreshOnTabChange` (`UIComponents/CancellableRefresh.swift`), tracking each large-list refresh (Library section/Collection/Reading Queue "see all", Home section "see all", Library select-mode) as an explicit `Task` and cancelling it on tab switch, since `TabView` keeps hidden tabs mounted so a `.refreshable` task otherwise survives a tab change; (2) made `AO3RequestCoordinator.acquire()` cancellation-aware via `withTaskCancellationHandler` so a queued waiter stops immediately instead of waiting for an unrelated slot-holder to finish (new regression test `cancelledWaiterStopsWaitingWithoutConsumingASlot`); (3) deduped the triplicated tag-merge/normalize helpers (`WorkTags`/`WorkMetadataRefresh`/`ReadingQueueService`) into a shared `TagMerge` enum. **Regression fix (Claude, owner-reported):** pull-to-refresh on Home/Library was clearing the Subscriptions/Marked-for-Later carousels on any transient fetch failure (network hiccup, rate limit, expired session) — `AO3AuthService.accountWorks`/`accountSubscriptions` unconditionally returned `[]` on error (by original design, for the one-shot initial-load case), and `HomeView`/`LibrarySectionListView`/`LibraryView` all unconditionally overwrote their `@State` list with that result. Changed both `AO3AuthService` methods to `throws` (still returns `[]` only for the legitimate signed-out case) and updated all three callers to keep the existing list and log on failure instead of wiping it — matching the same never-destructively-overwrite-on-failure principle already applied to `WorkMetadataRefresh`. | Codex, Claude | `ui-refresh` | ✅ DONE | Verified: `Scripts/lint.sh` (warnings only, pre-existing), full iOS test suite on `iPhone 17`/iOS 26.5, macOS build. Pushed to `origin/ui-refresh`. **Not merged to `main`** — owner has not requested merge. |
| T-57 | **Work-card list controls + card-color regression fix** — (1) Fixed a regression where the metadata-inside-card revamp left every Library/Home cover card the same color: reintroduced the stable per-title hue (`CoverArt.hue`) as a subtle theme-aware surface tint + accent border on `WorkSummaryCardSurface` (dark/light/sepia tuned), so neighbouring cards read as distinct again — Codex's metadata layout/elevation untouched. (2) Added **Expand-all + page-contextual Filter** to every full-work-card page, reusing existing features: new shared `WorkCardListControls` toolbar cluster; local pages (Library section list, Home section list, Collection detail, Local History, Local Favorites) reuse `LibraryFilters`/`LibraryFilterPanel` applied live to that page's works; remote summary pages (Account lists — bookmarks/history/subs/my works/collections/marked-for-later — and Browse→Tag works) reuse `AO3FilterPanel` in a new `.refine` mode + new client-side `AO3SearchFilters.apply(to:[AO3WorkSummary])` (`AO3SummaryFilter.swift`), narrowing the loaded page in place (not a website-wide search); `WorkRow` gains the same expand affordance as `AO3WorkRow`; every filter-empty state has a Clear Filters escape; idle (no filter) preserves each section's own ordering. **Verified:** lint clean (new code), iOS + macOS builds, full iOS test suite green (`iPhone 17`, OS 26.5). Uncommitted on branch — owner reviewing in sim. **Follow-ups (same review cycle):** (3) **Tag retention** — new `SavedWork.ao3Unavailable` flag set when AO3 returns 404 in `WorkTags.refreshFromAO3` (`AO3Error.notFound`) so works **deleted from AO3 stop being re-fetched** and keep their existing tags; `needsAO3Refresh` short-circuits on it. Extracted the on-open EPUB-tag backfill into `WorkTags.backfillFromEPUB` and run it in the Library background pass too, so **downloaded works always keep their EPUB tags** (pure-local, works offline / for deleted works); works still missing categorized/extra data are still enriched from AO3, never overwriting existing tags (owner chose "Enrich, never overwrite"). (4) **Progress card duplicate %** — `WorkCoverCard.progressText` no longer echoes the Readium `readingProgressLabel` ("60%") on the bottom-left of the progress bar (that was the duplicate); shows "Reading"/"Finished"/"Ch N" instead, keeping the bottom-right percent. Verified in sim. | Claude | `feature/native-ao3-actions` | 🔄 IN REVIEW | Implemented + verified; awaiting owner sim check, then commit. |
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
| T-67 | **Queue tombstone conflict fix + iCloud sync staging** — added default-safe queue deletion metadata, queue membership freshness, and backup v4 queue/member timestamps; `.kudosbackup` restore now computes `effectiveQueueModifiedAt`, suppresses only stale queue/member snapshots, revives newer queue metadata or membership activity over older tombstones, preserves/reports ambiguous conflicts, and never falls back suppressed memberships into Saved for Later. Settings import summaries now report suppressed/revived/ambiguous queue conflicts. iCloud remains honestly staged: no entitlement/container or real-device CloudKit verification is claimed; docs list the blockers and manual device checklist. Added deterministic queue conflict/migration tests. Verified `git diff --check`, `Scripts/lint.sh`, focused Persistence/Backup xcodebuild tests, full iOS suite (`Scripts/test.sh 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`), and macOS build. **Adversarial review + fix pass (Claude):** found and fixed two real gaps this commit had — (1) `effectiveQueueModifiedAt`/`effectiveModifiedAt` folded the backup file's own `exportedAt` wall-clock time into the revival decision, so a content-stale queue could be revived purely because the file it shipped in was written later than the tombstone (fixed by dropping `exportedAt`/`restoreOrImportDate` from the calculation entirely — only the queue's/memberships' own timestamps count now). (2) `SyncTombstone` rows never traveled in the `.kudosbackup` manifest at all, so a fresh install/reinstall restoring a backup had zero local tombstone history and no protection against resurrecting anything deleted after that backup was made — the single most common real-world use of `.kudosbackup` (device migration/reinstall). Fixed via manifest v5: tombstones now export with the backup and merge into the target's local store on restore, before conflict resolution runs, so a fresh device inherits the source device's deletion history. Added 2 regression tests for both fixes. Verified: lint clean, iOS build clean, full iOS suite green. | Codex, Claude | `codex-icloud-sync-queue-conflict-fix` | (this commit) | 2026-07-04 |
| T-66 | **iCloud backup & persistence refinement** — documented the current SwiftData + Application Support/Caches + `.kudosbackup` architecture, chose a conservative metadata-first iCloud-ready design, and added stable sync metadata/tombstones/migration state without enabling unverified CloudKit entitlements. Backup schema v3 now preserves sync/progress metadata with timestamp-aware merge rules; EPUBs keep stable asset identifiers and remain local/manual-backup assets until a signed iCloud build is tested. Settings shows local persistence readiness and iCloud account availability. Added persistence migration/merge/tombstone tests and docs. Verified `git diff --check`, `Scripts/lint.sh`, iOS build (`iPhone 17`, OS 26.5), full iOS tests (`Scripts/test.sh 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`), and macOS build. **Adversarial review + fix passes (Claude, `e8a6164` + follow-up):** backup import now consults tombstones (was write-only — older backups could resurrect explicitly-deleted works, including privacy-cleared history) with a newest-tombstone-wins index and a newer-snapshot escape for works; members of a suppressed queue are dropped, not re-homed into Saved for Later; isFavorite/isSaved/isFinished/isComplete no longer OR-merge (older backups resurrected explicitly-unset flags) while brand-new records still adopt archive flags; `WorkLifecycle.delete` tombstones cascade-deleted queue memberships; `PersistenceMigrationService` is async with yield points + a re-entrancy guard + deleted-model guards (Settings retry no longer blocks the main thread); stage-aware migration error logging; Settings disclosure states nothing syncs to iCloud in this build. Six regression tests added. **Known toolchain issue (pre-existing, tracked separately):** Release-config builds (macOS + iOS device archive) crash the beta Swift compiler inside vendored SwiftSoup (`Element.appendNormalisedText` SIL ownership verifier); Debug builds unaffected. | Codex, Claude | `backup-refinement-icloud` | (this commit) | 2026-07-04 |
| T-62 | **Reading queue review pass + reader page-turn correction** — Independent adversarial re-review of `feature/native-ao3-queue` (13-dimension fan-out): confirmed lifecycle protection, split non-destructive/destructive removal, series consent-before-enumeration + quick auto-preserve toggle, custom-queue optional series, full 7-way series result accounting, atomic EPUB replacement, backup v1/v2 + AO3-identity restore, and container/schema coverage are all correctly implemented (prior "P0 lifecycle" review was stale). **Fixed** confirmed data-safety leak: the Library "Saved for Later" section (`LibrarySectionListView`) exposed queue-only works to a generic destructive Delete swipe that called `WorkLifecycle.delete` (hard-deleting the preserved EPUB, single-swipe when confirm-off) — now routes queue-only works to non-destructive `removeFromAllQueues`. **Fixed** history-query leak: `PrivacyDataView` + `AccountView` reading-history `#Predicate<SavedWork> { !$0.hasEPUB }` now also excludes `isQueuedForLater` (a queued work with pending/failed preservation has `hasEPUB == false` but is protected). **Cleanups:** removed dead `addAndPreserveCancellable`; deduped `postedChapterCount` into shared `SavedWork.postedChapterCount(from:)`. **Reader:** removed T-61's wrapper page-turn transform + floating page-edge overlay — it fired post-hoc on `locationDidChange`, after Readium already animated its native paginated swipe, producing a whole-view jiggle that didn't match Apple Books; paged turns now defer to Readium's native horizontal slide (Apple Books-like). Swipe-down-to-dismiss retained. Verified `Scripts/lint.sh` (warnings only, pre-existing), iOS build (`iPhone 17`, OS 26.5), focused `ReadingQueueTests`+`KudosBackupTests` (32 passed). | Claude | `feature/native-ao3-queue` | (uncommitted) | 2026-07-01 |
| T-61 | **Reader UI refinements** — iOS Readium reader now supports a vertical-dominant swipe-down dismissal with distance/velocity thresholds, horizontal-swipe rejection, scroll-mode top-of-scroll gating, a progress flush before dismiss, and the existing close/navigation affordances intact. Added a lightweight wrapper-level Apple Books-inspired page/card shuffle animation for paged Readium locator changes, with direction inferred from Readium positions/progression and a reduced-motion minimal fade/slide path; chapter-list jumps are suppressed. **Limitation:** Readium owns the actual page renderer/gesture internals, so the shuffle is a wrapper-level transform around the navigator rather than a true per-page renderer transition. No Reading Queue data/model/backup logic touched. Verified `git diff --check`, `Scripts/lint.sh` (warnings only), iOS build (`iPhone 17`, OS 26.5), macOS build, and full iOS tests. | Codex | `feature/native-ao3-queue` | (this commit) | 2026-07-01 |
| T-60 | **Reading queue review follow-up + Browse category tint** — Browse category icons now use the active theme tint; queue removal is non-destructive by default with explicit destructive variants; series preservation prompts use one-page preview context before full enumeration, include the small-series auto-preserve toggle, and pace/cancel preservation; custom queues can explicitly add selected series works; result accounting separates preserved/already-preserved/unavailable/failed/skipped/cancelled; critical queue/preservation/lifecycle saves are throwing or explicitly logged; EPUB replacement paths audited around validated atomic replacement. Added focused queue/series/removal/download-failure tests. Verified `git diff --check`, `Scripts/lint.sh`, focused `ReadingQueueTests`, full iOS tests (`Scripts/test.sh 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`), and macOS build. | Codex | `feature/native-ao3-queue` | (this commit) | 2026-07-01 |
| T-59 | **Native Reading Queues + Saved for Later preservation** — first-class ReadingQueue/ReadingQueueMembership state; queue-preserved EPUB lifecycle protection; default Saved for Later queue; backup v2/v1-compatible restore; queue-aware Library visibility; Work Detail queue actions; Settings queue storage/migration controls; safe small-series auto-preserve via one-page AO3 series preview; cancellable/slow-paced series preservation with progress; focused lifecycle/v1-backup/removal tests. Follow-up `89650ec` makes last-queue removal delete queue-only records, makes storage removal remove queue membership only, paces/cancels bulk preservation/migration work, and preserves saved/favorite records/files. Review-hardening `9fbd02e` fixes strict queue normalization, AO3-first/canonical backup restore identity, missing preserved EPUB repair, broken membership restore skipping, remote Save for Later failure semantics, canonical AO3 matching, and atomic EPUB replacement coverage. Verified `Scripts/lint.sh`, focused queue/backup/work-tag tests, `Scripts/test.sh 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`, and macOS build. | Codex | `feature/native-ao3-queue` | `f0e7886`, `6cee074`, `c5659ca`, `16e2e18`, `89650ec`, `9fbd02e` | 2026-06-30 |
| — | **Browse category icon theming fix** — In `MediaBrowserView.categoryCard`, changed the main category icon from `.foregroundStyle(.primary)` to `.foregroundStyle(.tint)` (matching stat icons and other themed elements) so it respects the current app theme (AO3 red on Light/Dark, warm brown on Sepia). Small polish follow-up to native Browse on the queue branch. | Grok | `feature/native-ao3-queue` | (this commit) | 2026-06-30 |
| T-58 | **Import AO3 EPUB files** — Settings now has an Import EPUB row with native multi-file `.epub` picker; user EPUBs are validated, inspected, copied into existing `SavedWork.fileURL` storage, parsed for EPUB/AO3 metadata, deduped by AO3 work ID or title+author+file size, and enriched through the existing throttled AO3 tag refresh only when an AO3 work URL/ID is present. Imported EPUBs use the normal Library/Work Detail/Reader path and existing backup assets. Added focused EPUB/import tests. Verified lint, iOS build, macOS build, targeted EPUB tests, and full iOS simulator tests (`iPhone 17`, OS 26.5). | Codex | `feature/native-ao3-actions` | `3fec492` | 2026-06-28 |
| T-56 | **Expanded result tags + Library card depth follow-up** — expanded shared `AO3WorkRow` now shows de-duplicated Additional Tags after Characters and omits the section when empty; Library/Home work cards have stronger theme-aware elevation/border plus carousel padding so shadows are not clipped. UI-only; no AO3 behavior/data/navigation changes. Verified lint, iOS build, macOS build, and iOS simulator tests (`iPhone 17`, OS 26.5). | Codex | `feature/native-ao3-actions` | `154257a` | 2026-06-27 |
| T-55 | **Native iOS UI refinement pass** — Library/Home cards are self-contained AO3 work summaries (title/author/fandom/status/stats/state/progress inside the card, no fake cover placeholders); Browse category title-to-stats divider removed while lower dividers remain; category-detail fandom rows stack `|` names with one fandom icon and trailing work-count icon; canonical Work Detail gains a shared overview section. Preserved AO3 behavior/actions/navigation and avoided reader/network refactors. Verified lint, iOS build, macOS build, and iOS simulator tests (`iPhone 17`, OS 26.5). | Codex | `feature/native-ao3-actions` | `e4e1842` | 2026-06-27 |
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
  
