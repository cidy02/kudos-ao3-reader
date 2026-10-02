# Brief 2b-ii Result: Reading Log and Queue Tags

Implemented additive v8 backup fields for `readingSessions`, `readingFavorites`,
`fandomReadWatermarks`, and queue `tagNames`.

## iOS rules found

- Reading sessions match by record ID. A restored session remaps `workID` when
  its archived work merged into a different local UUID; detached history remains.
- Reading favourites match by ID first, then exact `(kindRaw, targetKey)`.
  Work-favourite targets follow the same work-ID remap.
- Fandom watermarks match by ID first, then exact raw `fandomName`.
- Reconcile applies an incoming matched row when its `lastModifiedAt` is at
  least the local value. Merge preserves a same-ID local row; target/name matches
  still use LWW. Replace removes unmatched rows. Accepted newer tombstones suppress
  stale incoming and existing rows; Replace bypasses tombstones and mints them for
  omitted rows.
- Queue tags match exact trimmed names and reuse shared tags. Merge/Reconcile are
  union-only. Replace removes missing queue cross-references but never deletes the
  shared `Tag` rows. Export sorts names.

## Android locations

- Wire records/defaults: `backup/BackupManifest.kt`
- Room/snapshot mappings: `backup/KudosBackup.kt`, `backup/BackupMappers.kt`
- Identity, LWW, tombstone, Replace, and queue-tag rules:
  `backup/BackupMergeService.kt`
- Room capture/apply: `backup/BackupRepository.kt` through `ReadingLogDao` and
  `TagDao`
- Tombstone type parity: `core/model/SyncModels.kt`
- Coverage: `backup/BackupReadingLogTest.kt`
