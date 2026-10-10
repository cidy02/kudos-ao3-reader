# Library Audit: iOS vs Android

This document lists the differences between the iOS and Android implementations of the Library section, focusing on what Android still lacks or where it diverges from iOS. 

## 1. Dashboard & Sections
1. **iOS:** `Features/Library/LibraryView.swift`
2. **Shows:** The Library dashboard with sections `Reading Now`, `Saved for Later`, `Finished`, `Collections`, `Downloaded`, `Reading History`, and `Favorites`. It uses a `WorkListMoreMenu` for layout picking, mature toggle, select mode, and reading insights. `Recently Deleted` is a button at the bottom of the dashboard list.
3. **Android:** `io/github/cidy02/kudos/library/LibraryScreen.kt` and `io/github/cidy02/kudos/library/LibraryShellChrome.kt`
4. **Differences:** 
   - Android's `LibraryShellChrome.kt` dropdown menu contains "Reading Queues" and "Recently Deleted", whereas iOS puts "Recently Deleted" at the bottom of the `LibraryView.swift` list and lacks "Reading Queues" in the `WorkListMoreMenu`.
   - Android's `LibraryScreen.kt` hardcodes order descriptions differently from iOS `LibrarySectionKind.swift`:
     - **Finished:** iOS: `"most recently read first"`, Android: `"most recently finished first"`
     - **Saved for Later:** iOS: `"most recently read or added first"`, Android: `"most recently added first"`
     - **Downloaded:** iOS: `"newest first"`, Android: `"most recently downloaded first"`
     - **Favorites:** iOS: `"newest first"`, Android: `"most recently added first"`

## 2. Filters Panel
1. **iOS:** `Features/Library/LibraryFilterPanel.swift`
2. **Shows:** Sort by, Rating, Warnings, Categories, Completion, Language, Word count, Tags (Your Tags, Fandoms, Characters, Relationships, Additional Tags, Exclude Tags).
3. **Android:** `io/github/cidy02/kudos/library/LibraryFilterPanel.kt`
4. **Differences:** 
   - Android adds extra filter controls not present in iOS: a `"Status"` group with a `"Favorites"` toggle and `"Status"` choice (Finished), a `"Download"` choice, a `"Collections"` multi-select, and a `"Search library"` text field. 

## 3. Empty States
1. **iOS:** `Features/Library/LibraryFilterEmptyState.swift`
2. **Shows:** `LibraryFilterCollisionCard` with the collision title, detail text, and buttons to drop individual colliding filters, "Clear all filters", and "Edit".
3. **Android:** `io/github/cidy02/kudos/library/LibraryFilterEmptyState.kt`
4. **Differences:** None. Both share the same logic and text for `LibraryFilterCollisionCard`.

## 4. Work Context Menus
1. **iOS:** `Features/Library/WorkCardActions.swift`
2. **Shows:** Delete, Download/Save, Save for Later, Add to Queue, Mark Finished, Add to Collection, Work Details.
3. **Android:** `io/github/cidy02/kudos/library/LibraryScreen.kt` (`ContextMenuItem`)
4. **Differences:** 
   - Android's context menu includes `"Select"`, `"Favorite"`, `"Comments"`, `"Read"`, and `"Rebuild from Original"`. iOS does not include these in the context menu (iOS relies on swipe actions or other buttons for Favorite, and its remote card has a different subset).

## 5. Favorites Scopes & Quick Filters
1. **iOS:** `Features/Library/FavoriteQuickFilter.swift`
2. **Shows:** Quick filters for Works scope (`All`, `Rereads`, `Offline`, `WIP`) and for Authors scope (`All`, `With new work`).
3. **Android:** `io/github/cidy02/kudos/library/LibrarySectionQuickFilter.kt`
4. **Differences:** 
   - Android completely lacks the `"With new work"` quick filter for the Favorite Authors scope. 
   - Android applies the Works quick filters (`All`, `WIP`) to the `ReadingNow` section as well, while iOS only applies them to `Favorites`.

## 6. History Grouping
1. **iOS:** `Features/Library/LibraryHistoryGrouping.swift`
2. **Shows:** Groupings for `Time`, `State`, `Fandom`, and `Flat`.
3. **Android:** `io/github/cidy02/kudos/library/LibraryHistoryGrouping.kt`
4. **Differences:** None. Both match identically.

## 7. Recently Deleted
1. **iOS:** `Features/Library/RecentlyDeletedView.swift`
2. **Shows:** A list of recently deleted works, queues, and collections, showing time remaining before permanent deletion. Swipe actions for "Restore" and "Delete".
3. **Android:** `io/github/cidy02/kudos/library/RecentlyDeletedScreen.kt`
4. **Differences:** None. Strings and actions match closely.

## 8. Add Library Works Sheet
1. **iOS:** `Features/Library/AddLibraryWorksSheet.swift`
2. **Shows:** A dedicated picker sheet to add existing library works to a collection or reading queue. Shows a search bar, eligible works, and handles privacy gating.
3. **Android:** Not found. Android lacks a standalone `AddLibraryWorksSheet.kt` file. (Searched for "AddLibraryWorksSheet", "AddWorksSheet"). Android implements adding works inline within `CollectionDetailScreen.kt` and `QueueDetailScreen.kt`.
4. **Differences:** iOS extracts this into a reusable, full-screen sheet component.

## Summary of Gaps

| iOS Screen / Control | iOS Path:Line | Android Path:Line | Gap |
| --- | --- | --- | --- |
| Favorite Author Quick Filter | `FavoriteQuickFilter.swift:80` | Not found | Android lacks `"With new work"` filter |
| Add Library Works Sheet | `AddLibraryWorksSheet.swift:14` | Not found | Android lacks standalone sheet, uses inline picker |
| Dashboard More Menu | `LibraryView.swift:163` | `LibraryShellChrome.kt:97` | Android adds "Reading Queues" and "Recently Deleted" to the menu |
| Filter Panel | `LibraryFilterPanel.swift:15` | `LibraryFilterPanel.kt:53` | Android adds Status, Download, Collections, and Search controls |
| Work Context Menu | `WorkCardActions.swift:23` | `LibraryScreen.kt:1270` | Android adds Select, Favorite, Comments, Read, Rebuild from Original |
| Section Sort Order Text | `LibrarySectionKind.swift:51` | `LibraryScreen.kt:614` | 4 string differences in order descriptions |
