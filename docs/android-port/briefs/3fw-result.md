# Brief 3fw result

HEAD `8becf4c2` (`android/agent-grok-3fw`). Rows checked against this tree, including `c30bb605` (3fy), `e8258853` (3gb), and `2f00aa6a` (a paused sync stays paused). No commit. Tests were not executed: this brief forbids Gradle.

## #97 — sync stays paused after a failed Replace

**Not real** at this HEAD.

The pause is not in `BackupRepository`. `BackupRepository.kt:134` is `prepareForImport`, which only recovers Replace file asides. The reader-chosen pause is `BackupScreen.kt:161-163`: after the undo copy succeeds, and only when the sheet's pause box is checked and sync is currently on, `settingsRepository.updateSyncIsEnabled(false)` runs before `importV2ZipBytes`. The failure path at `BackupScreen.kt:178` sets the error text and does not turn sync back on. Leaving the box unchecked never pauses. A pause that was already on stays on, because the write is skipped when `pending.syncEnabled` is false.

iOS does the same. `Settings/SettingsBackupPage.swift:151-156` calls `FolderSyncService.setAutoSyncEnabled(false)` before `restorePendingBackup`. The restore `catch` at `Settings/SettingsBackupPage.swift:369-373` reports the error and does not re-enable sync. `Services/FolderSyncService.swift:165` only stores the flag. `KudosBackupService.restore` (`Services/KudosBackup.swift`) does not touch auto-sync. The cited `Services/KudosBackupService.swift` does not exist.

`2f00aa6a` / 3fy / 3gb make that stored pause actually skip automatic runs and get re-checked inside the persistence gate (`SyncRepository.kt:66-71`). They do not clear it on failure. Turning sync back on after a failed Replace would diverge from iOS.

No code change. No test (the row is not a defect).

## #96 — hold library file writes off during Replace and folder sync

**Confirmed.** Not fixed by 3fy. 3fy made `deleteWorkEpub` / `workEpubExists` open and added import `admit`. `WorkFileStore.kt:31` `writeWorkEpub`, `:89` `writeOriginal`, and `:154` `writeConversionRecord` did not take `PersistenceGate`. The production store at `KudosAppContainer.kt:86-88` was built with only the files directory. There is no cover-file writer; the library files are the EPUB and the original, plus the conversion record beside the original (Replace writes that record while it holds the gate, `BackupRepository.kt:258`).

iOS `Services/PersistenceOperationGate.swift` does not exist. The gate is `Services/PersistenceSync.swift:83-100` (`begin` fails when an operation is active). File writers such as `Services/ReadingQueueService.swift:912` `replaceEPUB` do not call it. They wait because backup import and folder sync hold the gate and run on `MainActor`, so another `MainActor` writer cannot run. Android has no `MainActor`. The shared mutex is the same exclusion. The launch sweep already holds that mutex and then deletes files (`KudosApplication.kt:73-79`, `WorkRepository.kt:490-493` `deleteWorkEpub` / `deleteOriginal`), so deletes take the lock too.

What changed:

- `PersistenceGate.kt:24-28` is re-entrant for the coroutine that already holds it. A permit in the coroutine context is inherited by `withContext(Dispatchers.IO)`. A second `Mutex` acquire on that coroutine would deadlock a Replace, or the sweep, on its own file write.
- `WorkFileStore.kt:26-29` takes the gate, when one was supplied, around `writeWorkEpub`, `writeOriginal`, `writeConversionRecord`, `deleteWorkEpub`, and `deleteOriginal`, before the IO hop. Empty bytes return before the lock. Reads stay outside it. The gate parameter defaults to null so existing stores keep today's behavior.
- `KudosAppContainer.kt:87` builds the production store with `persistenceGate`. `DemoLibrary.kt:266` passes that store into `seedPrivacyData`, which uses it at `:281` instead of a second ungated store.

`FontFileStore` is unchanged. It is not an EPUB, cover, or original.

Test: `files/WorkFileStoreGateTest.kt`. `epubAndOriginalWritesWaitUntilTheGateIsReleased` holds the gate and fails if `writeWorkEpub` / `writeOriginal` finish within 300ms (they used to). `writesAndDeletesReenterWhenTheCallerAlreadyHoldsTheGate` times out at 5s if a write or delete inside `withLock` deadlocks.

## #117 — refuse a central directory MiniZip would refuse

**Confirmed.** `BackupImporter.kt` checked only that the bytes contained an end-of-central-directory signature, then streamed local headers with `ZipInputStream`. A flipped central-directory signature, a truncated ZIP64 extra, or an EOCD stuck at `0xFFFF` without a ZIP64 locator was still imported. iOS `Reading/MiniZip.swift:111-162` and `:331-434` rejects those before extraction. Messages are `MiniZip.swift:22-23` and `:27`.

What changed:

- `ZipCentralDirectory.kt:17` runs at `BackupImporter.kt:24`, after the existing 1 GiB check and before `ZipInputStream`, font staging, or `prepareForImport` (`BackupRepository.kt:110-111`).
- It follows iOS: scan back at most 65536 bytes for the EOCD, follow a ZIP64 locator (`0x07064b50`) and ZIP64 EOCD (`0x06064b50`), reject classic `0xFFFF` / `0xFFFFFFFF` sentinels with no locator, and when a central-directory size or local offset is `0xFFFFFFFF` require extra id `0x0001` with the saturated fields in order. A block that runs past the extra area is "An archive record is truncated or points outside the file." A missing or short ZIP64 value, a bad signature, or a bad locator is "The archive's central directory is missing or malformed." More than 250,000 entries is iOS's backup entry cap ("The archive's total uncompressed size exceeds the allowed limit."), a loop guard, not a new byte ceiling.
- Entry paths, methods, and duplicates are not re-checked here. The stream still reports those with `UnsafePath` and `DuplicateEntry`. An empty directory (count 0) falls through, so an empty zip is still `MissingManifest`. Payloads stay on `ZipInputStream`. No manifest version bump.

Test: `backup/BackupCentralDirectoryImportTest.kt`, through `BackupRepository.importV2ZipBytes`. `aBrokenCentralDirectoryIsRefusedBeforeAnyWrite` flips the central-directory signature (local headers stay readable). `aTruncatedZip64ExtraIsRefusedBeforeAnyWrite` sets the EPUB record's sizes to `0xFFFFFFFF` with a 4-byte extra whose ZIP64 block claims 16 bytes. `aSaturatedEndOfCentralDirectoryWithoutZip64IsRefusedBeforeAnyWrite` sets the EOCD count to `0xFFFF`. Each expects `BackupError.InvalidPackage` with the iOS sentence written out in the test, then zero work rows and no EPUB file. `aRealBackupStillRestores` and `aWellFormedZip64ExtraStillRestores` import a backup iOS would keep, including a resolved ZIP64 extra. `anEmptyArchiveIsStillAMissingManifest` keeps the empty-zip error.

## #112 — stage EPUB and backup temps in cacheDir

**Confirmed.** `EpubImportMetadata.kt:208` created `incoming*.epub` with `File.createTempFile` and no directory, which is `java.io.tmpdir`. `BackupFontValidator` (`BackupImporter.kt:247-250`) called `Files.createTempFile(prefix, suffix)` the same way. Both already deleted in `finally`; the directory was the bug. iOS inspects an EPUB at its URL (`EPUB.swift` `inspectPackage`) and does not stage package metadata in the process temp directory. Android still needs a file for `ZipFile`. The brief puts that file in `context.cacheDir`.

What changed:

- `EpubImportMetadata.kt:212-216` and `:231` create the package temp with `CacheStaging.file` in the given directory and still `file.delete()` on every path, including a `ZipFile` failure. `BackupMergeService.kt:188` passes the directory through. Callers that omit it keep the process temp dir, so existing one-argument checks still compile.
- `BackupImporter.kt:242-250` stages a font in that directory when no test supplies its own factory. `finally` at `:308-309` still deletes on success and on failure. `BackupRepository.kt:46` takes `cacheDirectory` and passes it into `importV2Zip` (`:110`), `importPackage` (`:126`), and the merge. `CustomFontRepository.kt:30` and `:60` do the same for a font the reader imports.
- `KudosAppContainer.kt:112` and `:322` pass `appContext.cacheDir`.

Test: `works/EpubPackageCacheTest.kt` `unreadablePackageIsStagedInTheCacheAndDeletedWhenTheReadFails` passes a cache directory and bytes that are not a zip. It fails if the temp is not recorded in that directory or still exists afterwards. `backup/BackupCacheStagingTest.kt` builds `BackupRepository` with a cache directory. `aRestoredEpubIsStagedInTheCacheAndRemoved` imports a real EPUB and requires the staged file's parent to be that cache, the file to be gone, and the work to exist. `fontValidationIsStagedInTheCacheAndRemoved` imports a structurally valid sfnt (`Reader.ttf`) so validation reaches the temp file; the file must be in that cache and gone afterwards, whether or not `Typeface` accepts it. `CacheStaging` records the path at creation because the `finally` block deletes it before the test can look. The probe is installed as a coroutine thread-context element so it is visible on `Dispatchers.IO`, where import runs.
