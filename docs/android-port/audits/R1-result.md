# Android Port Audit: Missing Features (R1)

### A10. Account shortcut editor
1. **Where on iOS**: `kudos-ao3-reader/Features/Account/AccountShortcuts.swift:104-162` (`AccountShortcutsEditor`), model `AccountShortcutStore` at `:70-84`. No service call.
2. **How a reader gets there**: On the Account screen, a section header labelled "SHORTCUTS" with an `onSeeAll` button (accessibility label "See all Shortcuts") at `kudos-ao3-reader/Features/Account/AccountView.swift:657`.
3. **What is on screen**:
   - Navigation title "Shortcuts".
   - Section header "On the grid".
   - For each chosen shortcut: row with accessibility label "Remove {title}" and system image `minus.circle.fill`.
   - Section footer: "If you choose none, the grid is hidden. You can still find every destination in the sections below." (appears when chosen is empty).
   - Section header "Not on the grid" (appears when available is not empty).
   - For each available shortcut: row with accessibility label "Add {title}" and system image `plus.circle.fill`.
   - Button "Reset to Default" (disabled when default).
   - Toolbar button "Done".
4. **What it reads and writes**: No network requests. Reads and writes the device `@AppStorage` key `"account.shortcuts"`. It is not stored in the `.kudosbackup` archive.
5. **Where it would go on Android**: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:886`. The header has `onSeeAll = { /* TODO implement shortcut editor */ }`. Android already draws a fixed grid.
6. **Size**: medium (a sheet or a sub-screen).

### A10. Manage collection items
1. **Where on iOS**: `kudos-ao3-reader/Features/Account/AccountMoreOnAO3View.swift:170`, view `AccountExternalNavCard.swift:7-40`. Service call at `AccountExternalNavCard.swift:120-125`.
2. **How a reader gets there**: On the "More on AO3" screen, a row at `kudos-ao3-reader/Features/Account/AccountMoreOnAO3View.swift:170`.
3. **What is on screen**: A row labeled "Manage collection items" with system image "rectangle.stack".
4. **What it reads and writes**: When tapped, GET `https://archiveofourown.org/users/{username}/collection_items`. Does not POST. No library changes.
5. **Where it would go on Android**: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountMoreOnAO3Screen.kt:82`, beside the existing "Manage collections" card. Android has `AO3CollectionItems` which is a different page (one collection's moderator list).
6. **Size**: small (a row or a menu item on an existing screen).

### A10. Open a chapter's comments from the inbox
1. **Where on iOS**: `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:246` and `:439`. Destination logic `kudos-ao3-reader/Features/Account/AccountView.swift:1022-1043` and service `kudos-ao3-reader/Services/AO3Client+Comments.swift:19-37`.
2. **How a reader gets there**: From an inbox comment row's overflow menu (`kudos-ao3-reader/Features/Account/AccountInboxViews.swift:439`), or the accessibility action (`:246`).
3. **What is on screen**: Accessibility action "Open Chapter Comments". Menu label "Chapter Comments" with system image "text.bubble". (Both appear when `item.chapterPosition != nil`).
4. **What it reads and writes**: The menu item itself makes no requests. The destination loads comments via GET `https://archiveofourown.org/works/{workID}/chapters/{chapterID}?show_comments=true&view_adult=true` (with `page` when past 1). No library changes.
5. **Where it would go on Android**: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxPane.kt:979` on the overflow menu. Android already has "Open Thread" that focuses on the specific inbox comment.
6. **Size**: small (a menu item on an existing screen).

### A10. Share an author profile
1. **Where on iOS**: `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:878`. Model `kudos-ao3-reader/Models/AO3AuthorModels.swift:103-113`.
2. **How a reader gets there**: The author profile screen's top menu (`kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:878`).
3. **What is on screen**: A `ShareLink` button labeled "Share Profile" with system image "square.and.arrow.up".
4. **What it reads and writes**: No network requests (local share). The URL is `https://archiveofourown.org/users/{name}` or `.../pseuds/{pseud}`.
5. **Where it would go on Android**: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:145-185`, in the author menu. Android has "Open on AO3" there.
6. **Size**: small (a menu item on an existing screen).

### A10. Read Aloud downloads on Privacy
1. **Where on iOS**: `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:109` and `:425-428`.
2. **How a reader gets there**: Scrolling to the bottom of the Privacy screen (`kudos-ao3-reader/Features/Account/PrivacyDataView.swift:109`).
3. **What is on screen**: Section header "Read Aloud downloads". Text: "Optional Voice Pack downloads stay separate from your reading data." Text: "Kudos never sends a work's text, spoken audio, your AO3 sign-in, saved works, reading history, usage information, or anything that identifies your account to the Voice Pack provider. The provider can see your IP address and basic details about the connection. Kudos tells you this before downloading a Voice Pack, and the installed voices stay on this device."
4. **What it reads and writes**: No network requests or data writes.
5. **Where it would go on Android**: `android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:100-109`. Android has a "No ads or tracking…" card that mentions a Voice Pack connection but lacks these exact sentences.
6. **Size**: medium (a sub-screen or a section on an existing screen).

### A10. "Showing cached AO3 data"
1. **Where on iOS**: `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:713`, `kudos-ao3-reader/Features/Account/AccountView.swift:747`, `kudos-ao3-reader/Features/Account/AccountView.swift:753`, `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:251`, `kudos-ao3-reader/Features/Authors/AO3SeriesDetailView.swift:60`.
2. **How a reader gets there**: Viewing Inbox, Account profile, Author profile, or Series when the local data is flagged as stale.
3. **What is on screen**: A banner reading "Showing cached AO3 data".
4. **What it reads and writes**: The banner does not fetch. It reads a locally flagged `isStale` state populated by their respective GET requests: GET `https://archiveofourown.org/users/{name}/inbox`, GET `https://archiveofourown.org/users/{name}` (or `.../pseuds/{pseud}`), or GET `AO3Client.seriesPageURL(series.url, page:)`.
5. **Where it would go on Android**: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxPane.kt`, `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt`, `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt`, `android/app/src/main/java/io/github/cidy02/kudos/app/SeriesWorksScreen.kt`.
6. **Size**: small (a row or a menu item on an existing screen).

### A9. Popular tags in the tag picker
1. **Where on iOS**: `kudos-ao3-reader/Features/Search/TagSelectField.swift:247`. Service `kudos-ao3-reader/Services/AO3Client.swift:1597-1627`.
2. **How a reader gets there**: Opening the filter tag picker for a tag kind that is not fandom, while a fandom is set (`kudos-ao3-reader/Features/Search/TagSelectField.swift:242`).
3. **What is on screen**: Text "Choose a fandom to see its most-used {kind} here." (when no fandom is set). If a fandom is set and the popular list loads, it shows the most-used tags.
4. **What it reads and writes**: When a fandom is set and the popular list is empty, GET `https://archiveofourown.org/tags/{tagPathSegment}/works` and reads the sidebar checkboxes `include_work_search[character_ids|relationship_ids|freeform_ids][]`.
5. **Where it would go on Android**: `android/app/src/main/java/io/github/cidy02/kudos/search/FilterTagPicker.kt:145-154`. Android currently says "Type above to search AO3 …" and searches once at least two characters are typed.
6. **Size**: medium (a state in the tag picker sheet).

### A9. Works sort and completion on an author
1. **Where on iOS**: `kudos-ao3-reader/Features/Search/AO3FilterPanel.swift:667`. Models `kudos-ao3-reader/Models/AO3WorksSort.swift:135-146`, Service `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:298`.
2. **How a reader gets there**: Opening the works sort sheet from an author's profile works list.
3. **What is on screen**: The works sort sheet footer: "AO3 applies this choice to all matching works, not only the page you can see."
4. **What it reads and writes**: Apply calls `applyWorksSort` which reloads the page with GET `https://archiveofourown.org/users/{name}[/pseuds/{pseud}]/{scope}`. Adds queries `work_search[sort_column]`, `work_search[sort_direction]`, and `work_search[complete]` when not AO3's default.
5. **Where it would go on Android**: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:366-378`, beside the scope chips. `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/author/AO3AuthorUrls.kt:70-79` can add the query but the tab doesn't pass a non-default sort.
6. **Size**: medium (a sheet or a sub-screen).

### A9. Bookmark the in-app browser page
1. **Where on iOS**: `kudos-ao3-reader/Features/Browse/BrowseView.swift:78` and `:143-147`.
2. **How a reader gets there**: The in-app browser toolbar (`kudos-ao3-reader/Features/Browse/BrowseView.swift:78`).
3. **What is on screen**: An image button with accessibility label "Add Bookmark".
4. **What it reads and writes**: No network requests. Inserts a local `Bookmark`.
5. **Where it would go on Android**: `android/app/src/main/java/io/github/cidy02/kudos/web/AO3WebViewFallbackScreen.kt`. Android uses a read-only WebView.
6. **Size**: small (a button on an existing screen).

### A9. Nearby pages in the page jump
1. **Where on iOS**: `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:411-414`.
2. **How a reader gets there**: The page jump sheet/bar.
3. **What is on screen**: Section "Nearby" with ten page tiles.
4. **What it reads and writes**: Confirming a page uses the list's existing page load. The tiles only set the draft locally.
5. **Where it would go on Android**: `android/app/src/main/java/io/github/cidy02/kudos/ui/components/KudosPaginationBar.kt:146-201`. Android has a sheet with a slider, "First", "Last", and "Go".
6. **Size**: small (a row or section in an existing sheet).

### A11. "Show in Library" after an external import
1. **Where on iOS**: `kudos-ao3-reader/App/ContentView.swift:142-144`.
2. **How a reader gets there**: The import-notice alert after an external file import.
3. **What is on screen**: A button "Show in Library" that appears when `notice.workID != nil`.
4. **What it reads and writes**: No network requests. Handles a local file import. Selects the Library tab.
5. **Where it would go on Android**: `android/app/src/main/java/io/github/cidy02/kudos/app/KudosApp.kt:87`, `:213-223`. Android's dialog currently only has "OK".
6. **Size**: small (a button on an existing dialog).

## Triage (Claude, 2026-10-08, first pass)

A reading, not an audit: eleven features, each checked against the code as it was used.

- **Manage collection items: done, and it uncovered a fault.** No row on Android's More on
  AO3 screen opened anything: each handed the browser a bare path ("collections"), which the
  browser refuses, and the screen closed again. The rows were also a different set from
  iOS's. The screen now has iOS's four sections and 23 rows with full addresses
  (`MoreOnAO3`, tests in `MoreOnAO3Test`). Seen on the emulator: the row opens the browser
  and it stays.
- **Share an author profile: done** ("Share Profile" in the author menu; the pseud's page
  when one is chosen, as iOS's `dashboardURL`). Not seen on the emulator.
- **Bookmark the in-app browser page: not ported.** Audit A20 found that nothing on iOS
  ever reads those bookmarks back: a button that saves to nowhere.
- Small, still to do by hand: "Open Chapter Comments" in the inbox menu, the "Showing cached
  AO3 data" banner, "Nearby" pages in the page jump, "Show in Library" after an import.
- Medium, to brief for Codex: the Account shortcut editor, Read Aloud downloads on Privacy,
  popular tags in the tag picker, works sort and completion on an author.
