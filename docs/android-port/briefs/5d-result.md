# Brief 5d result

Reference data-loss risk found (iOS, left untouched): in `KudosBackup.swift` restore's invalid-EPUB catch around 2495–2518, a new work supplied unusable bytes bypasses the missing-file branch that sets `remoteEPUBPending`. `SavedWork` initially defaults `hasEPUB` to true, but `ReadingQueueService.normalize` (around 326–328) and `PersistenceSync.swift` missing-asset reconciliation (around 366) set it false when the file is absent. Inferred consequence: that device can then publish `hasEPUB = false` despite the incoming promise. Android covers this case in Part 1. Also, iOS still ORs `isQueuedForLater` (around 4508); Part 2 follows this brief's explicit newer-snapshot rule. Existing 5c findings outside this brief are left alone.

Working on `android/agent-codex-5d` in this worktree only. No Gradle/Xcode run, sign-in, AO3 contact, commit, push, or branch switch. iOS reference at `/Users/cidy02/kudos-ios-polish/` is read-only. All compilation and runtime claims below require Claude's test run. Backup version, keys and asset layout remain unchanged.

## Part 1 — implemented; tests not run

- Added device-local `SavedWork.remoteEpubPending`, `WorkEntity` default `0`, both entity mappings, Room 14 and registered `MIGRATION_13_14`. No manifest field added. Claude must let KSP generate `android/app/schemas/.../14.json`; no fabricated schema supplied.
- `BackupMergeService.merge` sets the promise after every merge mode when `hasEPUB` was promised, no usable EPUB was accepted and no local file exists. It keeps an existing promise until bytes are written or explicitly removed. File presence decides `hasEpub`, including stale true flags with no file. `BackupRepository.applyMergeResult` clears pending after a successful EPUB write, and retains a promise if installation fails with no file.
- `SavedWork.toBackupWork` exports `hasEPUB = hasEpub || remoteEpubPending`; both ZIP export and sync use that mapper. `SyncRepository.importManifest` has only the requested `hasEPUB` guard added to its asset loop.
- Writer audit: changed `BackupMergeService.merge`, `BackupRepository.applyMergeResult`, `WorkRepository.setHasEpub` / `deleteLocalEpub`, `WorkImporter` matched file import / `persistDownloadedEpub` / `rebuildFromOriginal`. Hard deletion already removes the entire row. Soft deletion retains the file and promise, as iOS does; it is not `freeEPUB`. Fresh importer and `DemoLibrary` records default false. `WorkMetadataMerger` only carries the existing file state during metadata work and keeps the existing promise; its caller writes through `persistDownloadedEpub`. The other `hasEpub` assignments are DTO/entity mappings or merge helpers followed by the shared asset-state block. All production `writeWorkEpub` callers: backup restore, the four importer paths, and demo fixture setup. All `deleteWorkEpub` callers: `deleteLocalEpub` (changed) and `hardDelete` (row removed). `ReaderRepository` marks a missing file via `setHasEpub(false)` (now clears pending, like explicit local removal).
- Tests written: migration default/row preservation plus real schema-13→current Room validation (existing 7/10/12→current and fresh checks updated to 14); `IncomingEpubGateTest.aPromisedEpubWithMissingOrUnusableBytesIsStillPublished` and `aLateEpubClearsThePendingPromiseEvenInFileMerge` cover all three import modes; four `SyncRepositoryTest` tests assert backup/sync re-publication, late arrival clearing, failed installation/retry, and remove/peer-reclaim behaviour with actual stored EPUB bytes.
- iOS evidence: `KudosBackup.swift` export near 975–980 and restore near 2525–2535; `FolderSyncService.swift:readChangedRemoteAssets` begins `for work in manifest.works where work.hasEPUB`. That loop leaves a removed local copy absent when the entry is false, and fetches it when a peer says true. `WorkLifecycle.freeEPUB`, `WorkImporter.copyImportedEPUB`, `ReadingQueueService.replaceEPUB` clear the promise.
- Reference discrepancy: iOS's invalid-EPUB catch in restore (around 2495–2518) does not reach the missing-file `else if`; a new work with supplied-but-invalid bytes may never get its promised flag. Left iOS untouched. Android handles absent and unusable bytes per this brief. Runtime/build, migration validation and all added tests still need Claude's run.


## Part 2 — implemented; tests not run

- `BackupMergeService.mergeWork` takes `isSaved` and `isQueuedForLater` from the incoming snapshot only when it wins; an older incoming snapshot cannot set either flag back to true. The queue-only comment/protection and file-preserving `hasEpub` merge remain. No file deletion is introduced.
- Four added `SyncRepositoryTest` tests exercise repository imports with real local files: newer clears, older clears ignored, older true cannot revive a locally cleared flag, and queue-only stays queue-only. Each asserts the EPUB remains byte-for-byte on disk.
- iOS reference discrepancy: `KudosBackupService.apply` in `KudosBackup.swift` near 4448 takes the winner's `isSaved`, but near 4508 still ORs `isQueuedForLater`. Android follows the explicit brief for both flags. iOS unchanged; its queued flag needs owner/Claude review. Membership normalization still sets queued for works actually belonging to a queue, as before; this change concerns the snapshot flags, not membership deletion.
- Requires Claude compilation and test run.

## Part 3 — implemented; tests not run

- `BackupRepository.removeRecordsAbsentFromReplaceSnapshot` now upserts omitted collections/custom queues as deleted, with `deletedAt = clock()` and a 90-day deadline. Already-deleted rows keep their countdown. Collection links and queue rows are retained; no tombstone is minted. Replace's separate membership cleanup now applies only to custom queues present in the replacement snapshot, retaining omitted queues' links and all system-queue links.
- `BackupMergeService` retains system-queue memberships in the merge snapshot (so queued-work normalization also sees them), and leaves an omitted system queue's exact existing record intact through queue finalization. Replace still handles listed custom queue memberships as before. No Room or backup format change.
- `AnnotationEntity` already supports `isPendingDeletion` and `deletedAt`; omitted annotations are now marked with those fields, retaining locator, highlight, note and prior deletion date. There is no annotation 90-day deadline column, and iOS does not assign one in its Replace branch either.
- Three added `SyncRepositoryTest` tests assert 90-day Recently Deleted rows, retained/restorable collection and queue memberships, no countdown reset/no tombstones, intact EPUB bytes, exact omitted system-queue row and links, and annotation row preservation across repeated Replace.
- iOS reference: `KudosBackup.swift` Replace branch around 3387–3419. Runtime/Room/UI behavior requires Claude's test run; Recently Deleted assertions use the existing DAO/repository queries, not seen on screen.

## Part 4 — implemented; tests not run

- `SettingsRepository` persists `syncLastError` beside `syncLastSyncAt`; `SyncSettings.lastError` exposes it. It is excluded from the backup settings mapper/payload and is untouched by `replaceAll`.
- `SyncRepository.runSync` records every Error result, including early folder-access failures/exceptions, and clears the message for Success; a skipped concurrent run leaves it alone. Cancellation propagates. Connect/disconnect clear it as on iOS. `SettingsFolderSyncPage` reads the stored message instead of `remember` state. `SettingsHubScreen` shows Off without a folder, Error with a stored message, On while enabled, otherwise Paused, matching `SettingsRoute.syncFolder`.
- `SyncRepositoryTest.aFailedBackgroundRunStoresItsMessageAndTheNextSuccessClearsIt` verifies repository-driven failure/success, backup exclusion and survival across settings restore; `anEarlySyncFailureAlsoStoresItsMessage` covers the early return.
- iOS reference: `FolderSyncService.lastErrorKey` / `recordError` / `recordSuccess`, connect/disconnect; `Settings/SettingsRoute.swift:syncFolder`. Requires Claude compilation, tests and visual review of both Settings locations; no UI was seen here.

## Part 5 — test implemented; fixture generation pending Claude's run

- Added `SyncRepositoryTest.androidAddsItsWorkToTheIosFolderWithoutPruningEitherDevicesAssets`. It loads the existing iOS resource folder into the SAF provider, seeds one distinct Android work with an EPUB, HTML original and conversion record, then runs a real `SyncRepository.runSync`.
- Assertions: every old asset remains byte-for-byte at its old path; exactly three Android asset files were added; all three work IDs have `hasEPUB`; manifest version stays 8 and writer is Android; iOS's unknown `pronunciations` object survives; `.bak` is exactly iOS's replaced manifest. Added deletion recording to the existing test provider and assert no document deletion occurred.
- Opt-in `-Dkudos.writeGolden=true` saves the resulting live manifest/assets to `KudosTests/Fixtures/cross-platform/android-after-ios-sync-folder/KudosLibrary/`. No hand-made/stub fixture was created here. Claude must generate it by running the test; the Android assertions run even without that property and do not require the new fixture in advance. iOS test remains Claude's work, per the brief.

The generated interoperability folder contains exactly these eight files beneath `KudosLibrary/`:

```text
manifest.json
Works/2000ABCD-0000-4000-8000-00000000000A.epub
Works/2000ABCD-0000-4000-8000-00000000000B.epub
Originals/2000ABCD-0000-4000-8000-00000000000A.html
Originals/2000ABCD-0000-4000-8000-00000000000A.conversion.json
Works/3000ABCD-0000-4000-8000-00000000000A.epub
Originals/3000ABCD-0000-4000-8000-00000000000A.html
Originals/3000ABCD-0000-4000-8000-00000000000A.conversion.json
```

The `2000ABCD` assets are iOS's originals, unchanged; the `3000ABCD` assets are Android's distinct story and source/record. IDs normalize to lowercase in Android's manifest JSON; filenames use iOS's uppercase UUID naming. `Fonts/` is empty; Android's `.bak` is verified in the live folder but excluded from the exported fixture, like the existing golden.

- Manifest: the two iOS records (AO3 IDs 2001/2002, titles Folder Sync One/Two) plus Android's own work (3001, title Android's own work), all claiming EPUBs. Export clock is the source fixture's export plus 60 seconds, so the mixed snapshot does not predate its source. The source's empty pronunciation maps are carried through unchanged.

## Handoff / verification

- No Gradle/Xcode build or Android/iOS test suite was run, as instructed. `git diff --check` passed. An in-memory Python SQLite smoke check applied the actual `MIGRATION_13_14` SQL to the exported schema-13 works table and passed: existing title retained, new INTEGER column non-null/default 0, update to 1 supported. This does not validate Kotlin, generated Room schema or migration registration. Runtime statements above describe intended behavior and assertions, not executed suite results.
- Claude: compile Android/KSP (generates Room 14 schema), run `KudosDatabaseMigrationTest`, `IncomingEpubGateTest`, and `SyncRepositoryTest`, then the full Android unit suite. Run the new mixed-folder test with `-Dkudos.writeGolden=true` to produce the eight-file iOS fixture, and write/run the iOS consumer test in the authorized iOS worktree. Review Settings' stored error on screen, including a background failure and subsequent success.
- No backup format changes, other Room changes, helper scripts, `.orig` files, commits, pushes, branch switches, or iOS edits.

