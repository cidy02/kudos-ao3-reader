# Brief 5a: folder sync, Android against iOS

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't change Room schemas, migrations, or the backup format** (manifest version, key
names, file names). If a fix seems to need one, stop and describe it in the result instead. Don't
edit `TASKS.md`. Your sandbox can't run Gradle; Claude builds and tests afterwards, so make it
compile by reading the real symbols you use.

The owner's rule: iOS and Android must behave the same, and a library synced through a shared
folder by one must be read by the other with nothing lost. Backup and restore are proven both ways
(`backup/CrossPlatformRestoreTest.kt` and its golden archives). **Folder sync has never been
checked against iOS.** Check it, test it, and fix what differs.

Read first:

- `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`: "Merge rules" and "Folder sync safety";
- iOS (the lane is `/Users/cidy02/kudos-ios-polish`): `kudos-ao3-reader/Services/FolderSyncService.swift`,
  `FolderSyncBackgroundTask.swift`, `PersistenceSync.swift`, `TombstoneSigning.swift`, and the tests
  `KudosTests/FolderSyncTests.swift`, `EqualSizeEPUBStillSyncsTests.swift`,
  `MergeMissingEPUBRecoveryTests.swift`, `NewestTombstoneWinsTests.swift`,
  `StaleSyncUpKeepsRemoteAssetsTests.swift`, `TombstoneSweepsExistingRecordsTests.swift`,
  `PersistenceSyncTests.swift`;
- Android (`android/app/src/main/java/io/github/cidy02/kudos/backup/`): `SyncRepository.kt`,
  `FolderSyncWorker.kt`, `BackupMergeService.kt`, `BackupPaths.kt`, `PersistenceGate.kt`,
  `TombstoneSigning.kt`, and `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt`.

## Do this

1. **Compare, rule by rule.** At least: the folder's layout and every file name in it (letter case
   included: T-354 was an uppercase/lowercase EPUB name that lost files on restore); what is
   written, and in what order; what a sync-down does before a sync-up; when an EPUB is copied
   again (size, digest, dates); what happens when the folder's EPUB is missing; what a stale device
   may and may not remove from the folder; tombstones (newest wins, signatures, sweeping records
   that already exist); and what stops a sync from running at all.
2. **One Android test per iOS test.** For each test in the iOS files above, find the Android test
   that pins the same rule. Where there is none, write it as a JVM unit test beside
   `SyncRepositoryTest.kt`, using the fakes already there (`FakeTempDocumentsProvider`). Use the
   same scenario and the same expected outcome as the iOS test.
3. **Fix differences in `backup/` only**, where iOS's rule is clear from its code and tests. Cite
   the iOS file and line in a comment on each fix. If Android is stricter than iOS in a way that
   protects data, leave it and report it.
4. If the two apps would misread each other's folder (a name, a path, a field), that is the most
   important finding: put it first in the result, with the exact strings on each side.

## Result

Write `docs/android-port/briefs/5a-result.md`: a table of rule, iOS test, Android test (existing or
new), and verdict (same, fixed, differs and why not fixed); every file changed; anything that
needs a schema or format change; anything you could not determine from the code.
