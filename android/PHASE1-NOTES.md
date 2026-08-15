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
- `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupTrustPhase1Test.kt` (new)
- `android/app/src/test/java/io/github/cidy02/kudos/works/WorkIdentityIndexTest.kt`

## Behaviour

- **Merge (default, also folder sync):** add / LWW-update works. Do not delete
  local works. Do not upsert incoming tombstones. Do not suppress from incoming
  tombstones. Tombstones already in Room still suppress.
- **Replace Library:** this device’s works / collections / queues / annotations
  become the snapshot. Fonts and appearance stay. Incoming unsigned tombstones
  are not persisted. Removed rows are deleted via existing DAO deletes **without**
  minting tombstones, so a later Merge of a real backup can insert them again.
- **File-import UI** (`BackupScreen`): empty library → one Restore button.
  Non-empty → counts, Merge vs Replace, “Remove N works…” checkbox, 1.5s delay,
  pause-sync prompt (default Pause; folder is not wiped), timestamped safety
  `.kudosbackup` in app-specific Documents first.
- **Ledger companions:** `lastModifiedAt` is `min(value, exportedAt)` and
  rejected if `> now+24h`. `sourceURL` is canonicalized like iOS
  `WorkTags.canonicalAO3WorkURL` (work pages, chapters, `/downloads/<id>`).

Merge still LWW-updates overlapping work rows. That matches current iOS
`KudosBackup.restore` `apply`, existing Android LWW tests, and folder-sync
updates. Skip-apply on overlap would stop progress/metadata from crossing
devices.

## Rejected legitimate input (Phase 1)

Incoming deletion claims from a `.kudosbackup` or the Library Sync Folder are
ignored. **Your deletes on phone A will not appear on phone B** until Phase 2
signed tombstones. Owner accepted this short inconsistency.

Replace of an unsigned file cannot plant suppressors that block a later Merge
of the user’s real backup.

## Tests

Production entry points: `BackupMergeService.merge`,
`BackupRepository.importPackage`, `SyncRepository.runSync` (folder-sync ingest).

New / updated:

- `BackupTombstoneTrustPhase1MergeTest` (7)
- `BackupTrustPhase1Test` (5) — Room `importPackage` + folder-sync ingest
- `exportsAndReimportsTombstonesInManifest` still asserts the ZIP carries
  tombstones; merge adopt assertion is now `0` (unsigned incoming are dropped)
- `WorkIdentityIndexTest.canonicalUrlHelper` covers `/downloads/<id>`

GREEN last (`:app:testDebugUnitTest`): **779 tests, 0 failures, 0 errors**.

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

- Replace does not send removed works through Recently Deleted (a standing
  soft-deleted row would block “later Merge must insert”). DAO delete without
  a tombstone is used instead.
- Replace does not rewrite bookmarks / saved searches to the snapshot (they
  still merge). Fonts/appearance stay by spec.
- Safety backup is app-specific Documents (`getExternalFilesDir`), not the
  shared system Documents folder.
- No Compose UI test of the 1.5s Replace arming / pause-sync checkbox.
- Phase 2 Ed25519 not implemented (out of scope).
