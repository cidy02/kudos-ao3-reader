# Audit A29: the rules A25 found no Android test for, checked against Android's code

**Implemented:** 9
**Differs:** 2
**Absent:** 113
**Not applicable:** 0
**Not read:** 71

## Differences and Omissions

| Test | Rule | Path:Line | Output Difference | Severity |
|---|---|---|---|---|
| CanonicalWorkMergeTests | identityIndexFallsBackToRecordUUID | android/app/src/main/java/io/github/cidy02/kudos/works/CanonicalWorkMerge.kt:53 | differs: Android falls back to `sourceUrl` but not the record UUID like iOS does. | P3 |
| PreReplaceBackupNamingTests | theCopyIsNamedAsAnImportableBackup | android/app/src/main/java/io/github/cidy02/kudos/backup/BackupRepository.kt:14 | differs: iOS prefixes with "Kudos Library Before Replace ", Android uses "Kudos-before-replace-". | P3 |
| AO3InboxParseTests | visibleWorkMetadataDeduplicatesInScreenOrder | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3InboxParseTests | anonymousCreatorAlwaysResolvesToAuthorRole | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3InboxParseTests | inboxPillsArePresetsOverAO3sOwnFilters | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3InboxParseTests | unrecognizedMarkupThrowsInsteadOfFabricatingEmpty | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3InboxParseTests | countsOnlyCommentsTheReaderCanStillAnswer | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3InboxParseTests | headerLineMarksThePageOnlyCount | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3NamedSubscriptionsParseTests | aNonAuthorLinkInASeriesRowIsNotACreator | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3PreferencesParseTests | parsesTogglesSelectsTextAndWebLinks | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3PreferencesParseTests | parsesHelpPageBodyFromDefinitionList | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3SubscriptionsParseTests | readsTitleAndAllBylineAuthors | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3UserStatsParsingTests | totalsComeFromTheTotalsBlockNotTheFirstWork | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3UserStatsParsingTests | readsWordCountAndTheRestOfTheTotals | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3UserStatsParsingTests | userSubscriptionsIsNotMistakenForSubscriptions | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3UserStatsParsingTests | anAccountWithNoWorksParsesEmptyRatherThanThrowing | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3UserStatsParsingTests | statsURLAsksForAllYears | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| CustomFontBackupCompatibilityTests | everyRefusalExplainsItself | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| KudosBackupFontRestoreTests | unreadableLocalBytesAndOrphanSuffixArePreserved | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| KudosBackupTests | authorIdentityPersistsLocallyWithoutChangingBackupSchema | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| KudosBackupTests | streamedExportMatchesTheInMemoryArchive | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| KudosBackupTests | exportRefusesArchivesTheReaderWouldReject | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| PreReplaceBackupNamingTests | retriesWithinOneSecondEachGetTheirOwnName | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| PreReplaceBackupNamingTests | aSafetyCopyIsAttemptedMoreThanOnce | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| PreReplaceBackupNamingTests | writingRefusesToOverwriteAnExistingCopy | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| ReadiumProgressPersistenceTests | flushIsNilWhenNothingChanged | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| EqualSizeEPUBStillSyncsTests | anExistingBookGetsADigestOnReconcile | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| FailedRestoreKeepsEPUBsTests | aRestoreThatFailsLeavesTheExistingEPUBUntouched | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| BackupLazyReadTests | zipReadDoesNotExtractWorksUntilAccessed | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| BackupLazyReadTests | directoryReadDoesNotMaterializeEPUBs | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| BackupLazyReadTests | zipReadDoesNotExtractFontsUntilAccessed | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| BackupLazyReadTests | directoryReadDoesNotMaterializeFonts | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| BackupLazyReadTests | swappedZipIsRejectedAtConfirmedImport | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| BackupLazyReadTests | unchangedZipConfirmedImportReadsLazily | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| BackupLazyReadTests | swappedDirectoryAssetIsRejectedAtConfirmedImport | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| ExactColourBackupTests | archivedQueueCarriesColorHexAndOlderArchivesDecode | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| ExactColourBackupTests | restoreBringsBackExactQueueAndCollectionColours | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| FolderSyncBackgroundTaskTests | scheduleRequiresConnectedFolderAndAutoSyncEnabled | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| FolderSyncTests | connectingAFolderRecordsItAsConfigured | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| FolderSyncTests | disconnectingDoesNotReArmTheOnboardingPrompt | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| FolderSyncTests | folderSyncResultAbsorbsAnotherResultsCountsRatherThanDiscardingThem | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| IncompleteBackupReportingTests | aWorkWhosePromisedEPUBNeverArrivesIsCounted | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| IncompleteBackupReportingTests | aWorkThatNeverHadAnEPUBIsNotCounted | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| PersistenceSyncTests | migrationIsIdempotentAndMarksMissingEPUBRecoverable | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| PersistenceSyncTests | clearedMacPercentIsExportedAsNull | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| PersistenceSyncTests | manifestWithoutTheMacPercentKeyDecodesItAsNil | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| PersistenceSyncTests | deletingWorkCreatesTombstone | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| ReadingLogBackupTests | keepInProgressOverrideDecodesNilWhenAbsent | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| ReadingLogBackupTests | v7AndV8ArchivesWithoutNewKeysStillImport | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| ReadingLogBackupTests | addingReadingLogDidNotBumpTheSchemaVersion | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| ReadingLogRestoreDefectTests | replaceLibraryKeepsFavoritesAndWatermarksMatchedByTarget | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3CollectionParsingTests | existingParseCollectionsStillReadsNameTitleAndMaintainers | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3CollectionParsingTests | itemApprovalTabsAndStagedFieldsParse | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3CollectionParsingTests | collectionsIndexReadsOwnerClassCountsAndPageCount | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3CollectionParsingTests | accountItemsPageReadsEachRowsCollectionDateAndDisabledControls | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3CollectionParsingTests | collectionFormParsesHeaderPreferencesProfileAndFourFlags | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3CollectionParsingTests | absentCollectionControlsAreNotPosted | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3CollectionParsingTests | selectedBlankChallengeOptionWinsEvenWhenItIsNotFirst | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3CollectionParsingTests | nameAvailabilityHeuristic | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3CollectionParsingTests | collectionProfileTagSetSingular | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3CollectionParsingTests | collectionProfileTagSetsPlural | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3CollectionParsingTests | collectionProfileWithoutTagSetBlockReturnsEmpty | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3CollectionParsingTests | pagedPeopleCountIsExplicitlyPageScoped | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | challengeDatesStayInTheChallengesOwnZone | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | signUpIndexCountsEachRowsRequestsAndOffers | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | signUpJoinsAssignmentMatchedState | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | signUpMatchStateIsUnknownWithoutAssignments | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | emptyAssignmentListsLeaveMatchStateUnknown | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | failedLoadMoreKeepsRowsAndRetriesThePage | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | ownSignUpMatchesBylineOrPseudWithLogin | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | assignmentBadgeDerivesLateFromWorksDue | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | signUpTotalReadsTheLastPageAndPageLabels | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | assignmentTemplatesPreserveDefaultAndDeliveryStates | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | assignmentJoinFetchesEveryPageIncludingOpenAssignments | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | challengeSettingsParseFiveUTCDatesAndMatchingURL | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | promptMemeReadsAO3sPromptBlurbs | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | tagSetFourFieldsAndAssociationURLHaveNoWrite | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | ownSignUpParsesNestedRequestsAndOffers | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3ChallengeParsingTests | promptEditsLandOnThePromptByID | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| KokoroPronunciationBackupTests | captureReadsEveryLayer | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| KokoroPronunciationBackupTests | applyMergesRatherThanReplacing | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| KokoroPronunciationBackupTests | theArchiveWinsOnAConflict | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| KokoroPronunciationBackupTests | anEmptyArchiveChangesNothing | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| KokoroPronunciationBackupTests | archivesWithoutTheKeyStillDecode | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| KokoroPronunciationBackupTests | manifestRoundTripsWithPronunciations | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| KokoroPronunciationBackupTests | addingPronunciationsDidNotBumpTheSchemaVersion | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| KokoroPronunciationBackupTests | aManifestWithoutPronunciationsLeavesLocalCorrectionsAlone | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3WorkFormParsingTests | postConfirmationNamesWhatIsMissing | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3WorkFormParsingTests | bulkFormParsesCommentPermissionsAndSelfRemoval | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3WorkFormParsingTests | parsesChapterFormAndOmitsPositionWhenAbsent | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3WorkFormParsingTests | parsesSeriesManageOrder | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3WorkFormParsingTests | parsesCollectionRowStateOnTheBlurb | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3WorkFormParsingTests | parsesDeleteConfirmCountsWhenPresent | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3WorkFormParsingTests | draftsURLIsItsOwnIndexNotAWorksFilter | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| AO3WorkFormParsingTests | previewExtractsThePreviewPane | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| CanonicalWorkMergeTests | identityIndexFallsBackToRecordUUID | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneSweepsExistingRecordsTests | choosingNoAccountShortcutsStaysEmpty | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testMigrationFromUserDefaults | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testOutOfBandWriteIsReflected | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testUserDefaultsWriteAfterKeychainItemExistsIsIgnored | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testEmptyFirstLaunchPlantsSentinelAndIgnoresLaterUserDefaults | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testUnavailableKeychainDoesNotWipeUserDefaults | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testAddPublishesOnlyOwnPubUnderItsOwnKey | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testMergeAdoptsUnionOfAllPublishedDevicePubs | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testDisappearingPublishedPubDoesNotUntrust | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testStolenRevokePropagatesAndUntrustsOnOtherDevices | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testMergingARemoteRevocationUntrustsAndDenylistsLocally | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testDenylistedKeyCannotBeReimportedByAddOrMerge | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testRetiredRevokeUntrustsAndPropagatesButDoesNotDenylist | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testEmptyRemoteIsANoOpAndOwnKeyStaysTrusted | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testMalformedRemoteValuesAreRejectedNotCrashed | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testTrustedDevicesListsOnlyPeersWithLabel | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testMergedPeerGetsMetadataToo | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testRemoteRevocationClearsMetadataOnMerge | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |
| TombstoneTrustStoreTests | testReMergeDoesNotResetExistingMetadata | none | absent: Android has no such code. The feature is completely missing or drops the data. | P3 |

## Remaining Rules

- **AO3CommentsParseTests** - `ownAccountRoleOverridesWorkAuthorAndUsesUsernameNotPseud`: not read at `unknown`
- **AO3CommentsParseTests** - `missingCommentsRegionThrowsParse`: not read at `unknown`
- **AO3InboxParseTests** - `adminHiddenRowBecomesATombstoneInsteadOfBeingDropped`: not read at `unknown`
- **AO3InboxParseTests** - `rowMalformedAThirdWayFoldsIntoATombstoneRatherThanVanishing`: not read at `unknown`
- **AO3PreferencesParseTests** - `missingFormThrowsParseError`: not read at `unknown`
- **AO3ReadingsParsingTests** - `visitCountReadsTheWayTheBoardDraws`: implemented at `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3ReadingEntry.kt:40`
- **AO3SubscriptionsParseTests** - `usesLargestPaginationNumberForTotal`: not read at `unknown`
- **AO3SubscriptionsParseTests** - `readsTheUnsubscribeActionBesideEachWork`: not read at `unknown`
- **AO3SubscriptionsParseTests** - `aWorkWithoutAnUnsubscribeFormKeepsTheRowAndOmitsThePath`: not read at `unknown`
- **CustomFontBackupCompatibilityTests** - `aPathInTheNameIsRefused`: not read at `unknown`
- **KudosBackupFontRestoreTests** - `zipRestorePreservesAmbiguousCaseFoldedRowsAndFiles`: not read at `unknown`
- **KudosBackupFontRestoreTests** - `restorePreservesOneRowAndTwoCaseVariantFilesWhenIncomingMatchesOrphan`: not read at `unknown`
- **KudosBackupFontRestoreTests** - `restoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile`: not read at `unknown`
- **KudosBackupFontRestoreTests** - `legacyDirectoryRestorePreservesAmbiguousCaseFoldedRowsAndFiles`: not read at `unknown`
- **KudosBackupFontRestoreTests** - `zipRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile`: not read at `unknown`
- **KudosBackupFontRestoreTests** - `legacyDirectoryRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile`: not read at `unknown`
- **KudosBackupTests** - `failedRestoreLeavesNoSwiftDataMutationsVisibleAfterCallerAutosave`: not read at `unknown`
- **KudosBackupTests** - `restoreMergesByAO3WorkIDBeforeUUID`: not read at `unknown`
- **KudosBackupTests** - `restoreMergesByCanonicalAO3URLBeforeUUID`: not read at `unknown`
- **KudosBackupTests** - `restoreSkipsMembershipReferencingMissingWork`: not read at `unknown`
- **PreReplaceBackupNamingTests** - `twoCopiesOnTheSameDayDoNotShareAName`: not read at `unknown`
- **PreReplaceBackupNamingTests** - `theCopyIsNamedAsAnImportableBackup`: not read at `unknown`
- **ReadiumProgressPersistenceTests** - `progressionNoiseBelowThresholdIsNeverWritten`: not read at `unknown`
- **ReadiumProgressPersistenceTests** - `progressionPastThresholdIsWrittenAfterInterval`: not read at `unknown`
- **ReadiumProgressPersistenceTests** - `emptyLocatorIsIgnored`: not read at `unknown`
- **ReadiumProgressPersistenceTests** - `seedPreventsRewriteOfIdenticalOpenLocator`: not read at `unknown`
- **ReadiumProgressPersistenceTests** - `firstDifferentLocatorAfterSeedCanWrite`: not read at `unknown`
- **ReadiumProgressPersistenceTests** - `identicalStringAfterSeedDoesNotWriteEvenWithProgression`: not read at `unknown`
- **ReadiumProgressPersistenceTests** - `noiseDoesNotArmATrailingWrite`: not read at `unknown`
- **ReadiumProgressPersistenceTests** - `meaningfulChangeInsideWindowArmsTrailingWrite`: not read at `unknown`
- **FolderSyncTests** - `syncDownPreservesEveryCaseFoldedDatabaseRow`: not read at `unknown`
- **FolderSyncTests** - `syncDownTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile`: not read at `unknown`
- **FolderSyncTests** - `syncDownMissingFileIsNoop`: not read at `unknown`
- **FolderSyncTests** - `foldConflictContentsDoesNotAdoptIncomingUnsignedTombstones`: not read at `unknown`
- **FolderSyncTests** - `removedCollectionMembershipIsNotResurrectedByStaleSync`: not read at `unknown`
- **IncompleteBackupReportingTests** - `theStreamingExporterNamesWhatItCouldNotInclude`: not read at `unknown`
- **PersistenceSyncTests** - `progressMergeDoesNotRegressToOlderSnapshot`: not read at `unknown`
- **PersistenceSyncTests** - `backupRestoreKeepsNewerLocalProgress`: not read at `unknown`
- **PersistenceSyncTests** - `deletingWorkThenImportingOlderBackupDoesNotResurrectIt`: not read at `unknown`
- **PersistenceSyncTests** - `newestTombstoneDecidesSuppressionWhenSeveralShareAO3Identity`: not read at `unknown`
- **PersistenceSyncTests** - `membershipChangesUpdateQueueFreshnessSignal`: not read at `unknown`
- **PersistenceSyncTests** - `freshInstallRestoreAdoptsArchivedFlagsWithNoExistingLocalRecord`: not read at `unknown`
- **PersistenceSyncTests** - `tombstoneSurvivesBackupRoundTripIntoFreshInstall`: not read at `unknown`
- **ReadingLogBackupTests** - `tombstoneSuppressesResurrectionOfAnOlderArchive`: not read at `unknown`
- **ReadingLogBackupTests** - `replaceOmissionMintsTombstonesAndALaterMergeDoesNotResurrect`: not read at `unknown`
- **ReadingLogRestoreDefectTests** - `replaceLibraryStillDropsRecordsTheArchiveDoesNotHave`: not read at `unknown`
- **ReadingLogRestoreDefectTests** - `repeatingAnIdenticalReplaceLibraryIsNotDestructive`: not read at `unknown`
- **ReadingLogRestoreDefectTests** - `historyAndStarsFollowAWorkMergedIntoAnExistingCopy`: not read at `unknown`
- **ReadingLogRestoreDefectTests** - `historyForAWorkThatIsNotHereStaysDetachedRatherThanBeingDropped`: not read at `unknown`
- **ReadingLogRestoreDefectTests** - `aDeletionOnAnotherDeviceRemovesTheLocalCopy`: not read at `unknown`
- **AO3CollectionParsingTests** - `fourIndependentCollectionFlagsParseTogether`: not read at `unknown`
- **AO3CollectionParsingTests** - `collectionPeopleParse`: not read at `unknown`
- **AO3CollectionParsingTests** - `collectionShowParsesExactWorksAndBookmarksStats`: not read at `unknown`
- **AO3CollectionParsingTests** - `collectionShowReadsTotalsFromItsOwnNavLinks`: not read at `unknown`
- **AO3CollectionParsingTests** - `collectionSegmentParsersKeepEachPager`: not read at `unknown`
- **AO3ChallengeParsingTests** - `utcDateRoundTripDoesNotDrift`: not read at `unknown`
- **AO3ChallengeParsingTests** - `draftPromptIDsStayUniqueAndAreNeverPosted`: not read at `unknown`
- **AO3WorkFormParsingTests** - `tagRemovalIsADiffNotADeleteAPI`: not read at `unknown`
- **AO3WorkFormParsingTests** - `bulkPostCarriesOnlyUniformFieldsAndTagsMergePerWork`: not read at `unknown`
- **CanonicalWorkMergeTests** - `remoteLedMatchesBySourceURLWhenNoStoredID`: not read at `unknown`
- **CanonicalWorkMergeTests** - `remoteLedPassesUnmatchedRemoteThroughAndDropsLocalOnly`: not read at `unknown`
- **CanonicalWorkMergeTests** - `remoteLedPreservesRemoteOrder`: not read at `unknown`
- **CanonicalWorkMergeTests** - `remoteOnlyDropsEntriesWithALocalTwin`: implemented at `android/app/src/main/java/io/github/cidy02/kudos/works/CanonicalWorkMerge.kt:36`
- **NewestTombstoneWinsTests** - `aLaterDeletionReplacesTheEarlierTombstone`: not read at `unknown`
- **NewestTombstoneWinsTests** - `aSnapshotBetweenTheTwoDeletionsCannotResurrectTheWork`: not read at `unknown`
- **NewestTombstoneWinsTests** - `theAdoptedRowStillVerifiesAndTakesTheSignedIdentity`: not read at `unknown`
- **NewestTombstoneWinsTests** - `anOlderIncomingTombstoneLeavesTheLaterOneAlone`: not read at `unknown`
- **TombstoneSweepsExistingRecordsTests** - `aTrustedTombstoneRemovesASavedLinkButNotOneSavedAgainLater`: not read at `unknown`
- **TombstoneSweepsExistingRecordsTests** - `aTrustedTombstoneRemovesAHighlightButNotOneEditedLater`: not read at `unknown`
- **TombstoneSweepsExistingRecordsTests** - `aTrustedTombstoneRemovesAQueueMembershipButNotOneChangedLater`: not read at `unknown`
- **TombstoneSweepsExistingRecordsTests** - `aDeletedCopyDoesNotTakeTheOtherDevicesMarkOnTheSamePassageWithIt`: not read at `unknown`
- **TombstoneSweepsExistingRecordsTests** - `replaceLibraryDoesNotSweepExistingSavedLinks`: not read at `unknown`
- **TombstoneTrustStoreTests** - `testOwnDeviceAlwaysTrusted`: not read at `unknown`
- **TombstoneTrustStoreTests** - `testNormalizedPublicKeyAppliedOnEveryPath`: not read at `unknown`
- **CanonicalWorkMergeTests** - `canonicalWorkIDIsStableAcrossSides`: implemented at `android/app/src/main/java/io/github/cidy02/kudos/works/CanonicalWorkMerge.kt:11`
- **AO3ReadingsParsingTests** - `readsEveryRowInPageOrder`: implemented at `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3AccountParser.kt:44`
- **AO3ReadingsParsingTests** - `readsVisitCounts`: implemented at `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3ReadingEntry.kt:80`
- **AO3ReadingsParsingTests** - `readsTheVersionNote`: implemented at `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3ReadingEntry.kt:87`
- **AO3ReadingsParsingTests** - `lastVisitedKeepsAO3sOwnWordingAndOnlyAgoesADuration`: implemented at `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3ReadingEntry.kt:29`
- **AO3ReadingsParsingTests** - `readsMarkedForLaterAndFlaggedToSkip`: implemented at `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3ReadingEntry.kt:64`
- **AO3ReadingsParsingTests** - `readsADeletedWorkRow`: implemented at `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3ReadingEntry.kt:61`
- **AO3ReadingsParsingTests** - `aPageWithNoReadingsIsEmptyNotAFailure`: implemented at `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3AccountParser.kt`
