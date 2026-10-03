# Android Port Spec: Writing

This spec details the implementation requirements for the Writing feature on Android, mapping the exact behavior, layout, and data flow from the iOS implementation. As per the project guidelines, **iOS code is the absolute source of truth**. Android currently has no implementation of these features (GAP-INVENTORY).

---

## 1. Screen tree

The iOS implementation structures the Writing features into several distinct views for editing works, chapters, and tags.

### Writing Drafts (`WritingDraftsView.swift` - Artboard 1x)
*   **Top**: `SubjectHeaderBlock`.
*   **Notice**: An orange banner warning that drafts expire.
*   **List**: Cards representing drafts. Each card features an "N days left" chip and a "Created..." date.
*   **Empty State**: Message indicating no drafts exist.

### Work Edit (`WorkEditView.swift` - Artboards 1bo/1bs)
*   **Top**: `SubjectHeaderBlock`.
*   **Required**: `SubjectFormRow`s for Title.
*   **Tags**: `SubjectFormRow`s for Rating, Warnings, Fandoms, Categories, Relationships, Characters, Additional tags.
*   **Association**: `SubjectFormRow`s for Series, Collections, Co-creators, Source Work.
*   **Text**: `SubjectFormRow`s pushing to chapter text editors.
*   **Publication**: `SubjectFormRow`s for backdating.
*   **Post/Delete**: Sections with buttons to Post, Save Draft, or Delete on AO3.

### Add Chapter (`AddChapterView.swift` - Artboard 1bq)
*   **Top**: `SubjectHeaderBlock`.
*   **Chapter**: Title, Chapter Number, Expected Total, Position.
*   **Text**: Summary, Chapter Text, Notes.
*   **Publication**: Backdate toggle and date picker.
*   **Post**: Post without preview, This is the last chapter, Post chapter now, Save as draft.

### Text Editor (`WritingTextEditor.swift` - Artboard 1bv)
*   **Top**: Custom header.
*   **Toolbar**: Formatting buttons that insert raw HTML tags.
*   **Text Area**: `WritingNativeTextView`, a plain-text HTML buffer.
*   **Preview Panel**: Renders the HTML markup for review off the main thread.

### Edit Tags (`EditTagsView.swift` - Artboard 1bp)
*   **Sections**: Rating, Archive warnings, Categories, Tags.
*   **Interaction**: Checkmarks for singular selections (Rating), multi-select for warnings/categories. Pushes to `WritingTagsEditor` for tag search.

### Tags Editor (`WritingTagsEditor.swift` - Artboard 1bu)
*   **Search Field**: Text field for term search.
*   **Chips**: Selected tags displayed as dismissible `SubjectChip`s.
*   **Suggestions**: List of canonical autocomplete results from AO3.

### Association Pickers (`WorkAssociationPickers.swift` - Artboard 1bw)
*   **Collections**: List of collections to add to.
*   **Series**: Series list with reorder capability.
*   **Pseuds**: Multi-select for user's pseuds.
*   **Source Work**: Form for "Inspired by" URLs and Translation checkboxes.

### Multiple Works Editor (`EditMultipleWorksView.swift` - Artboard 1bn)
*   **Bulk Edit Form**: Applies visibility, rating, language, and collection changes across multiple selected works.

### Series Edit & Reorder (`SeriesEditView.swift` - Artboard 1br)
*   **Edit**: Title, Creators, Complete status.
*   **Reorder**: Drag-and-drop list to rearrange works within a series.

### Preview (`WritingPreviewView.swift` - Artboard 1bq/1bo preview path)
*   **Preview**: Read-only rendered view of the work or chapter.
*   **Post Action**: Contains the final "Post" or "Update" buttons.

---

## 2. Components

Android's design system must implement the following iOS components for the Writing flows.

*   **`SubjectHeaderBlock`, `SectionRuleHeader`, `SubjectRowSeparator`**: Standard layout elements available in Android `ui/subject/`.
*   **`SubjectFormRow`**: Essential for almost all settings and forms. Must support `.value`, `.control`, and `showsDisclosure`. **Android gap:** Missing.
*   **`SubjectChip`**: Used extensively for tags. Android has `SubjectChip` and `SubjectChipStyle`.
*   **Text Editor (`WritingNativeTextView.swift`)**: A native plain-text HTML buffer. "Inserting tags never parses or normalizes existing markup; the platform text system owns selection, IME and undo." (`WritingNativeTextView.swift:3`). **Android gap:** Needs a Compose `TextField` implementation that mimics this exact unstyled HTML buffer with undo stack preservation.
*   **Tag Bar (`WritingTextEditor.swift:253`)**: A scrolling horizontal row of `Button`s that insert HTML strings (e.g., `<b>`, `<i>`) directly at the cursor position.
*   **Bulk Tag State Picker (`BulkTagStatePicker.swift`)**: A three-state list component used in bulk edits. Options cycle through added (included), removed (excluded), and untouched (unchanged). **Android gap:** Needs implementation leveraging Android's `FilterSelectionState`.
*   **Checkmarks (`EditTagsView.swift:146`)**: Rows where tapping toggles a checkmark icon indicating selection.

---

## 3. Data

Data sources rely on authenticated endpoints. Writing operations must STRICTLY adhere to `docs/AO3_NETWORKING_POLICY.md`. There is no local write API without AO3.

*   **Drafts**: `AO3Client.shared.workDrafts`.
    *   **Expiry Calculation**: Read from the deletion date AO3 prints on the draft's blurb via `AO3Client.parseDraftDeletionDates` (`WritingDraftsView.swift:25`).
*   **Work Edit**: Driven by `AO3WorkForm`.
*   **Chapter Edit**: Driven by `AO3ChapterForm`.
*   **Tags Autocomplete**: Fetched from `/autocomplete/<kind>?term=`.
    *   **Parsing**: Returns `[{"id","name"}]`. Work counts are intentionally not fetched due to API cost (`WritingTagsEditor.swift:17`).
*   **Collections Autocomplete**: Fetched from `/autocomplete/open_collection_names`.

---

## 4. Interactions

The Writing flow relies on specific gesture rules and save behaviors to prevent data loss.

*   **Drafts (`WritingDraftsView.swift:30`)**: Post and Delete actions are explicit buttons, NOT swipe actions. "A swipe is the easiest gesture in the app to fire by accident."
*   **Text Editor Checkpoints (`WritingCheckpoint.swift`)**:
    *   Checkpoints run 1.5 seconds after typing stops (`idleDelay`), and at least every 20 seconds during continuous typing (`maxInterval`).
    *   Saves local recovery copies and updates the form binding off the main thread.
    *   "Done" updates the parent form; only an explicit Save/Post action on the parent form writes to AO3 (`WritingTextEditor.swift:4`).
*   **Preview & Post (`WritingPreviewView.swift:5`)**:
    *   Actions on the preview are Edit and Post (or Update). Save Draft and Cancel remain on the underlying form.
    *   Posting from the preview executes the form's save path and dismisses both views upon success.
*   **Bulk Edit (`EditMultipleWorksView.swift:145`)**:
    *   Rating and language fields overwrite the value on every selected work. A "Leave as is" option is prepended to the top of these pickers.
    *   Collections use the three-state add/remove/leave toggle.
*   **Series Reorder (`SeriesEditView.swift:260`)**:
    *   "Saves once, not per drag." The entire array order is sent in one request when the user commits the changes.
*   **Tag Auto-complete (`WritingTagsEditor.swift`)**:
    *   Debounced by 300ms.
    *   Tapping a suggestion adds it; suggestions are sorted by AO3's substring match algorithm, not by work count.

---

## 5. Strings

Verbatim user-facing strings that must be implemented:

*   "Recovery copy on this device · Save from the work form"
*   "AO3 supports only certain formatting. The toolbar adds formatting that AO3..."
*   "Changing the rating or language replaces that value on every selected work."
*   "Tap an option once to add it to every selected work, twice to remove it, or leave it unchanged."
*   "AO3 suggests only its canonical tags and doesn't provide work counts here."
*   "Canonical"
*   "Posts as typed"
*   "This will delete all comments on the chapter as well and cannot be undone."
*   "When you turn on Last chapter, Kudos sets the work's total to this chapter's number."
*   "Posting a chapter notifies your subscribers. Save it as a draft if you want to..."
*   "The chapter was saved. Only the work total will be retried."
*   "Save chapter changes", "Post chapter now", "Save as draft"

---

## 6. Owner decisions

Crucial product decisions embedded in the iOS source code that dictate Android's architecture:

*   **Draft Expiry Calculation (`WritingDraftsView.swift:135`)**: The design spec dictates 29 days, but AO3 deletes after 30 days (purges at 31, keeps at 29). "The number is 30 and the spec is off by one." Android must use 30 days.
*   **Work Post Path (`WorkEditView.swift:575`)**: "A NEW work is saved by AO3 as a draft to preview it (`works#create` redirects to its preview), so the form adopts that draft first — Post from the preview then updates it instead of creating a second work."
*   **Tags Autocomplete Work Counts (`WritingTagsEditor.swift:17`)**: "The work count... is not fetched, and the column is absent rather than drawn as 1bu's em dash: a dash in every row is a column of nothing". "AO3 suggests only its canonical tags".
*   **Series Delete (`SeriesEditView.swift:21`)**: "Delete is an Open-on-AO3 link, not a native action... deleting a series is irreversible and belongs on AO3's own confirm page."
*   **Series Reorder Persistence (`SeriesEditView.swift:260`)**: "Saves once, not per drag. `reorderSeries` sends the whole order in one request, as AO3's own manage page does".
*   **Bulk Toggles (`EditMultipleWorksView.swift:275`)**: 1bn draws visibility as switches, but otwarchive has three answers: keep current, on, off. "A switch has two... They take the 'Leave as is' choice".
*   **Co-creators Separation (`WorkAssociationPickers.swift:505`)**: Separated "which of your own pseuds this work is posted under" and "an invitation to another account", which AO3 hides under a single label.

---

## 7. Android gaps

The following components and behaviors are completely missing from Android and must be built:

1.  **`SubjectFormRow`**: Essential layout container for forms, supporting embedded controls and disclosure indicators.
2.  **`SubjectFieldLabel`**: Styling for group header labels within forms.
3.  **Native HTML Text Editor**: A `TextField` implementation that mimics `WritingNativeTextView.swift`. It must handle raw HTML text without applying rich styling, preserving system undo/redo, and integrating the checkpoint architecture defined in `docs/WRITING_EDITOR_ARCHITECTURE.md`.
4.  **Three-State Bulk Picker**: A list component (`BulkTagStatePicker`) that cycles through Added, Removed, and Unchanged states, mapped to Android's `FilterSelectionState`.
5.  **Tag Bar**: A horizontally scrolling toolbar of HTML insertion actions.
6.  **Drag-and-Drop List**: Required for the Series Reorder view, matching the iOS native list reordering functionality.

## Detailed Component Specifications

To ensure the Android implementation matches the iOS source perfectly, here are the explicit details for building the missing components:

*   **HTML Toolbar Actions (`WritingTextEditor.swift:253-315`)**:
    *   The toolbar is a horizontal scrolling list of buttons.
    *   Each button applies an HTML tag (e.g., `<b>`, `<i>`, `<strike>`).
    *   It uses `systemImage` icons corresponding to each action.
    *   When a selection exists, the tag wraps the selection. When no selection exists, it inserts the opening and closing tags and places the cursor between them.
    *   The Link action is the only tag that cannot be written from a button alone; it opens an alert that asks for the URL and validates it before inserting.

*   **Checkpoint Architecture Details (`WritingCheckpoint.swift`)**:
    *   `idleDelay` is exactly 1.5 seconds.
    *   `maxInterval` is 20 seconds.
    *   "Checkpoints now — Done, leaving the screen, restoring a copy, a scene change — and drops the pending deadline. Runs even when nothing is pending: the checkpoint itself decides whether the text changed." (`WritingCheckpoint.swift:53`)
    *   The word count is evaluated off the main thread at each checkpoint using `AO3WordCounter`. The word count displayed must match what AO3 prints once the chapter is posted (`WritingCheckpoint.swift:98`).
    *   A recovery copy is saved locally and can be restored. Restoring prompts the user: "The text on the form has changed since this copy began. Review the copy before restoring it."

*   **Pseuds vs. Invitations (`WorkAssociationPickers.swift:502-511`)**:
    *   On AO3, co-creators and pseuds are handled under a single field.
    *   In the iOS app, these are split into two distinct sections: "Your pseuds" (which of the user's own pseuds this work is posted under) and "Invite a co-creator" (inviting another account).
    *   This split prevents users from confusing pseuds with external accounts, as inviting an external account requires them to accept the invitation before the work updates.

*   **Chapter Numbering and Totals (`AddChapterView.swift:155-211`)**:
    *   The chapter number and expected total are entered in a specific format.
    *   "When you turn on Last chapter, Kudos sets the work's total to this chapter's number." (`AddChapterView.swift:90`).
    *   The "Position" field uses "After chapter". For example, "Position 13 reads '12' after 'After chapter'." (`AddChapterView.swift:204`).
