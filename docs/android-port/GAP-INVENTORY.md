# Android gap inventory (Grok, 2026-10-02, read-only audit; spot-check before acting)

Android already has a working reader, library, search, account lists, inbox, and comments. It does not have the redesign, and several whole areas (challenges, writing, session-based insights, queue and collection colour) are missing. Nothing below was checked on a device. Where a file was only named, not opened, that is marked.

Redesign, once: a search of the Kotlin tree found no `SubjectPalette`, kicker, `cardWash`, `colorHex`, or subject header. `ui/theme/Theme.kt` is Material 3 with Light, Dark, OLED, Sepia, and accent `#990000`. Sepia forces its own brown and ignores the accent. Screens use Material type and a `NavigationBar`. Treat every row below as the older look unless a row says otherwise.

## Shell (matrix row)

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `App/ContentView.swift` | `app/MainScaffold.kt`, `app/Routes.kt` | Four tabs plus a Search icon in the top bar. iOS puts Search in the system search-role slot. No floating bar, no subject wash under a title-less bar. | M |
| `App/DemoLibrary.swift` | none | No demo library or debug-route launch extra. | L |

## Home

`HomeSectionKind.kt` matches the four local sections in `HomeSections.swift`. Its comment records a deliberate empty-copy change for Recently Updated.

| iOS (file) | Android | Gap | Size |
|---|---|---|---|
| `HomeView.swift` | `home/HomeScreen.kt` | Shelves for Reading Now, Recently Updated, Subscriptions, Favorites, Recently Opened, plus select mode. No resume hero, no Show-on-Home collection shelves, no 1b stacked queue deck. | L |
| `HomeResumeHero.swift` | none | Resume block absent. | M |
| `HomeCollectionShelves.swift` | none | `showsOnHome` has no Android field, so no shelf can appear. | M |
| `HomeSectionListView.swift` | `home/HomeSectionListScreen.kt` | See-all, select, and `LibraryFilterPanel` exist. Header is a Material title. | M |
| `HomeCards.swift`, `CanonicalWorkCoverCard.swift` | `ui/components/WorkCoverCard.kt`, `AO3WorkCard.kt` | Long-press and select exist (`combinedClickable`). No subject wash, progress ring, or download ring. | M |

## Library

`LibrarySectionKind.swift` has seven shelves: Reading Now, Saved for Later, Finished, Collections, Downloaded, Reading History, Favorites. `LibraryModels.kt` documents the Android dashboard as Reading Now, Saved for Later, Finished, and Downloaded. History and favorites are separate plain lists.

| iOS (file) | Android | Gap | Size |
|---|---|---|---|
| `LibraryView.swift` | `library/LibraryScreen.kt` | Select mode, context menu, add-to-queue and add-to-collection. Menu "Download" / "Remove Download" toggles `isSaved` only (`LibraryScreen.kt`; `WorkRepository.setSaved` does not touch the file). | L |
| `LibrarySectionListView.swift`, `LibrarySectionKind.swift` | shelves inside `LibraryScreen.kt`; history/favorites in `account/LocalLibraryListsScreen.kt` | History and favorites are unsorted rows, not ledger shelves. Collections are a different screen. | M |
| `LibraryFilters.swift`, `LibraryFilterPanel.swift` | `LibraryFilter.kt`, `LibraryFilterPanel.kt` | Android facets: favorite, finished, download, completion, user tags, collections, rating, warnings, categories, fandoms, relationships, characters, freeforms. No language, word range, or exclude-tags (those fields are on the iOS struct). Download filter tests `hasEpub`, not "kept" (`LibraryQuery.kt`). | M |
| `LibraryWorkSwipeActions.swift` | none on the library rows | Swipe-to-dismiss appears on `settings/QueueStorageScreen.kt` only. | S |
| `WorkRow.swift`, `WorkCardActions.swift` | rows in `LibraryScreen.kt` | Long-press menu has Read, Comments, Select, Download, Save for Later, Favorite. No keep-offline wording and no download ring. | M |

## Reading queues

`ReadingQueueEntity` stores id, name, kind, sort, dates, and soft-delete. Memberships store order and `note`. No hue, `colorHex`, pin, notes, tags, or `keepsWorksOffline`.

| iOS (file) | Android | Gap | Size |
|---|---|---|---|
| `ReadingQueues.swift`, `ReadingQueueBrowser.swift`, `ReadingQueuePageParts.swift` | `library/ReadingQueueBrowserScreen.kt`, `QueueDetailScreen.kt` | Create-by-name and a list of works. `ReadingQueueBrowserScreen.kt` still draws `QueueSwitcherBar`. iOS owner decision T-343 removes that bar. | L |
| `NewReadingQueueSheet.swift` | name dialog in the browser | No Edit Queue sheet: no colour, keep-offline, notes, or tags. | L |
| `QueueCardMenu.swift` | none | No press-and-hold Edit / Pin / Delete. | M |
| `QueueTagManagerView.swift`, `QueueTagSheet.swift` | none | Queue tags absent. `Tag` is work-only. | M |
| `ReadingQueueOrganizer.swift`, `ReadingQueueSettingsView.swift` | `settings/QueueStorageScreen.kt` | Storage list with swipe-to-dismiss, not the queue editor. | M |

## Local collections

iOS `WorkCollection` has `hue`, `colorHex`, `keepsWorksOffline`, `showsOnHome`, and `workOrderRaw`. The model comment says `collectionDescription` is stored so Android backups round-trip, and that iOS does not render it.

| iOS (file) | Android | Gap | Size |
|---|---|---|---|
| `Collections.swift`, `CollectionLedgerRow.swift` | `library/CollectionsScreen.kt`, `CollectionDetailScreen.kt` | Name, description, and sort order (`CollectionEntity`). Description is shown. No colour, keep-offline, Show on Home, or reader order. Cross-ref is an unordered pair. | L |
| `NewCollectionSheet.swift` | create path on `CollectionsScreen.kt` (body not fully read) | No swatch row and no wash from the picked colour (T-350). | M |

## Recently Deleted

| iOS (file) | Android | Gap | Size |
|---|---|---|---|
| `RecentlyDeletedView.swift` | `library/RecentlyDeletedScreen.kt` | Works, collections, and queues restore or delete forever. Copy says 90 days. No "Finished, not kept" section and no `freedAt` 60-day hold. | M |

## Reading Insights

| iOS (file) | Android | Gap | Size |
|---|---|---|---|
| `ReadingInsightsView.swift`, `Services/ReadingInsights.swift`, `Models/ReadingSession.swift` | `library/ReadingStatisticsScreen.kt`, `ReadingStatistics.kt` | Android counts works: started, finished, words of finished works, opens in 7 and 30 days, top fandoms. The file says it does not track sessions. iOS uses `ReadingSession` hours, a seven-week chart, and month/year. No `ReadingSession` entity. | L |
| `ReadingHistoryFactsStrip.swift`, `ReadingAffinities.swift`, `FavoriteAffinityRow.swift` | none | Affinity and history strips absent. | M |

## Browse

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `Browse/BrowseView.swift`, `NativeBrowseView.swift` | `browse/BrowseScreen.kt` | Categories, then fandoms, with local counts (`CategoryStats.kt`, `BrowseLocalIndicators.kt`). | M |
| `Search/FandomListView.swift`, `FandomListFilterSheet.swift`, `FandomCatalog.swift` | `browse/FandomListScreen.kt`, `network/.../FandomCatalogCache.kt` | List and cache exist. Filter sheet parity was not opened. | M |
| `Browse` fandom and tag work lists | `FandomWorksScreen.kt`, `TagWorksScreen.kt` | Screens exist. Multi-select batch actions were not confirmed in those files. | M |
| `Search/MediaBrowserView.swift` | none under that name | Media browse as its own screen was not found. | S |

## Search and filters

`AO3SearchFilters.kt` covers query, include and exclude tags, rating, warnings, categories, crossover, completion, word bounds, updated, language, and sort. Save and delete go through `SavedSearchRepository`.

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `SearchView.swift`, `SearchLocalResultsList.swift` | `search/SearchScreen.kt` | Local matches plus AO3 results, save dialog, delete. | M |
| `AO3FilterPanel.swift`, `FilterLanguagePicker.swift`, `FilterRangeSlider.swift`, `TagSelectField.kt` | `SearchFilterSheet.kt`, `TagSuggestField.kt` | Filter model is broad. Sheet layout versus the iOS panel was not compared control by control. | M |
| `SaveSearchSheet.swift` | dialog inside `SearchScreen.kt` | Save exists. Redesign sheet does not. | S |
| `SearchResultsHero.kt` | `search/SearchResultsHero.kt` | Both exist. Visual match not checked. | S |
| `AO3WorkRow.swift`, `SearchPaginationBar.swift` | `AO3WorkCard.kt`, `KudosPaginationBar.kt` | Row and pager exist, Material styling. | S |

## Work detail

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `WorkDetailView.swift` and the section files beside it (`WorkDetailFactsSections`, `Overview`, `Identity`, `Figures`, `Provenance`, `AO3WorkActionsMenu`) | `works/WorkDetailScreen.kt` | One large screen: download queue, subscribe label, bookmark notes, series-preservation prompt, comments, write actions. "My copy" as its own sheet was not found. Section-by-section match with 1a was not completed. | M |

`SavedWork.hasGivenKudos` is not on the Android model, so a filled kudos heart cannot persist the way the iOS field does.

## Reader

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `ReaderReadium/ReadiumReaderView.swift` plus chrome (`ReaderChromeTopBar`, `ReaderFanMenu`, `ReaderPositionCard`, `ReaderContentsSheet`, `ReaderDismissDrag`) | `reader/ReaderScreen.kt`, `reader/readium/*` | Readium open, progress, in-book search, highlight decorations, font and theme sheet. Fan menu, peel-to-dismiss, and the position card were not found. | L |
| Annotations (`ReaderHighlightHost`, `ReaderNoteEditor`, `ReadingAnnotation`) | `AnnotationEntity`, `AnnotationRepository` | Bookmark, highlight, note, colour, and locator are stored. Colour picker and contents-sheet segments were not confirmed. | M |
| `ReaderSpeechController.swift`, `SystemTTSService.swift`, `CoreMLKokoroTTSService.swift`, pronunciation and skip files | `reader/speech/ReaderSpeechController.kt`, `KokoroTTSController.kt` | Speech exists and is sherpa-onnx Kokoro only. No system-voice fallback, no Core ML pack, no pronunciation backup. Now Playing and chapter skip were not found. | L |

## Comments

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `CommentsView.swift`, `CommentThreadScreen.swift`, `CommentThreadRow.swift`, `CommentMarkup.swift` | `comments/CommentsScreen.kt`, `CommentsViewModel.kt` | Thread load, reply, edit, drafts, chapter deep link from the reader. Markup and the 1f / 1ba layout were not compared. | M |

## Account hub

`docs/ARCHITECTURE_MAP.md` describes iOS as one flat hub: Shortcuts, then Reading, Writing, Activity, Account. No segmented control.

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `AccountView.swift`, `AccountComponents.swift`, `AccountShortcuts.swift` | `account/AccountScreen.kt` | Signed-in and signed-out states, profile header, Privacy row. The screen is tabbed: Overview / Reading / Writing / Activity (`AccountHubTabRow`). | L |
| `AO3DashboardView.swift` | `account/AO3DashboardScreen.kt` | iOS dashboard is your own author profile (recent fandoms, works, series, bookmarks). Android is a link list: Works, Collections, Bookmarks, Subscriptions, Marked for Later. | L |
| `Auth/AO3LoginView.swift` | `auth/AO3WebLoginScreen.kt`, `AO3NativeLoginScreen.kt` | Web login plus a native username form. | S |

## Marked for Later, bookmarks, history, subscriptions

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `AO3MarkedForLaterWorksBrowser.swift`, `AO3BookmarksWorksBrowser.swift`, `AO3HistoryWorksBrowser.swift`, `AO3SubscriptionsWorksBrowser.swift` | `AccountListType` plus `account-list` route (`Routes.kt`) | The four lists exist as one account-list screen. Refine, select, and session reload were not opened. | M |
| `AO3NamedSubscriptionsList.swift`, `AO3SubscriptionsRefine.swift` | none found | No named-subscription screen in the Android tree. | M |
| `AO3AccountWorksList.swift` | same account-list path, `AccountListType.MyWorks` | Works list exists. Bulk bar parity with `OwnWorksBulkBar.swift` was not confirmed. | M |

## Inbox

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `AccountInboxScreen.swift`, `AccountInboxViews.swift`, `AccountInboxFilterSheet.swift`, `AO3InboxModel.swift` | `account/AccountInboxPane.kt`, `AccountInboxViewModel.kt` | Page load, filter form, current-page selection, bulk mark read, unread, and delete. It is a pane, not its own route in `Routes.kt`. 1l layout absent. | M |

## Authors

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `AuthorProfileView.swift`, `AuthorProfileComponents.swift`, `AuthorProfileContentSections.swift` | `author/AuthorProfileScreen.kt` | Tabs Works, Series, Bookmarks, About, with paged loads. | M |
| `AuthorWorks` scope inside the profile, `WorksScopeAndSort.swift`, `OwnWorksBulkBar.swift` | `author/AuthorWorksScreen.kt` | Selection is implemented there. Sort and bulk-edit scope not confirmed. | M |
| `AO3SeriesDetailView.swift` | `app/SeriesWorksScreen.kt` | Series works list exists. Challenge and collection actions on a series were not seen. | S |

## AO3 collections

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `AO3CollectionsList.swift`, `AO3CollectionsFilter.swift`, `AO3CollectionsFilterPanel.swift` | `account/AO3CollectionsScreen.kt` | A name list that opens `AccountListType.Collection`. No filter panel. | M |
| `AO3CollectionDetailView.swift`, `AO3CollectionFormView.swift`, `AO3CollectionItemsView.swift`, `AO3CollectionItemStaging.swift` | none | No create, edit, item staging, or collection detail. | L |

## Challenges

No `challenges` package and no matching screen names in the Kotlin tree.

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `ChallengeAssignmentsView`, `ChallengeSettingsView`, `ChallengeSettingsEditView`, `ChallengeSignUpView`, `ChallengeSignUpsView`, `PromptMemeView`, `PromptTagsEditorView`, `TagSetView`, `CollectionModerationView`, `CollectionMaintainersView` | none | The whole challenge and moderation surface is absent. | L |

## Writing

`network/ao3/writes/AO3WriteRepository.kt` is kudos, bookmarks, and comments. It is not a posting editor. `AccountScreen` has a Writing tab; there is no `Features/Writing` counterpart.

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `WritingDraftsView`, `WorkEditView`, `AddChapterView`, `WritingChaptersView`, `EditTagsView`, `WritingTagsEditor`, `BulkTagStatePicker`, `EditMultipleWorksView`, `SeriesEditView`, `SeriesReorderDestination`, `WritingPreviewView`, `WritingNativeTextView`, `WritingTextEditor`, `WorkAssociationPickers` | none | Drafts, work edit, chapters, tags, and series edit are absent as screens. | L |

## AO3 Preferences

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `AO3PreferencesView.swift`, `Models/AO3PreferencesModels.swift` | `account/AO3PreferencesScreen.kt` | Loads the snapshot and saves toggles, selects, and text fields, with a help link per toggle. Material list, not the 1z / 1bb subject form. | M |

## Settings

iOS `SettingsRoute.swift` pushes Appearance, Font, Reader, Listening, Downloads, Preservation, Reading Queues, Library, Backup, Sync Folder, Import, AO3 Account, Privacy, About.

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `SettingsHubView.swift`, `SettingsReadingPages.swift`, `SettingsStoragePages.swift` | `settings/SettingsScreen.kt` (one scroll), `QueueStorageScreen.kt` | Theme, fonts, reader sliders, library toggles, backup entry, privacy. The screen comment marks Sync as N/A. No "Keep works you read" string in the Kotlin tree. | L |
| `SettingsBackupPage.swift`, `PairingSheet.swift` | `backup/BackupScreen.kt`, `PairingSheet.kt` | Export, import, and pairing exist. | M |
| `SettingsSyncFolderPage.swift`, `SettingsImportPage.swift` | `backup/FolderSyncWorker.kt`, `onboarding/SyncFolderOnboardingScreen.kt` | Worker and first-run screen exist. No settings page equivalent was in `settings/`. | M |
| `SettingsAccountPages.swift`, `AboutView.swift`, `LegalNoticesView.swift` | `account/AboutScreen.kt` | About exists. Legal notices as their own page were not found. | S |

## More on AO3

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `AccountMoreOnAO3View.swift` | none | Seven Browse links (support, abuse report, terms, content policy, privacy, FAQ, donate). No matching screen name in Kotlin. `web/AO3WebViewFallbackScreen.kt` can open a URL if something navigates there. | M |

## Onboarding and support

| iOS (file) | Android (file or "none") | Gap | Size |
|---|---|---|---|
| `WelcomeView.swift` | `onboarding/WelcomeScreen.kt` | First-run gate exists (`KudosApp.kt`). | S |
| `SyncFolderOnboardingView.swift` | `SyncFolderOnboardingScreen.kt` | Present, including permanent dismiss. | S |
| `BugReportView.swift`, `ShakeDetector.swift` | `account/BugReportScreen.kt`, `support/ShakeDetector.kt` | Both exist. | S |
| `WhatsNew.swift` | none found as a file | Release notes are handled by `update/ReleaseNotesPresentation.kt` inside the Android updater, which iOS does not have. | S |

## Data parity

iOS `SavedWork.isDownloaded` is `hasEPUB` and (`isSaved`, or kept by a queue or collection, or an import with no AO3 id) (`Models.swift`). Android's library menu treats `isSaved` as downloaded and leaves the file in place. Finishing an unprotected work deletes the EPUB immediately (`WorkRepository.setFinished`). There is no `freedAt`, so no 60-day held copy.

Room work row (`WorkEntity`) and domain `SavedWork` omit, among other iOS fields: `hasGivenKudos`, `keepInProgressOverride`, `hiddenFromHistoryAt`, `freedAt`, `legacyReaderProgress`, `ao3WorkID`, bookmark count, `datePublished`, `dateUpdated`, `ao3SeriesID`, `authorIdentitiesJSON`, `assetIdentifier`, `epubDigest`, `remoteEPUBPending`, and the sync-status trio. `ao3Unavailable` is present. Preservation columns are stored and the entity comment says Android must not act on them.

`BackupWork` in `BackupManifest.kt` does declare some of those keys (`ao3WorkID`, dates, `ao3SeriesID`, `assetIdentifier`, `metadataSyncStatusRaw`). Whether the importer writes them anywhere was not traced past the DTO. They are not on `SavedWork`.

Absent from the Android manifest types that were read, and present on iOS `KudosBackup.swift`: top-level `readingSessions`, `readingFavorites`, `fandomReadWatermarks`, `pronunciations`; work keys `hasGivenKudos`, `keepInProgressOverride`, `bookmarks`, `legacyReaderProgress`, `hiddenFromHistoryAt`, `epubDigest`; collection `hue`, `colorHex`, `keepsWorksOffline`, `showsOnHome`, `workOrderRaw`; queue `hue`, `colorHex`, `isPinned`, `keepsWorksOffline`, `notes`, and tag names. No Room entity for `ReadingSession`, `ReadingFavorite`, or `FandomReadWatermark`. Queue memberships lack soft-delete and sync fields the iOS join has.

| iOS | Android | Gap | Size |
|---|---|---|---|
| `Models/Models.swift` (`SavedWork`, `WorkCollection`, `ReadingQueue`) | `WorkEntity`, `CollectionEntity`, `ReadingQueueEntity` | Colour, keep, pin, history-hide, kudos-given, and held-copy fields missing. | L |
| `Models/ReadingSession.swift`, `ReadingFavorite.swift`, `FandomReadWatermark.swift` | none | Insights and backup cannot round-trip. | L |
| `Services/KudosBackup.swift` v8 additive keys | `backup/BackupManifest.kt` | Manifest is v8 for annotations (`BackupVersion.kt`) and drops the keys above. | L |
| `Services/KeepOffline.swift`, `WorkDownload.swift`, `WorkLifecycle.swift` | `WorkRepository.setSaved` / `setFinished` | Keep, un-keep, and the 60-day hold are a different behaviour. | L |
| `Services/FolderSyncService.swift` | `backup/FolderSyncWorker.kt` | A worker exists. Parity with the iOS coordinator was not read. | M |

## The ten largest gaps

1. The subject design system. Every screen still uses Material 3, so restyling cannot start until the shared pieces exist.
2. Download and keep semantics: "Downloaded" means `isSaved` or `hasEpub`, Remove Download does not un-keep a file, finishing deletes the file immediately, and there is no 60-day hold.
3. Backup round-trip: sessions, favorites, fandom watermarks, pronunciations, queue and collection colour, pin, keep, notes, and the newer work fields.
4. Challenges, the whole `Features/Challenges` set.
5. Writing, the whole `Features/Writing` set.
6. Reading queues: Edit Queue, exact colour, pin, tags, keep-offline, and the press-and-hold menu. The bottom switcher is still there.
7. Local collections: colour, keep, Show on Home, and reader order. Home cannot grow those shelves until the fields exist.
8. Reading Insights as session hours, a chart, and a period control, rather than work counts.
9. AO3 collection management (create, edit, items) and the dashboard, which should be the signed-in author profile rather than a link list.
10. Reader chrome and read-aloud: fan menu, position card, system voice beside Kokoro, chapter skip, and pronunciation. Settings is one page instead of the 1ab hub, including "Keep works you read".

## Shared pieces Android lacks

From `UIComponents/` and the Phase 1 list in `docs/android-port/LIVING-PROMPT.md`, none of these names appear in Kotlin:

- Theme tokens used as the subject wash, with the accent applied as picked on controls (T-348). Sepia already drops the accent on purpose.
- `SubjectPalette` (`SubjectSurface.swift`, `CarouselCardStyle.swift`): accent, card, row, and panel washes, borders, chip fill, and `init(color:)` for a picked colour at alpha.
- `SubjectHeaderBlock`, `SectionRuleHeader`, `SubjectChip`, `SubjectStatStrip`, `WorkProgressRing`, the download ring and dimming, `SubjectFormRow`, `subjectPanel`, `cardRow`.
- Glass toolbar buttons, `ActionToolbar` (at most four), `WorkListMoreMenu`, `FilterButton` with a badge, `SubjectFilterRail` (chips only).
- `WorkLedgerRow`, `WorkCoverCard` at the spec size, the 1b queue deck card, the collection card, `SubjectHueSwatchRow` (five presets, dashed "+", `colorHex`).
- Demo mode equivalent to `-KudosDemoLibrary YES`.

`ui/components/` already has cover cards, a work card, bulk bar, pagination, refresh, and a glass field bar. Those are the older components, not the subject set.

## What Android has that iOS does not

- In-app updates from GitHub (`update/`, including download and install). iOS has no matching package.
- Sherpa-onnx Kokoro as the read-aloud engine (`KokoroTTSController.kt`). The architecture map says iOS playback is the system voice plus Core ML Kokoro, and that Sherpa is not linked for playback.
- A native username login screen beside the web login.
- Collection description drawn on `CollectionsScreen.kt`. iOS stores the field and does not render it.
- A bottom queue switcher. iOS removed it (T-343).
- An Account hub built as Overview / Reading / Writing / Activity tabs. iOS is one flat page.
- `WorkRepository.deleteLocalEpub`, a direct file delete. That is a different action from iOS Remove Download, which only clears the keep.
