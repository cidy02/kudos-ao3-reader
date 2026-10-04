# Review brief: the sync and backup changes of 2026-10-04 (briefs 5a and 5b)

You are reviewing, not fixing. Rules (binding): read only; change no file, and don't commit,
push, or switch branches; never sign in and never contact archiveofourown.org; your sandbox
can't run Gradle or Xcode, so reason from the code and say when a claim needs a test run to
settle.

## What to review

Eleven commits by Claude on `android/redesign-parity`, all in one day and none reviewed by
anyone else. They change how the Android app syncs through a shared folder and how it restores
a backup: code that can lose a reader's library if it is wrong.

```
git diff f29dd32e..HEAD -- \
  android/app/src/main/java/io/github/cidy02/kudos/backup \
  android/app/src/main/java/io/github/cidy02/kudos/files/WorkFileStore.kt \
  android/app/src/main/java/io/github/cidy02/kudos/works/EpubImportMetadata.kt
```

Nine files, about 540 lines added. The tests are beside them under
`android/app/src/test/java/io/github/cidy02/kudos/backup/` (`SyncRepositoryTest`,
`IncomingEpubGateTest`, `OriginalsRoundTripTest`, `QueueTombstoneMergeTest`,
`MacReadingPositionMergeTest`, `BackupTrustPhase2Test`, `CrossPlatformRestoreTest`). Ignore
every other change in that range (it also holds UI work).

What each commit was meant to do, and the iOS rule it copies, is written down:
`docs/android-port/briefs/5a-result.md` and `5b-result.md`. Read them first, then check the
code against them: a claim there that the code does not keep is a finding.

| Commit | Meant to |
|---|---|
| `d60ff5a4`, `94f1e444` | name an EPUB in the sync folder as iOS does (UUID in capitals); find either case; keep every work and font the manifest lists; prune nothing when the manifest could not be read; replace an old lowercase file by delete and recreate |
| `932d1e93` | let an incoming EPUB replace a local one only by iOS's rule (`mayReplaceEpub`), and only if it is a readable EPUB (`EpubImportMetadata.isReadablePackage`) |
| `f4da80c3` | read from the folder only the EPUBs that changed (size, then digest), 32 MB at a time, merging the manifest once per batch; write the real digest into the manifest |
| `de066460` | prune nothing when the manifest's date moved between this run's read and its write |
| `0c7db7b0` | remove a saved search this device still has when a trusted tombstone covers it; `BackupRepository` deletes saved searches the merge removed |
| `0370ebad` | let a trusted tombstone replace the row it shares an id with, only for the same record and only when later |
| `d8f0d17e` | merge the Mac's reading percent (`legacyReaderProgress`) with the reading progress, not with the metadata |
| `b799dda8` | skip a font over the limits instead of failing the sync; prune nothing while a font is outstanding |
| `28231dac`, `9cb02ad4` | carry `Originals/` (a converted import's original file and its conversion record) through the backup archive and the sync folder |

The reference is the iOS app, at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`:
`Services/FolderSyncService.swift`, `Services/KudosBackup.swift` (`restore`, `mayReplaceEPUB`,
`applyTombstonesToExisting`, the originals loop), `Services/KudosBackupExport.swift`,
`Services/PersistenceSync.swift` (`applyProgress`, `tombstoneResolution`),
`Services/Storage.swift`, `Services/WorkConversionRecord.swift`. The owner's rule is that the
two apps behave the same and that nothing is lost in a backup or a sync.

## What to look for, in this order

1. **Anything that can delete or overwrite what it should keep.** For each of these, try to
   construct the sequence of states that loses a file or a record:
   - the three prunes in `SyncRepository` (works, fonts, originals) and every way
     `folderViewIsCurrent` is set: a manifest restored from `.bak`, conflict copies, a font left
     for a later pass, the manifest's date moving mid-run, a provider that reports no dates;
   - the lowercase file's delete-then-create in `writeIfChanged` and `copyIfSizeDiffers`, if the
     run dies between the two;
   - `BackupRepository.applyMergeResult` now deleting every saved search that is not in the
     merged set: can a search made while the merge runs be deleted? Is the merged set ever not
     the whole set (a merge mode, an early return)?
   - the tombstone row replacement in `BackupMergeService`: can a trusted peer use it to make a
     local deletion suppress less, or suppress a different record?
   - `mayReplaceEpub` deciding by the file on disk, not the `hasEpub` flag: is there a state in
     which a good local file is now replaced, or a missing one is not filled?
   - the originals restore in `BackupRepository.restoreOriginals`: over, beside, or under the
     wrong work.
2. **Calling the merge more than once per sync.** `SyncRepository.importManifest` now calls
   `backupRepository.importPackage` once per batch of EPUBs and once per batch of originals,
   each time with the whole manifest and the same fonts. Is every part of
   `BackupMergeService.merge` and `applyMergeResult` safe to repeat: the font merge (a
   colliding font getting a new suffixed copy each pass?), collection and queue name
   collisions, tombstone minting, the unknown-signer record, counts?
3. **Good files refused.** `isReadablePackage` wants a ZIP end record and an `.opf` with a
   spine item among the first entries it scans. Which real EPUBs would it wrongly refuse (a
   ZIP64 file, a package document not named `.opf`, one past the scan limit, an EPUB 2 with a
   quirk)? A refused EPUB is a book that silently does not arrive.
4. **Where Android still differs from iOS** in these paths, beyond what the result files admit.
5. **Tests that prove less than they claim.** The host file system ignores letter case; the
   documents provider is a fake. Which of the new tests would still pass if the fix they name
   were removed?
6. **The trust boundary.** Anyone who can write to the sync folder can put files there. Names
   (`BackupPaths.parseOriginalFileName`), sizes (an EPUB read from the folder has no limit; an
   original is checked by the size the provider reports), and anything that reads a whole file
   into memory.

## What to return

Your final message is the review; write no file. Findings first, most severe first. For each:
the file and line; what is wrong; the concrete sequence (state, then input, then the wrong
outcome); and the smallest fix you would make. Then a short list of what you checked and found
sound, so it is clear what was covered. Say plainly which findings you are sure of and which
are suspicions that need a test. Don't pad: no finding is better than a weak one.
