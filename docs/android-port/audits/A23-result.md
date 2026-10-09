# Audit A23 result

Read-only. Lines are the current source in this worktree. iOS paths are under `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. A22's five findings and its closed Inbox-cache suspicion are not re-filed. Recorded on purpose in `briefs/3b*-result.md` and `DECISIONS.md` (3bs seven merge rules, 3bn series preservation including the restricted skip, 3az recovery-copy sentence, 3bl hidden-field replay, 3bt edit-tags pin and unmodeled replay, 3bo Save token-from-loaded-form) are not re-filed.

| id | severity | file:line | statement |
| --- | --- | --- | --- |
| A23-1 | P1 | `network/ao3/writing/AO3WorkFormEncoder.kt:7-10` | Edit-tags Save drops `authenticity_token` from the body when AO3 served the token only in `<meta name=csrf-token>`. |
| A23-2 | P1 | `backup/BackupMergeService.kt:1221-1229` | Replace Library copies the archive row over this device's hold date and un-gives kudos. |
| A23-3 | P2 | `backup/BackupMergeService.kt:1307-1337` | File Merge, and a reconcile whose collection clock loses, never take a trusted collection-membership tombstone off a work that is already in the collection. |
| A23-4 | P2 | `backup/BackupMergeService.kt:780-818` | A winning work merge replaces AO3 tag lists instead of unioning them, so a fandom only this device fetched is dropped. |
| A23-5 | P2 | `writing/WritingEditTagsScreen.kt:168-169` | Two chip removes on one composition restore the first tag. |

## A23-1 Edit tags omits the body token when it lived only in the meta tag

`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormEncoder.kt:5-13` and `:96-108`

```kotlin
fun encode(form: AO3WorkForm, submit: AO3WorkSubmitAction): List<Pair<String, String>> {
    val modeled = iosParameters(form, submit).let { pairs ->
        if (form.kind != AO3WorkFormKind.EditTags) pairs else {
            val served = form.servedControls.filterNot { it.disabled }.map { it.name }.toSet()
            pairs.filter { it.first in served }
        }
    }
    val overridden = modeled.map { it.first }.toSet()
    return modeled + carriedParameters(form, submit, overridden)
}

private fun editTagsParameters(form: AO3WorkForm, submit: AO3WorkSubmitAction) = buildList {
    add(AO3WorkFormField.authenticityToken to form.csrfToken)
    ...
}
```

`AO3WorkFormParser.kt:71-73` and `:153-157`

```kotlin
val token = doc.selectFirst("meta[name=csrf-token]")?.attr("content")?.trim()?.takeIf(String::isNotEmpty)
    ?: input(AO3WorkFormField.authenticityToken)?.takeIf(String::isNotEmpty)
    ?: invalid("AO3 didn't give the work form a security token.")

internal fun servedControls(doc: Document, element: Element): List<AO3ServedControl> {
    val rawControls = doc.select("input, select, textarea, button").filter { control ->
        ...
    }.map(::snapshot)
```

The parser still takes `csrfToken` from the meta tag. `editTagsParameters` still puts that value on `authenticity_token`. `encode` then throws the pair away unless some enabled form control has that name. A meta tag is not a served control. `carriedParameters` cannot put it back: it only walks `servedControls`.

`AO3WriteRepository.editWorkTags` (`AO3WriteRepository.kt:74-85`) POSTs `form.parameters(...)` and separately sets `X-CSRF-Token` from `form.csrfToken`. The header is right. The body is missing the field iOS always sends.

iOS, `Services/AO3Client+Works.swift:198-200` and `:302-308`, `Models/AO3WritingModels.swift:652-664`, `Services/AO3Client.swift:933-937`:

```swift
guard let csrf = parseCSRFToken(from: html)
    ?? inputValue(form, name: AO3WorkFormField.authenticityToken)
else { throw AO3Error.parse }

func parameters(submit: AO3WorkSubmitAction) -> [(String, String)] {
    var pairs: [(String, String)] = [
        (AO3WorkFormField.authenticityToken, csrfToken)
    ]
    ...
}

static func parseCSRFToken(from html: String) -> String? {
    ... doc.select("meta[name=csrf-token]").first()?.attr("content")
```

`editTags` (`AO3WorkActions.swift:147-159`) POSTs that list. It never filters modeled names to served inputs. Brief `3bt-result.md` says the body starts with `authenticity_token` from the fresh meta token (input fallback).

Failing case. Posted work 995006. The fresh GET `/works/995006/edit_tags` has `<meta name="csrf-token" content="meta-only==">` and no `input[name=authenticity_token]`. Save. Android's POST to `/works/{id}/update_tags` has `X-CSRF-Token: meta-only==` and no `authenticity_token=` in the body. iOS's body begins `authenticity_token=meta-only==`. The demo fixture still has the hidden input, so `WritingEditTagsTest.oneOpeningReadNoOpeningPostAndSaveUsesFreshTokenActionMethodAndLanguage` and `tagsOnlyFixtureParsesWithoutTitleOrTextAndReplaysUntouchedBrowserFields` stay green: they compare against `iosTags`, which always emits the token, and the fixture's served snapshot still contains that name.

Smallest fix. For Edit tags, do not filter `authenticity_token` (and `_method`, `update_button`) out of the modeled list. Keep the served-name filter for the seven tag fields, which is the 3bt rule for not inventing a missing control.

## A23-2 Replace Library clears the hold date and un-gives kudos

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt:220-222` and `:1221-1229`

```kotlin
} else if (mode == BackupImportMode.REPLACE_LIBRARY) {
    summary = summary.copy(worksUpdated = summary.worksUpdated + 1)
    applyReplaceWork(existing, restored)
}

private fun applyReplaceWork(existing: SavedWork, restored: SavedWork): SavedWork {
    return restored.copy(
        id = existing.id,
        hasEpub = existing.hasEpub || restored.hasEpub,
        downloadedAt = restored.downloadedAt ?: existing.downloadedAt,
        dateAdded = minInstant(existing.dateAdded, restored.dateAdded),
        ao3Unavailable = existing.ao3Unavailable || restored.ao3Unavailable,
        assetIdentifier = existing.assetIdentifier.ifEmpty { restored.assetIdentifier }
    )
}
```

`restored` is `archived.toSavedWork(...)`. `BackupWork` has no `freedAt` or `authorIdentitiesJSON`; `toSavedWork` therefore leaves `freedAt = null` and `authorIdentitiesJSON = ""` (`SavedWork.kt:91`, `BackupMappers.kt:218-325`). `hasGivenKudos` is the archive flag, default false. `keepInProgressOverride` is `archived.keepInProgressOverride ?: false`.

The same service's reconcile path already keeps those fields (`mergeWork` at `:806-808`):

```kotlin
hasGivenKudos = existing.hasGivenKudos || restored.hasGivenKudos,
freedAt = existing.freedAt,
authorIdentitiesJSON = existing.authorIdentitiesJSON,
```

iOS, `Services/KudosBackup.swift:2411-2416` (Replace of an existing row still runs `apply`) and `:4443-4447`, `:4499-4508`. `apply` never assigns `freedAt`. Kudos-given is monotonic in every mode, including Replace:

```swift
work.hasGivenKudos = work.hasGivenKudos || archived.hasGivenKudos
```

`WorkLifecycle.holdFinishedCopy` (`WorkLifecycle.swift:27-30`) stamps `freedAt` only when it is nil. Android's hold uses the same field (`DECISIONS.md` 3br: the copy's hold starts on leaving the reader).

Failing case. Work W is finished, un-kept, `freedAt` 50 days ago, `hasGivenKudos = true`, `keepInProgressOverride = true`. Replace Library from a backup taken before those facts (or from a device that never had them). Android writes `freedAt = null`, `hasGivenKudos = false`, `keepInProgressOverride = false`. The next leave of the reader starts a new 60-day hold. Give Kudos is offered again. The work drops out of In progress. iOS keeps the hold date, keeps kudos-given, and only takes `keepInProgressOverride` from the archive when that key is present and the archive wins. `BackupPhase2FieldsTest.freedAtAndAuthorIdentitiesJsonSurviveAWinningArchive` stays green: it calls `merge` in the default reconcile mode, which uses `mergeWork`, not `applyReplaceWork`.

Smallest fix. Drive Replace of an existing work through `apply`/`mergeWork` with `incomingWins = true`, and keep the three device-local assignments `mergeWork` already has (`freedAt`, `authorIdentitiesJSON`, `hasGivenKudos` OR). Fill `keepInProgressOverride` only when the archive key is present.

## A23-3 A collection membership already here is not removed by a trusted tombstone

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt:1307-1340`

```kotlin
} else if (mode == BackupImportMode.MERGE) {
    val incomingWorkIds = archived.workIDs
        ...
        .filterNot { workId ->
            tombstoneIndex.collectionMembershipResolution(
                collectionMembershipRecordId(id, workId),
                incomingModified
            ) == TombstoneResolution.SUPPRESS_STALE
        }
    val existingIds = existing.workIds
        .map { BackupPaths.normalizeIdForComparison(it) }
        .toSet()
    val added = incomingWorkIds.filter { it !in existingIds }
    val filled = fillCollectionFields(...)
    val target = if (added.isNotEmpty()) {
        filled.copy(workIds = filled.workIds + added)
    } else {
        filled
    }
} else {
    val localModified = existing.lastModifiedAt ?: existing.dateAdded
    if (!SyncMerge.shouldApplyIncoming(localModified, incomingModified)) {
        val filled = fillCollectionFields(
            existing, archived, incomingWins = false, exportedAt = exportedAt
        )
        ...
        return@forEach
    }
```

File Merge only *adds* incoming work ids that the tombstone does not suppress. A work already in `existing.workIds` is never tested. Reconcile, when the local collection clock wins, fills colour/home/order and returns: `workIds` stay as they were. The winning-reconcile branch at `:1351-1362` does filter the union against the tombstone. There is no second pass over memberships already here, unlike queue memberships (`:1772-1776`) and annotations (`:2132-2136`), which 3bs added for A12.

iOS, `Services/KudosBackup.swift:2697-2736`, after the add loop, in every mode except Replace:

```swift
if mode != .replaceLibrary {
    let locallyChangedAt = collection.lastMembershipChangedAt
        ?? collection.lastModifiedAt
    let doomed = collection.works.filter { member in
        !archiveAffirmedMemberships.contains(member.id)
            && tombstones.suppressesCollectionMembership(
            collectionID: collection.id,
            workID: member.id,
            incomingModifiedAt: locallyChangedAt
        )
    }
    ...
    collection.works.removeAll { doomedIDs.contains($0.id) }
}
```

`WorkCollection.lastMembershipChangedAt` exists on Android (`LibraryModels.kt:43`) and is unused here.

Failing case. Collection C on this phone still contains work W. A paired backup carries a signed `workCollectionMembership` tombstone for `(C, W)` newer than C's `lastMembershipChangedAt`. File Merge, or a reconcile where this phone also renamed C more recently than the archive's collection row. W stays in C. The next export publishes W in C again, so the other device's removal never settles. iOS removes W. Queue memberships on the same restore already would.

Smallest fix. After the incoming collection loop, when `mode != REPLACE_LIBRARY`, drop any local `workIds` entry whose membership record id resolves `SUPPRESS_STALE` against `lastMembershipChangedAt ?: lastModifiedAt`, skipping ids the archive just affirmed (the iOS `archiveAffirmedMemberships` guard).

## A23-4 A winning work merge drops AO3 tags this device added

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt:780-818` and `:833-842`

When `incomingWins`, `mergeWork` starts from `restored.copy(...)`. That copy does not mention `workWarnings` / `workFandoms` / …, so they are the archive lists from `toSavedWork`. The losing branch unions:

```kotlin
workWarnings = mergeStringLists(existing.workWarnings, restored.workWarnings),
workCategories = mergeStringLists(existing.workCategories, restored.workCategories),
workTags = mergeStringLists(existing.workTags, restored.workTags),
workFandoms = mergeStringLists(existing.workFandoms, restored.workFandoms),
...
```

User tags (the separate `userTagsByWorkId` map) are still unioned in `merge` at `:245-250`. That is a different list.

iOS `apply` always unions, with no `incomingWins` gate (`KudosBackup.swift:4499-4505`):

```swift
work.workWarnings = TagMerge.merged(work.workWarnings, archived.workWarnings)
work.workCategories = TagMerge.merged(work.workCategories, archived.workCategories)
work.workTags = TagMerge.merged(work.workTags, archived.workTags)
work.workFandoms = TagMerge.merged(work.workFandoms, archived.workFandoms)
work.workCharacters = TagMerge.merged(work.workCharacters, archived.workCharacters)
work.workRelationships = TagMerge.merged(work.workRelationships, archived.workRelationships)
work.workFreeforms = TagMerge.merged(work.workFreeforms, archived.workFreeforms)
```

Failing case. This phone refreshed work W and now has fandoms `[Good Omens, Discworld]`. The archive is newer because the other phone starred W, and still has fandoms `[Good Omens]`. Reconcile. Android's winning copy is `[Good Omens]`. iOS's is `[Good Omens, Discworld]`. Replace (`applyReplaceWork`) has the same replacement, with no union at all.

Smallest fix. After either clock branch, assign the seven AO3 lists with `mergeStringLists(existing, restored)`, matching `apply`. Replace of an existing row should use the same union if it goes through `mergeWork`.

## A23-5 Two Edit-tags chip removes on one composition leave one tag

`android/app/src/main/java/io/github/cidy02/kudos/writing/WritingEditTagsScreen.kt:142-170`

```kotlin
for ((kindIndex, tagKind) in WritingTagKind.entries.withIndex()) {
    val values = tagKind.values(form)
    ...
    row.forEachIndexed { chipIndex, chip ->
        ...
        SubjectChip(chip.name, ...,
            .clickable(role = Role.Button) {
                model.writingTags(tagKind, values.filterNot { it == chip.name })
            }
```

`values` is the list from this composition. `writingTags` (`WritingWorkFormState.kt:255-260`) replaces the kind's list with the argument. Compose `Modifier.clickable` invokes the lambda captured at the last successful composition (androidx.compose.foundation `ClickableNode`); it does not re-read `values` at pointer-up.

iOS, `Features/Writing/WritingTagsEditor.swift:215-216`:

```swift
Button {
    values.removeAll { $0 == value }
}
```

That mutates the live `Binding` at tap time. A second remove sees the list after the first.

Failing case. Fandom chips `Good Omens` and `Supernatural` on one composition (`values = [Good Omens, Supernatural]`). Invoke both Remove click lambdas before the next composition (instrumented test, or two pointers). First write `[Supernatural]`. Second write `values.filterNot { it == "Supernatural" }` = `[Good Omens]`. One tag remains. Both should be gone. A single tap still works because the next composition captures the new list.

Smallest fix. In the click lambda, read the current form from `model.state.value` (or `tagKind.values(form)`) and filter that, the way `WritingTagsEditorScreen` already uses `readValues` for a later add.

## A22 suspicions, settled

1. **Right-to-left paginated end — closed, the inversion is right.** Readium Kotlin 3.3.0 `EpubNavigatorFragment.notifyCurrentLocation` (upstream `3.3.0`, around lines 1099-1103) reports `pageIndex = webView.mCurItem` and `totalPages = webView.numPages`. `R2WebView.updateCurrentItem` sets `mCurItem = round(scrollX / clientWidth)`: zero-based **physical** page from the left. In RTL, `goToNextResource` seeds `setCurrentItem(numPages - 1)` and `goToPreviousResource` seeds `setCurrentItem(0)` (`EpubNavigatorFragment` around 916-941): the start of an RTL resource is the high physical index, the end is physical 0. `ReadiumNavigatorHost.kt:105-106` `totalPages - pageIndex` is then 1-based logical page, so the last page is `page == pageCount` and `EndOfWorkActions.isAtEndOfPublication` (`EndOfWorkActions.kt:40`) finishes there. If `pageIndex` were already logical, a complete RTL work would finish on logical page 1; it is not.

2. **`ReaderProgressSaver.onProgress` after the last flush — unconfirmed.** `onProgress` (`ReaderProgressSaver.kt:26-32`) writes `pending` without the mutex and launches a 1500 ms job. `flush` (`:35-38`) cancels that job and writes `pending` under the mutex. `ReaderViewModel.close` (`ReaderViewModel.kt:190-197`) flushes once, then ends the session; it does not ignore later `onProgress`. `ReaderScreen.kt:299-300` calls `close` from the screen's `DisposableEffect`. The navigator host is a child (`ReadiumNavigatorHost.kt:156-166`) and Compose disposes child effects first, cancelling `viewportJob` and removing the fragment before that `close`. A natural callback after flush therefore needs a `PaginationListener` event already posted on the main looper. Confirm by calling `onProgress` after `flush()` returns and cancelling the saver's scope before 1500 ms: `pending` would never be written. Do not treat that as observed on close.

3. **Annotation tombstone record-id case — closed, both sides compare UUID identity.** iOS `SyncTombstones.recordDeletion(of: annotation)` (`PersistenceSync.swift:441-442`) stores `recordID: annotation.id` (a `UUID`). `TombstoneIndex.annotationResolution` looks up `annotationTombstonesByID[id]` with that `UUID` (`KudosBackup.swift:4188-4192`). Swift `UUID` equality does not depend on the hex case of `uuidString`. Android `AnnotationRepository.deleteAnnotation` stores `recordID = id.lowercase()` (`AnnotationRepository.kt:51`). `TombstoneIndex` indexes with `BackupPaths.normalizeIdForComparison` (`BackupMergeService.kt:2517, 2597-2601`), which is `UUID.fromString(value).toString()` (`BackupPaths.kt:69-74`). Java `UUID.toString()` is defined to use lowercase hex; `fromString` accepts either case. An iOS backup with `E621E1F8-…` and an Android tombstone with `e621e1f8-…` resolve to the same key on both sides. A backup from iOS will suppress the highlight.

4. **Edit-tags two chip removes — confirmed as A23-5.**

5. **Edit-tags body token when only the meta tag carries it — confirmed as A23-1.** The demo fixture still has the hidden input, which is why the existing tests did not catch it.

## Unconfirmed

- Progress after close, as in suspicion 2 above. The saver will drop a post-flush `onProgress` if its scope dies during debounce; whether the reader actually delivers one after `close()`'s flush was not shown by reading.
- `epubDigest` copied when the archive clock wins (`mergeWork` `:813`, A3's unconfirmed). 3bs left the field alone. Android's sync-down hashes the local file (`A3-result.md`); I did not re-open `SyncRepository` to prove a permanent skip. Not re-filed.
- `WritingDraftsState.load`'s `finally` writes an empty `WritingDraftsUiState()` if `loading` is still true (`WritingDraftsState.kt:41-43`). A generation mismatch or cancellation on the *same* state object would flash an empty list with no error. The screen keys a new `WritingDraftsState` on `generation` (`WritingDraftsScreen.kt:99-105`), so that write is discarded. Confirm only if a caller invokes `load` on a state object that outlives a generation change.

## Not read

Not compared line by line, or only sampled: iOS `restoreIsolatedContents` EPUB journaling and font validation; Android `mergeFonts`, `refreshForApply`, `preview`; `BackupRepository.applyStoredMerge`; Work Detail's series prompt driver in `WorkDetailScreen.kt` beyond the repository loop; `WritingDraftsRepository` parser internals and `DraftExpiry` calendar math against every iOS threshold; challenge sign-up *screen* chrome (`AO3ChallengeSignUpScreen.kt`); `AO3WorkFormEncoder.iosParameters` parent/series hidden-carry against a live AO3 document (order was checked against `AO3WritingModels.swift:555-635` and matches, including empty series id/title and `workSkinID`); iOS `ReadingQueueService.preserve` `syncMetadata` after a successful EPUB (3bn already records that remaining difference). `docs/android-port/DECISIONS.md` backup-merge entries and `docs/AO3_NETWORKING_POLICY.md` were read for recorded decisions. No source file was edited. Nothing was built, committed, or requested from AO3.

## Triage (Claude, 2026-10-09)

All five read against the code and against iOS; all real, all fixed (gate 2,257).

- **A23-1 real, fixed.** Edit tags' body always carries the token, the method and the
  submit, as iOS's does; the served-name rule is kept for the seven tag fields only. Test
  `theTokenGoesInTheBodyEvenWhenOnlyTheMetaTagCarriesIt`. An older test that expected the
  submit to be left out when the page drew no button was corrected: iOS always names the
  action. No write of this kind has ever run against AO3, so nothing was lost.
- **A23-2 real, fixed.** Replace Library keeps what the archive does not carry: the date a
  finished copy's hold began, kudos given (never un-given), the author identities, and every
  optional key an older archive lacks (the keep-in-progress override, hidden-from-history,
  comments, hits, bookmarks, the AO3 ids). Test `replaceLibraryKeepsWhatTheArchiveDoesNotCarry`.
- **A23-3 real, fixed.** A second pass after the collections loop, in every mode but
  Replace, as iOS: a work already in a collection is taken out by a deletion record newer
  than the collection's last membership change, unless the archive affirms it. Test
  `aDeletionRecordRemovesAMembershipThatIsAlreadyHere` (reconcile where this device's copy
  wins, File Merge, and the affirming archive).
- **A23-4 real, fixed.** The seven AO3 tag lists are merged whoever wins, and in Replace.
  Test `aWinningArchiveMergesTheTagListsInsteadOfReplacingThem`.
- **A23-5 real, fixed.** A chip's remove reads the list as it is at the tap. No test (it
  needs two click lambdas from one composition).

The five suspicions from A22: right-to-left paginated end, closed (the inversion is right);
a deletion record's id case, closed (both sides compare as UUIDs); two chip removes and the
meta-only token, confirmed and fixed above; a reading position after the reader's last
flush, still unconfirmed.

Open: `epubDigest` copied when the archive wins (A3's unconfirmed item, not re-read).
Not read: font merging, `refreshForApply`, `BackupRepository.applyStoredMerge`, Work
Detail's series question, the drafts parser, the sign-up screen's chrome.
