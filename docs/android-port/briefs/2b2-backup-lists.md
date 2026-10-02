# Brief 2b-ii: back up and restore queue tags and the reading log, as iOS does

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network.
Leave changes uncommitted. Gradle may not run in your sandbox. If it can't, compile carefully by
reading and say so in the result; Claude runs the gate and sends failures back.

Context: Room schema 11 already has the tables `reading_sessions`, `reading_favorites`,
`fandom_read_watermarks` and `queue_tag_cross_refs` (`data/local/entity/ReadingLogEntities.kt`,
`data/local/dao/ReadingLogDao.kt`). Phase 2b-i (commit 63ecaf4e) added the scalar fields to the
backup. Read `docs/android-port/briefs/2b-backup-fields.md` and `2b-result.md` for the patterns
already established (`BackupJson`, `PresentNullJsonSerializer`, `fillQueueFields`, `chosenColor`).

## iOS reference (`kudos-ao3-reader/Services/KudosBackup.swift`)
- `KudosBackupManifest`: the top-level `readingSessions`, `readingFavorites` and
  `fandomReadWatermarks` arrays (~line 613), each defaulting to empty when absent.
- `KudosBackupReadingSession` (~1232), `KudosBackupReadingFavorite` (~1294) and
  `KudosBackupFandomReadWatermark` (~1328): keys, decode defaults, and how restore merges them.
  Find the apply code by searching for `readingSessions` and `fandomReadWatermarks` further down.
  Match its identity, last-writer-wins and tombstone rules exactly, and say in the result which
  rules you found.
- `KudosBackupReadingQueue.tagNames` (~1478) and the queue tag merge (~2853): union-only under
  merge and reconcile, matched on the exact trimmed name and reusing existing tags; under Replace,
  tags the snapshot lacks are dropped from the queue, but the `Tag` rows themselves stay.

## Android today
- `backup/KudosBackup.kt`: `BackupLibrarySnapshot` has no sessions, favourites, watermarks or
  queue tags.
- `backup/BackupRepository.kt` (and `BackupImporter.kt`, `SyncRepository.kt`): build the
  snapshot from Room for export, and write the merged snapshot back. Find both directions.
- `backup/BackupMergeService.kt`: `merge` returns the merged snapshot and a summary.
- `backup/BackupManifest.kt`, `BackupMappers.kt`.

## Do
1. Add the three lists to `KudosBackupManifest` (default empty) with record types matching the iOS
   keys, add `tagNames: List<String>? = null` to `BackupReadingQueue`, and add mappers in both
   directions.
2. Add the lists and a `queueTagNamesByQueueId: Map<String, List<String>>` to `BackupLibrarySnapshot`.
   Load them from Room for export, and write them back on import, through `ReadingLogDao` and
   `TagDao`, in the same transaction or flow the rest of the import uses.
3. Merge them in `BackupMergeService`, following iOS's rules for each.
4. Export sorts queue tag names, as iOS does (`.sorted()`).
5. Tests in `app/src/test/.../backup/BackupReadingLogTest.kt`:
   - a round trip of each list through export → JSON → import;
   - an older archive with no lists leaves local rows alone;
   - queue tags merge as a union, and Replace drops tags the snapshot lacks without deleting
     the `Tag` row;
   - a literal JSON snippet shaped like an iOS export decodes.
6. Write `docs/android-port/briefs/2b2-result.md` (under 400 words): the rules you found on iOS and
   where each lives on Android.

## Don't
Touch `ui/`, the screens, `works/WorkRepository.kt` download logic, or migrations (the schema is final
for this brief).
