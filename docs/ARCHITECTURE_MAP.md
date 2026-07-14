# ARCHITECTURE_MAP.md — where everything lives

All paths relative to `kudos-ao3-reader/` unless noted. Confirmed as of 2026-07-10.

## App shell & navigation

| Thing | File |
|---|---|
| App entry, shared `ModelContainer`, BGTask registration | `App/MyApp.swift` |
| Root TabView, launch housekeeping (`.task`: session restore → queue normalize → migration → Recently-Deleted sweep → index rebuild → folder sync), scene-phase sync triggers | `App/ContentView.swift` |
| Cross-tab routing (tag→search, native author profiles, pending URLs, inspector panel ownership) | `App/AppRouter.swift`; author destinations registered by `UIComponents/AO3AuthorNavigation.swift` |

## Feature surfaces

| Surface | Files |
|---|---|
| Home (carousel dashboard: Reading Now / Recently Updated / Subscriptions / Favorites / Recently Opened) | `Features/Home/HomeView.swift`, `HomeSectionListView.swift`, `HomeCards.swift` (WorkCoverCard, AO3WorkCoverCard, SelectableWorkCoverCard), `CanonicalWorkCoverCard.swift` |
| Library (carousel dashboard + select mode + filters + Recently Deleted entry) | `Features/Library/LibraryView.swift`, `LibrarySectionListView.swift`, `LibrarySectionKind.swift`, `LibraryFilters.swift`, `LibraryFilterPanel.swift`, `WorkRow.swift`, `WorkCardActions.swift` (local+remote context menus, `LocalWorkDestination`), `RecentlyDeletedView.swift` |
| Collections / Reading Queues | `Features/Library/Collections.swift` (incl. `AddToCollectionView(works:)`), `ReadingQueues.swift` (incl. `AddToQueueView(works:)`) |
| Browse (categories → fandoms → works; multi-select batch actions) | `Features/Browse/NativeBrowseView.swift` (`BrowseView`, `FandomWorksView`, `TagWorksView`), `Features/Search/MediaBrowserView.swift`, `FandomListView.swift`, `FandomCatalog.swift` |
| Search (global: local index matches + AO3 search) | `Features/Search/SearchView.swift`, `AO3WorkRow.swift` (remote result row, selection-capable) |
| Account (AO3 profile hub) | `Features/Account/AccountView.swift` — primary segments **Overview / Reading / Writing / Activity**; Overview hub + `AccountMoreOnAO3View`; Reading = Later/Subscriptions/Bookmarks/Collections; Writing = Works/Series/Drafts; Activity = History/Inbox. `AO3PreferencesView.swift`, `PrivacyDataView.swift`, `AO3AccountWorksList.swift`; preferences in `AO3Client+Preferences.swift` / `AO3PreferencesActions.swift` / `AO3PreferencesModels.swift` |
| Native AO3 author profiles (pseud scope, Works/Series/Bookmarks/About, series detail) | `Features/Authors/AuthorProfileView.swift`, `AuthorProfileComponents.swift`, `AO3SeriesDetailView.swift`; shared tappable bylines in `UIComponents/AO3AuthorNavigation.swift` |
| Settings (fonts, backup, folder sync, EPUB import, privacy prefs) | `Settings/SettingsView.swift` — ONE enum-driven `.fileImporter` (`FileImportKind`), see onboarding pitfalls |
| Reader — iOS | `Features/ReaderReadium/ReadiumReaderView.swift` + `ReadiumProgressPersistence.swift` (locator stream is debounced ~2s / progression delta; flush on dismiss, disappear, scene background; mid-session writes use `applyDebouncedReadiumLocator` so shelf order / folder-sync dirty don't thrash on scroll) |
| Reader — macOS (legacy) | `Features/Reader/ReaderView.swift` + `ReaderController.swift` (`#if os(macOS)`); progress = `lastSpineIndex`/`lastScrollFraction` via debounced `ReaderProgressBridge` |
| Reader routing | `BookReaderView` (grep) routes per-platform |
| Privacy (M/E) | `Features/Privacy/MatureContent.swift` — see below |

## AO3 networking / scraping

| Concern | Where |
|---|---|
| Central client (all GETs/POSTs/EPUB downloads, pacing, retry, status→typed errors, parsers) | `Services/AO3Client.swift` (actor) |
| Politeness primitives | `pace()` in AO3Client; `Services/AO3RequestCoordinator.swift` (3-slot concurrency cap); `Services/RequestCoalescer.swift` (in-flight dedup, anonymous by URL + authenticated by URL+Cookie) |
| Auth (WebKit login, Keychain session, validator, generation-owned lifecycle, serialized WebKit-cookie reconciliation, `authenticatedRequest`, `accountWorks`) | `Services/AO3AuthService.swift` (incl. `AO3RequestDefaults.userAgent` — the single UA), `AO3SessionVault.swift`, `AO3WebLoginCoordinator.swift` |
| Write actions (kudos/comments; CSRF; never retried/coalesced) | `Services/AO3WriteActions.swift` + `AO3Client.submitWrite` ⚠️ never live-verified against AO3 |
| Tag/metadata enrichment | `Services/WorkTags.swift` (24h attempt cooldown), `WorkMetadataRefresh.swift`, `WorkUpdateChecker.swift` (WIP-only, 6h throttle incl. failures) |
| Author/profile parsing, lazy state, and auth-scoped 5-minute HTML cache (Inbox private HTML/forms add session generation to their cache scope) | `Services/AO3Client+Authors.swift`, `AO3AuthorProfileService.swift`; values/routes in `Models/AO3AuthorModels.swift` |
| Download queue (sequential, skip/revive existing) | `Services/DownloadQueue.swift` |
| EPUB import funnels | `Services/WorkImporter.swift` — `importEPUB` (AO3 downloads; post-download dedup/merge/revive) and `importUserEPUB` (user files) |

## Persistence / backup / sync

| Concern | Where |
|---|---|
| Models + identity + `markModified` | `Models/Models.swift` |
| `.kudosbackup` package (manifest v7 + EPUB/font blobs), restore merge rules, tombstone index, `WorkRestoreIndex` | `Services/KudosBackup.swift` |
| Folder sync (iCloud Drive via user-picked folder; NSFileCoordinator; safe replace; skip-unchanged stamp; conflict folding) | `Services/FolderSyncService.swift`; background refresh `FolderSyncBackgroundTask.swift` (BGTask id `com.cidy02.Kudos.folderSyncRefresh`, iOS-only) |
| Migration + asset reconciliation + gate | `Services/PersistenceSync.swift` (`PersistenceMigrationService`, `PersistenceOperationGate`, `SyncTombstones`, `SyncMerge`) |
| Soft delete / 90-day recovery / hard delete / sweep | `Services/PreservedWorkService.swift`; permanent path `WorkLifecycle.hardDelete` in `WorkLifecycle.swift` |
| File locations (EPUBs by `effectiveAssetIdentifier`, reader cache, temp) | `Services/Storage.swift` |
| Design doc | `docs/iCloudPersistence.md` |

## Identity, search, dedup

| Concern | Where |
|---|---|
| 3-tier work identity (AO3 id → canonical URL → record UUID) | `Services/WorkIdentityIndex.swift` — the ONLY matcher; used by restore, context menus, queue service, canonical merge |
| Local/remote card dedup (`remoteLed` / `remoteOnly`) | `Services/CanonicalWorkMerge.swift` + `Models/CanonicalWork.swift` |
| Derived search index (normalize/reindex/match/rebuild) | `Services/WorkSearchIndex.swift`; fields `SavedWork.searchText` + `searchIndexVersion` |
| Verified AO3 account/pseud identity | `Models/AO3AuthorModels.swift`; parsed beside legacy author strings and persisted as `SavedWork.authorIdentitiesJSON` only after AO3 enrichment; never infer routes from display text |
| Queue service (membership, preservation, `resolveLocalWork`, `addToSavedForLater`, series preservation) | `Services/ReadingQueueService.swift` |

## Privacy / M-E blur

- `Features/Privacy/MatureContent.swift`: `SavedWork.isAdult` (rating == Mature/Explicit), `PrivacyGate` (@Observable; reveal state; `isHidden` = Hide-mode only), `SensitiveWorkRow` (List rows), `SensitiveWorkCoverCard` (carousel cards), `MatureRevealToggle` (the Privacy button), `PrivacyGate.hasVisibleMatureWorks(in:hideMature:)` (the single button-visibility rule).
- Modes: `MaturePrivacyMode.obscure` (blur, tap-to-reveal) / `.hide` (filtered out pre-render). Prefs: `@AppStorage("hideMatureContent")`, `("matureContentMode")`.
- Invariant: the Privacy button gates on the **currently visible, filtered** set of the surface, via the shared rule — never the raw `@Query`.
- `CanonicalWorkMerge` pairing matches only privacy-visible local works (Hide-mode works keep plain remote rows).

## Themes / UI kit

`ThemeManager` (environment), `UIComponents/` (`WorkCardListControls` — expand-all + filter button with `onClearFilters` long-press, `AppThemeSurface` with `.appThemedScroll()/.appThemedRows()`), `WorkSelectionBubble` in `HomeCards.swift`.

## Unknowns / verify-before-touching

- Legacy macOS reader internals (`ReaderController.swift`) — least-touched area this cycle.
- `AO3WebLoginCoordinator.inspectPage()` JS selectors — duplicated with `LiveAO3SessionValidator.isLoggedIn` (keep-in-sync comment in `AO3AuthService.swift:101`).
- Live behavior of write actions (`AO3WriteActions`) — logic-tested only.
