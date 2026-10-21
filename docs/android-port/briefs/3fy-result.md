# 3fy result

A67 F1–F9, fixed at this HEAD. No commit. Room schema and backup manifest v8 are unchanged (new `UPDATE` queries only). `res/xml/file_paths.xml` does not list the undo copies. Gradle was not run, per the brief, so these tests are written and not executed here.

The stale-copy writers (F1–F6) no longer save a whole row taken before a yield. A writer that changes one or two columns uses a column `UPDATE`. A writer that changes more re-reads the row inside a transaction and then writes. `WorkRepository.upsert` is unchanged.

## F1 — fixed

Launch search rebuild no longer writes the work it loaded at the start.

- `WorkDao.updateSearchIndex` (`WorkDao.kt:151`) sets only `searchText` and `searchIndexVersion`. A missing id updates nothing, so a deleted work is not put back.
- `WorkRepository.rebuildSearchIndexIfNeeded` (`WorkRepository.kt:264`) saves each stale work through that query. `beforeIndexingStaleWork` (`WorkRepository.kt:57`, called at `WorkRepository.kt:257`) runs after the launch snapshot is taken.
- `reindexSearchForWork` (`WorkRepository.kt:696`) uses the same query, so a tag read cannot write the rest of the row either.

iOS `WorkSearchIndex.reindex` (`Services/WorkSearchIndex.swift:98`) writes `searchText` and `searchIndexVersion` on the live record and does not call `markModified`. `rebuildIfNeeded` (`WorkSearchIndex.swift:115`) saves that record.

Test: `WorkLifecycleRepositoryTest.searchRebuildKeepsAPlaceWrittenBetweenBatches` (`WorkLifecycleTest.kt:1038`). A spine and a favourite written while the stale work's tags are loaded are still there, and the index version is 2. The old `upsertAll` of the launch copy would put the spine back.

A title edited during the rebuild can leave derived search text stale until the next upsert. The title column itself is kept.

## F7 — fixed

An automatic sync that already passed the Auto Sync check does not import after Replace pauses sync. Sync Now still imports.

- `runAutoSync` (`SyncRepository.kt:140`) calls `runSync(stopWhenPaused = true)`. `runSync()` stays the manual path and does not stop when paused.
- `folderImportStillAllowed` (`SyncRepository.kt:179`) is the admit check for that run only.
- `importV2ZipBytes` (`BackupRepository.kt:103`), `importPackage` (`BackupRepository.kt:119`), and `importOriginalFiles` (`BackupRepository.kt:177`) throw `ImportDeclined` as the first line inside the persistence gate when admit is false. The default admit still imports, so file Merge and Replace are unchanged.
- `runSyncLocked` (`SyncRepository.kt:446`) and the outer `runSync` (`SyncRepository.kt:160`) catch `ImportDeclined` and return `SyncResult.Success` without an error, an export, a digest update, or a prune. The worker's existing `when` stays exhaustive.

iOS automatic runs read `autoSyncEnabled` before they start (`FolderSyncService`). Sync Now is not gated on that flag. `setAutoSyncEnabled` (`FolderSyncService.swift:165`) only stores it. An in-flight sync that cannot take the gate does not import. Pause on Replace is still `updateSyncIsEnabled(false)` after the undo copy and before `importV2ZipBytes` (`BackupScreen.kt:148`).

Test: `SyncRepositoryTest.autoSyncThatAlreadyPassedItsCheckDoesNotImportAfterReplacePauses` (`SyncRepositoryTest.kt:248`). The gate turns Auto Sync off as the import lock is taken, after the start-of-run check. The automatic run returns success and does not create the foreign work. Sync Now then imports it, so the folder was not overwritten and a manual sync still imports. `autoSyncOffSkipsAutomaticRunsButNotSyncNow` still covers a flag that was already off (that run returns null and never takes the lock).

## F8 — fixed

Replace's undo copy uses iOS's names and is a document the Import picker can open. A failed copy still refuses Replace. There is no "I understand the risks" bypass.

- `PreReplaceBackupNaming.fileName` (`PreReplaceSafetyCopy.kt:28`): `Kudos Library Before Replace yyyy-MM-dd HH-mm-ss`, plus ` (n)` on a retry, extension `kudosbackup`, three attempts. Same rule as iOS `PreReplaceBackupNaming` (`Settings/SettingsView.swift:534`).
- `SafetyCopies.write` (`PreReplaceSafetyCopy.kt:48`) stages a dotfile, then moves it without replacing an existing destination. Same shape as iOS `makePreReplaceBackup` (`Settings/SettingsBackupPage.swift:394`).
- The directory is still app Documents (`getExternalFilesDir(DIRECTORY_DOCUMENTS)`, else `filesDir/Documents`). `KudosSafetyDocumentsProvider` (`AndroidManifest.xml:57`, authority `${applicationId}.safetycopies`) lists `*.kudosbackup` there and opens them read-only.
- Import uses `OpenBackupDocument` (`KudosSafetyDocumentsProvider.kt:148`, `BackupScreen.kt:97`) with `EXTRA_INITIAL_URI` on that root. `BackupScreen.runImport` (`BackupScreen.kt:142`) writes through `SafetyCopies` and still pauses only after the name is known.

The library archive is not in public Downloads and not in `file_paths.xml`.

Test: `PreReplaceSafetyCopyTest.undoCopiesKeepDistinctNamesAndTheImportPickerCanReadThem` (`PreReplaceSafetyCopyTest.kt:36`). Two writes in the same second get different names, the first bytes stay, a pre-existing attempt-0 name forces attempt 1, no dotfile is left, `queryChildDocuments` lists both and `openDocument` returns the bytes, the Import intent's initial URI is the provider root, and `resolveContentProvider` finds `${packageName}.safetycopies`.

## F2 — fixed

Deleting a local EPUB, and clearing a hold the sweep no longer qualifies, no longer write the row from before the yield.

- `deleteLocalEpub` (`WorkRepository.kt:414`) deletes the file, then `clearLocalEpub` (`WorkRepository.kt:421`) sets `hasEpub`, `remoteEpubPending`, `freedAt`, and `lastModifiedAt` through `WorkDao.updateLocalEpubFlags` (`WorkDao.kt:162`). The returned work is the live row.
- The sweep's "does not qualify" branch (`WorkRepository.kt:398`) calls `WorkDao.clearFreedAt` (`WorkDao.kt:171`) instead of upserting the loop-start row.
- `deleteWorkEpub` and `workEpubExists` on `WorkFileStore` are open so a test can write during the yield.

iOS `WorkLifecycle.freeEPUB` (`Services/WorkLifecycle.swift:149`) clears the file flag on the live record (`hasEPUB`, `freedAt`, `remoteEPUBPending`). This update is those fields plus `lastModifiedAt`, which is what Android already wrote. It does not also set a queued work's preservation status to `missingFile`; that was not part of this write.

Tests: `WorkLifecycleRepositoryTest.deleteLocalEpubKeepsAPlaceWrittenDuringTheFileDelete` (`WorkLifecycleTest.kt:1063`) and `sweepHeldCopiesKeepsAPlaceWrittenWhileAnEarlierCopyIsFreed` (`WorkLifecycleTest.kt:1088`). A spine and a favourite written during the file delete, or during an earlier free in the same sweep, survive. The old upsert of the pre-delete copy, or of the list loaded at the start, would put them back.

## F3 — fixed

Re-importing an EPUB the library already has merges onto the row read after the file write.

`importLocalEpub`'s existing-work branch (`WorkImporter.kt:314`) calls `WorkRepository.rewriteFresh` (`WorkRepository.kt:275`): inside a transaction, re-read, restore from Recently Deleted when the live row is deleted, then fill-only metadata and `withImportedAo3Ids`. A brand-new import is unchanged. The file write stays outside the transaction.

iOS import re-checks the existing work after the file await and merges fill-only.

Test: `WorkImporterLifecycleTest.reimportKeepsAPlaceWrittenDuringTheEpubWrite` (`WorkLifecycleTest.kt:1652`). A spine and a favourite written during `writeWorkEpub` survive, and `hasEpub` stays true. `userEPUBImportRevivesRecentlyDeletedDuplicate` still goes through this path: the live row, including its locator and favourite, is what gets restored.

## F4 — fixed

Adding a work to a queue no longer upserts the row from before the file stat.

`normalizeWork` (`ReadingQueueRepository.kt:719`) stats the file outside the transaction, then re-reads inside `withTransaction` and upserts only if the fresh row changed. Callers that already hold a transaction join it. When there is no file probe, `hasEpub` comes from that fresh row.

iOS normalize mutates the live record.

Test: `ReadingQueueRepositoryTest.addWorkKeepsAPlaceWrittenDuringTheFileCheck` (`ReadingQueueRepositoryTest.kt:91`). A spine and a favourite written inside `epubOnDisk` survive, and `isQueuedForLater` becomes true. `enqueueMissingEpub` is false, so the test does not download.

## F5 — fixed

Preserving a queued work whose file is already on disk writes the row read after the exists check.

The success path (`WorkImporter.kt:135`) uses the same `rewriteFresh`. It sets `epubPreservationStatusRaw` to `preserved` and keeps an existing `preservedAt`. The `lastPreservationAttemptAt` upsert before the check is unchanged: that copy is taken by the caller and the yield is the exists check after it. Failure and cancel paths already re-read.

iOS preservation updates the live record.

Test: `WorkImporterLifecycleTest.preserveKeepsAPlaceWrittenDuringTheExistsCheck` (`WorkLifecycleTest.kt:1685`). A spine and a favourite written during `workEpubExists` survive, and the status is `preserved`.

## F6 — fixed

Opening the reader stamps Continue Reading dates on the live row after the font list is read.

`WorkDao.noteOpened` (`WorkDao.kt:182`) sets `lastReadDate`, `progressModifiedAt`, `lastModifiedAt`, and clears `hiddenFromHistoryAt`. `WorkRepository.noteOpened` (`WorkRepository.kt:284`) does that and returns the live row. `ReaderRepository.open` (`ReaderRepository.kt:64`) calls it after `preferencesFor`, instead of upserting the copy from before the font list. It does not write the place. `releaseHeldCopy` and `setSaved` are unchanged. `finishReading` has no yield between its read and its write, so it is unchanged.

iOS `ReadiumSessionStamp.noteOpened` (`Features/ReaderReadium/ReadiumReaderView.swift:40`) calls `markProgressModified` (`Models/Models.swift:649`): those dates, and `hiddenFromHistoryAt = nil`. The stored place stays.

Test: `ReaderRepositoryTest.openKeepsAPlaceWrittenWhileFontsAreListed` (`ReaderRepositoryTest.kt:271`). A spine and a favourite written by `customFontsProvider` survive, `lastReadDate` is the open clock, and `hiddenFromHistoryAt` is cleared.

## F9 — fixed

A multi-item Inbox delete sends the items the dialog captured.

`AccountInboxPane` confirm (`AccountInboxPane.kt:160`) calls `startBulkAction(Delete, openedIn, pending.items)` for one item and for many. `startBulkAction` (`AccountInboxViewModel.kt:289`) sends that list when the dialog passes one. Mark read and mark unread pass none, so they still send the live selection. `startAction` still requires each id to be on the current page.

iOS deletes the items the dialog captured.

Test: `InboxFailedPageTest.aConfirmedMultiDeleteSendsTheItemsTheDialogCaptured` (`InboxFailedPageTest.kt:112`). Two items (checkbox values 501 and 502) are selected, a reload clears the selection, and the confirm method posts once with both checkbox values. A method that re-read the selection would post nothing.
