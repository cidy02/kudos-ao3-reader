# A3 result: Android persistence, backup and folder sync

Read-only audit of the Android app against `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`, `docs/KUDOSBACKUP_FORMAT.md`, and the iOS sources under `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. No source file was edited. Nothing was built or run. Room's per-statement transaction rule is taken from the Android Room `@Transaction` reference: a `@Insert`, `@Update`, or `@Delete`, and a `@Query` that writes, is its own transaction; several of those calls commit together only inside `withTransaction` or a `@Transaction` method.

Migrations `MIGRATION_1_2` through `MIGRATION_13_14` are registered in `KudosAppContainer` with no destructive fallback. Schema files 1–14 differ by added columns and tables only. Released 0.2.1 and 0.2.2 are schema 7, and `MIGRATION_7_8` … `MIGRATION_13_14` reach version 14. No migration finding. Manifest `BackupVersion.CURRENT` is 8.

| id | severity | where | statement |
| --- | --- | --- | --- |
| A3-1 | P1 | `BackupMergeService.kt:851` | A newer archive can clear `preserved`, and the next restore may then overwrite that EPUB. |
| A3-2 | P1 | `BackupMergeService.kt:198` | File Merge of a work in Recently Deleted writes the archive over the local row, including an older reading position. |
| A3-3 | P2 | `BackupMergeService.kt:781` | Date Added and a queue's Date Created are not always the earlier of the two copies. |
| A3-4 | P2 | `BackupMergeService.kt:1606` | Replace Library still last-write-wins for a queue and its memberships. |
| A3-5 | P2 | `BackupMergeService.kt:1268` | File Merge does not return a collection or queue from Recently Deleted, and leaves the work tombstone in place. |
| A3-6 | P2 | `BackupMappers.kt:801` | One tombstone whose `recordTypeRaw` this build does not know fails the whole merge. |
| A3-7 | P2 | `BackupMergeService.kt:2054` | A newer copy of the same highlight replaces the note, and the previous text is dropped. |
| A3-8 | P2 | `AnnotationRepository.kt:45` | A delete and its tombstone commit as two transactions. |
| A3-9 | P3 | `KudosDatabaseMigrationTest.kt:249` | Two migration tests build a one-column `works` table, so they stay green if the real table is mishandled. |

## A3-1. A winning archive demotes `preserved`

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt:851-855`

```kotlin
epubPreservationStatusRaw = if (incomingWins) {
    restored.epubPreservationStatusRaw ?: existing.epubPreservationStatusRaw
} else {
    existing.epubPreservationStatusRaw ?: restored.epubPreservationStatusRaw
},
```

When the archive clock wins and the archive carries a status, that status replaces a local `preserved`. Absent status (`null`) keeps the local value, which is why `IncomingEpubGateTest.aPreservedWorkThatStillHasItsFileIsNeverReplaced` stays green: its archive omits the key.

iOS refuses the demotion. `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift:4510-4518`

```swift
// Preservation is monotonic under merge: an archive may promote a work to
// `.preserved`, never demote one. ...
if work.epubPreservationStatus != .preserved,
   incomingWins || work.epubPreservationStatus == .notPreserved {
    work.epubPreservationStatusRaw = archived.epubPreservationStatusRaw
}
```

The same restore still refuses the file, because `mayRestoreEpub` (`BackupMergeService.kt:2567-2577`) reads the status from the row before this copy. `mayReplaceEpub` (`BackupMergeService.kt:2554-2558`) returns false while `isPreserved` is true. The demoted status is what the next restore sees.

Failing case. This phone has the work preserved, file on disk, `lastModifiedAt` 1 March. The other phone has the same work as `notPreserved`, edits the title on 2 March, and syncs. This merge sets `epubPreservationStatusRaw` to `notPreserved` and leaves the file. On the next sync the other phone's EPUB is newer, `mayReplaceEpub` allows it, and the preserved bytes are replaced. The preserved file should stay the file, and the status should stay `preserved`, on both passes.

Smallest fix. Keep a local `preserved` the way iOS does: assign the archive status only when the local status is not `preserved`.

## A3-2. File Merge of a deleted work copies the archive onto the row

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt:198-207`

```kotlin
} else if (mode == BackupImportMode.MERGE && existing.isDeleted) {
    // Recently Deleted is not in the active library. File Merge
    // adds it back without planting a tombstone, matching iOS.
    summary = summary.copy(worksUpdated = summary.worksUpdated + 1)
    restored.copy(
        id = existing.id,
        isDeleted = false,
        deletedAt = null,
        permanentDeletionScheduledAt = null
    )
}
```

`restored` is `archived.toSavedWork` (`BackupMergeService.kt:187`). The assignment is the whole archive row. `mergeWork` / `applyProgressLww` is not used on this branch.

iOS clears the deletion, retracts the tombstone, then runs `apply`, which last-write-wins. `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift:2358-2375` and the call to `apply` after line 2439. `incomingWins` is false when the local clock is newer (`KudosBackup.swift:4401-4404`), so progress and title stay.

Failing case. The phone read the work to chapter 20 today, then deleted it (Recently Deleted, `lastModifiedAt` is now). File Merge of last month's backup, where the locator is chapter 2. Android stores chapter 2, the old title, and `isDeleted = false`. iOS would show the work again and keep chapter 20.

Smallest fix. On this branch clear `isDeleted`, `deletedAt`, and `permanentDeletionScheduledAt` on `existing`, drop the matching saved-work tombstone (A3-5), then call `mergeWork` so the clocks still decide the fields.

## A3-3. Date Added / Date Created is not the earlier of the two copies

`docs/android-port/DECISIONS.md` T-353 records the rule both apps are supposed to share: Date Added is the earlier of the two copies. iOS applies it on every reconcile and replace, including when the local clock wins.

Works, only the winning branch mins. `BackupMergeService.kt:781` is inside `if (incomingWins)`. The lose branch (`BackupMergeService.kt:802-837`) copies `existing` and never sets `dateAdded`.

```kotlin
dateAdded = minInstant(existing.dateAdded, restored.dateAdded),
```

iOS, unconditional, `KudosBackup.swift:4407`:

```swift
work.dateAdded = min(work.dateAdded, archived.dateAdded)
```

File Merge of a work that is still in the library matches iOS: iOS `continue`s at `KudosBackup.swift:2409` without calling `apply`. That path is fine. Replace of a work mins in `applyReplaceWork` (`BackupMergeService.kt:1190`). That path is fine.

Collections. Incoming-wins assigns the archive date (`BackupMergeService.kt:1322-1328`), so a later archive date replaces an earlier local one:

```kotlin
val base = existing.copy(
    name = if (archivedIsDeleted) existing.name else archived.name,
    dateAdded = BackupValidator.parseInstant(
        archived.dateAdded,
        "collection.dateAdded",
        exportedAt
    ),
```

The local-wins branch (`BackupMergeService.kt:1298-1306`) and File Merge (`BackupMergeService.kt:1284-1290`) call `fillCollectionFields`, which never touches `dateAdded` (`BackupMergeService.kt:1387-1401`). Replace builds a new collection from the archive (`BackupMergeService.kt:1215-1218`) and drops the local date.

iOS mins on every mode, `KudosBackup.swift:2634`:

```swift
collection.dateAdded = min(collection.dateAdded, archived.dateAdded)
```

Queues. `dateCreated` is mins only when the archive clock wins (`BackupMergeService.kt:1640`). The lose branch (`BackupMergeService.kt:1651-1656`) and File Merge (`BackupMergeService.kt:1599-1604`) go through `fillQueueFields`, which does not set `dateCreated` (`BackupMergeService.kt:1780-1785`).

iOS mins on every mode, including File Merge where `incomingWins` is false. `KudosBackup.swift:2920`:

```swift
queue.dateCreated = min(queue.dateCreated, archived.dateCreated)
```

Failing case. Local work `dateAdded` 1 June 2024, `lastModifiedAt` 1 October 2026 after a title edit. Archive of the same work `dateAdded` 1 January 2024, older `lastModifiedAt`. Reconcile keeps 1 June 2024. Library sort by Date Added should use 1 January 2024. Same inputs for a collection whose archive clock wins and whose archive `dateAdded` is 2026: Android stores 2026. iOS stores the earlier local date.

Smallest fix. Set `dateAdded` / `dateCreated` to `minInstant` of the local value and the archive value on every branch that keeps an existing row, including `replaceCollections` and the queue lose / File Merge branches. Do this outside the `incomingWins` test.

## A3-4. Replace Library last-write-wins a queue

`BackupMergeService.kt:1606-1657` handles every mode except File Merge, including `REPLACE_LIBRARY`, with `shouldApplyIncoming`. A newer local queue keeps its name, sort, and deletion flags. Memberships do the same at `BackupMergeService.kt:1709-1713`:

```kotlin
} else if (mode != BackupImportMode.MERGE &&
    SyncMerge.shouldApplyIncoming(existing.lastModifiedAt ?: existing.queuedAt, incomingModified)
) {
    membershipsById[id] = restored
}
```

iOS forces the snapshot. `KudosBackup.swift:2838-2846`:

```swift
let incomingWins = switch mode {
case .merge: false
case .replaceLibrary: true
case .reconcile:
    SyncMerge.shouldApplyIncoming(
```

and for a membership that already exists, `KudosBackup.swift:3006-3014`:

```swift
let membershipWins = switch mode {
case .merge: false
case .replaceLibrary: true
case .reconcile:
    SyncMerge.shouldApplyIncoming(
```

The iOS comment at `KudosBackup.swift:2999-3004` says a Replace left gated on recency kept a membership the reader had moved since the backup, which is the edit Replace is supposed to undo.

Works and collections do take the snapshot (`applyReplaceWork`, `replaceCollections`). Annotations force Replace at `BackupMergeService.kt:2051-2052`. Queues do not. Reading sessions and favorites stay last-write-wins on iOS as well (`KudosBackup.swift:3499-3503`, `3631-3634`); that part matches.

Failing case. Backup from January: queue "Hold" with works A, B, C in that order. Since then the phone renamed it "Reread" and moved C to the top. Replace Library with the January file. The phone still shows "Reread" and C on top. iOS shows "Hold" and A, B, C.

Smallest fix. For `REPLACE_LIBRARY`, take the archive queue and the archive membership (as the winning branch already does) without `shouldApplyIncoming`. Keep `dateCreated` as the earlier of the two (A3-3). Leave the system queue's name and kind pinned, which the winning branch already does.

## A3-5. File Merge leaves collections and queues deleted, and leaves the work tombstone

Collections, File Merge, `BackupMergeService.kt:1268-1290`: `fillCollectionFields` and extra work ids. `isDeleted` is untouched. Queues, `BackupMergeService.kt:1599-1604`: same for `isDeleted`.

iOS clears it before the rest of the merge. Collections, `KudosBackup.swift:2556-2561`:

```swift
// Mirror the work path: Merge must be able to undo a prior
// Replace that parked this collection in Recently Deleted.
if mode == .merge, existing.isPendingDeletion {
    existing.isPendingDeletion = false
    existing.deletedAt = nil
    existing.permanentDeletionScheduledAt = nil
}
```

Queues, `KudosBackup.swift:2787-2793`, the same three assignments.

The work path does clear `isDeleted` (A3-2) and does not remove the tombstone. `tombstonesById` is seeded from the local rows (`BackupMergeService.kt:71-72`) and the File Merge branch never drops the saved-work entry. iOS retracts it at `KudosBackup.swift:2365-2373` (`PreservedWorkService.retractTombstone`). The next export still carries the deletion. A peer with no row for that work hits `suppressesWorkResurrection` (`BackupMergeService.kt:2423-2441`) and will not add it.

Failing case. Replace Library parked the collection "Favorites" and the queue "Hold" in Recently Deleted. File Merge of a backup that still contains both. They stay in Recently Deleted. iOS puts both back in the library. Separately: File Merge brings a deleted work back on this phone, the saved-work tombstone is still exported, and the other phone, which does not have the row, refuses to add it.

Smallest fix. In the File Merge branch for an existing collection or queue, clear `isDeleted`, `deletedAt`, and `permanentDeletionScheduledAt` the way iOS does. When a deleted work is brought back, remove saved-work tombstones for its id, AO3 id, and canonical URL from `tombstonesById` before the snapshot is returned.

## A3-6. An unknown tombstone type fails the restore

`BackupMappers.kt:801-803`

```kotlin
if (type.isEmpty() || type !in knownTypes) {
    throw IllegalArgumentException("Invalid or unknown tombstone recordTypeRaw: $recordTypeRaw")
}
```

`BackupMergeService.merge` calls `archived.toSyncTombstone` for every tombstone before signature checks (`BackupMergeService.kt:84`). The exception leaves the function. No later row is merged. `BackupRestoreSecurityTest.testM2b_MergeRejectsBlankOrUnknownTombstone` asserts this throw.

iOS skips that one tombstone and continues. `KudosBackup.swift:4257-4260` returns nil from `makeTombstone` when `SyncTombstoneRecordType(rawValue:)` fails. The caller continues at `KudosBackup.swift:2296`: `guard let adopted = makeTombstone(from: archived) else { continue }`.

Failing case. A backup or sync folder whose manifest is otherwise version 8 contains one tombstone with `recordTypeRaw` set to a type this build does not list (a later app version, or a single bad row). `BackupMergeService.merge` throws. No work, progress, or EPUB from that file is applied. Folder sync throws on every run while that row is in the manifest. iOS restores the library and ignores that tombstone. A blank type can keep failing; an unrecognised non-blank type should not fail the file.

Smallest fix. In the tombstone loop, skip a non-blank unknown `recordTypeRaw` the way iOS does, and change `testM2b_MergeRejectsBlankOrUnknownTombstone` so the unknown-type package still merges.

## A3-7. Replacing a highlight drops the previous note

`BackupMergeService.kt:2051-2057`

```kotlin
} else if (mode == BackupImportMode.REPLACE_LIBRARY ||
    SyncMerge.shouldApplyIncoming(existing.effectiveLastModifiedAt, incomingModified)
) {
    byId[id] = restored.copy(
        createdAt = minInstant(existing.createdAt, restored.createdAt)
    )
```

`restored` is the archive annotation, including its note. The local note is not copied anywhere.

iOS writes the local note onto a hidden sibling before the live row takes the new text. `KudosBackup.swift:3830-3832`:

```swift
if preexistingIDs.contains(local.id), !local.note.isEmpty, archived.note != local.note {
    parkDisplacedNote(local.note, from: local, work: work, in: context)
}
```

`parkDisplacedNote` (`KudosBackup.swift:3905-3930`) inserts a pending-deletion annotation with that note. The live row then last-write-wins. `docs/REGRESSION_TEST_MATRIX.md` requires the non-empty note to be salvaged.

Failing case. Both phones share highlight id `H`. This phone's note is "keep this", last modified Monday. The other phone's note on `H` is "other", last modified Tuesday. Sync. This phone's highlight shows "other". "keep this" is not in the database and will not be in the next export. iOS shows "other" on the live highlight and still has "keep this" on a pending-deletion row that exports.

Smallest fix. Before the assignment at `BackupMergeService.kt:2054`, if the local note is non-empty and different, insert a copy with a new id, `isPendingDeletion = true`, and `deletedAt = now`, then last-write-wins the live row.

Same-passage collapse (two UUIDs, one locator) is a separate gap: iOS `dedupeSamePassageAnnotations` at `KudosBackup.swift:3950`. Android keeps both rows, so the text is not deleted. It is listed under Unconfirmed rather than here.

## A3-8. The row is deleted in one transaction and the tombstone in another

Room wraps each `@Insert` / `@Delete` in its own transaction. These call sites do the delete, return, then insert the tombstone.

Highlight, `reader/AnnotationRepository.kt:43-59`:

```kotlin
suspend fun deleteAnnotation(id: String) {
    val existing = dao.getById(id)
    dao.deleteById(id)
    if (existing == null) return
    val now = clock()
    tombstoneDao.upsert(
```

Queue membership, `library/ReadingQueueRepository.kt:143-157`: `deleteMembershipById`, then `upsertSignedTombstone`. The comment on lines 144-146 says a missing tombstone lets a backup resurrect the membership.

Work hard-delete, `works/WorkRepository.kt:381-388`: `deleteDependents`, delete the EPUB, `workDao.deleteById`, then `recordWorkTombstone`. Inside `deleteDependents` (`WorkRepository.kt:400-425`) each membership and annotation is deleted, then its tombstone is written, still one statement at a time.

Collection membership, `WorkRepository.kt:795-811`: `removeWork`, then `touchCollection`, then `upsertSignedTombstone`.

`SavedSearchRepository.delete` writes the tombstone first and then deletes the row (`SavedSearchRepository.kt:48-65`). A crash there leaves the row and a tombstone, and the next merge can still suppress it. The sites above leave the opposite: the row is gone and there is no tombstone.

Failing case. Delete a highlight. The process is killed after `deleteById` commits and before `tombstoneDao.upsert` commits. The highlight is gone on this phone. The other phone still has it and syncs. Nothing local suppresses that id, so the highlight is inserted again. The same sequence on "remove from queue" puts the work back in the queue.

Smallest fix. Wrap each pair in `database.withTransaction`, and insert the signed tombstone before deleting the row, matching `SavedSearchRepository.delete`.

## A3-9. Migration tests that do not open the real `works` table

`android/app/src/test/java/io/github/cidy02/kudos/data/local/KudosDatabaseMigrationTest.kt:249-251` (`migrate9To10_addsHasGivenKudosDefaultingToFalse`):

```kotlin
override fun onCreate(db: SupportSQLiteDatabase) {
    db.execSQL("CREATE TABLE IF NOT EXISTS `works` (`id` TEXT NOT NULL, PRIMARY KEY(`id`))")
}
```

`migrate12To13AddsNullableDownloadedAtWithoutBackfill` does the same at `KudosDatabaseMigrationTest.kt:300`: `CREATE TABLE works (id TEXT NOT NULL, PRIMARY KEY(id))`.

Both would still pass if `MIGRATION_9_10` or `MIGRATION_12_13` dropped or retyped every other column of the real `works` table, because those columns are not in the database under test. They also never open Room against `WorkEntity`, so a default Room rejects (`Migration didn't properly handle`) is invisible to them.

`releasedSchema7MigratesToCurrentAndPassesRoomValidation`, `schema10MigratesToCurrentAndPassesRoomValidation`, `schema12MigratesToCurrentAndPassesRoomValidation`, and `schema13MigratesTo14AndPassesRoomValidation` do build from the exported schema and open Room. Those are the tests that would catch a bad migration on a released database. Schemas 1–6, 8, 9, and 11 have no such test. Schema 7 is the released database, and its path runs 8→9 and 9→10, so those two steps are covered there. 8, 9, and 11 as starting points are not.

`IncomingEpubGateTest.aPreservedWorkThatStillHasItsFileIsNeverReplaced` asserts the file is not in `epubFilesToWriteByWorkId` and does not assert that `epubPreservationStatusRaw` is still `preserved`. A3-1 stays green under that test.

Smallest fix. Point `migrate9To10` and `migrate12To13` at the exported schema for that version, or delete them and keep the `migrateFromExportedSchema` tests. Add a merge test whose archive clock wins, whose archive status is `notPreserved`, and whose local status is `preserved`, and expect `preserved`.

## Unconfirmed

- `epubDigest` is copied onto the row when the archive clock wins, or when the local digest is blank (`BackupMergeService.kt:796` and `:832`). iOS does not restore it (`KudosBackup.swift:4523-4532`) because a digest of bytes that never arrived makes the next sync skip the download. Android's sync-down compares the manifest digest to a hash of the local file (`SyncRepository.kt:649-654`), and sync-up publishes a hash of the bytes it uploads (`SyncRepository.kt:286` and `:351-352`). I could not show the permanent skip on Android's own sync. Confirm with a same-size EPUB whose stored digest was copied from the archive and is then used as the skip key without hashing the file, including a manual `.kudosbackup` export (that path does not recompute).
- `BackupMappers.toBackupWork` fills `progressModifiedAt` from `lastReadDate` when the column is null, and fills `lastModifiedAt` from `dateAdded`. Both importers already fall back at apply time. Confirm with a row that has `lastReadDate` and a null `progressModifiedAt`, exported by Android and merged on iOS, where iOS would have omitted the key and chosen the other winner.
- `DatabaseChangeTracker` does not observe `reading_favorites`, `fandom_read_watermarks`, bookmarks, saved searches, fonts, or tags. `syncHasPendingChanges` is set by the tracker and cleared after a successful sync. The periodic worker and `KudosApplication.maybeRunFolderSync` do not read the flag, so a missing observer does not by itself skip a sync. Confirm only if some caller skips `runSync` when the flag is false.
- On an incoming-wins work, `assetIdentifier` is replaced (`BackupMergeService.kt:797`). iOS only fills an empty one (`KudosBackup.swift:4414-4416`). Android opens the EPUB by work id (`WorkFileStore.workEpubPath`). Confirm on an iOS restore of an Android export whose `assetIdentifier` is not `<uuid>.epub`.
- Android does not collapse two live annotations that share work, kind, and exact locator (`KudosBackup.swift:3950`). Both rows remain, so this is duplicate marks, which the regression matrix says should collapse. Confirm whether any later pass deletes one of them.
- `ao3Unavailable` is last-write-wins via `toSavedWork` (`BackupMappers.kt:287`). iOS ORs it (`KudosBackup.swift:4507`). A newer archive can clear a local "unavailable". I did not find a path where that deletes a file.

## What was not read

Not read line by line, or not re-read in full after the first pass: `BackupExporter.kt`, `BackupImporter.kt`, `BackupValidator.kt`, `BackupJson.kt`, `BackupPaths.kt`, `TombstoneSigning.kt`, `TombstoneTrustStore.kt`, `TombstoneLocalMigration.kt`, `KeyRevocationService.kt`, the DAO files, `EntityMappers.kt`, and the entity files other than the work, collection, queue, annotation, and tombstone columns cited above. `SettingsRepository` / `KudosSettingsDataStore` were not classified field by field into device-local versus backed up. `FolderSyncService.swift` was read around manifest backup and `readChangedRemoteAssets`, not all 1,092 lines. `TombstoneSigning.swift` and `Models.swift` were not read through. `KudosBackup.swift` sections for fonts and originals were sampled, not every branch. `DECISIONS.md` entries that are only UI were scanned by title. Schema JSON 1–14 was diffed for added versus dropped columns in the first pass of this audit and not opened again while writing this file. Tests under `android/app/src/test` were sampled (`KudosDatabaseMigrationTest`, `IncomingEpubGateTest`, `BackupRestoreSecurityTest`, `BackupTrustPhase2Test`, `BackupCompatibilityTest`, parts of `SyncRepositoryTest`); the rest were not. No test was executed.

## Triage (Claude, 2026-10-08, first pass)

- **A3-1 real, fixed.** A local "preserved" is the floor, as iOS's `apply`; an archive may
  promote and never demote. Test `aWinningArchiveNeverDemotesAPreservedWork` (two passes).
- **A3-2 real, fixed.** File Merge of a work in Recently Deleted clears the deletion and then
  merges by the clocks. Test `fileMergeBringsBackADeletedWorkAndKeepsItsNewerState`. An older
  test expected the archive's title on a row whose own clock was newer; its expectation now
  follows iOS's rule. **Not done: the saved-work tombstone is still not retracted (A3-5).**
- **A3-3 to A3-9 and the six unconfirmed suspicions: not yet verified.** Each is in the most
  data-sensitive code in the app: read both sides line by line and add a test before each
  change. A3-5 (File Merge leaves collections and queues deleted, and leaves the work's
  tombstone) and A3-6 (one unknown tombstone type fails the whole merge) first.
