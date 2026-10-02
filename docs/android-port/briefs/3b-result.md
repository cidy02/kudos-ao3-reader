# 3b — Library result

## Built

- Rebuilt Library as the iOS subject dashboard: fandom rail; Reading Now, Saved for Later, Finished, Collections, Downloaded, Reading History, and Favorites in order; conditional Recently Deleted row; 12-item dashboard caps; collapsible sections; persistent Carousels/Detailed List layout.
- Added Filter-with-count, New Collection, and More chrome. More retains Android Reading Queues alongside Privacy, Select, Layout, and Reading Insights. Search and sorting remain available in the filter sheet.
- Added pushed See All work lists with subject headers, filtering, privacy reveal, partial swipe actions, long-press actions, pull-to-refresh, and select-all/bulk Delete–Actions–Done UI. Selection hides the floating tab bar.
- Restyled Collections See All as an adaptive card grid with create/open/delete behavior. Recently Deleted now counts works, collections, and queues.
- Preserved `WorkDownloadSemantics`, soft deletion, Saved for Later membership, collection/queue actions, and the history hide marker (`hiddenFromHistoryAt`).

## iOS → Kotlin

- `WorkCarouselSection` → `ui/subject/WorkLibraryComponents.kt::WorkCarouselSection`
- `WorkCoverCard` → `ui/subject/WorkLibraryComponents.kt::WorkCoverCard`
- `WorkLedgerRow` → `ui/subject/WorkLibraryComponents.kt::WorkLedgerRow`
- `LibraryWorkSwipeActions` → `SwipeActionRow` plus Library action mapping
- `LibrarySectionKind` / `LibrarySectionListView` → `LibrarySectionKind.kt` plus `LibrarySection` navigation
- `CollectionCard` / `CollectionLedgerRow` → `LibrarySubjectComponents.kt`
- `WorkBulkActionBar` → `LibrarySelectionActionBar`

Home 3a was parallel work: Claude must reconcile its cover-card, carousel-section, and ledger-row implementations with the shared iOS-named components added under `ui/subject/` here.

## Differences / verification

- Reading Queues stays in More instead of adding a non-iOS dashboard shelf. Privacy-obscured titles are omitted from full-grid collection previews rather than blurred, preventing title disclosure with the current miniature component.
- `:app:assembleDebug` and `:app:compileDebugUnitTestKotlin` pass offline. Five focused JUnit tests pass (section order/routes, history removal, partial-swipe settling).
- The requested Gradle test task compiled all tests, but its worker could not start because this sandbox forbids localhost sockets (`SocketException: Operation not permitted`). ADB is blocked by the same socket policy, so no Dark/Sepia emulator screenshots were captured.
