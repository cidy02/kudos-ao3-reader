# A33: Edit multiple works

## 1. Requests

**Opening (loadBulkEditForm):**
Android `AO3WriteRepository.kt:136`:
- `GET` `AO3WorkFormUrls.editWork(ids.first())` (via `bulkToken`)
- `POST` `AO3BulkWorkUrls.page(username, "edit_multiple")`

iOS `AO3WorkActions.swift:56`:
- `GET` `AO3Client.workEditURL(workID: first)` (via `csrfPage`)
- `POST` `AO3Client.editMultipleWorksURL(username: username)`

Both make one `GET` to the first work's edit page for a CSRF token, followed by a `POST` to `edit_multiple` to render the bulk form.

**Writing (bulkEditWorks):**
Android `AO3WriteRepository.kt:158`:
- For each work with tag changes: `GET` `AO3WorkFormUrls.editTags(id)`, then `POST` `AO3WorkFormUrls.editTags(id)` (via `editWorkTags`)
- If uniform changes exist: `GET` `AO3WorkFormUrls.editWork(first)` (via `bulkToken`), then `POST` `AO3BulkWorkUrls.page(username, "update_multiple")`

iOS `AO3WorkActions.swift:383`:
- For each work with tag changes: `GET` `AO3Client.workEditTagsURL(workID: workID)`, then `POST` `AO3Client.workEditTagsURL` (via `editTags`)
- If uniform changes exist: `GET` `AO3Client.workEditURL(workID: first)`, then `POST` `AO3Client.updateMultipleWorksURL(username: username)`

The requests match exactly.

**Bulk Delete:**
Android `AO3WriteRepository.kt:189`:
- `GET` `show_multiple` (via `bulkToken`)
- `POST` `delete_multiple`

iOS `AO3WorkActions.swift:432`:
- `GET` `showMultipleWorksURL`
- `POST` `deleteMultipleWorksURL`

The requests match exactly.

## 2. Verdicts and failures

**Success/Refusal for writes:**
Android uses `workVerdict` (`AO3WriteRepository.kt:415`):
- `error != null` -> `Failure(Validation(error))`
- `notice != null` or `statusCode in 300..399` -> `Success(Unit)`
- `statusCode in 200..299` -> `Failure(Validation(UNCONFIRMED))`
- `else` -> `Failure(Validation("AO3 didn't accept the change."))`

iOS `submitWorkForm` (`AO3WorkActions.swift:548`):
- `error != nil` -> `throw AO3WorkWriteError.rejected(error)`
- `notice != nil` -> returns `notice`
- `(300...399).contains(status)` -> returns `"Saved."`
- `(200...299).contains(status)` -> `throw AO3WorkWriteError.unconfirmed`
- `else` -> `throw AO3WorkWriteError.rejected("AO3 didn't accept the change.")`

Both platforms consider an error flash as refusal, a notice flash or 3xx as success, a 2xx without a notice as unconfirmed, and anything else as rejected.

**Read failures:**
Android `WritingBulkEditState.kt:21` (load):
- Network exceptions -> `workFormFailure` (converted to string).
- Empty IDs -> `"Select at least one work."` (`AO3WriteRepository.kt:139`)
- Parse error -> `"Couldn't read AO3's work form."` (`AO3WriteRepository.kt:152`)

iOS `AO3WorkActions.swift:56` (loadBulkEditForm):
- Empty IDs -> `"Select at least one work."` (`AO3WorkActions.swift:58`)
- Parse error -> `try AO3Client.parseBulkEditForm(from: body)` which throws parse errors.

## 3. Words on screen

UI strings match exactly. No differences to list.
- Android: `WritingBulkEditScreen.kt` and `WritingBulkEditState.kt`
- iOS: `EditMultipleWorksView.swift` and `BulkTagStatePicker.swift`

## 4. Second taps and stale answers

**Second taps:**
Android disables the Save button and guards the save function:
`WritingBulkEditScreen.kt:73`: `IconButton(enabled = !state.saving && !state.saved, ...)`
`WritingBulkEditState.kt:42`: `if (!active || old.form == null || old.saving || old.saved) return`

iOS disables the Save button:
`EditMultipleWorksView.swift:140`: `.disabled(isSaving)`

**Stale answers:**
Android guards against session changes during writes by checking generation before state updates:
`WritingBulkEditState.kt:32`: `catch (_: CancellationException) { if (active) mutable.value = state.value.copy(failure = WORK_FORM_SESSION_CHANGED) }`
`WritingBulkEditState.kt:46`: `when (val answer = writes.bulkEditWorks(old.changes, generation)) { is AO3Result.Success -> if (active) ...`

iOS uses `Task` cancellation implicitly when dismissed or the `auth` service throws `AO3WorkWriteError.notSignedIn` upon checking `requireWorkSession()`.

## 5. The body sent

Android `AO3BulkEditChanges.kt:31` (`parameters`):
```kotlin
    fun parameters(token: String): List<Pair<String, String>> = buildList {
        add("authenticity_token" to token); add("_method" to "patch")
        workIDs.forEach { add("work_ids[]" to it.toString()) }
        fun scalar(name: String) { scalars[name]?.takeIf(String::isNotEmpty)?.let { add(name to it) } }
        scalar(AO3WorkFormField.rating); scalar(AO3WorkFormField.languageID)
        joinWorkList(collectionsToAdd).takeIf(String::isNotEmpty)?.let { add("work[collections_to_add]" to it) }
        collectionsToRemove.forEach { add("work[collections_to_remove][]" to it) }
        scalar(AO3WorkFormField.restricted); scalar(AO3WorkFormField.moderatedCommenting)
        scalar(AO3WorkFormField.commentPermissions); scalar(AO3WorkFormField.workSkinID)
        if (pseudsToAdd.isNotEmpty()) add("work[pseuds_to_add]" to pseudsToAdd)
        if (removesSelf) add("remove_me" to "1")
    }
```

iOS `AO3WritingModels.swift:858` (`parameters`):
```swift
    func parameters(csrfToken: String, methodOverride: String = "patch") -> [(String, String)] {
        var pairs: [(String, String)] = [
            (AO3WorkFormField.authenticityToken, csrfToken),
            (AO3WorkFormField.methodOverride, methodOverride)
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
        if removesSelfAsCreator { pairs.append((AO3WorkFormField.removeMe, "1")) }
        return pairs
    }
```
Both send `authenticity_token`, `_method` (patch), and `work_ids[]`. Neither sends any tag fields. Empty strings/unmodified fields are omitted.

## Issues

| Number | Severity | Android | iOS | Description |
|---|---|---|---|---|
| 1 | P3 | `AO3WriteRepository.kt:158` | `AO3WorkActions.swift:383` | Android `bulkEditWorks` loops tag changes sequentially without `AO3RequestCoordinator`, whereas iOS paces them with `AO3RequestCoordinator.shared.withSlot`. |
