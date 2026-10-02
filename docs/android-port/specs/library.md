# Library Porting Spec

**Source:** `kudos-ao3-reader/Features/Library/LibraryView.swift`

## 1. Screen tree
The Library dashboard operates in a `NavigationStack` with the large inline title "Library". When in `isSelecting` mode, the title dynamically changes to "Select Works" or "X Selected" (`WorkSelectionTitle.text(selectedCount:)`). The background is `themeManager.appTheme.appBaseBackground ?? Color.clear`. 

The core view branches based on the user-selected `dashboardLayout` (`.shelves` or `.ledger`), which is toggled via the toolbar's Layout picker.
* **Shelves Layout (`shelvesDashboard`)**: A `ScrollView` with a `VStack` (alignment `.leading`, spacing: 22, vertical padding: 12). Sections are rendered as horizontal carousels (`localCarousel`) utilizing `WorkCarouselSection`.
* **Ledger Layout (`ledgerDashboard`)**: A `List` (`.listStyle(.plain)`) with `.scrollContentBackground(.hidden)`. Sections are rendered as stacked vertical rows (`localLedgerSection`) using `WorkLedgerListSection` with `.dashboardListRow` modifiers (which resets padding to 16pt horizontally, removes row backgrounds, and hides list separators).

Both layouts follow the exact same vertical ordering of sections:
1. `fandomFilterBar` (Filter chips, `LibraryFilterPanel.swift`)
2. `readingNow`
3. `savedForLater`
4. `finished`
5. `collections`
6. `downloaded`
7. `history`
8. `favorites`
9. `recentlyDeletedRow` (Only shown if `recentlyDeletedCount > 0`).

## 2. Components
* **Shelves Layout Sections**: Uses `WorkCarouselSection` (`WorkCarouselSection.swift`) with `SensitiveWorkCoverCard` items.
* **Ledger Layout Sections**: Uses `WorkLedgerListSection` with `WorkRow` (`presentation: .ledger`) items.
* **`WorkLedgerRow` (Inside `WorkRow`)**: Compact, washed row (`SubjectScreen.swift`).
  * **Structure**: `HStack` (alignment top, spacing 13).
  * **Padding**: Horizontal 16, vertical 15 (if `drawsBackground` is true). In lists, `drawsBackground` is false and the list paints the `subjectPalette.cardWash`.
  * **Leading edge**: `WorkProgressRing` (44pt) or queue position number.
  * **Middle**: 
    * `kickerView`: `SubjectKicker` (size 9, rule spacing 5). Muted via `saturation(0)` if `kickerMuted` (e.g. abandoned work).
    * `titleLine`: `titleSize` (16.5pt). Can have a trailing icon (e.g., `star.fill` tinted `.subjectFavoriteGold` in Favorites, with spacing 6).
    * `metadataLine`: `metadataSize` (11.5pt). Includes `WorkStat.localWorkMetadata` (dot-separated Author, Words, Chapters).
  * **Trailing edge**: `WorkStatusIconGrid` (4-signal tray, `tileSize` 22).
* **Recently Deleted Row**: A `subjectPanel()` row (`HStack`) with a trash icon, text, count (monospaced, `compactCount`), and chevron. Padded vertically 13, horizontally 16.
* **FilterBar**: Horizontally scrolling list of filter chips (`LibraryFilterPanel.swift`) for tags, characters, and reading statuses.
* **Kotlin**: `SubjectHeaderBlock` and `SectionRuleHeader` exist. Missing: `WorkLedgerRow`, carousel components (`WorkCarouselSection`), `SubjectFilterRail`, and `FilterButton`.

## 3. Data
All sections cap the displayed works to 12 items (`.prefix(12)`) in the dashboard.
* The data for sections is derived from `cachedWorks(for: kind)` which applies the active `LibraryFilters` (tags, characters, completion status) and the specific section predicate (e.g. `isFinished`, `isFavorite`, `isDownloaded`) to the global library `works`.
* **Collections**: Lists user-created collections up to 12, filtered by `showsOnHome == false` (or all collections in Library context).
* **Android source**: `io.github.cidy02.kudos.library.*` (e.g., `LibraryViewModel`, `LibraryRepository`).

## 4. Interactions
* **Taps**: 
  * Work tap -> Pushes `WorkDetailView(work: work)` (Unlike Home, which goes straight to Reader. Rationale: "The facts a disclosure used to reveal... are what Work Detail is for, one tap away").
  * Collection tap -> Pushes `CollectionDetailView`.
  * Recently Deleted tap -> Pushes `RecentlyDeletedView`.
* **See All**: Section headers push `LibrarySectionRoute(kind: kind)`.
* **Swipe Actions (Ledger / List view only)** (`LibraryWorkSwipeActions.swift`):
  * *Leading (no full swipe)*: "Save for Later" (only if history or favorites list), "Download" (cloud), "Favorite"/"Unfavorite" (yellow tint, absent in favorites list).
  * *Trailing (no full swipe)*: "Unfavorite" (yellow tint, only in favorites list), "Remove" (history or queue-only works; destructive role but non-deleting; adds a hide marker or removes queue membership), "Delete" (red tint, soft-deletes the work with confirmation alert).
* **Select Mode**: Triggered via the toolbar.
  * Tab bar hides. Top right changes to "Select All" / "Deselect All".
  * Bottom bar (`WorkBulkActionBar`) appears with: "Delete" (destructive), "Actions" (Bulk Download, Favorite, Save for Later, Add to Queue, Add to Collection, Tag, Mark Finished), and "Done" (checkmark).
* **Long-press (Context Menu)**: Shared with Home. Read, Comments, Select, Download, Favorite, Save for Later, Add to Queue, Mark Finished, Add to Collection, Rebuild from Original, Work Details, Delete.
* **Toolbar (Top Right)**:
  * "New Collection" (`plus`). Opens `showingNewCollection`.
  * "Filter" button (if works aren't empty, icon `Icons.Filled.FilterList`).
  * "More" menu (`ellipsis`): Contains "Privacy" (`MatureRevealToggle`), "Select" (`checklist`), "Layout" (`Picker` for `.shelves` vs `.ledger`), and "Reading Insights" (`chart.bar.xaxis`).
* **Pull-to-refresh**: Calls `refreshLibraryDashboard()`.

## 5. Strings
* Navigation title: "Library", "Select Works", "X Selected".
* Section titles: "Reading Now", "Saved for Later", "Finished", "Collections", "Downloaded", "Reading History", "Favorites", "Recently Deleted".
* Layout Picker: "Layout" (options "Show Carousels" / "Show Detailed List").
* Swipe Actions: "Save for Later", "Download", "Favorite", "Unfavorite", "Remove", "Delete".
* Toolbar/Menu labels: "New Collection", "Select", "Reading Insights".
* Bulk Action Bar: "Delete" (trash), "Actions", "Done" (checkmark). "Select All", "Deselect All".

## 6. Owner decisions
* `"The 'New collection' row is the toolbar's '+' now (owner, 2026-10-01: global actions live in the top-right chrome)."` (`LibraryView.swift`) - Prevents UI shifting when rows are empty.
* `"Filter is the only other control directly visible; Privacy lives behind '...' (with Select and Reading Insights)."` (`LibraryView.swift`) - Reduces toolbar clutter.
* `"Spec 1c puts the layout choice in the '…' rather than on the page: it is set once and then lived with, unlike Filters, which is changed constantly and keeps its own button."` (`LibraryView.swift`) - Rationale for placing Layout inside the overflow menu.
* `"A ledger row does not expand. It is a different kind of card from a search result... The facts a disclosure used to reveal... are what Work Detail is for, one tap away. Owner's call, 2026-09-12."` (`WorkRow.swift:76`)

## 7. Android gaps
* Missing `WorkLedgerRow` UI (the compact swipeable ledger row).
* Missing carousel layout handling (`WorkCarouselSection`) inside `LibraryViewModel`.
* Missing standard Swipe Actions implementations for `LazyColumn` items matching the iOS semantics (especially partial swipe without full-swipe commit).
* Missing `SubjectFilterRail` UI (horizontally scrolling filter chips).
* Missing the custom top-right "More" menu with the Layout picker.
* Missing `WorkBulkActionBar` and global select mode logic for the Library screen.
