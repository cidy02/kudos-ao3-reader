# Android Phase 1 — backup trust

Local-only work on `security-fixes/tombstone-trust`. Incoming unsigned
tombstones are dropped on file Merge, file Replace, and folder-sync ingest.

## Files

- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/KudosBackup.kt`
  (`BackupImportMode`, `BackupImportPreview`, `worksRemoved`)
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMappers.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkTags.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupTrustPhase1Test.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/works/WorkIdentityIndexTest.kt`

## Behaviour

Three restore modes. **Do not collapse file Merge and folder sync.**

- **Reconcile (default of `merge()` / `importPackage` / `importV2ZipBytes`;
  folder-sync ingest):** last-writer-wins on overlap. Add missing works. Do
  **not** delete local works omitted from the snapshot. Do not upsert incoming
  tombstones. Do not suppress from incoming tombstones. Tombstones already in
  Room still suppress. Tag union on overlap.
- **Merge (file-import Merge button only):** add-only. Insert works not already
  in the library. Keep the existing overlap row — title, progress, tags, and
  EPUB stay local. Do **not** overwrite EPUB. Do **not** union incoming tags
  onto an existing work. If the local hit is Recently Deleted (`isDeleted`),
  undelete and apply the file. Drop incoming tombstones.
- **Replace Library:** this device’s works / progress / collections / queues /
  annotations / **saved links (bookmarks)** / **saved searches** become the
  snapshot (R8). Fonts and appearance stay. Incoming unsigned tombstones are
  not persisted. Omitted **works** are soft-deleted into Recently Deleted
  (`isDeleted` + 90-day `WorkRepository.RECOVERY_WINDOW`) **without** minting
  tombstones and **without** deleting the EPUB (R9). Collections / queues /
  annotations / bookmarks / saved searches omitted from the file are dropped
  from this device (no tombstones). A later file Merge undeletes a
  Recently Deleted work that is present in the file (`bf81772`).
- **File-import UI** (`BackupScreen`): empty library → one Restore button.
  Non-empty → counts, Merge vs Replace, “Remove N works…” checkbox, 1.5s delay,
  pause-sync prompt (default Pause; folder is not wiped), timestamped safety
  `.kudosbackup` in app-specific Documents first. File Merge passes
  `BackupImportMode.MERGE`. Replace passes `REPLACE_LIBRARY`. Folder sync
  omits the mode so it stays `RECONCILE`.
- **Ledger companions:** `lastModifiedAt` is `min(value, exportedAt)` and
  rejected if `> now+24h`. `sourceURL` is canonicalized like iOS
  `WorkTags.canonicalAO3WorkURL` (work pages, chapters, `/downloads/<id>`).

Using file Merge for folder sync would freeze overlap on every peer. Using
folder LWW for file Merge would let a hostile file overwrite local
notes/progress.

## Rejected legitimate input (Phase 1)

Incoming deletion claims from a `.kudosbackup` or the Library Sync Folder are
ignored. **Your deletes on phone A will not appear on phone B** until Phase 2
signed tombstones. Owner accepted this short inconsistency.

Replace of an unsigned file cannot plant suppressors that block a later Merge
of the user’s real backup. File Merge of an unsigned file cannot overwrite
local overlap.

## Tests

Production entry points: `BackupMergeService.merge`,
`BackupRepository.importPackage`, `SyncRepository.runSync` (folder-sync ingest).

New / updated:

- `BackupTombstoneTrustPhase1MergeTest` — tombstone drop + MERGE add-only vs
  RECONCILE LWW at `BackupMergeService.merge`
- `BackupTrustPhase1Test` — Room `importPackage` MERGE/RECONCILE + folder-sync
  ingest (tombstones dropped; overlap still LWW on reconcile)
- `exportsAndReimportsTombstonesInManifest` still asserts the ZIP carries
  tombstones; merge adopt assertion is now `0` (unsigned incoming are dropped)
- `WorkIdentityIndexTest.canonicalUrlHelper` covers `/downloads/<id>`

GREEN last (`:app:testDebugUnitTest`): **794 tests, 0 failures, 0 errors**.

### Mutation A — restore unconditional tombstone adopt

Temporarily re-inserted the incoming-tombstone upsert into `merge`. RED:

- `mergeDoesNotAdoptOrSuppressWithIncomingTombstones`  
  `"incoming unsigned tombstones must not be adopted"`  
  time `0.04s`
- `importPackageDoesNotAdoptIncomingTombstones` also RED (incoming tombstone
  suppressed the work / landed in Room)

### Mutation B — drop on merge, still adopt on folder-sync `importPackage`

`mergeDoesNotAdoptOrSuppressWithIncomingTombstones` stayed GREEN (time `0.035s`).
RED:

- `folderSyncIngestDoesNotAdoptIncomingTombstones`  
  `"folder-sync must not insert the remote unsigned tombstone"`  
  time `3.212s`
- `importPackageDoesNotAdoptIncomingTombstones`  
  `"incoming unsigned tombstones must not be written to Room"`  
  time `0.035s`

Mutations reverted. GREEN last as above.

## Gaps / follow-up

Closed this pass (R1 / R2 / R4 / R8 / R9 / R10):

- File Merge **does** undelete Recently Deleted (`bf81772`). Active overlap
  still keeps title / progress / tags / EPUB.
- File Merge is add-only on existing annotation / collection-name / queue-name
  / membership-note IDs (R2). New annotation IDs on a work you already have
  are inserted (R10). Reconcile stays LWW.
- Replace confirmation counts (`BackupMergeService.preview`) **and restore
  apply** rematch works `ao3WorkID` → `WorkTags.canonicalAO3WorkURL` → record
  UUID (same order as iOS `WorkIdentityIndex`). The local row keeps its id;
  annotations / memberships / collection work IDs remap. A same-AO3 backup
  with a different UUID no longer inserts a second row.
- Replace snapshots bookmarks and saved searches (R8). Merge/reconcile still
  merge-add.
- Replace soft-deletes omitted works into Recently Deleted with no
  `SyncTombstone` and keeps the EPUB (R9). Later Merge undeletes.

Still open / out of scope:

- Safety backup is app-specific Documents (`getExternalFilesDir`), not the
  shared system Documents folder.
- No Compose UI test of the 1.5s Replace arming / pause-sync checkbox (R6).
- Phase 2 Ed25519 is in `android/PHASE2-NOTES.md`.
