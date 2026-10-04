# 5b result: a converted import's original, through the backup and the sync folder

Done by Claude (no agent is available until 2026-10-06). Three commits: `28231dac` (the backup),
`9cb02ad4` (the sync folder), and the one this file is in (the golden files and tests).

## What was wrong

iOS keeps the file a converted import was made from (a PDF, HTML, text or ZIP), and a record of
the conversion, in `Originals/`: in every backup archive and in the sync folder. Android's
restore dropped them, Android's export wrote none (not even Android's own), and Android's folder
sync never looked at `Originals/`. A library that passed through Android lost them.

A second fault, found on the way: an original over Android's 128 MB per-entry limit made the
**whole restore fail**. It is now left out, and the rest restores.

## What changed

| Rule (iOS) | Android now | Test |
|---|---|---|
| A backup carries each work's original as `Originals/<UUID>.<ext>`, and its record as `<UUID>.conversion.json` (`KudosBackupExport`) | the same names, the id in capitals | `aBackupCarriesAnOriginalAndItsRecordToAnEmptyLibrary` |
| A restore writes an original under the id its work has here (`restoredWorksByArchivedID`) | the merge's id remap | `anOriginalFollowsItsWorkToTheIdItHasHere` |
| Never over an original already here, and never beside one | the same | `anArchivesOriginalNeverGoesOverOrBesideOneAlreadyHere` |
| A name that is not `<work>.<ext>` is ignored | the same | `aFileInOriginalsThatIosWouldNotHaveWrittenIsIgnored` |
| The record is not the original (`existingOriginalDocumentURL`) | `findOriginal` skips it; it is removed with its original | `theConversionRecordIsNotMistakenForTheOriginal` |
| Sync-up writes originals into the folder (`writeSyncDirectoryContents`) | streamed, and only when the folder has none of that name and size | `syncUpWritesAnOriginalAndItsRecordUnderIosNames` |
| Sync-down fetches one only for a listed work, and only when this device holds none (`readChangedRemoteAssets`) | the same | `syncDownBringsAnOriginalThisDeviceLacks`, `syncDownLeavesALocalOriginalAlone` |
| An original whose work is no longer listed is pruned; a file not shaped like ours is left alone (`removeOrphanedOriginals`) | the same, and only when a prune is allowed at all | `anOriginalOfAWorkNoLongerListedIsPrunedAndAStrangersFileIsNot` |

## With each app's own code

The golden files now hold a converted import:

- iOS's archive (`ios-export.kudosbackup`) has `Originals/…001.html` and its record. Android's
  `CrossPlatformRestoreTest` restores it, finds both on the device, exports, and finds both in its
  own archive byte for byte; then restores that archive on a second device and finds them again.
- Android's archive (`android-export.kudosbackup`) is restored by iOS's
  `CrossPlatformBackupTests`, with the seeded copies removed first so the restore has to bring
  its own: the original and the record are there, and the record decodes to what iOS wrote.
- The sync folders the same way (`ios-sync-folder/`, `android-sync-folder/`,
  `CrossPlatformFolderSyncTests`, `SyncRepositoryTest`).

All pass on both sides. Android gate: 1,232 tests.

## The conversion record: passed through, not ported

Android writes no conversion record of its own. It stores the one that arrives, byte for byte,
and writes it back out. Two consequences:

- An original imported on Android has no record. iOS reads that as "no record", which only costs
  it the ability to tell that the EPUB was made by an older converter.
- A record is taken only together with the original it describes. iOS takes a record whenever it
  has none; on iOS a local original always has its own record, so the two cannot disagree there.
  On Android a local original never has one, and taking another device's record for it would
  describe the wrong file.

## Limits and leftovers

- An original over 128 MB is left out of an Android backup and of an Android restore. iOS allows
  1 GB an entry. Android reads a whole archive into memory, so this needs streaming first.
- The directory importer (`BackupImporter.importV1Directory`) does not read `Originals/`. Only
  tests call it.
- In the sync folder, a work whose original was imported separately on two devices as two kinds
  of file has both in `Originals/`. Each device keeps its own. The same happens between two
  iPhones.
- Sync-up compares an original by size only (marked in the code). One re-imported at exactly the
  same size is not uploaded again.
