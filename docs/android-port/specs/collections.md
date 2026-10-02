# Collections Spec

This specification details the UI and behaviour for porting the iOS Collections feature to Android, referencing the iOS codebase as the source of truth.

## 1. Screen tree

*   **`CollectionDetailView`** (`Collections.swift:101`)
    *   **Wash/Background:** Uses `.subjectScreenWash(palette: palette)`.
    *   **Empty State:** `ContentUnavailableView` showing the collection name, a `square.stack` icon, and description text. Provides an "Add Works" button.
    *   **List (when works exist):**
        *   **Header Section:** `SubjectHeaderBlock` with kicker "Library", title of the collection, and tally line subtitle. Background is clear, separator hidden.
        *   **Works Section:** `SectionRuleHeader` ("Works" with count). Then a `ForEach` of `visibleWorks` rendering `SensitiveWorkRow` (`displayMode` toggles between `.ledger` and `.detailed`).
            *   *Swipe action:* "Remove" (destructive button).
        *   **Filter Empty State:** Displayed as an overlay if filters return no works. Shows `ContentUnavailableView` with a `line.3.horizontal.decrease.circle` icon and a "Clear Filters" button.
    *   **Sheets presented:**
        *   `AddLibraryWorksSheet`
        *   `detailsSheet` (NavigationStack with Form sections for Colour, Description, Behaviour)
        *   `CollectionReorderSheet`
        *   Rename alert and Delete confirmation dialog.
    *   **Filter Panel:** `LibraryFilterPanel` presented as an inspector/panel.
    *   **Select Mode:** Bottom bar (iOS) or primary action (macOS) with `ScopedRemovalBulkActionBar`. Top right toolbar item for "Select All".

*   **`NewCollectionSheet`** (`NewCollectionSheet.swift:15`)
    *   NavigationStack containing a `List`.
    *   **Collection Group:** `SubjectFieldLabel` ("Collection"), `collectionPanel` with Name (`SubjectFormRow`), Description (`SubjectFormRow`), and Colour (`SubjectHueSwatchRow`), followed by a footnote.
    *   **Behaviour Group:** `SubjectFieldLabel` ("Behaviour"), `behaviourPanel` with toggles for "Keep downloads" and "Show on Home", followed by a footnote.
    *   **Footer:** A footnote explaining privacy.

*   **`CollectionReorderSheet`** (`NewCollectionSheet.swift:172`)
    *   NavigationStack containing a `List`.
    *   **Header Section:** `SubjectHeaderBlock` (kicker "Library › Collections", title "Reorder", subtitle).
    *   **Order Section:** `SubjectFieldLabel` ("Reading order") and `ForEach` over `ordered` works rendering `orderRow` (position number, title, author). Supports `.onMove`.
    *   **Footer Section:** Explanatory text about the reading order.

*   **`CollectionLedgerRow`** (`CollectionLedgerRow.swift:8`)
    *   `HStack` containing `previewGrid` (128×114 grid of 2×2 miniature covers), `labelColumn` (title, count), and a trailing chevron.

## 2. Components

*   **`CollectionCard`** (`Collections.swift:11`): A carousel card showing a 2×2 preview of works (`tileHeight` 221 × scale). If empty, displays a hue-tinted tile with a `square.stack.fill` icon (0.6 opacity). Title is 15pt semibold, count is 12pt secondary.
*   **`MiniatureWorkCover`** (`CollectionLedgerRow.swift:103`): 61×54 thumbnail. Has a 13×2 capsule accent, 9pt semibold title (max 2 lines), and 8pt secondary author (max 1 line) over a diagonal wash.
*   **`EmptyMiniatureWorkCover`** (`CollectionLedgerRow.swift:163`): Empty 61×54 placeholder slot, filled with `glassFill(0.04)` and bordered with `glassStroke(0.06)`.
*   **`CollectionLedgerRow`** (`CollectionLedgerRow.swift:8`): Ledger list row using the miniature grid, 15pt semibold title, 12pt secondary text.
*   **`SubjectHeaderBlock` / `SubjectKicker`**: Standard block for top-of-page subject details.
*   **`SubjectFormRow` / `SubjectHueSwatchRow` / `SubjectFieldLabel` / `SubjectRowSeparator`**: Form elements for details and creation sheets.

**Android comparison (`SubjectComponents.kt`):**
Android possesses `subjectScreenWash`, `subjectPanel`, `SubjectRowSeparator`, `SubjectKicker`, `SubjectHeaderBlock`, and `SectionRuleHeader`.
**Missing on Android:** `CollectionCard`, `CollectionLedgerRow`, `MiniatureWorkCover`, and `EmptyMiniatureWorkCover`.

## 3. Data

*   **Works query:** `collection.works.filter { !$0.isPendingDeletion }.sorted { $0.dateAdded > $1.dateAdded }` for default reverse-chronological order. (`Collections.swift:30`)
*   **Reading order:** Uses `collection.inReadingOrder(...)` when displaying the collection's natural order. Filters re-sort according to the filter's defaults. Reordering saves to `workOrderRaw`.
*   **Add candidates:** Valid library works excluding queue-only works and those already in the collection: `!work.isQueueOnlyWork && !work.collections.contains { $0.id == collection.id }`.
*   **Android Source:** UNSURE. Likely a Flow/SQLDelight query located in a `CollectionRepository` mapping into a ViewModel state, but Android's exact repository architecture for Collections is not currently visible in the provided components file.

## 4. Interactions

*   **Taps:**
    *   Tapping a collection card or ledger row opens `CollectionDetailView`.
    *   Tapping a work opens the reader (`openMode: .reader`).
*   **Long-press menus:**
    *   On collection cards: "Delete Collection".
    *   `WorkListMoreMenu` on `CollectionDetailView` (top right): "Select", "Reorder" (disabled if filters are active), Display Mode Picker (Ledger / Detailed), "Expand All" (if detailed mode), "Rename", "Details", "Delete Collection".
*   **Swipe actions:** Swiping left on a work reveals a "Remove" button (`minus.circle`). Checks `confirmBeforeDelete` preference.
*   **Select mode:** Enters bulk selection. Toolbar adds "Select All" / "Deselect All". Bottom bar provides "Remove from Collection".
*   **Reordering:** Drag-and-drop rows in `CollectionReorderSheet`. Commits only on tapping "Done" to avoid frequent DB saves (`NewCollectionSheet.swift:170`).
*   **Pull-to-refresh:** Triggers `WorkMetadataRefresh.refresh(visibleWorks, in: context, auth: auth)` on the list.
*   **Toolbar buttons:** "Add Works" (`plus`), Filter button (`line.3.horizontal.decrease.circle` equivalent), More menu (`ellipsis`).

## 5. Strings

*   **Counts:** `"\(workCount) work"`, `"\(workCount) works"`. Tally line: `"\(count) works · kept offline"`.
*   **Accessibility Labels:**
    *   Empty card: `"[Name], [Count] works. Opens collection."`
    *   Reorder row: `"[Position]. [Title], [Author]"` or `"[Position]. [Title]"`
*   **Empty States:**
    *   Collection empty: `"Add works from your Library here, or choose Add to Collection on a work's page."`
    *   Filter empty: `"No matching works"`, `"Your filters don't match any works in this collection."`
*   **Buttons / Menus:**
    *   `"Add Works"`
    *   `"Clear Filters"`
    *   `"Select"`
    *   `"Reorder"`, `"Clear Filters to Reorder"`
    *   `"Rename"`
    *   `"Details"`
    *   `"Delete Collection"`
    *   `"Remove from Collection"`
    *   `"Remove"` (swipe action)
    *   `"Cancel"`, `"Done"`, `"Save"`, `"Create"`, `"Add"`
*   **Dialogs:**
    *   Rename Alert: `"Rename Collection"`, `"Name"` (placeholder).
    *   Delete Collection Confirmation: `"Delete “[Name]”?"`, `"Kudos will move this collection to Recently Deleted for 90 days. Its works will stay in your Library."`
    *   Remove Work Confirmation: `"Remove this work?"`, `"“[Title]” will no longer be in “[Collection]”. The work itself stays in your Library."`
*   **Details / New Sheet:**
    *   `"New collection"`
    *   `"Collection"`, `"Colour"`, `"Name"`, `"Description"`, `"Optional"`
    *   `"Behaviour"`, `"Keep downloads"`, `"Show on Home"`
    *   `"Kudos picks a colour from the collection name. Renaming it may change the colour."`
    *   `"Your chosen colour stays the same if you rename the collection."`
    *   `"Keep downloads keeps a downloaded copy of every work in this collection. Show on Home adds the collection above Recently Updated."`
    *   `"This collection stays on this device. AO3 doesn't see it, and it isn't shared with your other devices."`
    *   `"You have no collections yet. Create one above to group works together."` (Add to Collection View)
*   **Reorder Sheet:**
    *   `"Library › Collections"`, `"Reading order"`, `"Reorder works"`
    *   `"This order is used when no filter is on. Works you add later, or restore from Recently Deleted after tapping Done, appear at the end."`

## 6. Owner decisions

*   **1bk Form:** Draws two distinct groups (Collection and Behaviour). Colour is picked here rather than assigned. Editing details uses the same sheet structure. (`NewCollectionSheet.swift:4`)
*   **Wash Tint:** The new sheet takes a wash in whichever swatch is tapped (owner, 2026-10-01). Untapped, it keeps the app's own accent. (`NewCollectionSheet.swift:36`)
*   **Behaviour Footnotes:** 1bk writes each behaviour's consequence right under it. True since T-276 (`KeepOffline`). (`NewCollectionSheet.swift:8`)
*   **Reordering Saves:** Committed on "Done" rather than per frame of a drag because a collection can hold hundreds of works. (`NewCollectionSheet.swift:169`)
*   **Mature Titles in Reorder:** Whether a mature work's title belongs behind `PrivacyGate` in the reorder sheet is an open question for the owner — not decided by a restyle. (`NewCollectionSheet.swift:199`)
*   **Keep downloads side-effect:** Toggling "Keep downloads" immediately fetches works missing their EPUB (T-276). (`Collections.swift:235`)
*   **Select Menu:** Select lives in the More menu ("…"), as on every other list (owner, 2026-10-01). (`LibraryView.swift`/`Collections.swift:420`)

## 7. Android gaps

*   **Missing UI Components:** `CollectionCard`, `CollectionLedgerRow`, `MiniatureWorkCover`, and `EmptyMiniatureWorkCover` must be created in or near `SubjectComponents.kt`.
*   **Missing Screens:** The specific forms for `NewCollectionSheet`, `CollectionReorderSheet`, and `CollectionDetailView` (with its specific `subjectScreenWash` integration and empty states) need to be constructed.
*   **Drag-to-Reorder:** Android needs an equivalent implementation for `.onMove` that defers committing to the database until "Done" is pressed.
*   **Multi-Select / Bulk Actions:** The selection bar UI and interaction model for bulk removals from collections is missing.
