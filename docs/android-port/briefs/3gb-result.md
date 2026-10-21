# Brief 3gb result

## 1. #3 Replace is offered whenever Replace would remove something

Changed:

- `android/app/src/main/java/io/github/cidy02/kudos/backup/KudosBackup.kt:79` adds `hasReplaceableRecords` on `BackupImportPreview`. `isLibraryEmpty` stays, for the empty-library footnote.
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt:764` sets it from the current snapshot: active works, bookmarks, saved searches, collections that are not deleted, and queues other than Saved for Later.
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt:473` offers Restore alone only when `!preview.hasReplaceableRecords`. Merge and Replace Library stay on the other branch.

iOS followed: `Settings/SettingsBackupPage.swift:74` `hasAnythingReplaceWouldRemove`, passed as `hasReplaceableRecords` at line 148. Saved for Later is excluded there because that queue always exists.

Test: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupReplaceOfferTest.kt` `noWorksButABookmarkOffersReplaceAndTheAlwaysThereQueueDoesNot`. Zero works and one bookmark is true. A deleted collection alone, and Saved for Later alone, are false. Taking out the snapshot check leaves `hasReplaceableRecords` at its default false, so the bookmark assertion fails.

UI: `ImportBackupChoicesTest.replaceIsOfferedWhenABookmarkWouldBeRemovedAndNotOnlyWhenThereAreWorks` renders the import choices with an empty work list and `hasReplaceableRecords` true, and requires "Replace Library…". Gating on `isLibraryEmpty` again shows "Restore from Backup" and that node assertion fails.

## 3. #9 Replace checks match iOS

Changed:

- `android/app/src/main/java/io/github/cidy02/kudos/backup/KudosBackup.kt:85` `isMuchSmallerThanLibrary` is `willRemove >= 20 && willRemove >= willAdd * 10`.
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt:399` the "far fewer works" line is inside the Replace review. The choice step does not show it. `isLibraryEmpty` still suppresses it when there are no works.

iOS followed: `Settings/SettingsView.swift:401` `backupIsMuchSmaller`, shown only in the Replace Library sheet (`:453`). Naming and the three tries were already iOS's: `PreReplaceSafetyCopy.kt:21` `PreReplaceBackupNaming` (`Kudos Library Before Replace`, attempt suffix ` (2)` / ` (3)`, `attemptLimit = 3`) and `SafetyCopies.write` at line 47, called from `BackupScreen.runImport`. Nothing of that write was left to change. The copy is still taken when Replace is confirmed, and Replace is still refused when the copy cannot be saved. Writing it when the review opens was the verifier's optional note, and it is not required for the undo.

Test: `BackupReplaceOfferTest.farFewerWorksUsesIosLargeRemovalThreshold`. A removal of 19, and a file under half the library that removes only 6, are not "far fewer". A removal of 20 that is at least ten times the additions is, including when the file is not under half the library. The old `fileWorkCount * 2 < localWorkCount` rule fails those assertions.

UI: `ImportBackupChoicesTest.farFewerWorksShowsOnlyWhileReplaceIsBeingReviewed` finds no warning on the choice step and finds it after "Replace Library…". `aSmallerFileThatIsNotALargeRemovalDoesNotWarnOnReview` opens the review for a 19-work removal and requires the warning to be absent. Showing the warning on the choice step, or keeping the old threshold, fails those.

## 2. #8 Settings › Backup opens the exporter in one tap

Changed:

- `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsHubScreen.kt:47` takes `onOpenBackup`. Line 159 the Backup row calls it. It does not `navigate("backup")`.
- `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsScreen.kt:60` passes the shell's `onOpenBackup`, which is `Routes.Backup` (`AppNavHost.kt`). The inner `backup` route and `SettingsBackupPageWrapper` are gone (`SettingsPages2.kt`).
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt:267` keeps "Reset settings to defaults" and its confirmation (line 277). Export and Import on that screen still open the system picker.

iOS followed: `Settings/SettingsBackupPage.swift:84` the Backup page itself holds export and import, and the file exporter and importer are on that same page (`:98`, `:106`). iOS has no Reset row. The row stays, moved onto the screen the hub now opens.

Test: `android/app/src/test/java/io/github/cidy02/kudos/settings/SettingsHubBackupTest.kt` `backupRowOpensTheExporterAndDoesNotPushASecondPage`. The tap must call `onOpenBackup` once and leave the settings route on `hub`. A graph in that test still has the old `backup` destination, so `navigate("backup")` again fails the route assertion and never calls `onOpenBackup`. `SettingsStringsTest` also reads `BackupScreen.kt`, so deleting the Reset row fails that existing guard.

## 4. #10 The skipped-deletion tap clears the count, and Revoke leaves Recently Deleted

Changed:

- `android/app/src/main/java/io/github/cidy02/kudos/data/preferences/SettingsRepository.kt:537` `clearUnknownSignerTombstoneIds` removes `Keys.UnknownSignerTombstoneIds`.
- `android/app/src/main/java/io/github/cidy02/kudos/backup/PairingSheet.kt:138` the badge tap sets the count to 0, clears that preference (line 139), then opens the pairing sheet (line 140).
- `android/app/src/main/java/io/github/cidy02/kudos/backup/PairingSheet.kt:220` Revoke only calls `revocationService.revoke`, then refreshes the list and sets "Revoked that device." (line 222). `KeyRevocationService.kt:10` is that revoke: it removes the key and does not restore works. `PairingCard` still takes the database and work repository so Backup and Sync Folder keep the same call.

iOS followed: `Settings/PairingSheet.swift:82` `UnknownSignerTracker.reset()` and line 83 `unknownSignerCount = 0` before the sheet. `RevokeDeviceSheet` at line 145 calls `TombstoneTrustStore.remove` only, then line 147 sets "Revoked that device."

Test: `android/app/src/test/java/io/github/cidy02/kudos/backup/PairingRevokeTest.kt` `revokeLeavesTheWorkDeletedAndTheSkippedDeletionTapClearsTheCount`. It taps the device row's Revoke, confirms with the default "Stolen or compromised", and requires the work to stay deleted with its tombstone. Restoring on confirm makes `isDeleted` false and that assertion fails. It then taps "1 deletion skipped from an unpaired device" and requires `unknownSignerTombstoneIdsSnapshot()` to be empty. A tap that only hides the row leaves the id stored, and that wait fails. `KeyRevocationServiceTest.stolenRevokeLeavesTheWorkInRecentlyDeleted` fails the same way if `revoke` itself puts the work back.

## 5. Tests for the three fixes already in the tree

No production change. Commit `c30bb605` already re-reads on save and on the held-copy sweep, and already refuses the export after Replace pauses sync. These tests fail if that re-read or that refusal is taken out.

### (a) Search text is the title at save time

Locked code: `android/app/src/main/java/io/github/cidy02/kudos/works/WorkRepository.kt:264` `reindexSearchForWork(work.id)`, which reads the row again (`:694`).

iOS followed: `Services/WorkSearchIndex.swift:129` `reindex(work)` writes the live model, then `context.save()` at line 140. Android's rebuild holds copies from launch, so the save has to read the row again to do the same thing.

Test: `android/app/src/test/java/io/github/cidy02/kudos/works/WorkLifecycleTest.kt` `searchRebuildWritesTheTitleTheRowHasAtSaveTime`. Two works start as "Old Title" with a stale index. Before each is indexed, the row's title becomes "Fresh Title" plus its id, through the DAO. The stored `searchText` must contain "fresh title" and that id, must not contain "old title", and the stamp must be `CURRENT_VERSION` (2). Saving the launch copy stamps "old title" and the assertion fails.

### (b) The held-copy sweep decides on the fresh row

Locked code: `android/app/src/main/java/io/github/cidy02/kudos/works/WorkRepository.kt:398` `getWork(entity.id)?.takeIf { it.freedAt != null }`. `getHeldCopies` is ordered by `freedAt` ascending.

iOS followed: `Services/WorkLifecycle.swift:56` walks the fetched models in place. `releaseHeldCopy` at line 72 sets `freedAt = nil` on that same model, so the loop sees the release. Android's list is a snapshot, so the loop reads each row again.

Test: `WorkLifecycleTest.sweepHeldCopiesKeepsAFileWhoseHoldWasReleasedWhileAnEarlierCopyIsFreed`. Two unprotected finished copies with AO3 urls are both past the 60-day window; the later `freedAt` is one hour after the earlier. While the earlier file is deleted, the later row's `freedAt` is cleared. The sweep must free one copy. The later file must still exist, with `hasEpub` true. Deciding from the list loaded at the start deletes that file, and both the count and `workEpubExists` fail.

### (c) An automatic sync that waited on the export gate publishes nothing and prunes nothing

Locked code: `android/app/src/main/java/io/github/cidy02/kudos/backup/SyncRepository.kt:293` `if (!folderImportStillAllowed()) throw ImportDeclined()`, inside the export `withLock`. `runAutoSync` (`:140`) is what sets the pause check. `ImportDeclined` returns `SyncResult.Success`.

iOS followed: `Services/FolderSyncService.swift:203` reads and then writes inside `runGuarded` (`:261`), which holds `PersistenceOperationGate` for the whole run. Replace turns automatic sync off at `Settings/SettingsBackupPage.swift:153` `setAutoSyncEnabled(false)`. A run that already passed Android's opening check still has to read that flag again before it publishes.

Test: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt` `autoSyncThatWaitedOnTheExportGatePublishesNothingAndPrunesNothing`. A first sync publishes the library and stores the manifest digest. The local title is then renamed and `orphan-not-in-manifest.epub` is added under Works. A second repository's gate turns sync off as the export lock is taken, and the run is `runAutoSync`. The result must be `Success`, the manifest bytes must be unchanged, and the orphan must still hold its original bytes. Taking out the export check writes the new title and deletes the orphan, so those assertions fail. The digest assert keeps this on the export lock: that run does not import, and an empty Originals takes no gate.

