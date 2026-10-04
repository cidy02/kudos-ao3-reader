# 5a result (first part)

Done by Claude: Codex's weekly limit ran out before it could start. This covers the part of the
brief that matters most, the folder's layout and what each app writes, reads and deletes. The
rest of the brief is listed at the end as not done.

## Most important: the two apps misread, and deleted, each other's EPUBs

| | iOS (`Services/FolderSyncService.swift`) | Android before (`backup/SyncRepository.kt`) |
|---|---|---|
| An EPUB's name | `Works/<UUID IN CAPITALS>.epub` (`work.id.uuidString`) | `Works/<uuid in lowercase>.epub` |
| Reading | exactly that path | `findFile` on exactly the lowercase name |
| Kept after a sync-up | the EPUB of **every work the manifest lists**, whether or not this device holds a copy | only the EPUBs of works **this device holds a file for** |
| Pruned | any other name, compared exactly; only when this device's view of the folder is current | any other name, compared exactly; always |

So, in a folder shared by an iPhone and an Android phone:

- Android never found the EPUBs iOS wrote: works arrived without their files.
- Android then deleted iOS's files as orphans.
- iOS deletes Android's lowercase files as orphans, and on case-sensitive storage does not find
  them either.

And between two Android devices: a device that had removed its download of a work deleted the
folder's copy of it on its next sync, though the manifest still listed the work.

## Fixed on Android

- EPUBs are written under iOS's name (`BackupPaths.iosEpubAssetIdentifier`).
- An EPUB is found under either case, from one listing of the folder (a `findFile` per work
  listed it every time).
- A lowercase file left by an older Android build is renamed to iOS's name the next time this
  device writes it.
- Every work and every font the outgoing manifest lists is kept, as on iOS.
- Nothing is pruned when the folder holds a manifest this run could not read.
- Pruning compares names without regard to case, and skips hidden files, as iOS does.

## Tests

New in `SyncRepositoryTest` (17 tests, all passing): `syncUpNamesEpubsTheWayIosDoes`,
`syncDownFindsAnEpubIosWrote`, `aLowercaseEpubFromAnOlderAndroidBuildIsFoundAndKept`,
`syncUpKeepsTheEpubOfAListedWorkThisDeviceDoesNotHold`,
`nothingIsPrunedWhenTheFoldersManifestCannotBeRead`. The older tests look an EPUB up by work
rather than by a lowercase name. The rename itself is not asserted: the test host's file system
folds case.

## Found and not changed (for the owner, or a later brief)

- **iOS compares names exactly** when it reads and when it prunes. Released Android builds (0.2.1,
  0.2.2) wrote lowercase names. An iPhone that joins such a folder before the Android device has
  updated and synced would not find those EPUBs on case-sensitive storage, and would prune them.
  The safe fix is for iOS to compare without regard to case too. It only ever keeps more.
- **Mixed Android versions.** An Android device still on an older build does not find the new
  names and prunes them, as it already pruned any EPUB it held no copy of. Each device re-uploads
  what it holds, so nothing is lost from a library, but the folder churns until both update.
- **`Originals/`.** iOS syncs imported originals there (`<workID>.<ext>` and
  `<workID>.conversion.json`). Android neither reads nor writes that folder, and never deletes
  from it.
- **Incoming EPUBs are not checked.** iOS inspects an incoming EPUB before it replaces a local
  one, and never replaces a preserved work's bytes. Android writes whatever the folder holds. Not
  looked at further.

## Not done from the brief

The test-by-test table against iOS's seven test files; tombstones (newest wins, signatures,
sweeping existing records); the order of sync-down and sync-up under a stale device; conflict
copies; what stops a sync from running at all.
