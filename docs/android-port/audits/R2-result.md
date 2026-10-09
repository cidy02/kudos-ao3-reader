# R2: what iOS has in Writing that Android lacks (a reading, for briefs)

## Post a draft, with its preview step
1. **Where on iOS**: `Features/Writing/WorkEditView.swift` (lines 314-315, 710-721), `Features/Writing/WritingPreviewView.swift` (lines 10-126), `Services/AO3WorkActions.swift` (lines 127-141, 483-492, 596-615).
2. **How a reader gets there**: Tapping the "Post work" button (`WorkEditView.swift:710`) or "Preview on AO3" button (`WorkEditView.swift:714`) in the Post section of the `WorkEditView` form. From `WritingPreviewView`, the `postTitle` button (either "Post chapter", "Post work", or "Update") (`WritingPreviewView.swift:48`).
3. **What is on screen**: The Post panel in `WorkEditView` shows `Post work`, `Preview on AO3`, and if the work is a draft, `Delete draft`. The alert "Post this work?" appears with "Post work" or "Fill in what is missing" and "Cancel" buttons (`WorkEditView.swift:214-222`). The `WritingPreviewView` shows a "Preview" header with subtitle, any notice string from AO3 (`preview.notice`), the rendered `AO3PreviewHTML.Block` elements, and a "Post" section containing the `postTitle` button and an "Edit" button.
4. **What it reads and writes**:
   - Preview request: `postPreview` (POST to `url` with `parameters: form.parameters(submit: .preview)` and `_method=post`?) (`AO3WorkActions.swift:596`).
   - Post request: `saveWork` (POST to `form.actionURL` with `form.parameters(submit: .post)` or `.postWithoutPreview`) in `AO3WorkActions.swift:138`. Checks `form.missingRequiredFields()`.
   - Determines success based on `(200 ... 399).contains(status)` for preview, and notices for post.
5. **Where it would go on Android**: Existing `writing/WritingWorkFormScreen.kt` for the Post panel and logic, and `writing/WritingBufferPreview.kt` / new `WritingPreviewScreen.kt` for the preview page.
6. **Size**: Medium.

## Delete a work or a draft
1. **Where on iOS**: `Features/Writing/WorkEditView.swift` (lines 525-529, 784-796), `Services/AO3WorkActions.swift` (lines 84-98, 418-423, 580-594).
2. **How a reader gets there**: Tapping "Delete work on AO3" (`WorkEditView.swift:527`) or "Delete draft" (`WorkEditView.swift:717`) in the `WorkEditView` form.
3. **What is on screen**: Confirmation dialog titled "Delete this draft?" or "Delete this work?", with "Delete" or "Delete on AO3" (destructive) and "Cancel" buttons. Shows the caution text from `deleteImplications.cautionText` (`WorkEditView.swift:224-236`).
4. **What it reads and writes**:
   - Read implications: `loadDeleteImplications(workID: Int)` sends GET to `AO3Client.workConfirmDeleteURL(workID: workID)` and parses counts.
   - Write delete: `deleteWork` calls `submitDelete(implications)` which sends a POST to `implications.actionURL` with `authenticity_token` and `_method=delete` (`AO3WorkActions.swift:580-594`).
5. **Where it would go on Android**: `writing/WritingWorkFormScreen.kt`.
6. **Size**: Small.

## Preview on AO3 from the text editor and from the form
1. **Where on iOS**: `Features/Writing/WritingPreviewView.swift` (lines 10-126), `Features/Writing/WorkEditView.swift` (lines 584-601), `Features/Writing/AddChapterView.swift` (lines 413-435).
2. **How a reader gets there**: Tapping the "Preview on AO3" row in `WorkEditView`'s post panel, or from `WritingTextEditorRow`'s `preview:` closure via `WritingChapterEditorActions` which calls `openPreview()` (`AddChapterView.swift:229`).
3. **What is on screen**: The `WritingPreviewView` screen with the parsed AO3 HTML blocks, a "Post" or "Update" button, and an "Edit" button. It shows a `ProgressView()` while `isPosting` is true (`WritingPreviewView.swift:106`). If `errorMessage != nil`, it displays an alert "AO3 could not post this".
4. **What it reads and writes**: `auth.previewWork(form)` or `auth.previewChapter(form)`, which call `postPreview`. It parses the response HTML into `AO3PreviewHTML` to adopt the drafted chapter/work ID to avoid duplicating works on save (`AddChapterView.swift:428`, `WorkEditView.swift:595`).
5. **Where it would go on Android**: Existing `writing/WritingTextEditorScreen.kt` for text editor entrances, and `writing/WritingWorkFormScreen.kt` for the form entrances.
6. **Size**: Medium.

## Edit multiple works
1. **Where on iOS**: `Features/Writing/EditMultipleWorksView.swift` (lines 4-376), `Features/Authors/OwnWorksBulkBar.swift` (lines 7-25), `Features/Account/AccountMoreOnAO3View.swift` (line 163), `Services/AO3WorkActions.swift` (lines 56-82, 385-414).
2. **How a reader gets there**: From `AccountMoreOnAO3View` tapping "Edit works in bulk" (`path:163`), or from Account's Own Works list in select mode (`OwnWorksBulkBar.swift:15`) tapping "Edit N", "Collections", or "Visibility".
3. **What is on screen**: The `EditMultipleWorksView` header "Edit N works" (subtitle is the joined titles). Sections: "Tags to add", "Tags to remove", "Change on all", "Collections and gifts", "Comments and visibility", "Creators". Pickers for all these fields, empty "Leave as is" options for scalars (`EditMultipleWorksView.swift:158`).
4. **What it reads and writes**:
   - Read: `loadBulkEditForm(workIDs:)` POSTs to `edit_multiple` (rendering form only) (`AO3WorkActions.swift:73`).
   - Write: `bulkEditWorks(changes:)`. Iterates through works calling `editTags(workID:current:desired:)` for tag merges sequentially (`AO3WorkActions.swift:395-405`), then POSTs uniform scalars (rating, language, collections, permissions) to `update_multiple` (`AO3WorkActions.swift:410`).
5. **Where it would go on Android**: A new screen `writing/WritingBulkEditScreen.kt` and a new selection toolbar component `account/OwnWorksBulkBar.kt`.
6. **Size**: Large.

## Add chapter / edit a chapter / delete a chapter / reorder chapters
1. **Where on iOS**: `Features/Writing/AddChapterView.swift` (lines 4-477), `Features/Writing/WritingChaptersView.swift` (lines 11-102). *Note: "Reorder chapters" is missing from iOS entirely; iOS only implements Reorder Series Works (`reorderSeries`), there is no reorder capability in the chapters list.*
2. **How a reader gets there**: "Add chapter" row in `WorkEditView.swift:448`, or tapping an existing chapter row in `WritingChaptersView.swift:63` which opens `WritingChapterDestination`.
3. **What is on screen**: As brief 3bu leaves out only "reorder chapters", there is nothing left to cover for this section because iOS does not have "reorder chapters". The remaining views (add/edit/delete chapter) are covered by the existing brief.
4. **What it reads and writes**: Covered by brief 3bu. (No reorder reads/writes).
5. **Where it would go on Android**: `writing/WritingChaptersScreen.kt` and `writing/WritingWorkFormScreen.kt`. Android is also missing these.
6. **Size**: Small (reorder chapters is missing from both platforms).

## The posted-work entrances
1. **Where on iOS**: `Features/Authors/AuthorProfileContentSections.swift` (lines 414-417), `Features/Authors/AuthorProfileView.swift` (lines 567-581). *Note: The work's own page (`WorkDetailView.swift`) does not contain an "Edit work" entrance in iOS.*
2. **How a reader gets there**:
   - **Account's own works**: Navigating to `AccountView` -> Works tab, which loads `AuthorProfileView` for the signed-in user.
   - **The author profile's owner menu**: In `AuthorProfileContentSections.swift`, a swipe action on a work row (`Label("Edit", systemImage: "square.and.pencil")`) triggers `onOwnWorkAction(.edit(workID: remote.id))`.
   - **A work's own page**: Missing from iOS. No `WritingWorkDestination` or `WorkEditView` call exists in `Features/WorkDetail/`.
3. **What is on screen**: A trailing swipe action on the list row showing the "Edit" label and the "square.and.pencil" icon, tinted blue (`AuthorProfileContentSections.swift:415-417`).
4. **What it reads and writes**: No new requests; it simply navigates to `WritingWorkDestination` which loads the work form.
5. **Where it would go on Android**: Row swipe actions in `account/AccountWorksList.kt` (or similar own profile list), and ideally a new toolbar button in `WorkDetailScreen.kt` to cover the missing detail entrance.
6. **Size**: Small.
