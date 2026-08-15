# iOS Phase 1 — backup trust (Opus + Grok finish)

Opus 4.6 started `KudosBackup.restore` + Settings import fork, then hit Antigravity
quota (`claude-opus-4-6-thinking` resets ~3h). Grok finished the compile-breaking
UI, split folder-sync from file Merge, and added tests.

## Files

- `kudos-ao3-reader/Services/KudosBackup.swift` — `BackupImportMode`, no incoming tombstone adopt
- `kudos-ao3-reader/Settings/SettingsView.swift` — Merge vs Replace Library sheet
- `KudosTests/KudosBackupTests.swift` — five production-entry tests
  (two original + three merge/reconcile overlap + folder-sync tests)

## Modes (locked three-mode spec)

Do not collapse file Merge and folder sync. Incoming unsigned tombstones
are dropped in every mode. Local tombstones already on this device still
suppress resurrection (except Replace, which ignores even local suppressors
so the snapshot can load).

- **reconcile** (`BackupImportMode.reconcile`, default of
  `KudosBackupService.restore`): Folder sync and any caller that omits
  `mode`. Last-writer-wins `apply` on overlap. Add missing works. Do **not**
  delete local works omitted from the snapshot. Incoming tombstones are not
  inserted and are not used to build `TombstoneIndex` for this batch.
- **merge** (`BackupImportMode.merge`): File-import **Merge** button
  (`SettingsView.restorePendingBackup` default). Add-only. Insert works not
  already in the active library. If the identity hit is `isPendingDeletion`,
  undelete then apply. If the hit is an *active* work, skip `apply` — local
  title, progress, tags, and EPUB stay. Do not remove local works. Still
  create collections/queues from the file when they introduce new works.
- **replaceLibrary** (`BackupImportMode.replaceLibrary`): File-import
  **Replace Library** after `ReplaceLibraryConfirmationView` +
  `makePreReplaceBackup()`. This device’s works / progress / collections /
  queues / annotations become the snapshot. Fonts, appearance, and AO3 login
  stay. Omissions are soft-deleted (Recently Deleted) **without** minting
  `SyncTombstone`. The file’s unsigned tombstones are not persisted.
  Replace is this device only; it does not wipe the sync folder.

Empty library / first run: one **Restore from Backup** (functionally Merge
into empty). Folder sync stays implicit **reconcile** forever.

## What legitimate input is rejected

Incoming deletion claims from a file or sync folder. Deletes do not cross devices until Phase 2.

## Tests

Present (production-entry `KudosBackupService.restore`, not a helper):

- `incomingUnsignedTombstonesAreNotAdoptedOnMerge` — Merge of a file that
  carries a `savedWork` tombstone must not persist that tombstone, and must
  still insert the work the file also contains.
- `replaceDoesNotLeaveStandingTombstonesThatBlockLaterMerge` — after
  Replace, omitted local works are gone from the active library, no new
  `SyncTombstone` rows exist, and a later Merge of a pre-Replace work must
  insert it.
- `fileMergeDoesNotOverwriteActiveOverlapTitleProgressOrUserTags` — File
  Merge (`mode: .merge`) leaves an active overlap’s title, `lastSpineIndex`,
  and user tags unchanged even when the file is `lastModifiedAt`-newer.
- `defaultReconcileAppliesLastWriterWinsOnOverlap` — omitting `mode`
  (default `.reconcile`) LWW-applies a newer overlap title and progress.
- `defaultReconcileDropsIncomingUnsignedTombstonesAndStillInsertsPresentWork`
  — default restore of a snapshot that also carries an unsigned `savedWork`
  tombstone does not persist that tombstone and still inserts the work
  present in the same snapshot.

`incomingUnsignedTombstonesAreNotAdoptedOnMerge` and
`replaceDoesNotLeaveStandingTombstonesThatBlockLaterMerge` were left
unchanged.

Folder-sync ingest uses default `.reconcile` so existing FolderSyncTests still hit LWW apply.

## Harness / mutations

Filter: `-only-testing:KudosTests/KudosBackupTests` matches **0** Swift
Testing cases (suite is nested under `PersistenceGateSuites`). The run
that actually executed tests used
`-only-testing:KudosTests/PersistenceGateSuites/KudosBackupTests`.
Never passed `-sdk iphonesimulator` with the UDID destination.
UDID `C71780B1-35DE-4E5E-ABCD-2AB66BCB28B0` (iPhone 17 Pro Max, iOS 26.5).

GREEN last (`xcrun xcresulttool get test-results summary --path /tmp/tomb-ios.xcresult --format json`):

```
result: Passed
passedTests: 30
failedTests: 0
totalTestCount: 30
```

`totalTestCount` is not 0.

### Mutation A — restore unconditional incoming-tombstone adopt

Temporarily re-inserted the pre-Phase-1 adopt loop (`for archived in
contents.manifest.tombstones { context.insert(...) }` then
`TombstoneIndex(localTombstones)`). Reverted after.

RED (durations > 0):

- `incomingUnsignedTombstonesAreNotAdoptedOnMerge()`  
  `"Incoming unsigned tombstone was persisted"`  
  failed after **0.223 seconds**
- `replaceDoesNotLeaveStandingTombstonesThatBlockLaterMerge()`  
  `Expectation failed: try context.fetch(FetchDescriptor<SyncTombstone>()).isEmpty`  
  failed after **0.023 seconds**
- `defaultReconcileDropsIncomingUnsignedTombstonesAndStillInsertsPresentWork()`  
  `"Incoming unsigned tombstone was persisted on reconcile"`  
  `"Reconcile must still insert a work present in the same remote snapshot"`  
  failed after **0.127 seconds**

### Mutation B — drop on explicit `.merge`, still adopt on default `.reconcile`

Wrapped the same adopt loop in `if mode != .merge`. Reverted after.

`incomingUnsignedTombstonesAreNotAdoptedOnMerge()` stayed GREEN
(passed after **0.011 seconds**).

RED (durations > 0):

- `defaultReconcileDropsIncomingUnsignedTombstonesAndStillInsertsPresentWork()`  
  `"Incoming unsigned tombstone was persisted on reconcile"`  
  `"Reconcile must still insert a work present in the same remote snapshot"`  
  failed after **0.210 seconds**
- `replaceDoesNotLeaveStandingTombstonesThatBlockLaterMerge()` also RED
  (Replace is not `.merge`, so the weaker substitute still adopted)

Mutations reverted. GREEN last as above.

## Opus leftovers Grok filled

- `ReplaceLibraryConfirmationView` + `makePreReplaceBackup` (referenced, not defined)
- `BackupImportMode.reconcile` so folder sync does not inherit add-only merge
