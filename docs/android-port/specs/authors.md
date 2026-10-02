# Authors Specification

## 1. Screen tree

The root view of the Authors feature is `AuthorProfileView` (`kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:63`). The view renders different states based on `model.headerPhase` and `model.contentPhase`:

*   **Loading/Idle State:** Draws `AO3AuthorProfileSkeleton`, a simulated list containing a mocked hero card with a 72x72 placeholder, a mocked segmented control row, and four `AO3WorkRowSkeleton` instances.
*   **Unavailable State:** Draws `ContentUnavailableView` (via `unavailableView`) showing "Author unavailable" and a prompt that the user may have been deleted, accompanied by an "Open on AO3" action button.
*   **Failed State:** Draws `failedProfileView` which keeps the header intact and places an `AO3ProfileMessageRow` underneath with a "Couldn't load author" title and a "Try Again" button.
*   **Loaded State:** A `List` containing several primary sections:
    *   **Account Header / Hero Card:** 
        *   If `usesAccountHeader` is true (the user is viewing their own dashboard or their own profile as a content destination), it draws a `SubjectHeaderBlock` with the kicker "AO3 Account", the title (the user's display name or current tab), and an optional subtitle (e.g. "Pseud of user · 2 pseuds").
        *   Otherwise, it draws `AO3AuthorHero` inside a `Section` wrapped with `.cardRow()`. This presents the author's avatar, their display name, their pseud relationship, their bio title, and a row of action buttons (Subscribe, Mute, Block).
    *   **Pseud Selector:** If the account has multiple pseuds and is not using the compact account header, it draws `pseudSelector` (a `Menu` row with "Scope" label and the current pseud) inside a `Section`.
    *   **Segmented Control:** If this is a standard profile screen (not a dashboard and not pushed as a strict content destination), it draws a `SubjectSegmentedControl` to switch between "Works", "Series", "Bookmarks", and "About" tabs.
    *   **Stale Cache Warning:** If `model.isShowingStaleCache` is true, a small banner `Label("Showing cached AO3 data")` appears.
    *   **Dashboard View:** If `showsDashboard` is true, it replaces the content rows with `AO3DashboardSections` (`AuthorDashboardSections.swift:5`), which contains four sub-sections:
        *   **Fandoms:** `SectionRuleHeader` followed by a wrapping `FlowLayout` of up to 5 `SubjectChip` items. If >5, an "Expand" / "Collapse" chip appears. Empty: "No fandoms listed on AO3." text panel.
        *   **Recent works:** `SectionRuleHeader`, a list of `AO3AuthorWorkCard` entries (merged with local library), and a "See all works" button. Empty: "No recent works visible on AO3." text panel.
        *   **Recent series:** `SectionRuleHeader`, a list of `AO3DashboardCompactCard` items, and a "See all series" button. Empty: "No recent series visible on AO3." text panel.
        *   **Recent bookmarks:** `SectionRuleHeader`, a list of `AO3DashboardCompactCard` items, and a "See all bookmarks" button. Empty: "No recent bookmarks visible on AO3." text panel.
    *   **Works Tab:** Driven by `AO3AuthorWorksSection`.
        *   **Scope & Funnel:** `AO3AuthorWorksScopeSection` renders three pills (Works, In collections, Gifts) alongside a filter funnel.
        *   **Fandom Filter:** `AO3AuthorFandomFilterSection` renders a horizontally scrolling list of `SubjectChip` fandom filters (if fandoms exist on the author's work index).
        *   **Rows:** Draws `selectableWorkRow` if in bulk selection mode; otherwise, draws `AO3AuthorWorkCard`. 
        *   **Empty:** `AO3AuthorContentMessage` ("No works").
        *   **Loading (Pagination):** `AO3AuthorPaginationRows` with a "Load More" button or a progress spinner.
    *   **Series Tab:** Driven by `AO3AuthorSeriesSection`. Draws a list of `AO3SeriesRow`.
        *   **Empty:** "No series". If this is the logged-in user's profile, it replaces the empty state with a rich card ("You have not made a series") featuring an `AccountExternalNavCard` to create one on AO3.
    *   **Bookmarks Tab:** Driven by `AO3AuthorBookmarksSection`. Draws `AO3AuthorBookmarkRow`.
        *   **Empty:** `AO3AuthorContentMessage` ("No visible bookmarks").
    *   **About Tab:** Driven by `aboutRows`. Draws sections for "Bio" (`AO3RichTextView`), "Pseuds", and "Account" (`LabeledContent` for Selected Pseud, Joined, User ID).

## 2. Components

*   **`AO3AuthorHero`** (`AuthorProfileComponents.swift:3`): Renders the main profile card. Contains an `AO3AuthorAvatar` (72x72, 8pt corner radius, `.quaternary` background). Draws the title (`.title2`, semibold) and subtitle (`.subheadline`, secondary). The action row features a Subscribe button (`.borderedProminent`, `.small`) and icon-only Mute/Block buttons (`.bordered`, `.small`). 
    *   *Android match:* Missing: build it.
*   **`AO3SeriesRow`** (`AuthorProfileComponents.swift:167`): 
    *   **Ledger Presentation:** Draws a 38x38 square icon using `seriesPalette.cardWash` fill and `seriesPalette.chipStroke` border. The icon contains `SeriesSpineStackMark` (three overlapping rounded rectangles representing book spines, offset diagonally, with a 1.25pt stroke). Text includes primary fandom (`10pt`, bold, `1.1` tracking), title (`19pt`, semibold), summary (`13.5pt`, secondary, `1.5` line spacing), and a footer with stats (`11.5pt`, secondary).
    *   **Standard Presentation:** A simpler card starting with the title (`.headline`) and flowing stats into a `FlowLayout` of `WorkStatLabel` (`.caption2`, tertiary).
    *   *Android match:* Missing: build it.
*   **`AO3AuthorWorkCard`** (`AuthorDashboardSections.swift:182`): A wrapper that delegates to `SensitiveWorkRow` (for local works) or `AO3WorkRow` (for remote works) and optionally appends an `AO3AuthorPerformanceStrip`.
    *   *Android match:* Existing `WorkCoverCard` or `WorkLedgerRow` (needs adaptation for the performance strip).
*   **`AO3AuthorPerformanceStrip`** (`AuthorDashboardSections.swift:220`): A row of stat cells displaying Kudos, Comments, Hits, and Bookmarks on own works. Uses `SubjectStatStrip`.
    *   *Android match:* `SubjectStatStrip` in `ui/subject/SubjectComponents.kt`.
*   **`AO3DashboardCompactCard`** (`AuthorDashboardSections.swift:259`): Compact card used for Dashboard series and bookmarks. Contains a kicker (9.5pt, bold, `0.1` tracking, colored by palette accent), title (15pt, semibold), and one line of meta text (11.5pt, secondary).
    *   *Android match:* Missing: build it.
*   **`AO3BookmarkFootnote`** (`AuthorProfileComponents.swift:393`): The extra content attached to a bookmark card. It renders a status badge row, the user's notes (`AO3RichTextView`, 14pt, line spacing 7, with a 2pt wide capsule colored by palette accent acting as a leading border), and bookmark tags.
    *   *Android match:* Missing: build it.
*   **`BookmarkTagPill`** (`AuthorProfileComponents.swift:446`): Specifically styled chip for bookmark tags: 13pt text, background `glassFill(0.09)`, bordered by `glassStroke(0.14)` (0.5pt width), 8pt corner radius.
    *   *Android match:* Implement via `KudosTokens` glass variables.
*   **`SubjectChip`** (`WorksScopeAndSort.swift:31`): Renders standard pills (Works, In collections, Gifts).
    *   *Android match:* `SubjectChip` with `SubjectChipStyle.Pill` in `ui/subject`.
*   **`SectionRuleHeader`**: Used heavily to break up dashboard and content lists.
    *   *Android match:* `SectionRuleHeader` in `ui/subject`.
*   **Wash and Panels**: The screen sets `.subjectScreenWash(palette: theme.scopePalette)` and cards use `.subjectPanel(cornerRadius: 16)` or `.cardRow()`.
    *   *Android match:* `Modifier.subjectScreenWash` and `Modifier.subjectPanel`.

## 3. Data

*   **Profile, Header, and Stats:** The central state is held by `AO3AuthorProfileModel`, fetched by `AO3AuthorProfileFetcher`. It queries AO3 for profile details, bio, pseuds, and the dashboard HTML.
    *   *Android source:* `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/author/AO3AuthorRepository.kt`.
*   **Works List:** The works list (`model.works`) can point to three different scopes: `AO3AuthorRoute.Content.works` (Works), `.collectedWorks` (In collections), and `.gifts` (Gifts). The data is sorted by `model.worksSort` (e.g. Date Updated, Hits, Kudos) and narrowed by `model.worksFilters` (`AO3SearchFilters`). Pagination is 20 works per page.
    *   *Android source:* `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/author/AO3AuthorWorksRepository.kt`.
*   **Local Works Merge:** The remote works are merged with downloaded local works to render `CanonicalWork`. On iOS, local works are fetched via `@Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion })`. The `PrivacyGate` hides mature content if configured.
    *   *Android source:* `LibraryRepository.kt`.
*   **Dashboard Collections:** The `header.recentWorks`, `header.recentSeries`, and `header.recentBookmarks` are populated directly from the parsed AO3 dashboard HTML (up to 5 items each).
*   **Series & Bookmarks:** Paginated lists requested through the respective AO3 profile endpoints, stored in `model.series` and `model.bookmarks`.

## 4. Interactions

*   **Taps:**
    *   **Avatar / Pseud Menu:** Tapping a specific pseud drops the current session and re-fetches the profile scoped exclusively to that pseud.
    *   **Subscribe / Mute / Block:** Fire moderation APIs. If the user is signed out, these trigger a "Log in to AO3" alert, wait 350ms, then present the `AO3LoginView` sheet. The actions resume automatically if login succeeds (`AuthorProfileView.swift:658`).
    *   **Fandom / Scope Chips:** Tapping a chip immediately applies the filter/scope, triggering a refetch, and forcefully exits bulk selection mode (`onWillChange: bulkSelection.exitSelectMode`).
    *   **Dashboard "See all":** Navigates to the corresponding tab by mutating `dashboardDestination`.
    *   **"New series on AO3":** Opens the AO3 `/series/new` URL in the internal Browse tab.
*   **Toolbar Actions:**
    *   **"+" (New Work):** Visible only on own profiles. Pushes `WritingWorkDestination`.
    *   **Filter (Funnel):** Visible on the Works tab. Displays a badge reflecting `activeCount` (sort overrides + facet filters applied). Tapping it presents `AO3AuthorWorksFilterPanel` as a sheet/inspector.
    *   **Select (Checklist):** Enters `isSelecting` mode. The toolbar swaps to `OwnWorksSelectionToolbar` (providing "Select All" / "Deselect All" and bulk operations).
*   **Long-press / "…" Menu (`profileMenu`):**
    *   Contains "Select Works" (if own works).
    *   "Display Mode" picker (Ledger vs Detailed).
    *   "Expand All" toggle.
    *   "About" (if viewing the Dashboard).
    *   "Open on AO3" and "Share Profile".
*   **Swipe Actions:**
    *   **Own Works (`AO3OwnWorkAction`):** 
        *   **Delete (Red):** Requires confirmation. Triggers a deletion on AO3.
        *   **Chapter (Indigo):** Appears only if `work.isComplete != true`. Pushes `WritingChapterDestination`.
        *   **Tags (Teal):** Pushes `WritingTagsDestination`.
        *   **Edit (Blue):** Pushes `WritingWorkDestination`.
    *   **Own Series:**
        *   **Reorder (Gray):** Pushes `SeriesReorderDestination`.
        *   **Edit (Blue):** Pushes `SeriesEditDestination`.
*   **Pull-to-refresh:**
    *   Swiping down on the primary List invokes `.refreshable { await model.refresh(auth: auth) }`.

## 5. Strings

*   **Navigation & Tabs:** "Author", "Dashboard", "Works", "Series", "Bookmarks", "About".
*   **Headers & Subtitles:** "AO3 Account", "Pseud of [username]", "[X] pseuds", "No series yet", "AO3 user".
*   **Scope & Stats:** "In collections", "Gifts", "All Pseuds", "Scope", "Fandom", "All", "Complete", "In progress", "Restricted", "Private", "Rec", "[X] work" / "[X] works", "[X] words", "[X] kudos", "[X] comments", "[X] hits", "[X] bookmark" / "[X] bookmarks".
*   **Dashboard:** "Fandoms", "No fandoms listed on AO3.", "Expand", "Collapse", "Recent works", "No recent works visible on AO3.", "Couldn't read recent works. Open the full list to try again.", "See all works", "Recent series", "No recent series visible on AO3.", "Couldn't read recent series. Open the full list to try again.", "See all series", "Recent bookmarks", "No recent bookmarks visible on AO3.", "Couldn't read recent bookmarks. Open the full list to try again.", "See all bookmarks".
*   **About Tab:** "Bio", "This user has not added a bio.", "Pseuds", "Account", "Selected Pseud", "Joined", "User ID", "Profile details unavailable", "Kudos could not read this AO3 profile page."
*   **Empty States & Errors:** "Author unavailable", "AO3 could not find this user or pseud. It may have been renamed or deleted.", "Couldn't load author", "Try Again", "No works", "No works by this author are visible to you on AO3.", "No series", "No series by this author are visible to you on AO3.", "You have not made a series.", "A series groups your works in reading order. Create one on AO3, then refresh this page to see it here.", "New series on AO3", "This opens AO3 in Browse, where you can create the series.", "No visible bookmarks", "No bookmarks by this author are visible to you on AO3.", "Showing cached AO3 data", "Loading…", "Load More", "Page [X] of [Y]", "Try Loading More".
*   **Alerts & Sheets:** "Delete “[Title]”?", "This permanently removes the work and its chapters, kudos, comments and bookmarks from AO3 for everyone.", "Delete on AO3", "Cancel", "Couldn’t delete", "AO3 refused the delete.", "Log in to AO3", "Log in to your AO3 account to do this.", "Log In", "Unsubscribe from [Username]?", "Unsubscribing here applies to the whole AO3 account, not only this pseud.", "Unsubscribe", "Confirm".
*   **Menu & Actions:** "Subscribe", "Unsubscribe", "New Work", "Select All", "Deselect All", "Nothing selected", "Choose the works to edit, then try again.", "Select Works", "Delete", "Chapter", "Tags", "Edit", "Reorder", "Open on AO3", "Share Profile", "Your works".

## 6. Owner decisions

*   **Filter placement:** The works funnel was intentionally moved up from the scope row because global actions belong in the top-right chrome (`AuthorProfileView.swift:795`: `owner, 2026-10-01: global actions live in the top-right chrome`).
*   **Hit targets (TASKS.md UI-3):** Sub-44pt hit targets were fixed. Tappable author bylines app-wide (glyph-sized) and carousel-section collapse/see-all chevrons were raised to a 44pt minimum floor to ensure accessibility.
*   **Modal Timing signals (TASKS.md UI-8):** The 350ms `Task.sleep` used to sequence modal teardowns was replaced with deterministic completion signals across the app. *However*, in `AuthorProfileView.swift` specifically, the 350ms delay preceding the login sheet presentation was deliberately kept. SwiftUI clears the `isPresented` binding on alerts immediately at the start of dismissal, meaning any immediate presentation drops the sheet. Because alerts lack a proper `onDismiss` closure, the tested 350ms duration stays until a real signal exists.

## 7. Android gaps

*   **Profile Header (`AO3AuthorHero`):** Android lacks the profile hero layout, including the `AO3AuthorAvatar` rounding logic, the subtitle arrangement, and the inline Subscribe/Mute/Block buttons.
*   **Component Missing: `SubjectSegmentedControl`:** The horizontal segmented tab switcher for Works/Series/Bookmarks/About is missing from `ui/subject` and must be built.
*   **Component Missing: `AO3SeriesRow`:** The Series ledger card (specifically the `SeriesSpineStackMark` drawing with three offset spines) and the detailed FlowLayout stats presentation do not exist.
*   **Component Missing: `AO3DashboardCompactCard`:** The dense, 3-line card used for Recent Series and Recent Bookmarks on the dashboard is missing.
*   **Component Missing: `AO3BookmarkFootnote`:** The trailing content for bookmarks—including the `palette.accent` capsule line, the rich text notes, and the bespoke `BookmarkTagPill` (with precise glassFill/glassStroke borders)—must be implemented.
*   **Missing Menus and Bulk Logic:** Android currently lacks `WorkListMoreMenu` for global author actions, as well as the own-works bulk selection toolbar and swipe actions for Works (Chapter/Tags/Edit/Delete) and Series (Reorder/Edit).
*   **Toolbar Filter Button:** The custom funnel `FilterButton` with badge counts for the top app bar is missing.
