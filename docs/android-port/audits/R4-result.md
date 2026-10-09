# R4 Audit: Edit multiple works and own-works list

## 1. Edit multiple works

**1. Where on iOS:**
- Form View: `Features/Writing/EditMultipleWorksView.swift`
- Toolbar: `Features/Authors/OwnWorksBulkBar.swift`
- Networking: `Services/AO3WorkActions.swift` (`loadBulkEditForm`, `bulkEditWorks`, `editTags`)
- Models: `Models/AO3WritingModels.swift` (`AO3BulkEditChanges`, `AO3WorkTagDiff`)

**2. How a reader gets there:**
- The own-works list is put into select mode (`Select` button in `Features/Authors/AuthorProfileView.swift:789`).
- The `OwnWorksBulkBar` (`Features/Authors/OwnWorksBulkBar.swift:15-19`) draws the buttons:
  - `Button(selectedCount > 0 ? "Edit \(selectedCount)" : "Edit") { edit(nil) }` -> opens `EditMultipleWorksView` showing all options.
  - `Button("Collections") { edit(.collections) }` -> opens `EditMultipleWorksView` focused on collections.
  - `Button("Visibility") { edit(.visibility) }` -> opens `EditMultipleWorksView` focused on visibility.
- It pushes `EditMultipleWorksView` via `navigationDestination` (`Features/Authors/AuthorProfileView.swift:85` and `617`).

**3. What is on screen:**
*In `Features/Writing/EditMultipleWorksView.swift`:*
- **Empty selection alert** (`Features/Authors/AuthorProfileView.swift:620`): `ContentUnavailableView("Nothing selected", systemImage: "checkmark.circle")` if 0 selected.
- **Section header**: `SectionRuleHeader(title: "Tags to add")` (`EditMultipleWorksView.swift:34`)
  - Row: `WritingTagsRow(title: "Fandoms", values: tags.fandoms, kind: .fandom)` (line 46)
  - Row: `WritingTagsRow(title: "Relationships", values: tags.relationships, kind: .relationship)` (line 50)
  - Row: `WritingTagsRow(title: "Characters", values: tags.characters, kind: .character)` (line 55)
  - Row: `WritingTagsRow(title: "Additional tags", values: tags.additionalTags, kind: .freeform)` (line 60)
- **Section header**: `SectionRuleHeader(title: "Tags to remove")` (line 37)
  - (Repeats the above four tag rows, pointed at `tagsToRemove` instead).
- **Section header**: `SectionRuleHeader(title: "Change on all")` (line 40)
  - Row: `WritingChoiceRow(title: "Rating", value: leaveAsIsBinding(\.rating), options: leaveAsIsOptions(form.ratingOptions))` (line 68)
  - Row: `bulkStateRow(title: "Archive warnings", options: form.warningOptions, ...)` (line 73)
  - Row: `bulkStateRow(title: "Categories", options: form.categoryOptions, ...)` (line 80)
  - Row: `WritingChoiceRow(title: "Language", value: leaveAsIsBinding(\.languageID), options: leaveAsIsOptions(form.languageOptions))` (line 87)
  - Footnote: `Text("Changing the rating or language replaces that value on every selected work. Leaving it as is keeps each work's current rating or language.")` (line 43)
- **Section header**: `SectionRuleHeader(title: "Collections and gifts")` (line 47)
  - Row: `BulkNameListRow(title: "Add to collections", placeholder: "Collection name", names: $changes.collectionsToAdd)` (line 95)
  - Row (if `form.currentCollections.isEmpty`): `SubjectFormRow(label: "Remove from collections", value: "None", showsDisclosure: false, isDisabled: true)` (line 101)
  - Row (if `!form.currentCollections.isEmpty`): `WritingTagsRow(title: "Remove from collections", values: $changes.collectionsToRemove, options: form.currentCollections)` (line 109)
  - Row: `SubjectFormRow(label: "Gift recipients", value: "Per work", showsDisclosure: false, isDisabled: true)` (line 119)
- **Section header**: `SectionRuleHeader(title: "Comments and visibility")` (line 50)
  - Row: `WritingChoiceRow(title: "Only show to registered users", value: leaveAsIsBinding(\.restricted), options: leaveAsIsOptions(Self.onOffOptions))` (line 134)
  - Row: `WritingChoiceRow(title: "Enable comment moderation", value: leaveAsIsBinding(\.moderatedCommenting), options: leaveAsIsOptions(Self.onOffOptions))` (line 139)
  - Row: `WritingChoiceRow(title: "Who can comment", value: leaveAsIsBinding(\.commentPermissions), options: leaveAsIsOptions(form.commentPermissionOptions))` (line 144)
  - Picker options for the boolean choices: `"On"` (`"1"`), `"Off"` (`"0"`).
- **Section header**: `SectionRuleHeader(title: "Creators")` (line 53)
  - Row: `SubjectFormRow(label: "Add co-creators", arrangement: .control)` containing `TextField("Pseud", text: $changes.pseudsToAdd)` (line 157)
  - Row: `SubjectFormRow(label: "Remove me as a co-creator", arrangement: .control)` containing `Toggle("Remove me as a co-creator", isOn: $changes.removesSelfAsCreator)` (line 167)
  - Footnote: `Text("AO3 sends each co-creator an invitation. Their work doesn't change until they accept it.")` (line 56)
- **Loading State**: `if isSaving { ProgressView().controlSize(.small) }` in the Save button (or similar) disabling interaction.
- **Values/Placeholders for bulkStateRow**: `listLabel` returns `"Leave as is"` if `added == 0 && removed == 0`, else `"+[added], -[removed]"`.
- **Error alert**: Sets `errorMessage = UserFacingError.message(for: error)` on catch (line 204).

**4. What it reads and writes:**
- `loadBulkEditForm`:
  ```swift
  let tokenPage = try await csrfPage(at: AO3Client.workEditURL(workID: first))
  var pairs: [(String, String)] = [
      (AO3WorkFormField.authenticityToken, tokenPage.token)
  ]
  for id in workIDs {
      pairs.append((AO3WorkFormField.workIDs, String(id)))
  }
  let request = try writeRequest(
      to: url,
      body: Self.formEncoded(pairs),
      csrf: tokenPage.token,
      referer: AO3Client.editMultipleWorksURL(username: username),
      ajax: false
  )
  ```
- `bulkEditWorks`:
  If `changes.hasTagChanges`, it fans out multiple requests per work, one after the other.
  ```swift
  for workID in changes.workIDs {
      lastResponse = try await AO3RequestCoordinator.shared.withSlot {
          let form = try await loadEditTagsForm(workID: workID)
          let merged = changes.applying(to: form.tags)
          return try await editTags(
              workID: workID, current: form.tags, desired: merged
          )
      }
  }
  ```
  If the third of five works fails, the loop halts. The exception is thrown up to the view, which catches it and sets `errorMessage`. Works 1 and 2 are permanently changed on AO3; works 3, 4, and 5 are completely unedited.

  If `changes.hasUniformChanges`, it sends a single `patch` request:
  ```swift
  var pairs: [(String, String)] = [
      (AO3WorkFormField.authenticityToken, csrfToken),
      (AO3WorkFormField.methodOverride, methodOverride) // "patch"
  ]
  for id in workIDs {
      pairs.append((AO3WorkFormField.workIDs, String(id)))
  }
  func sendJoined(field: String, names: [String]) { ... }
  if let rating, !rating.isEmpty { pairs.append((AO3WorkFormField.rating, rating)) }
  if let languageID, !languageID.isEmpty { pairs.append((AO3WorkFormField.languageID, languageID)) }
  sendJoined(field: AO3WorkFormField.collectionsToAdd, names: collectionsToAdd)
  for name in collectionsToRemove { pairs.append((AO3WorkFormField.collectionsToRemove, name)) }
  if let restricted, !restricted.isEmpty { pairs.append((AO3WorkFormField.restricted, restricted)) }
  if let moderatedCommenting, !moderatedCommenting.isEmpty { pairs.append((AO3WorkFormField.moderatedCommenting, moderatedCommenting)) }
  if let commentPermissions, !commentPermissions.isEmpty { pairs.append((AO3WorkFormField.commentPermissions, commentPermissions)) }
  if let workSkinID, !workSkinID.isEmpty { pairs.append((AO3WorkFormField.workSkinID, workSkinID)) }
  if !pseudsToAdd.isEmpty { pairs.append((AO3WorkFormField.pseudsToAdd, pseudsToAdd)) }
  if removesSelfAsCreator { pairs.append((AO3WorkFormField.removeSelfAsCreator, "1")) }
  ```
- AO3 success checking (`submitWorkForm` in `AO3WorkActions.swift:600`):
  ```swift
  if let error = AO3Client.workWriteError(in: body) {
      throw AO3WorkWriteError.rejected(error)
  }
  if let notice = AO3Client.workWriteNotice(in: body) {
      return notice
  }
  if (300 ... 399).contains(status) {
      return "Saved."
  }
  ```

**5. Where it would go on Android:**
- There is currently no equivalent bulk editing screen on Android. The ideal location would be a new screen: `author/EditMultipleWorksScreen.kt`. It would likely be opened from `account/AccountWorksListScreen.kt` or `author/AuthorProfileScreen.kt`, neither of which currently implement select mode for works.
- Existing components that draw the same kind of thing: `SubjectFormRow` equivalents like `WritingChoiceRow` or `WritingTagsRow` don't exist in bulk forms yet, but the individual `WritingTagsScreen` and single-work form components could be reused.

**6. Size:** 
large (a screen with its own data)


## 2. A writer's own works list and its entrances to the work form

**1. Where on iOS:**
- Works List UI: `Features/Authors/AuthorProfileContentSections.swift` and `Features/Authors/AuthorProfileView.swift`
- Networking: `Services/AO3WorkActions.swift` (`deleteWork`, `deleteWorks`)

**2. How a reader gets there:**
- The select mode: tapping `Select` in the top right `ActionToolbar` of the author profile (`Features/Authors/AuthorProfileView.swift:789`).
- Swipe actions: Swiping right-to-left on a `CanonicalWork` in the works list (`Features/Authors/AuthorProfileContentSections.swift:338`) or a `AO3SeriesSummary` (`Features/Authors/AuthorProfileContentSections.swift:541`).
- "New Work" entrance: A `ToolbarIconButton` inside `AuthorProfileView.swift:786`.
- "New series" entrance: An `AccountExternalNavCard` located in `AuthorProfileContentSections.swift:501`.

**3. What is on screen:**
- **Bulk bar** (`Features/Authors/OwnWorksBulkBar.swift:15`):
  - `Button(selectedCount > 0 ? "Edit \(selectedCount)" : "Edit") { edit(nil) }` -> Opens `EditMultipleWorksView`.
  - `Button("Collections") { edit(.collections) }` -> Opens `EditMultipleWorksView` (focus: collections).
  - `Button("Visibility") { edit(.visibility) }` -> Opens `EditMultipleWorksView` (focus: visibility).
  - `Button("Delete", role: .destructive)` -> Opens confirmation alert:
    - Alert Title: `"Delete “Title”?"` or `"Delete N works?"`
    - Alert Message: `"This permanently removes [“Title 1” and “Title 2” | the work] and [their | its] chapters, kudos, comments and bookmarks from AO3 for everyone."`
    - Buttons: `"Delete on AO3"` (destructive), `"Cancel"`.
- **Swipe actions for Own Works** (`Features/Authors/AuthorProfileContentSections.swift:573` `ownWorkSwipeActions`):
  - `Button(role: .destructive)` with `Label("Delete", systemImage: "trash")`. Opens the same single-item Delete confirmation as the bulk bar.
  - `Button` with `Label("Chapter", systemImage: "text.append")`. Opens `WritingChapterDestination(workID: workID, workTitle: title)`.
  - `Button` with `Label("Tags", systemImage: "tag")`. Opens `WritingTagsDestination(workID: workID, workTitle: title)`.
  - `Button` with `Label("Edit", systemImage: "square.and.pencil")`. Opens `WritingWorkDestination(workID: workID)`.
- **Swipe actions for Series** (`Features/Authors/AuthorProfileContentSections.swift:618` `seriesSwipeActions`):
  - `Button` with `Label("Reorder", systemImage: "list.number")`. Opens `SeriesReorderDestination`.
  - `Button` with `Label("Edit", systemImage: "square.and.pencil")`. Opens `SeriesEditDestination`.
- **New Work entrance** (`AuthorProfileView.swift:786`): `ToolbarIconButton(title: "New Work", systemImage: "plus")` -> opens `WritingWorkDestination(workID: nil)`.
- **New series entrance** (`AuthorProfileContentSections.swift:501`): `AccountExternalNavCard(title: "New series on AO3", systemImage: "square.stack.badge.plus")` opens `/series/new` in Safari/Browse.
  - Footnote: `Text("This opens AO3 in Browse, where you can create the series.")`

**4. What it reads and writes:**
- `deleteWork(workID: Int)`: Calls `loadDeleteImplications` (GET) then `submitDelete` (POST).
- `deleteWorks(workIDs: [Int], expectedGeneration: Int)`:
  ```swift
  let csrf = try csrfToken(from: try await workFormHTML(at: referer, using: client))
  let params = [(AO3WorkFormField.authenticityToken, csrf)]
      + workIDs.map { (AO3WorkFormField.workIDs, String($0)) }
      + [("commit", "Yes, Delete Works")]
  return try await submitWorkForm(url, params, referer: referer, using: client)
  ```
- Success is checked implicitly by `submitWorkForm` via `AO3Client.workWriteError(in: body) == nil` and HTTP response codes.

**5. Where it would go on Android:**
- Currently, Android's `author/AuthorProfileScreen.kt` displays works using `AO3AuthorWorkCard` (lines 318, 400, 448). The swipe actions ("Delete", "Chapter", "Tags", "Edit") and "New Work" / "New series" entrances are entirely missing.
- Android has a delete swipe implemented only for history items in `account/AccountWorksListScreen.kt` (line 950): `SubjectChip(text = "Delete", style = SubjectChipStyle.Neutral, leadingIcon = Icons.Outlined.Delete)`.
- The new swipe actions and edit entrances would be added to `AuthorProfileScreen.kt` around `AO3AuthorWorkCard`. The "New Work" icon would be added to the TopAppBar actions. The bulk bar would require a new selection state in `AuthorProfileScreen.kt`.

**6. Size:** 
small (a row or a menu item on an existing screen) for the swipe actions; medium (a sheet or sub-screen) for the bulk edit selection framework.
