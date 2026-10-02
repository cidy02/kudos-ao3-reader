# AO3 Collections (Android Port)

## 1. Screen tree

**`AO3CollectionsList`** (Artboard 1r) (`AO3CollectionsList.swift:80`)
- **Toolbar:** `+` (New Collection) and Filter button (`AO3CollectionsList.swift:85`).
- **Header:** `SubjectHeaderBlock` with kicker "AO3 Account", title "Collections", and subtitle tally (`AO3CollectionsList.swift:300`).
- **Scope Rail:** Horizontal scroll of `SubjectChip` pills for "Collections" and "Your items" (`AO3CollectionsList.swift:312`).
- **Filter Rail:** (Visible if filters active) Horizontal `SubjectFilterRail` with tinted chips (`AO3CollectionsList.swift:332`).
- **Pagination Bar:** (If multiple pages) `SearchPaginationBar` (`AO3CollectionsList.swift:340`).
- **List Section:**
  - *Empty State:* `subjectPanel` with "No collections" / "No collections match" and "Clear Filters" button (`AO3CollectionsList.swift:351`).
  - *Populated:* `AO3CollectionCard` items in a card list layout (`AO3CollectionsList.swift:228`).
- **Footer:** Informational text "These are your AO3 collections..." (`AO3CollectionsList.swift:381`).

**`AO3CollectionsFilterPanel`** (Artboard 1bm) (`AO3CollectionsFilterPanel.swift:30`)
- **Sort Group:** "Sort by" label, "Order by" picker row, "Direction" segmented control (`AO3CollectionsFilterPanel.swift:72`).
- **Show Only Group:** Toggles for "Open to new works", "Has works", "Moderated", "Unrevealed" (`AO3CollectionsFilterPanel.swift:115`).
- **Note:** Explains missing role filter (`AO3CollectionsFilterPanel.swift:146`).
- **Reset Bar:** Bottom bar with "Reset" button (`AO3CollectionsFilterPanel.swift:159`).

**`AO3CollectionItemsView`** (Artboard 1s) (`AO3CollectionItemsView.swift:130`)
- **Toolbar:** "Submit" and "Discard" actions with staged count (`AO3CollectionItemsView.swift:173`).
- **Header:** `SubjectHeaderBlock` ("AO3 Account › Collections", "Collection items") (`AO3CollectionItemsView.swift:239`).
- **Tab Strip:** `SubjectChip` pills for tabs (Awaiting collection, Awaiting you, Rejected, Approved) and Reset (`AO3CollectionItemsView.swift:266`).
- **List Section:**
  - *Empty State:* `subjectPanel` "Nothing in this tab." (`AO3CollectionItemsView.swift:352`).
  - *Populated:* `AO3CollectionItemCard` items (`AO3CollectionItemsView.swift:339`).
- **Pagination Bar:** `SearchPaginationBar` (`AO3CollectionItemsView.swift:305`).

**`AO3CollectionFormView`** (Artboard 1bl, 1cf) (`AO3CollectionFormView.swift:65`)
- **Header:** "New collection" or "Edit collection" (`AO3CollectionFormView.swift:218`).
- **Form Groups:** Header, Images, Preferences, Challenge, Profile using `SubjectFieldLabel` and `SubjectFormRow` (`AO3CollectionFormView.swift:127`).
- **Actions:** "Save Changes" / "Create Collection" prominent button, and "Open Collection Settings on AO3" panel with "Delete Collection" (`AO3CollectionFormView.swift:204`).

**`AO3CollectionDetailView`** (Artboard 1ci, 1cg, 1bx) (`AO3CollectionDetailView.swift:75`)
- **Header:** `SubjectHeaderBlock` with title and subtitle (`AO3CollectionDetailView.swift:164`).
- **Stat Strip:** `SubjectStatStrip` showing Works and Bookmarks counts (`AO3CollectionDetailView.swift:186`).
- **Segment Strip:** `SubjectSegmentedControl` (Works, Bookmarks, People) (`AO3CollectionDetailView.swift:197`).
- **Manage Rows:** List of `SubjectFormRow` navigation links to manage forms (Maintainers, Moderation, Settings, etc.) (`AO3CollectionDetailView.swift:329`).
- **Segment Content:** 
  - Works/Bookmarks: `EnrichingAO3WorkRow` with Anonymous/Gift badges (`AO3CollectionDetailView.swift:228`).
  - People: `AO3CollectionPersonRow` list (`AO3CollectionDetailView.swift:292`).
- **Pagination Bar:** `SearchPaginationBar` (`AO3CollectionDetailView.swift:606`).

## 2. Components

- **`SubjectHeaderBlock`**: Base UI component. Title uses 32sp font. (Matches Kotlin `SubjectHeaderBlock` in `SubjectComponents.kt:199`).
- **`SubjectChip`**: Used for tabs and filter indicators. (Matches Kotlin `SubjectChip` in `SubjectComponents.kt:348`).
- **`subjectPanel`**: Modifier drawing glass panel backgrounds with stroke. (Matches Kotlin `Modifier.subjectPanel` in `SubjectComponents.kt:129`).
- **`SubjectRowSeparator`**: Inter-row 0.5dp divider line. (Matches Kotlin `SubjectRowSeparator` in `SubjectComponents.kt:143`).
- **`SubjectStatStrip`**: Row of tappable metric cells. (Matches Kotlin `SubjectStatStrip` in `SubjectComponents.kt:457`).
- **`AO3CollectionCard`**: Custom iOS component (`AO3CollectionsList.swift:637`). 19pt bold title, 12.5pt summary, 11.5pt metadata. Eyebrow uses `SubjectKicker`.
  - *Kotlin:* **missing: build it**.
- **`AO3CollectionItemCard`**: Custom iOS component (`AO3CollectionItemsView.swift:560`). 19pt title, 13.5pt settings labels, 11.5pt caption. Uses custom `Menu`/picker chip for approval states (`AO3CollectionItemsView.swift:666`).
  - *Kotlin:* **missing: build it**.
- **`AO3CollectionPersonRow`**: Custom iOS component (`AO3CollectionDetailView.swift:619`). 15pt name, 11pt count.
  - *Kotlin:* **missing: build it**.
- **`SubjectFormRow` & `SubjectFieldLabel`**: Custom iOS components drawing standard settings rows and group headers.
  - *Kotlin:* **missing: build it**.
- **`SubjectFilterRail` & `SubjectSegmentedControl` & `SearchPaginationBar`**: Filter rails and segmented tabs.
  - *Kotlin:* **missing: build it**.

## 3. Data

- **Collections List (`AO3CollectionsList`)**: Fetched from `AO3Client.collectionsIndex`. Limits to standard AO3 pages. Filters require `AO3CollectionsWholeIndex` fetching logic to download all pages in background (`AO3CollectionsList.swift:459`, `528`).
- **Items (`AO3CollectionItemsView`)**: Fetched from `AO3Client.collectionItems` (collection scope) or `userCollectionItems` (account scope). Tab defaults differ: account defaults to `.invited` (Awaiting you), collection defaults to `.unreviewed` (`AO3CollectionItemsView.swift:61`). Uses `AO3CollectionItemStaging` for batching edits.
- **Form (`AO3CollectionFormView`)**: Loads `AO3CollectionForm` from `AO3Client.collectionEditForm`. Name availability checked via debounce `AO3Client.collectionNameAvailable` (`AO3CollectionFormView.swift:448`, `531`).
- **Detail (`AO3CollectionDetailView`)**: Fetches `AO3CollectionShow`, `collectionWorks`, `collectionBookmarks`, `collectionPeople`. Segments load independently (`AO3CollectionDetailView.swift:459`).
- **Android Sources**: No direct `ViewModel` or `Repository` yet for collections (T-115 Wave 0 noted "Collections = placeholder (no model yet)"). Will need to add new fetching logic to `Ao3Repository` and feature-specific ViewModels (e.g. `CollectionsViewModel`).

## 4. Interactions

- **Pull-to-refresh:** On Collections list, Items view, and Detail view, drops cache and refetches the current segment/page (`AO3CollectionsList.swift:246`).
- **Card Taps:** 
  - `AO3CollectionCard` pushes `AO3CollectionDetailView`.
- **Card Menus & Swipes:** 
  - Context menu: "Edit Collection" (push form), "Manage Items" (push items view).
  - Trailing swipe: "Edit" (`AO3CollectionsList.swift:272`).
- **Items View Controls:** 
  - Tab changes swap the list view (`AO3CollectionItemsView.swift:272`).
  - Approval row taps open a Menu to choose "Awaiting", "Approved", "Rejected". Toggles directly switch "On/Off". Destructive "Remove from collection" toggles strikethrough state (`AO3CollectionItemsView.swift:666`, `785`).
  - Toolbar "Submit" commits all staged changes in one POST (`AO3CollectionItemsView.swift:513`).
- **Toolbar Buttons:** `+` pushes `AO3CollectionFormView(slug: nil)`. Filter button opens `AO3CollectionsFilterPanel` sheet (`AO3CollectionsList.swift:85`).
- **Forms:** Name field dynamically validates on typing with 600ms debounce. Deletion requires exact-name confirmation typed into alert (`AO3CollectionFormView.swift:308`, `85`).

## 5. Strings

- **Headers:** "AO3 Account", "Collections", "Collection items", "New collection", "Edit collection", "Collection".
- **Empty States:** "No collections", "No collections match", "Collections you create or maintain on AO3 show up here.", "Nothing in this tab.", "Couldn't load collections", "Try Again".
- **Tabs/Filters:** "Collections", "Your items", "Awaiting collection", "Awaiting you", "Rejected", "Approved", "Declined", "Reset", "Sort and filter", "Sort by", "Order by", "Direction", "Show only", "Open to new works", "Has works", "Moderated", "Unrevealed".
- **Buttons:** "Submit", "Discard", "Save Changes", "Create Collection", "Delete Collection", "Open Collection Settings on AO3", "Clear Filters".
- **Item Form:** "Approved by creator", "Approved by moderators", "Remove from collection", "Keep". "This work will leave the collection when you submit your changes. It stays on AO3."
- **Deletion Alert:** "Delete “{name}”?", "This removes the collection, its challenge settings and any gift assignments from AO3...", "Delete on AO3".
- **Detail View:** "Works", "Bookmarks", "People", "Manage", "Maintainers", "Moderation", "Collection Settings", "Sign-ups", "Assignments", "Prompts", "Your Sign-up", "Challenge Settings".
- **Badges:** "ANON".

## 6. Owner decisions

- **Collections Placeholder:** `TASKS.md` explicitly noted "Collections = placeholder (no model yet)" previously.
- **Challenge Settings Visibility:** `AO3CollectionDetailView.swift:384`: "Owners only (REDESIGN_DECISIONS 1by): AO3 prints the Challenge Settings link for collection owners alone and refuses its edit page to everyone else..."
- **Missing Roles:** `AO3CollectionsFilterPanel.swift:147`: "AO3 doesn't show your role in its collections list, so you can't filter by Maintainer, Member or Invited here."
- **Owner Deletion:** `AO3CollectionFormView.swift:27`: "Closing stays on AO3. Owners can delete after a destructive confirmation; AO3's owner-gated edit form is what makes that action available here."
- **Anonymous Badge:** `AO3CollectionDetailView.swift:18`: "Anonymous is the collection's state, not the work's. The same work reads as Anonymous here and under its creator everywhere else..."
- **Batched Submissions:** `AO3CollectionItemsView.swift:19`: "Changes stage rather than apply. AO3 takes the whole items form in one POST... The toolbar counts what is staged and the checkmark submits."

## 7. Android gaps

What Android currently lacks to draw this:
- **`SubjectFormRow`**: Settings row with trailing controls/disclosure.
- **`SubjectFieldLabel`**: Group header style.
- **`SubjectFilterRail`**: Horizontally scrolling filter chips.
- **`SubjectSegmentedControl`**: Styled segmented tabs.
- **`SearchPaginationBar`**: The standard pagination footer component.
- **Cards**: `AO3CollectionCard`, `AO3CollectionItemCard`, `AO3CollectionPersonRow`.
- **Data Layer**: Models, parsing, repositories, and ViewModels for AO3 collections logic.
