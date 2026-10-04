# 5a result (parts 1 to 3)

Done by Claude: Codex's weekly limit ran out before it could start. Part 1 (`d60ff5a4`) is the
folder's layout and what each app writes, reads and deletes. Part 2 is when an incoming EPUB may
replace a local one. Part 3 is which EPUBs a sync-down reads. The rest of the brief is listed at
the end as not done.

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

## Part 2: when an incoming EPUB may replace a local one

iOS decides in `KudosBackupService.mayReplaceEPUB` and checks the bytes in
`ReadingQueueService.replaceEPUB` (`EPUBDocument.inspectPackage`). Android differed four ways:

| Case | iOS | Android before | Now |
|---|---|---|---|
| The local work is **preserved** and still has its file | never replaced, however new the archive | replaced by a newer archive | never replaced |
| The incoming bytes are **not a readable EPUB** (garbage, or a copy cut off part-way) | skipped; the local file, `hasEPUB` and preservation are untouched | written over the local file | skipped |
| The record says it has an EPUB but **the file is gone** | filled in (iOS marks such a work `.missingFile` at launch) | filled only by a newer archive | filled in |
| File Merge of a work in **Recently Deleted** | bytes replaced only by a newer archive | always replaced | as iOS |

The rule is one pure function, `mayReplaceEpub` in `BackupMergeService.kt`, as on iOS. The check
on the bytes is `EpubImportMetadata.isReadablePackage`: the ZIP is whole (it has its end record)
and its package document lists at least one readable spine item. It reuses the OPF reader the
importer already had, which is why this fix touches one file outside `backup/`.

It applies to every restore, not only folder sync: the gate is in the shared merge. Replace
Library and brand-new records are unchanged (they take the archive's file, if it is readable).

Tests: `IncomingEpubGateTest` (9 tests: the rule case by case, the package check, and each row
of the table through `BackupMergeService.merge`), and
`SyncRepositoryTest.syncDownRejectsAnInvalidEpubWithoutOverwritingTheLocalCopy` (iOS's test of the
same name, with the folder's record the newer one). Three older fixtures used placeholder text
as EPUB bytes and now use a real EPUB. The iOS-written golden archive still restores with both
its EPUBs, so Android's check accepts what iOS builds.

**Android is stricter than iOS in one place, kept:** on equal clocks iOS takes the incoming copy
(`shouldApplyIncoming` uses >=) and Android keeps the local one. It only ever keeps a file.

## Part 3: which EPUBs a sync-down reads

| | iOS (`readChangedRemoteAssets`) | Android before | Now |
|---|---|---|---|
| Which EPUBs are read from the folder | only those whose size differs from the local file, or whose size is equal and whose digest differs | every listed EPUB, on every sync | as iOS |
| How many are held in memory | the changed ones | the whole library at once | at most one batch (32 MB, then the next) |
| `epubDigest` in the manifest it writes | the digest of the file (`Storage.fileDigest`) | whatever an earlier manifest said, never recomputed | the digest of the bytes it uploads |

A library of a thousand works held several hundred megabytes in one map on every sync, which
is more than an Android app's heap: the sync would crash rather than fail. And a stale digest in
Android's manifest could make another device skip a changed book.

The manifest is merged once per batch. A merge that brings nothing new changes nothing (every
sync already merged the whole manifest again), and each work is offered once.

Same as iOS, and a known limit: with no digest in the manifest (one written by Android 0.2.1 or
0.2.2, or by an old iOS build), an EPUB of exactly the same size counts as unchanged.

Tests in `SyncRepositoryTest`: `aCorrectedBookOfTheSameLengthIsStillFetched` (iOS
`EqualSizeEPUBStillSyncsTests`), `withNoDigestAnEqualSizeCountsAsUnchanged`,
`syncUpWritesTheDigestOfTheEpubItUploads`, `aSyncDownLargerThanOneBatchStillBringsEveryEpub`.

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
- **Android's stored digest is still only carried through.** The sync folder's manifest now has
  the real one, but a `.kudosbackup` file exported from Android still carries whatever digest an
  earlier manifest gave the work. The fix is to compute it where Android writes an EPUB
  (`WorkFileStore.writeWorkEpub`'s callers), as iOS's `replaceEPUB` does.
- **Sync-up still reads the folder's copy to compare** when the sizes are equal
  (`writeIfChanged`). The digest could settle that too.
- **No size limit on an EPUB read from the folder**, on either platform.
- **A manifest that changes between this device's read and its write.** iOS compares the
  manifest's date before writing and skips the prune if another device wrote in between. Android
  only knows that it read a manifest.
- **Android shows no restore summary.** iOS tells the reader "Skipped N invalid EPUB files to
  protect your existing copy." and how many works arrived without their EPUB. Android counts
  neither.
- **Downloads and imports.** iOS runs the same package check on an AO3 download and on a file the
  reader imports. Android's importer checks only that the file is a ZIP.
- **Each app's older sync file.** iOS folds `KudosLibrary.kudosbackup` (a folder package);
  Android folds `Kudos.kudosbackup` (a zip). Neither reads the other's. Nothing is misread.

## Not done from the brief

The test-by-test table against iOS's seven test files (65 tests); tombstones (newest wins,
signatures, sweeping existing records); conflict copies; what stops a sync from running at all.
