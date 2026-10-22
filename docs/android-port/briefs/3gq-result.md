# Brief 3gq result

Worktree: `/Users/cidy02/kudos-agent-grok` on `android/agent-grok-3gq`.
Source audit: A75 "Differs and absent, ranked" items #2, #5, #6, #7, #10, #12, #14.
Items are written as they finish. Nothing is committed.

## #2 first place after opening a book — fixed

The first locator that differs from the seed is written immediately (the two-second interval has not started). A meaningful move inside that window arms one trailing write for the time remaining, and noise does not cancel it. An empty locator is ignored, including one that still carries a spine index and a progression: it does not replace the stored place and does not move the chapter or the progress clock. A non-empty locator that differs from a missing Readium locator is a real write; `applyProgress` then clears a macOS percent when there was no previous Readium progression, which is what iOS does.

- Android: `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderProgressGate.kt:49` (`seed`), `:71` (`note`), `:126` (empty locator returns), `:133` (`isMeaningfullyChanged`), `:150` (`scheduleTrailingWrite`). Wired from `ReaderRepository.kt:110` (`noteLocation`) and `ReaderViewModel.kt:174` (`onProgress`) through `ReaderViewModel.kt:90` (trailing scheduler; a due write uses `ReaderProgressSaver.schedule` with delay 0).
- iOS: `kudos-ao3-reader/Features/ReaderReadium/ReadiumProgressPersistence.swift:50` (`seed`), `:64` (empty `record` returns), `:75` (`note`), `:91` (`locatorForDebouncedWrite`), `:138` (`isMeaningfullyChanged`), `:160` (`scheduleTrailingWrite`). Interval is 2s and the progression delta is 0.001.
- Tests: `android/app/src/test/java/io/github/cidy02/kudos/reader/ReaderProgressGateTest.kt` — `progressionPastThresholdIsWrittenAfterInterval` (`:49`), `emptyLocatorIsIgnored` (`:62`, includes the empty-locator-with-spine case), `firstDifferentLocatorAfterSeedCanWrite` (`:98`), `meaningfulChangeInsideWindowArmsTrailingWrite` (`:113`). The trailing test uses a manual scheduler and asserts the armed delay is 1800 ms, then fires it.
- If the fix were reverted: `firstDifferentLocatorAfterSeedCanWrite` would see no write (the first different locator was dropped). `emptyLocatorIsIgnored` would see spine 7 replace spine 1, or an empty string become the latest locator. `meaningfulChangeInsideWindowArmsTrailingWrite` would either write inside the window (`writes` not empty) or arm no trailing task (`delayMillis` null, so firing it does not write the 0.35 locator). `progressionPastThresholdIsWrittenAfterInterval` would not record the 0.52 locator after 2.5 s.

Existing tests that pinned the old drop:

- `ReaderRepositoryTest.openThenCloseWithoutMovingKeepsFortyTwoPercent` now seeds a stored locator and reports an empty locator with a different spine. The old test dropped a real 0% locator so the macOS percent survived; iOS writes that locator and clears the percent. The empty report must leave chapter, scroll, percent, and locator alone, and close still stamps the dates because the seed is a session position.
- `ReaderRepositoryTest.aLaterMovePersistsAtTheInjectedClockAndRetiresTheMacPercent` now expects the first locator to be accepted. It still persists only the later move, so the clock assertions stay on that write.
- `ReaderCompletionTest` gives the end-of-work landing a locator. A locator-less landing is not a session position, so pause would not stamp `lastReadDate`. The publication-end path still persists that live progress directly.

## #5 and #6 fonts restored beside a case-variant file — fixed

When more than one database row or more than one file folds to the same name, the incoming font is written under `-restored-N` before any byte compare. Every existing row and file stays. The reader's selection stays `custom:<archived name>` only when that exact file is on disk or about to be written; otherwise it becomes `system`. It is not moved onto the suffix or onto a case-variant the reader did not pick. A suffix file always gets a row. A pre-existing orphan that already had no row stays an orphan.

- Android: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt:1159` (ambiguous before the byte compare), `:1133` (`uniqueSuffixedFontFileName`, `-restored-N`, case of the incoming name kept), `:456` (selection uses file names present on disk or in this restore, via `BackupValidator.normalizeSettings`). Zip, directory, and folder sync all enter this merge.
- iOS: `kudos-ao3-reader/Services/KudosBackup.swift:3296` (suffix when `existingMatches.count > 1 || localMatches.count > 1`), `:3458` (`custom:` kept only when that exact file exists).
- Tests: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupFontCaseRestoreTest.kt` — `zipRestorePreservesAmbiguousCaseFoldedRowsAndFiles` (`:20`), `legacyDirectoryRestorePreservesAmbiguousCaseFoldedRowsAndFiles` (`:25`), `syncDownPreservesEveryCaseFoldedDatabaseRow` (`:30`), `restorePreservesOneRowAndTwoCaseVariantFilesWhenIncomingMatchesOrphan` (`:55`), `restoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile` (`:79`), `zipRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile` (`:84`), `legacyDirectoryRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile` (`:89`), `syncDownTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile` (`:94`).
- If the fix were reverted: `syncDownTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile` would not install `sync-local-restored-1.ttf`, or it would point `readerFontID` at the suffix or at `sync-local.TTF`. `syncDownPreservesEveryCaseFoldedDatabaseRow` would drop a case-variant row or change `custom:SYNC-CASE.TTF`. `restorePreservesOneRowAndTwoCaseVariantFilesWhenIncomingMatchesOrphan` would give the orphan a row or overwrite `ONE-ROW-CASE.TTF`.

Existing tests whose selection expectations changed, because the merge no longer rewrites the id onto a suffix or a case variant:

- `BackupCompatibilityTest.collidingDifferentFontBytesAreSuffixedAndTheOriginalNameStaysSelected` (`:573`) expects `custom:Reader.ttf`. The exact file is still there.
- `BackupCompatibilityTest.identicalCaseVariantReusesOrphanFileAndDropsTheMissingSelection` (`:588`), `differentCaseVariantBytesAreSuffixedWithoutOverwritingOrphan` (`:605`), `missingFileForExistingDatabaseRowIsHealedInPlace` (`:619`), `unreadableOccupiedFileForExistingRowIsPreservedWithSuffix` (`:641`), and `missingExactDatabaseFileDoesNotCopyOverCaseVariantOrphan` (`:691`) expect `system`. The archived name is not a file that exists.
- `BackupCompatibilityTest.caseVariantOrphanNeverSubstitutesForExactDatabaseFile` (`:668`) still expects `custom:Reader.ttf`.
- `SyncRepositoryTest.restoringTheSameCollidingArchiveTwiceReusesTheSuffixedFontAndRetainsTheLocalSelector` (`:959`) expects the merge snapshot to keep `custom:reader.otf`. The DataStore id at `:954` was already that value, because replace does not write `readerFontId`.

## #7 export of a book over 128 MB — not changed

Export does not stream an entry. `BackupExporter.exportV2` builds the whole archive in a `ByteArrayOutputStream` (`BackupExporter.kt:31`) and `writeEntry` takes the entry as a `ByteArray` (`:85`, size check at `:92`). Raising `BackupLimits.MAX_ENTRY_BYTES` (`BackupVersion.kt:38`, 128 MB) to iOS's 1 GB would keep that book as one array. The archive cap is already 1 GB. The per-entry cap stays 128 MB.

- iOS: `kudos-ao3-reader/Reading/MiniZip.swift:101` (`maxSingleEntryUncompressedSize: 1_000_000_000` on `Limits.backup`).
- No test. The brief allows the higher cap only when each entry is streamed, and this export is not.

## #10 content hashes — fixed

An existing book with a file and an empty `epubDigest` is hashed at launch, at most 100 books a pass. The hash is streamed in 1 MiB chunks. After the read, the column is written only while it is still empty, so an import that stored one during the hash keeps its value. The pass runs after the search rebuild and outside the persistence gate. A backup work entry already writes a non-blank digest and omits a blank one (`encodeDefaults = true`, `explicitNulls = false`). That key stays additive on manifest v8. The schema was not bumped, and the released migration that added `epubDigest` was not edited. Restore still does not copy an archive digest onto the work, which is what iOS does on purpose.

- Android: `WorkRepository.kt:276` (`backfillEpubDigests`), `:1173` (`DIGEST_BACKFILL_PER_PASS = 100`); `WorkDao.kt:185` (`worksMissingEpubDigest`), `:193` (`fillEpubDigestIfBlank`); `BackupPaths.kt:194` (`sha256(File)`); `KudosApplication.kt:84` (the launch call). The backup key is the existing `BackupMappers.kt:180`.
- iOS: `kudos-ao3-reader/Services/PersistenceSync.swift:130` (`digestBackfillPerPass`), `:157` (`backfillEPUBDigests`), `:174` (re-check `epubDigest.isEmpty` after the hash). Backup key: `kudos-ao3-reader/Services/KudosBackup.swift:1027`.
- Tests: `android/app/src/test/java/io/github/cidy02/kudos/works/EpubDigestBackfillTest.kt` — `anExistingBookGetsADigestOnReconcile` (`:48`), `aDigestFilledMeanwhileIsNotOverwritten` (`:64`), `backfillStopsAfterThePassLimit` (`:76`). The JSON key was already pinned by `BackupPhase2FieldsTest.workWithEveryNewFieldRoundTrips` (`:26`) and `workWithNullTriStateFieldsRoundTripsAsJsonNull` (`:55`, empty digest omitted).
- If the fix were reverted: `anExistingBookGetsADigestOnReconcile` would leave `epubDigest` empty. `aDigestFilledMeanwhileIsNotOverwritten` would let a second fill replace `imported-wins`, or `backfillEpubDigests` would return 1 and overwrite it. `backfillStopsAfterThePassLimit` would fill both books when the limit is 1.

## #12 and #14 what a restore and a sync say — fixed

A work whose manifest says `hasEPUB`, whose package has no bytes for it, and which has no local file increments `worksMissingPromisedEPUB`. The restore sentence is "N work(s) restored without its/their EPUB — the backup listed the file but did not contain readable bytes for it." A work that never had an EPUB is not counted. Bytes that arrived but are not a readable EPUB are not counted. A file already on disk is not counted. A tombstone that suppresses the work is not counted, and that work is not in `worksRestored`.

`worksRestored` is every archived work that was not suppressed. File Merge does not increment `worksUpdated` for an existing live work, so created plus updated would undercount.

Queue counts follow decisions the merge already made, and only for a queue that is not already here: suppress, revive, or an ambiguous clock. An ambiguous membership is still applied and counted. An existing queue is not re-checked. A membership whose queue is missing is still dropped. Nothing about who is created or deleted changed.

A sync absorbs those counts the way iOS `FolderSyncResult.absorb` does: restored works, suppressed queues, revived queues, ambiguous queue conflicts, and folded conflicts. Only the first EPUB batch of a manifest is absorbed, because later batches merge the same manifest again. The legacy zip is absorbed once. The Sync Folder page shows a footnote for each count that is above zero. iOS shows the same counts as labeled rows on Sync Details, including zeros. Android already used one footnote for folded conflicts, and the new sentences sit there. A zero stays off the page. The suppressed-queue sentence does not include a membership count, because the sync result does not carry one.

- Android: `KudosBackup.kt:125` (`worksRestored`), `:131` (`worksMissingPromisedEPUB`), `:133`–`:137` (queue counts). `BackupMergeService.kt:167` (restored), `:195` (missing promised EPUB), `:1719` (queue decision), `:1848` (ambiguous membership). `BackupRepository.kt:827` (the sentence). `SyncRepository.kt:903` (`absorb`), `:662` (first batch only), `:271` and `:280` and `:298` (live manifest, each conflict, legacy zip), `:475` (the result). `SettingsPages2.kt:764` (the footnotes, from `footnoteLines` at `SyncRepository.kt:925`).
- iOS: `kudos-ao3-reader/Services/KudosBackup.swift:1935` (the EPUB sentence), `:2525` (the count when `archived.hasEPUB` and no file). `kudos-ao3-reader/Services/FolderSyncService.swift:47` (`absorb`). `kudos-ao3-reader/Settings/SettingsSyncFolderPage.swift:250` (Conflicts Folded, Works Restored, Queues Suppressed, Queues Revived, Ambiguous Queue Conflicts). Queue increments: `KudosBackup.swift:2802`, `:2807`, `:2812`, `:2974`.
- Tests: `android/app/src/test/java/io/github/cidy02/kudos/backup/RestoreAndSyncReportingTest.kt` — `aWorkWhosePromisedEPUBNeverArrivesIsCounted` (`:22`), `aWorkThatNeverHadAnEPUBIsNotCounted` (`:39`), `twoWorksWhosePromisedEpubsNeverArriveUseThePlural` (`:47`), `unreadableBytesAreNotAMissingPromisedEpub` (`:63`), `aPromisedEpubAlreadyOnDiskIsNotCounted` (`:75`), `aSuppressedWorkIsNotCountedAsRestored` (`:89`), `queueTombstoneDecisionsAreCounted` (`:122`), `folderSyncResultAbsorbsAnotherResultsCountsRatherThanDiscardingThem` (`:164`, expects 3, 4, 1, 1, 2 and the five footnote sentences).
- If the fix were reverted: `aWorkWhosePromisedEPUBNeverArrivesIsCounted` would see `worksMissingPromisedEPUB` of 0 and no EPUB sentence. `twoWorksWhosePromisedEpubsNeverArriveUseThePlural` would miss "their". `unreadableBytesAreNotAMissingPromisedEpub` would count the garbage bytes. `aPromisedEpubAlreadyOnDiskIsNotCounted` would count a file that is already here. `aSuppressedWorkIsNotCountedAsRestored` would count a work the tombstone dropped. `queueTombstoneDecisionsAreCounted` would leave the three queue counters at 0, or would drop the revived queue, the ambiguous queue, or the ambiguous membership. `folderSyncResultAbsorbsAnotherResultsCountsRatherThanDiscardingThem` would not reach 3, 4, 1, 1, 2, or would omit a footnote sentence.

Existing test that pinned the old sync result: `SyncRepositoryTest.aReadableConflictCopyIsMergedAndRemoved` (`:1841`) now expects `SyncResult.Success(foldedConflicts = 1, restoredWorks = 2)`. The live manifest and the conflict copy each restore one work. The new fields default to 0, so other `SyncResult.Success` comparisons stay equal unless that run actually restored works.

Gradle was not run. Claude builds and tests this.
