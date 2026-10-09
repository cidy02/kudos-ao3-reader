# Audit A25: iOS test rules with no Android test, for parsing, backup and sync

### AO3CommentsParseTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParser.kt`
- Searches: `grep -rn 'Comments' android/app/src/test`
**Rules:**
- `parsesThreadedComments`: parses comment tree. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParserTest.kt:15`]
- `parsesPaginationAndTotals`: paginates. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParserTest.kt:85`]
- `recognizedEmptyCommentsPageParsesAsEmpty`: empty handles. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParserTest.kt:33`]
- `ownAccountRoleOverridesWorkAuthorAndUsesUsernameNotPseud`: parses role overrides. [uncovered: parseThread]
  - `    @Test func ownAccountRoleOverridesWorkAuthorAndUsesUsernameNotPseud() {`
- `missingCommentsRegionThrowsParse`: fails without ol. [uncovered: parseThread]
  - `    @Test func missingCommentsRegionThrowsParse() {`

### AO3InboxParseTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxParser.kt`
- Searches: `grep -rn 'Inbox' android/app/src/test`
**Rules:**
- `visibleWorkMetadataDeduplicatesInScreenOrder`: deduplicates work IDs. [uncovered: uniqueWorkIDs]
  - `        #expect(AO3InboxModel.uniqueWorkIDs([123, 456, 123, 789, 456]) == [123, 456, 789])`
- `parsesEntriesWithIdentityWorkAndState`: parses standard comment rows. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxParserTest.kt:20`]
- `parsesGuestCommentAndRepliedState`: parses guest properties. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxParserTest.kt:47`]
- `tagCommentHasNoWorkButKeepsWebLink`: handles no work tags. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxParserTest.kt:70`]
- `anonymousCreatorAlwaysResolvesToAuthorRole`: anonymous creator role. [uncovered: participantRole]
  - `        #expect(anon.participantRole(workAuthors: workAuthors, currentUsername: "C") == .workAuthor)`
- `readsHeadingTotalsAndPagination`: parses page totals. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxParserTest.kt:85`]
- `parsesFixtureDerivedBulkFormAndDistinctInboxRowIDs`: parses bulk forms. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxParserTest.kt:111`]
- `parsesFixtureDerivedFiltersAndBuildsTheirGETURL`: filter parsing. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxParserTest.kt:182`]
- `inboxPillsArePresetsOverAO3sOwnFilters`: builds filter pills. [uncovered: AO3InboxFilterPill]
  - `        let pills = try AO3InboxFilterPills(form: filters)`
- `buildsFixtureDerivedBulkRequestBody`: form body. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxParserTest.kt:145`]
- `recognizedEmptyInboxParsesAsEmpty`: empty inbox handling. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxParserTest.kt:225`]
- `unrecognizedMarkupThrowsInsteadOfFabricatingEmpty`: throws on missing ol. [weaker: lacks ol check]
  - `        #expect(throws: AO3Error.self) { _ = try AO3Client.parseInboxPage(malformed, page: 1) }`
- `adminHiddenRowBecomesATombstoneInsteadOfBeingDropped`: tombstone parsing. [uncovered: parseInboxPage]
  - `        #expect(tombstone.isUnavailable)`
- `rowMalformedAThirdWayFoldsIntoATombstoneRatherThanVanishing`: fallback parsing. [uncovered: parseInboxPage]
  - `        let malformedRow = try #require(page.items.first { $0.id < 0 })`
- `buildsInboxURL`: URL generation. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxParserTest.kt:246`]
- `countsOnlyCommentsTheReaderCanStillAnswer`: count active replies. [uncovered: awaitingReplyCount]
  - `        #expect(AO3InboxTally.awaitingReplyCount(items) == 2)`
- `headerLineMarksThePageOnlyCount`: builds header string. [uncovered: headerLine]
  - `        #expect(paged.hasSuffix("3 awaiting your reply on this page"))`


### AO3NamedSubscriptionsParseTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3NamedSubscriptions.kt`
- Searches: `grep -rn 'Subscriptions' android/app/src/test`
**Rules:**
- `seriesScopeKeepsSeriesRowsWithTheirBylineAndForm`: Extracts series subscriptions. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/account/AO3AccountParserTest.kt:85`]
- `usersScopeKeepsOnlyUserRows`: Extracts user subscriptions. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/account/AO3AccountParserTest.kt:85`]
- `aNonAuthorLinkInASeriesRowIsNotACreator`: only rel=author is creator. [weaker: lacks rel=author check]
  - `        let page = try AO3Client.parseNamedSubscriptions(row, scope: .series, page: 1)`
  - `        #expect(page.rows.first?.creators.map(\.displayName) == ["a"])`
- `scopeIsTheTypeParameter`: Scope determines type in URL. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/account/AO3AccountParserTest.kt:15`]
- `subtitleCountsThePageInTheScopesNoun`: subtitle logic. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/account/AO3AccountParserTest.kt:111`]


### AO3PreferencesParseTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/preferences/AO3PreferencesParser.kt`
- Searches: `grep -rn 'Preferences' android/app/src/test`
**Rules:**
- `parsesTogglesSelectsTextAndWebLinks`: parses toggles, selects, text inputs, strips question marks. [weaker: lacks selects, texts, ? stripping]
  - `        #expect(!form.sections.map(\.title).contains(where: { $0.contains("?") }))`
  - `        #expect(skin.selectedValue == "42")`
- `parsesHelpPageBodyFromDefinitionList`: parses help page content. [no code: parseHelpPage]
- `missingFormThrowsParseError`: throws on missing form. [uncovered: parse]
  - `        #expect(throws: AO3Error.self) { try AO3Client.parsePreferencesForm(from: "<html><body>no form</body></html>") }`


### AO3ReadingsParsingTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3ReadingEntry.kt`
- Searches: `grep -rn 'Reading' android/app/src/test`
**Rules:**
- `readsEveryRowInPageOrder`: basic metadata parsing. [uncovered: parseFromBlurb]
  - `        #expect(entries.map(\.workID) == [11, 22, 33, nil])`
- `readsVisitCounts`: parses visit count. [uncovered: parseVisitCount]
  - `        #expect(entries.map(\.visitCount) == [7, 2, 1, nil])`
- `visitCountReadsTheWayTheBoardDraws`: formats visit count string. [uncovered: visitCountDisplay]
  - `        #expect(entries[1].visitCountDisplay == "Visited twice")`
- `readsTheVersionNote`: parses version status. [uncovered: parseVersionStatus]
  - `        #expect(entries[0].versionDisplay == "Update available")`
- `lastVisitedKeepsAO3sOwnWordingAndOnlyAgoesADuration`: formats last visited string. [uncovered: lastVisitedDisplay]
  - `        #expect(entries[0].lastVisitedDisplay == "Last visited 2 days ago")`
- `readsMarkedForLaterAndFlaggedToSkip`: parses later/skip flags. [uncovered: parseFromBlurb]
  - `        #expect(entries.map(\.isMarkedForLater) == [false, true, false, false])`
- `readsADeletedWorkRow`: parses deleted work row. [uncovered: parseFromBlurb]
  - `        #expect(deleted.isDeletedWork)`
- `aPageWithNoReadingsIsEmptyNotAFailure`: empty page returns empty list. [uncovered: parseFromBlurb]
  - `        #expect(try AO3Client.parseReadingEntries(from: "<html><body></body></html>").isEmpty)`


### AO3SubscriptionsParseTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3AccountParser.kt`
- Searches: `grep -rn 'parseSubscriptionsPage' android/app/src/main/java/io/github/cidy02/kudos`
**Rules:**
- `keepsOnlyWorkSubscriptions`: Only work subscriptions (from `<dt>` items) should surface; series and user subscriptions are dropped. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/account/AO3AccountParserTest.kt:130`].
- `readsTitleAndAllBylineAuthors`: Co-authored works list every byline pseud. [weaker: lacks a co-authored work with multiple authors in the test].
  - Essential lines:
    ```swift
        // Co-authored works list every byline pseud.
        #expect(page.works[1].authors == ["penname", "cowriter"])
    ```
- `usesLargestPaginationNumberForTotal`: Uses the largest pagination number for the total pages. [uncovered: parseSubscriptionsPage].
  - Essential lines:
    ```swift
        let page = try AO3Client.parseSubscriptionsPage(html, page: 1)
        #expect(page.currentPage == 1)
        #expect(page.totalPages == 3)
    ```
- `readsTheUnsubscribeActionBesideEachWork`: Reads the unsubscribe action beside each work. [uncovered: parseSubscriptionsPage].
  - Essential lines:
    ```swift
        let index = try AO3Client.parseSubscriptionsIndex(html, page: 1)
        #expect(index.page.works.map(\.id) == [45_678_901, 12_345])
        #expect(index.unsubscribePaths == [
            45_678_901: "/users/me/subscriptions/1",
            12_345: "/users/me/subscriptions/2"
        ])
    ```
- `aWorkWithoutAnUnsubscribeFormKeepsTheRowAndOmitsThePath`: A work without an unsubscribe form keeps the row and omits the path. [uncovered: parseSubscriptionsPage].
  - Essential lines:
    ```swift
        let index = try AO3Client.parseSubscriptionsIndex(bare, page: 1)
        #expect(index.page.works.map(\.id) == [11, 22])
        #expect(index.unsubscribePaths == [22: "/users/me/subscriptions/9"])
    ```


### AO3UserStatsParsingTests
- Code: No code for UserStats
- Searches: `grep -rn 'parseUserStats' android/app/src/main/java/io/github/cidy02/kudos`
**Rules:**
- `totalsComeFromTheTotalsBlockNotTheFirstWork`: Totals come from the totals block, not the first work. [no code: UserStats].
- `readsWordCountAndTheRestOfTheTotals`: Reads word count and the rest of the totals. [no code: UserStats].
- `userSubscriptionsIsNotMistakenForSubscriptions`: User subscriptions is not mistaken for subscriptions. [no code: UserStats].
- `anAccountWithNoWorksParsesEmptyRatherThanThrowing`: An account with no works parses empty rather than throwing. [no code: UserStats].
- `statsURLAsksForAllYears`: Stats URL asks for all years. [no code: UserStats].


### CustomFontBackupCompatibilityTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/files/CustomFontRepository.kt`
- Searches: `grep -rn 'font' android/app/src/main/java/io/github/cidy02/kudos/backup/BackupValidator.kt android/app/src/main/java/io/github/cidy02/kudos/files/CustomFontRepository.kt android/app/src/main/java/io/github/cidy02/kudos/files/FontFileStore.kt`
**Rules:**
- `aRealInstalledFontIsAccepted`: A real installed font is accepted. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupSecurityTest.kt:103`].
- `aGoodFontInAnUnsupportedContainerIsRefused`: A good font in an unsupported container is refused. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupSecurityTest.kt:197`].
- `aFontLargerThanABackupCanCarryIsRefused`: A font larger than a backup can carry is refused. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupSecurityTest.kt:174`].
- `bytesThatAreNotAFontAreRefused`: Bytes that are not a font are refused. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupSecurityTest.kt:137`].
- `aPathInTheNameIsRefused`: A path in the font name is refused. [uncovered: requireSafeFontFileName].
  - Essential lines:
    ```swift
        for name in ["../escape.ttf", "nested/font.ttf"] {
            #expect(
                KudosBackupContents.fontRejectionReason(fileName: name, data: font.data) != nil,
                "\(name) must not reach a backup"
            )
        }
    ```
- `everyRefusalExplainsItself`: Every font rejection reason explains itself to the user. [uncovered: validate].
  - Essential lines:
    ```swift
        let reason = KudosBackupContents.fontRejectionReason(
            fileName: "\(UUID().uuidString).woff", data: Data([0x00])
        )
        let text = try? #require(reason)
        #expect(text?.isEmpty == false)
        #expect(text?.hasSuffix(".") == true)
    ```


### KudosBackupFontRestoreTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupImporter.kt`
- Searches: `grep -rn 'font' android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt`
**Rules:**
- `validFontRestoresInstalledBytes`: A valid font restores its installed bytes. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupSecurityTest.kt:103`].
- `invalidBytesWithSFNTSignatureAreRejected`: Invalid bytes with SFNT signature are rejected. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupSecurityTest.kt:137`].
- `unsupportedExtensionIsRejected`: Unsupported extension is rejected. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupSecurityTest.kt:197`].
- `zipOversizedEntryIsRejectedBeforeExtraction`: ZIP oversized entry is rejected before extraction. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupSecurityTest.kt:174`].
- `zipOversizedAggregateIsRejectedBeforeExtraction`: ZIP oversized aggregate is rejected before extraction. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupSecurityTest.kt:220`].
- `legacyDirectoryOversizedEntryIsRejectedBeforeRead`: Legacy directory oversized entry is rejected before read. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupSecurityTest.kt:174`].
- `unreadableLocalBytesAndOrphanSuffixArePreserved`: Unreadable local bytes and orphan suffix are preserved. [weaker: tests with empty byte array, lacks POSIX 0o000 permission test].
  - Essential lines:
    ```swift
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: occupiedURL.path)
    ```
- `identicalCaseVariantReusesLocalFileAndDatabaseRow`: Identical case variant reuses local file and database row. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt:569`].
- `zipRestorePreservesAmbiguousCaseFoldedRowsAndFiles`: Zip restore preserves ambiguous case folded rows and files. [uncovered: restore].
  - Essential lines:
    ```swift
        #expect(
            Set(rows.map(\.fileName)) == [
                fixture.archivedFileName,
                fixture.localFileName,
                fixture.suffixFileName
            ],
            "Ambiguous case-fold matches must preserve every DB row and install a suffixed font."
        )
    ```
- `restorePreservesOneRowAndTwoCaseVariantFilesWhenIncomingMatchesOrphan`: Restore preserves one row and two case variant files when incoming matches orphan. [uncovered: restore].
  - Essential lines:
    ```swift
            #expect(
                Set(try context.fetch(FetchDescriptor<CustomFont>()).map(\.fileName))
                    == [archivedFileName, suffixFileName],
                "The restore must retain the original row and add only the suffixed incoming row."
            )
    ```
- `restoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile`: Restore treats two local files as ambiguous when incoming matches database file. [uncovered: restore].
  - Essential lines:
    ```swift
        #expect(
            Set(try fixture.context.fetch(FetchDescriptor<CustomFont>()).map(\.fileName))
                == [fixture.archivedFileName, fixture.suffixFileName],
            "A local-file ambiguity must preserve the row-owned bytes and add a suffixed row."
        )
    ```
- `legacyDirectoryRestorePreservesAmbiguousCaseFoldedRowsAndFiles`: Legacy directory restore preserves ambiguous case folded rows and files. [uncovered: restore].
  - Essential lines:
    ```swift
            let decoded = try KudosBackupContents.read(from: packageURL)
            _ = try KudosBackupService.restore(
                decoded,
                into: fixture.context,
                defaults: fixture.defaults
            )
            try assertCaseVariantFixtureWasPreserved(fixture)
    ```
- `zipRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile`: Zip restore treats two local files as ambiguous when incoming matches database file. [uncovered: restore].
  - Essential lines:
    ```swift
            let decoded = try KudosBackupContents.read(from: archiveURL)
            _ = try KudosBackupService.restore(
                decoded,
                into: fixture.context,
                defaults: fixture.defaults
            )
            try assertLocalFileAmbiguityFixtureWasPreserved(fixture)
    ```
- `legacyDirectoryRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile`: Legacy directory restore treats two local files as ambiguous when incoming matches database file. [uncovered: restore].
  - Essential lines:
    ```swift
            let decoded = try KudosBackupContents.read(from: packageURL)
            _ = try KudosBackupService.restore(
                decoded,
                into: fixture.context,
                defaults: fixture.defaults
            )
            try assertLocalFileAmbiguityFixtureWasPreserved(fixture)
    ```
- `localReaderFontIDRetention`: Local reader font ID retention is respected. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:835`].


### KudosBackupTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupImporter.kt`
- Searches: `grep -rn 'backup' android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt`
**Rules:**
- `archiveRoundTripPreservesManifestAndAssets`: Archive round trip preserves manifest and assets. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt`].
- `authorIdentityPersistsLocallyWithoutChangingBackupSchema`: Author identity persists locally without changing backup schema. [no code: verifiedAuthorIdentities].
- `downloadedAtUsesRecencyAndAnAbsentKeyNeverClearsIt`: `downloadedAt` uses recency and an absent key never clears it. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/DownloadedAtBackupTest.kt:10`].
- `restoreMergesRecordsTagsAssetsAndSettings`: Restore merges records, tags, assets, and settings. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupTrustPhase2Test.kt`].
- `failedRestoreLeavesNoSwiftDataMutationsVisibleAfterCallerAutosave`: Failed restore leaves no database mutations visible. [uncovered: restore].
  - Essential lines:
    ```swift
        var restoreError: NSError?
        do {
            _ = try KudosBackupService.restore(
                contents,
                into: context,
                defaults: try testDefaults()
            )
    ```
- `backupRestoresReadingQueuesAndPreservedEPUBs`: Backup restores reading queues and preserved EPUBs. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt:1851`].
- `restoreMergesByAO3WorkIDBeforeUUID`: Restore merges by AO3 Work ID before UUID. [uncovered: restore].
  - Essential lines:
    ```swift
        let works = try context.fetch(FetchDescriptor<SavedWork>())
        let restored = try #require(works.first)
        #expect(works.count == 1)
        #expect(restored.id == existing.id)
        #expect(restored.title == "Archived AO3 Work")
    ```
- `restoreMergesByCanonicalAO3URLBeforeUUID`: Restore merges by canonical AO3 URL before UUID. [uncovered: restore].
  - Essential lines:
    ```swift
        let works = try context.fetch(FetchDescriptor<SavedWork>())
        let restored = try #require(works.first)
        #expect(works.count == 1)
        #expect(restored.id == existing.id)
        #expect(restored.title == "Archived URL Work")
    ```
- `restorePreservedStatusWithMissingEPUBBecomesMissingFile`: Restore preserved status with missing EPUB becomes missing file. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt:908`].
- `restoreSkipsMembershipReferencingMissingWork`: Restore skips membership referencing missing work. [uncovered: restore].
  - Essential lines:
    ```swift
        _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())
        #expect(try context.fetch(FetchDescriptor<SavedWork>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ReadingQueueMembership>()).isEmpty)
    ```
- `versionOneBackupDefaultsQueueFields`: Version one backup defaults queue fields. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt:59`].
- `unsupportedBackupVersionIsRejected`: Unsupported backup version is rejected. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt:705`].
- `legacyDirectoryPackageBackupRemainsReadable`: Legacy directory package backup remains readable. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt:131`].
- `truncatedArchiveIsRejectedAsInvalid`: Truncated archive is rejected as invalid. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt:786`].
- `streamedExportMatchesTheInMemoryArchive`: Streamed export matches the in-memory archive. [uncovered: makeExportPlan].
  - Essential lines:
    ```swift
        let plan = try KudosBackupService.makeExportPlan(...)
        try KudosBackupService.writeArchive(plan, to: destination)
        let streamedZip = try MiniZip(data: streamed, limits: .backup)
        #expect(streamedZip.names == inMemoryZip.names)
    ```
- `exportRefusesArchivesTheReaderWouldReject`: Export refuses archives the reader would reject. [uncovered: writeArchive].
  - Essential lines:
    ```swift
        #expect(throws: KudosBackupExportError.self) {
            try KudosBackupService.writeArchive(plan, to: destination, limits: limits(entries: 1))
        }
    ```

### PreReplaceBackupNamingTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupRepository.kt` and `BackupScreen.kt`
- Searches: `grep -rni 'Replace' ...`, `grep -rni 'before-replace' ...`, `grep -rni 'attemptLimit' ...`
**Rules:**
- `twoCopiesOnTheSameDayDoNotShareAName`: different hour/min shouldn't overwrite. [uncovered: `BackupRepository.suggestedSafetyBackupFileName`].
  - Essential lines:
    ```swift
        let morning = try Self.date("2026-09-20 09:15:00")
        let evening = try Self.date("2026-09-20 21:40:00")
        let first = PreReplaceBackupNaming.fileName(at: morning, attempt: 0)
        let second = PreReplaceBackupNaming.fileName(at: evening, attempt: 0)
        #expect(first != second)
    ```
- `retriesWithinOneSecondEachGetTheirOwnName`: changing attempt number generates a different name. [no code: retry loop].
  - Essential lines:
    ```swift
        let names = (0 ..< PreReplaceBackupNaming.attemptLimit).map {
            PreReplaceBackupNaming.fileName(at: instant, attempt: $0)
        }
        #expect(Set(names).count == names.count)
    ```
- `aSafetyCopyIsAttemptedMoreThanOnce`: disk must be allowed a retry for safety copies. [no code: retry loop].
  - Essential lines:
    ```swift
        #expect(PreReplaceBackupNaming.attemptLimit > 1)
    ```
- `theCopyIsNamedAsAnImportableBackup`: file has correct backup extension and prefix. [uncovered: `BackupRepository.suggestedSafetyBackupFileName`].
  - Essential lines:
    ```swift
        #expect(url.pathExtension == PreReplaceBackupNaming.fileExtension)
        #expect(url.lastPathComponent.hasPrefix("Kudos Library Before Replace "))
    ```
- `writingRefusesToOverwriteAnExistingCopy`: write must refuse rather than overwrite. [uncovered: `BackupScreen` file write logic].
  - Essential lines:
    ```swift
        let secondStage = directory.appendingPathComponent("stage-2")
        try Data("second".utf8).write(to: secondStage, options: .atomic)
        #expect(throws: (any Error).self) {
            try FileManager.default.moveItem(at: secondStage, to: url)
        }
    ```


### ReadiumProgressPersistenceTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderProgressGate.kt` and `ReaderProgressSaver.kt`
- Searches: `grep -rni 'debounce' ...`, `grep -rni 'lastReadDate' ...`
**Rules:**
- `streamedUpdatesAreDebounced`: fast progression updates are buffered. [covered: `android/app/src/test/java/io/github/cidy02/kudos/reader/ReaderProgressSaverTest.kt:14`].
- `noteEmitsWhenWindowElapsed`: buffered value emits after delay. [covered: `android/app/src/test/java/io/github/cidy02/kudos/reader/ReaderProgressSaverTest.kt:14`].
- `progressionNoiseBelowThresholdIsNeverWritten`: noise filter prevents micro-progressions from writing. [uncovered: `ReaderProgressGate.consider`].
  - Essential lines:
    ```swift
        let noisy = locator(total: 0.5004)
        bridge.note(locatorString: noisy, totalProgression: 0.5004, at: start.addingTimeInterval(10))
        #expect(writes.isEmpty)
    ```
- `progressionPastThresholdIsWrittenAfterInterval`: valid progression passes the filter. [uncovered: `ReaderProgressGate.consider`].
  - Essential lines:
    ```swift
        let moved = locator(total: 0.52)
        bridge.note(locatorString: moved, totalProgression: 0.52, at: start.addingTimeInterval(2.5))
        #expect(writes == [moved])
    ```
- `flushBypassesTheDebounceWindow`: manual flush writes pending value immediately. [covered: `android/app/src/test/java/io/github/cidy02/kudos/reader/ReaderProgressSaverTest.kt:81`].
- `flushIsNilWhenNothingChanged`: flushing an empty buffer does nothing. [uncovered: `ReaderProgressSaver.flush`].
  - Essential lines:
    ```swift
        bridge.seed(persistedLocatorString: s)
        bridge.markPersisted(locatorString: s, totalProgression: 0.3)
        #expect(bridge.locatorForFlush() == nil)
    ```
- `emptyLocatorIsIgnored`: blank locators are not recorded. [uncovered: `ReaderProgressGate.consider`].
  - Essential lines:
    ```swift
        bridge.note(locatorString: "", totalProgression: 0.5)
        #expect(bridge.latestLocatorString == nil)
    ```
- `seedPreventsRewriteOfIdenticalOpenLocator`: prevents re-writing identical locator on book open. [uncovered: `ReaderProgressGate.consider`].
  - Essential lines:
    ```swift
        bridge.seed(persistedLocatorString: s)
        bridge.record(locatorString: s, totalProgression: 0.25)
        bridge.markPersisted(locatorString: s, totalProgression: 0.25, at: Date())
        bridge.note(locatorString: s, totalProgression: 0.25, at: Date().addingTimeInterval(5))
        #expect(writes.isEmpty)
    ```
- `firstDifferentLocatorAfterSeedCanWrite`: actual progression post-open gets written. [uncovered: `ReaderProgressGate.consider`].
  - Essential lines:
    ```swift
        let opened = locator(total: 0.25)
        bridge.seed(persistedLocatorString: opened)
        let moved = locator(total: 0.40)
        bridge.note(locatorString: moved, totalProgression: 0.40, at: start)
        #expect(writes == [moved])
    ```
- `identicalStringAfterSeedDoesNotWriteEvenWithProgression`: re-reporting same locator string doesn't write. [uncovered: `ReaderProgressGate.consider`].
  - Essential lines:
    ```swift
        let opened = locator(total: 0.25)
        bridge.seed(persistedLocatorString: opened)
        bridge.note(locatorString: opened, totalProgression: 0.25, at: Date())
        #expect(writes.isEmpty)
    ```
- `debouncedLocatorDoesNotThrashLastReadDateOrLastModified`: debounced writes don't constantly bump library timestamp. [covered: `android/app/src/test/java/io/github/cidy02/kudos/reader/ReaderProgressMappingTest.kt:70`].
- `fullProgressStampUpdatesShelfAndSyncFields`: full progress save updates sync fields. [covered: `android/app/src/test/java/io/github/cidy02/kudos/reader/ReaderProgressMappingTest.kt:18`].
- `noiseDoesNotArmATrailingWrite`: below-threshold movement doesn't arm trailing write timer. [uncovered: `ReaderProgressGate`].
  - Essential lines:
    ```swift
        bridge.note(locatorString: locator(total: 0.5004), totalProgression: 0.5004, at: start.addingTimeInterval(0.1))
        // Wait past the debounce window; noise must still not emit.
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        #expect(writes.isEmpty)
    ```
- `meaningfulChangeInsideWindowArmsTrailingWrite`: valid move inside window sets up trailing timer. [uncovered: `ReaderProgressGate`].
  - Essential lines:
    ```swift
        let moved = locator(total: 0.35)
        bridge.note(locatorString: moved, totalProgression: 0.35, at: start.addingTimeInterval(0.2))
        #expect(writes.isEmpty) // still inside window
    ```


### EqualSizeEPUBStillSyncsTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/SyncRepository.kt`
- Searches: `grep -rni 'digest\|size' ...`
**Rules:**
- `aCorrectedBookOfTheSameLengthIsStillFetched`: changes that don't alter length are still fetched via digest. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:1102`].
- `anExistingBookGetsADigestOnReconcile`: old books without digests get one computed. [no code: background digest calculation migration].
  - Essential lines:
    ```swift
        _ = await PersistenceMigrationService.runIfNeeded(
            in: context, defaults: try testDefaults()
        )
        #expect(!work.epubDigest.isEmpty)
    ```


### FailedRestoreKeepsEPUBsTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupImporter.kt`
- Searches: `grep -rni 'fails' ...`, `grep -rni 'incoming' ...`
**Rules:**
- `aRestoreThatFailsLeavesTheExistingEPUBUntouched`: failed restore doesn't throw away local EPUBs. [no code: mid-restore validation failure (Android validates ZIP to memory before writing, avoiding partial failures natively)].
  - Essential lines:
    ```swift
        #expect(throws: (any Error).self) {
            _ = try KudosBackupService.restore(
                contents, into: context, defaults: defaults, mode: .replaceLibrary
            )
        }
        #expect(try Data(contentsOf: work.fileURL) == localBytes)
    ```
- `aRestoreThatSucceedsKeepsTheIncomingEPUB`: successful replace mode keeps the new EPUB. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/IncomingEpubGateTest.kt:47`].


### MergeMissingEPUBRecoveryTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`
- Searches: `grep -rni 'merge' ...`
**Rules:**
- `mergeRefillsAnEPUBThatWentMissingLocally`: merge mode fetches missing local EPUBs. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/IncomingEpubGateTest.kt:85`].
- `mergeLeavesAnExistingLocalEPUBAlone`: merge mode doesn't overwrite an existing local EPUB. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/IncomingEpubGateTest.kt:85`].


### ReadingAnnotationBackupTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`
- Searches: `grep -rni 'annotation' ...`, `grep -rni 'tombstone' ...`
**Rules:**
- `annotationsRoundTripThroughTheArchive`: annotations encode/decode fully through backup. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt:1858`].
- `olderArchivesWithoutAnnotationsStillDecode`: v7 archives process correctly without failing. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt`].
- `aDeletedAnnotationIsNotResurrectedByAnOlderArchive`: synced tombstones suppress deleted annotations. [covered: `android/app/src/test/java/io/github/cidy02/kudos/reader/AnnotationTombstoneTest.kt:273`].
- `aNewerArchivedEditWinsOverAnOlderLocalCopy`: newer edit wins and older snapshot is hidden/soft-deleted. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt:1660`].
- `sameChapterHighlightFromTwoDevicesCollapsesToOneOnRestore`: exact same passages deduplicate on restore. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupMergeParityTest.kt`].
- `differentKindOrLocatorNeverCollapses`: mismatched locators or kinds avoid deduplication. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupMergeParityTest.kt`].
- `hardDeletingAWorkTombstonesAndRemovesItsAnnotations`: work deletion cascades to annotations. [covered: `android/app/src/test/java/io/github/cidy02/kudos/works/WorkLifecycleTest.kt:419`].

### BackupLazyReadTests
- Code: No code for lazy ZIP/directory reading
- Searches: `find android/app/src/test/java/io/github/cidy02/kudos -type f -exec grep -l -i 'lazy' {} +`
**Rules:**
- `zipReadDoesNotExtractWorksUntilAccessed`: read(from:) must not extract Works/* or Fonts/* before an accessor. [no code: lazy ZIP reading].
- `directoryReadDoesNotMaterializeEPUBs`: Eager FileWrapper / Data(contentsOf:) of Works/ would throw here. Success means the tree was not read. [no code: lazy directory reading].
- `zipReadDoesNotExtractFontsUntilAccessed`: read(from:) must not extract Fonts/* until fontData is called. [no code: lazy ZIP reading].
- `directoryReadDoesNotMaterializeFonts`: Directory read lazy loads fonts. [no code: lazy directory reading].
- `swappedZipIsRejectedAtConfirmedImport`: Same path, different size: the confirm-time TOCTOU the split read introduced. Settings execute must refuse this. [no code: TOCTOU protection].
- `unchangedZipConfirmedImportReadsLazily`: Confirmed import reads lazily. [no code: lazy reading].
- `swappedDirectoryAssetIsRejectedAtConfirmedImport`: Dir swap rejected. [no code: TOCTOU protection].


### CrossPlatformBackupTests
- Code: `android/app/src/test/java/io/github/cidy02/kudos/backup/CrossPlatformRestoreTest.kt`
- Searches: `grep 'fun ' android/app/src/test/java/io/github/cidy02/kudos/backup/CrossPlatformRestoreTest.kt`
**Rules:**
- `iosAndAndroidGoldenArchivesRestoreAndRoundTrip`: golden archives restore and round trip. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/CrossPlatformRestoreTest.kt:53`].


### ExactColourBackupTests
- Code: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupPhase2FieldsTest.kt`
- Searches: `grep -i 'chosenColor' ...`
**Rules:**
- `chosenColorKeepsAnExactColourAnOlderArchiveDropped`: A custom "+" colour is stored as picked and survives a build that drops it. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupPhase2FieldsTest.kt:304`].
- `archivedQueueCarriesColorHexAndOlderArchivesDecode`: Archived queue carries colorHex. [uncovered: `decodeManifest`].
  - `let data = try JSONEncoder().encode(KudosBackupReadingQueue(queue: queue)); #expect(try JSONDecoder().decode(KudosBackupReadingQueue.self, from: data).colorHex == "#1E90FF")`
- `restoreBringsBackExactQueueAndCollectionColours`: Restore brings back exact queue and collection colours. [weaker: lacks queue check in its equivalent collection test].
  - `let restoredQueue = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first { $0.id == queue.id }); #expect(restoredQueue.colorHex == "#1E90FF" && restoredQueue.hue == 0.58)`


### FolderSyncBackgroundTaskTests
- Code: No code for folder sync background task autoSync scheduling
- Searches: `find android/app/src/test/java/io/github/cidy02/kudos -name '*FolderSyncWorker*'`
**Rules:**
- `scheduleRequiresConnectedFolderAndAutoSyncEnabled`: schedule requires connected folder and autoSync enabled. [no code: autoSyncEnabled].


### FolderSyncTests
- Code: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt`
- Searches: `grep 'fun ' android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt`
**Rules:**
- `aFolderWithFilesAndNoManifestIsWrittenToAndNothingInItIsPruned`: a folder with files and no manifest is written to and nothing in it is pruned. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:254`].
- `aManifestCutShortIsRepairedFromTheBackupAndNothingIsPruned`: a manifest cut short is repaired from the backup and nothing is pruned. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:182`].
- `aManifestThisBuildCannotReadIsNotWrittenOver`: a manifest this build cannot read is not written over. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:270`].
- `aListedLowercaseAndroidEPUBIsKeptAndRead`: a listed lowercase Android EPUB is kept and read. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:574`].
- `connectingAFolderRecordsItAsConfigured`: connecting a folder records it as configured. [no code: FolderSyncOnboardingState].
- `disconnectingDoesNotReArmTheOnboardingPrompt`: disconnecting does not re-arm the onboarding prompt. [no code: FolderSyncOnboardingState].
- `syncUpWritesReadableSyncDirectory`: sync up writes readable sync directory. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:717`].
- `syncDownRestoresWorkQueueAndCollection`: sync down restores work queue and collection. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:706`].
- `syncDownRejectsInvalidEPUBWithoutOverwritingLocalCopy`: sync down rejects invalid EPUB without overwriting local copy. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:607`].
- `syncDownRejectsInvalidFontWithoutPersistenceOrSelectorChange`: sync down rejects invalid font without persistence or selector change. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:479`].
- `syncDownSkipsOversizedFontAndRestoresUnrelatedState`: sync down skips oversized font and restores unrelated state. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:1010`].
- `syncDownPreservesCollidingFontBytesAndLocalSelector`: sync down preserves colliding font bytes and local selector. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:522`].
- `syncDownConvergesWhenFontLibraryExceedsAggregateCap`: sync down converges when font library exceeds aggregate cap. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:809`].
- `syncDownPreservesEveryCaseFoldedDatabaseRow`: sync down preserves every case folded database row. [uncovered: `runSync`].
  - `#expect(Set(rows.map(\.fileName)) == [archivedFileName, localFileName, suffixName], "Ambiguous case-fold matches must preserve every DB row and install a suffixed font.")`
- `syncDownTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile`: sync down treats two local files as ambiguous when incoming matches database file. [uncovered: `runSync`].
  - `#expect((try? Data(contentsOf: suffixURL)) == incomingData, "Local-file ambiguity must force a suffixed folder-sync restore.")`
- `syncUpThenSyncDownConvergesWithoutDuplicates`: sync up then sync down converges without duplicates. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:550`].
- `syncDownMissingFileIsNoop`: sync down missing file is noop. [uncovered: `runSync`].
  - `#expect(result.missingRemoteFile); #expect(result.didReadRemoteFile == false)`
- `operationGatePreventsInterleavedFolderSync`: operation gate prevents interleaved folder sync. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:1034`].
- `dirtyFlagOnlyClearsAfterAnActualWrite`: dirty flag only clears after an actual write. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:1044`].
- `foldConflictContentsMergesAllInputs`: fold conflict contents merges all inputs. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:1020`].
- `foldConflictContentsDoesNotAdoptIncomingUnsignedTombstones`: fold conflict contents does not adopt incoming unsigned tombstones. [uncovered: `foldConflictContents`].
  - `#expect(try targetContext.fetch(FetchDescriptor<SyncTombstone>()).isEmpty, "folder-sync fold must not insert the remote unsigned tombstone")`
- `folderSyncResultAbsorbsAnotherResultsCountsRatherThanDiscardingThem`: folder sync result absorbs another results counts rather than discarding them. [uncovered: `FolderSyncResult`].
  - `total.absorb(conflictFold); #expect(total.restoredWorks == 3)`
- `removedCollectionMembershipIsNotResurrectedByStaleSync`: removed collection membership is not resurrected by stale sync. [uncovered: `BackupMergeService.merge`].
  - `// The swift file cut off, but the expectation checks that a stale remote sync does not resurrect removed collection membership.`


### IncompleteBackupReportingTests
- Code: No code for Incomplete backup reporting (missing promised EPUB count)
- Searches: `grep -i -E 'missing|promised|Counted' android/app/src/test/java/io/github/cidy02/kudos/backup/*.kt`
**Rules:**
- `aWorkWhosePromisedEPUBNeverArrivesIsCounted`: restore reports missing promised EPUB. [no code: worksMissingPromisedEPUB counter].
- `aWorkThatNeverHadAnEPUBIsNotCounted`: works that never had an EPUB are not counted. [no code: worksMissingPromisedEPUB counter].
- `theStreamingExporterNamesWhatItCouldNotInclude`: exporter reports skipped entries. [uncovered: `BackupExporter.exportV2`].
  - `let skipped = try KudosBackupService.writeArchive(plan, to: destination); #expect(skipped == ["Works/\(work.id.uuidString).epub"])`


### OriginalsTravelInBackupsTests
- Code: `android/app/src/test/java/io/github/cidy02/kudos/backup/OriginalsRoundTripTest.kt`
- Searches: `grep -i 'originals' android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt`
**Rules:**
- `anOriginalSurvivesAZipRoundTrip`: Originals survive ZIP roundtrip. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/OriginalsRoundTripTest.kt:48`].
- `aSyncFolderCarriesOriginals`: Sync Folder carries originals. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:1062`].
- `restoreDoesNotOverwriteAnOriginalAlreadyHere`: Don't overwrite an original already here. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/OriginalsRoundTripTest.kt:67`].
- `restoreDoesNotLeaveASecondOriginalBesideTheFirst`: Don't leave a second original. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/OriginalsRoundTripTest.kt:67`].

### PersistenceSyncTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`
- Searches: `grep -rn 'newerMacPercentSurvivesBackupAndBeatsTheLocator' android/app/src/test/java/io/github/cidy02/kudos`
**Rules:**
- `migrationIsIdempotentAndMarksMissingEPUBRecoverable`: Missing EPUB is marked recoverable during migration. [no code: epub preservation migration].
  - `work.hasEPUB = true`, `work.epubPreservationStatus = .preserved`, `#expect(work.hasEPUB == false)`
- `progressMergeDoesNotRegressToOlderSnapshot`: Merging progress keeps the higher spine or newer progress. [uncovered: BackupMergeService.applyProgressLww].
  - `SyncMerge.applyProgress(SyncMerge.ProgressSnapshot(lastSpineIndex: 1...), to: work)`, `#expect(work.lastSpineIndex == 4)`
- `backupRestoreKeepsNewerLocalProgress`: Restoring backup should keep newer local progress. [uncovered: BackupMergeService.applyProgressLww].
  - `local.lastSpineIndex = 5`, `KudosBackupService.restore(...)`, `#expect(restored.lastSpineIndex == 5)`
- `newerMacPercentSurvivesBackupAndBeatsTheLocator`: Mac percent beats older locator. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/MacReadingPositionMergeTest.kt:21`].
- `olderMacPercentLeavesNewerLocalProgress`: Older Mac percent leaves newer local progress alone. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/MacReadingPositionMergeTest.kt:32`].
- `newerSnapshotWithoutMacPercentClearsIt`: Newer snapshot without Mac percent clears it. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/MacReadingPositionMergeTest.kt:54`].
- `keylessSnapshotAtTheSameTimeKeepsTheMacPercent`: Keyless snapshot at same time keeps the Mac percent. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/MacReadingPositionMergeTest.kt:66`].
- `newerKeylessSnapshotClearsTheMacPercentWhenTheLocatorMoves`: Newer keyless snapshot clears the Mac percent when the locator moves. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/MacReadingPositionMergeTest.kt:77`].
- `clearedMacPercentIsExportedAsNull`: Export cleared mac percent as null in JSON. [uncovered: BackupJson].
  - `let works = try #require(root["works"] as? [[String: Any]])`, `#expect(works[0]["legacyReaderProgress"] is NSNull)`
- `manifestWithoutTheMacPercentKeyDecodesItAsNil`: Missing key decodes as nil. [uncovered: BackupJson].
  - `works[0].removeValue(forKey: "legacyReaderProgress")`, `#expect(manifest.works.first?.legacyReaderProgress == nil)`
- `deletingWorkCreatesTombstone`: Work deletion creates a tombstone. [uncovered: WorkLifecycle.hardDelete].
  - `WorkLifecycle.hardDelete(work, in: context)`, `#expect(tombstones.count == 1)`
- `deletingWorkThenImportingOlderBackupDoesNotResurrectIt`: Older backup does not resurrect a deleted work. [uncovered: BackupMergeService.merge].
  - `WorkLifecycle.hardDelete(work, in: context)`, `KudosBackupService.restore(...)`, `#expect(try context.fetch(FetchDescriptor<SavedWork>()).isEmpty)`
- `backupImportDoesNotResurrectExplicitlyUnfavoritedWork`: Backup import doesn't resurrect unfavorited work. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/QueueTombstoneMergeTest.kt:100`].
- `newestTombstoneDecidesSuppressionWhenSeveralShareAO3Identity`: Several tombstones sharing AO3 identity suppress properly. [uncovered: BackupMergeService.merge].
  - `context.insert(SyncTombstone(... 300))`, `context.insert(SyncTombstone(... 50))`, `#expect(try context.fetch(FetchDescriptor<SavedWork>()).isEmpty)`
- `suppressedQueueMembershipsAreNotRehomedIntoSavedForLater`: Suppressed queue memberships are not saved for later. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/QueueTombstoneMergeTest.kt:20`].
- `newerMembershipChangeRevivesOlderQueueTombstone`: Newer membership change revives older queue tombstone. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/QueueTombstoneMergeTest.kt:33`].
- `newerQueueMetadataRevivesOlderQueueTombstone`: Newer queue metadata revives older queue tombstone. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/QueueTombstoneMergeTest.kt:44`].
- `ambiguousQueueTimestampsPreserveDataForSafety`: Ambiguous queue timestamps preserve data. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/QueueTombstoneMergeTest.kt:55`].
- `newestQueueTombstoneSuppressesDeterministically`: Newest queue tombstone suppresses deterministically. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/QueueTombstoneMergeTest.kt:63`].
- `oldQueueTombstoneDoesNotSuppressFreshQueueID`: Old queue tombstone doesn't suppress fresh queue ID. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/QueueTombstoneMergeTest.kt:78`].
- `membershipChangesUpdateQueueFreshnessSignal`: Membership changes update queue freshness signal. [uncovered: ReadingQueueService].
  - `let membership = ReadingQueueService.add(work, to: queue)`, `#expect(queue.lastMembershipChangedAt >= membership.lastModifiedAt)`
- `freshInstallRestoreAdoptsArchivedFlagsWithNoExistingLocalRecord`: Fresh install restore adopts archived flags. [uncovered: BackupMergeService.merge].
  - `archived.isFavorite = true`, `#expect(restored.isFavorite == true)`
- `exportedAtAloneDoesNotReviveContentStaleQueue`: Exported at alone doesn't revive content stale queue. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/QueueTombstoneMergeTest.kt:88`].
- `tombstoneSurvivesBackupRoundTripIntoFreshInstall`: Tombstone survives backup round trip. [uncovered: BackupMergeService.merge].
  - `WorkLifecycle.hardDelete(work, in: sourceContext)`, `KudosBackupService.restore(...)`, `#expect(try targetContext.fetch(FetchDescriptor<SyncTombstone>()).count == 1)`


### ReadingLogBackupTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`
- Searches: `grep -rn 'sessionsFavoritesAndWatermarksRoundTrip' android/app/src/test/java/io/github/cidy02/kudos`
**Rules:**
- `sessionsFavoritesAndWatermarksRoundTrip`: Reading log entities round trip through a backup. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupReadingLogTest.kt:102`].
- `keepInProgressOverrideDecodesNilWhenAbsent`: Omitted boolean key decodes as nil. [weaker: lacks `keepInProgressOverride` decoding from absent json explicitly].
  - `works[0].removeValue(forKey: "keepInProgressOverride")`, `#expect(decoded.works.first?.keepInProgressOverride == nil)`
- `v7AndV8ArchivesWithoutNewKeysStillImport`: Older backup manifests missing new tables still import. [uncovered: BackupJson].
  - `v7Object.removeValue(forKey: "readingSessions")`, `#expect(decodedV7.readingSessions.isEmpty)`
- `tombstoneSuppressesResurrectionOfAnOlderArchive`: Tombstones suppress old reading log entities. [uncovered: BackupMergeService.merge].
  - `target.insert(SyncTombstone(recordID: session.id...))`, `#expect(try target.fetch(FetchDescriptor<ReadingSession>()).isEmpty)`
- `replaceOmissionMintsTombstonesAndALaterMergeDoesNotResurrect`: Replace mints tombstones and doesn't resurrect. [uncovered: BackupMergeService.merge].
  - `KudosBackupService.restore(..., mode: .replaceLibrary)`, `#expect(tombs.contains { $0.recordType == .readingSession && $0.recordID == dropSessionID })`
- `addingReadingLogDidNotBumpTheSchemaVersion`: Reading log tables didn't bump backup schema version from 8. [uncovered: BackupManifest].
  - `#expect(KudosBackupManifest.currentVersion == 8)`


### ReadingLogRestoreDefectTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`
- Searches: `grep -rn 'replaceLibrary' android/app/src/test/java/io/github/cidy02/kudos`
**Rules:**
- `replaceLibraryKeepsFavoritesAndWatermarksMatchedByTarget`: Replace library keeps entities matched by target. [weaker: lacks watermarks and local UUID matching logic assertion].
  - `target.insert(localFavorite)`, `#expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).count == 1)`
- `replaceLibraryStillDropsRecordsTheArchiveDoesNotHave`: Replace library drops unmatched records. [uncovered: BackupMergeService.merge].
  - `target.insert(ReadingFavorite(kind: .tag, targetKey: "Slow Burn"))`, `#expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).isEmpty)`
- `repeatingAnIdenticalReplaceLibraryIsNotDestructive`: Repeating an identical replace library is idempotent. [uncovered: BackupMergeService.merge].
  - `KudosBackupService.restore(...)`, `#expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).count == 1)`
- `historyAndStarsFollowAWorkMergedIntoAnExistingCopy`: History and favorites attach to existing work UUID after merge. [uncovered: BackupMergeService.merge].
  - `target.insert(localWork)`, `#expect(restoredSession.workID == survivor.id)`
- `historyForAWorkThatIsNotHereStaysDetachedRatherThanBeingDropped`: History for missing work is preserved. [uncovered: BackupMergeService.merge].
  - `let orphan = session(workID: missingWorkID)`, `#expect(restored.workID == missingWorkID)`
- `aDeletionOnAnotherDeviceRemovesTheLocalCopy`: Deletion tombstone on another device removes local copy during merge. [uncovered: BackupMergeService.merge].
  - `target.insert(localCopy)`, `#expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).isEmpty)`


### StaleSyncUpKeepsRemoteAssetsTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/SyncRepository.kt`
- Searches: `grep -rn 'aStaleSyncUpKeepsAnotherDevicesRemoteEPUB' android/app/src/test/java/io/github/cidy02/kudos`
**Rules:**
- `aStaleSyncUpKeepsAnotherDevicesRemoteEPUB`: Stale sync up doesn't delete another device's remote EPUB. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncRepositoryTest.kt:1122`].


### AO3CollectionParsingTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3CollectionParser.kt`
- Searches: `grep -rn 'parseCollection' android/app/src/main/java/io/github/cidy02/kudos`
**Rules:**
- `fourIndependentCollectionFlagsParseTogether`: Parses the four independent collection flags (closed, moderated, unrevealed, anonymous) correctly. [uncovered: AO3CollectionParser.parseCollectionShow].
  - `let collections = try AO3Client.parseCollectionBlurbs(from: html)`, `#expect(collection.isClosed)`, `#expect(collection.isModerated)`
- `existingParseCollectionsStillReadsNameTitleAndMaintainers`: Parse collections still reads name, title, maintainers without flags. [uncovered: AO3AccountParser.parseCollections].
  - `let collections = try AO3Client.parseCollections(from: html)`, `#expect(collections[0].maintainerNames == ["Owner Pseud", "Mod Pseud"])`
- `itemApprovalTabsAndStagedFieldsParse`: Parse collection items with tabs and staged approval fields. [no code: Collection items parser].
  - `let tabs = try AO3Client.parseCollectionItemTabs(from: html)`, `#expect(tabs.contains(.unreviewed))`
- `collectionsIndexReadsOwnerClassCountsAndPageCount`: Parse collections index with owner class, works counts, and page numbers. [uncovered: AO3AccountParser.parseCollectionsIndex].
  - `let page = try AO3Client.parseCollectionsIndex(from: html, page: 1)`, `#expect(collection.viewerIsOwner)`, `#expect(collection.worksCount == 124)`
- `accountItemsPageReadsEachRowsCollectionDateAndDisabledControls`: Parse user items page reading rows, dates, disabled controls. [no code: Collection items parser].
  - `let page = try AO3Client.parseCollectionItemsPage(...)`, `#expect(item.collectionSlug == "fest")`, `#expect(!item.moderatorApprovalIsEditable)`
- `collectionFormParsesHeaderPreferencesProfileAndFourFlags`: Parses collection creation/edit form values. [no code: Collection form parser].
  - `let form = try AO3Client.parseCollectionForm(html, slug: "fest")`, `#expect(form.title == "Winter Fest")`
- `absentCollectionControlsAreNotPosted`: Absent form controls are correctly omitted from parsing. [no code: Collection form parser].
  - `let form = try AO3Client.parseCollectionForm(html, slug: "fest")`, `#expect(!names.contains(AO3CollectionParam.challengeType))`
- `selectedBlankChallengeOptionWinsEvenWhenItIsNotFirst`: Selects the blank challenge option properly even if not first. [no code: Collection form parser].
  - `let form = try AO3Client.parseCollectionForm(html, slug: "")`, `#expect(form.challengeType == "")`
- `nameAvailabilityHeuristic`: Heuristic for collection name availability correctly mapped from HTTP status. [no code: Collection API client].
  - `#expect(AO3Client.interpretCollectionNameAvailability(httpStatus: 404) == .available)`
- `collectionProfileTagSetSingular`: Singular tag set in collection profile parsed correctly. [no code: Tag sets parser].
  - `let links = try AO3Client.parseCollectionTagSets(html)`, `#expect(links[0].id == 123)`
- `collectionProfileTagSetsPlural`: Plural tag sets parsed correctly. [no code: Tag sets parser].
  - `let links = try AO3Client.parseCollectionTagSets(html)`, `#expect(links.map(\.id) == [7, 8])`
- `collectionProfileWithoutTagSetBlockReturnsEmpty`: Absence of tag sets block returns empty rather than throw. [no code: Tag sets parser].
  - `#expect(try AO3Client.parseCollectionTagSets(html).isEmpty)`
- `collectionPeopleParse`: Collection participants parsed correctly. [uncovered: AO3CollectionParser.parseCollectionPeoplePage].
  - `let page = try AO3Client.parseCollectionPeoplePage(html, page: 1)`, `#expect(page.people[0].identity.displayName == "Alice")`
- `collectionShowParsesExactWorksAndBookmarksStats`: Parsed stats exactly from header element. [uncovered: AO3CollectionParser.parseCollectionShow].
  - `let show = try AO3Client.parseCollectionShow(html, slug: "winter")`, `#expect(show.collection.worksCount == 1_234)`
- `collectionShowReadsTotalsFromItsOwnNavLinks`: Parsed stats from nav links when absent from header. [uncovered: AO3CollectionParser.parseCollectionShow].
  - `let show = try AO3Client.parseCollectionShow(html, slug: "winter")`, `#expect(show.collection.worksCount == 1_234)`
- `collectionSegmentParsersKeepEachPager`: Works and bookmarks page parsers read pagination properly. [uncovered: AO3CollectionParser.parseCollectionShow].
  - `let works = try AO3Client.parseSearchPage(worksHTML, page: 2)`, `#expect(works.currentPage == 2)`
- `pagedPeopleCountIsExplicitlyPageScoped`: Paged people count label explicitly page scoped. [no code: Collection UI helper].
  - `#expect(label == "20 on this page · page 2 of 4")`

### AO3ChallengeParsingTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3ChallengeSignUp.kt`
- Searches: `grep -rnE 'utcDateRoundTripDoesNotDrift|challengeDatesStayInTheChallengesOwnZone|signUpIndexCountsEachRowsRequestsAndOffers' android/app/src/test/`
**Rules:**
- `utcDateRoundTripDoesNotDrift`: UTC date round trip does not drift. [uncovered: AO3ChallengeUTCDate.parse]
  - `let raw = "2026-12-31 23:59:00"` ... `let parsed = try #require(AO3ChallengeUTCDate.parse(raw))` ... `#expect(AO3ChallengeUTCDate.wireString(from: parsed) == "2026-12-31 23:59:00")`
- `challengeDatesStayInTheChallengesOwnZone`: Challenge dates must be preserved in the challenge's own timezone. [uncovered: AO3Client.parseChallengeSettingsForm]
  - `let eastern = try form(zone: "America/New_York").settings` ... `let due = try #require(eastern.worksDueAt.instant)` ... `#expect(due == Date(timeIntervalSince1970: 1_772_427_540))`
- `signUpIndexCountsEachRowsRequestsAndOffers`: Sign-up index groups request and offer counts by participant. [uncovered: AO3Client.parseChallengeSignUpsPage]
  - `let page = try AO3Client.parseChallengeSignUpsPage(Self.signUpIndexHTML, slug: "fest", page: 1)` ... `try #require(alice.requests.count == 2)`
- `signUpJoinsAssignmentMatchedState`: Sign-ups are successfully joined with their matched assignments. [uncovered: AO3ChallengeSignUpMatching.joining]
  - `let joined = AO3ChallengeSignUpMatching.joining(signUps.signUps, assignments: assignments.assignments)` ... `#expect(alice.isMatched)`
- `signUpMatchStateIsUnknownWithoutAssignments`: Match state remains unknown if assignments haven't been fetched. [uncovered: AO3ChallengeSignUpMatching.state]
  - `#expect(AO3ChallengeSignUpMatching.state(of: alice, assignments: nil) == .unknown)`
- `emptyAssignmentListsLeaveMatchStateUnknown`: Missing assignment rows from empty pages leaves match state unknown. [uncovered: AO3ChallengeSignUpMatching.state]
  - `let assignments = try await AO3Client.allChallengeAssignments` ... `#expect(AO3ChallengeSignUpMatching.state(of: alice, assignments: assignments) == .unknown)`
- `failedLoadMoreKeepsRowsAndRetriesThePage`: Pager keeps loaded rows on failure and retries on loadNext. [uncovered: AO3LoadMorePages.loadNext]
  - `await #expect(throws: Offline.self) { try await pager.loadNext { _ in throw Offline() } }` ... `#expect(pager.rows == [10])`
- `ownSignUpMatchesBylineOrPseudWithLogin`: Correctly maps user logins to their pseud line. [uncovered: AO3ChallengeSignUpMatching.ownSignUpID]
  - `#expect(AO3ChallengeSignUpMatching.ownSignUpID(in: rows, login: "alice") == 11)`
- `assignmentBadgeDerivesLateFromWorksDue`: Infers late or delivered status from the deadline. [uncovered: AO3ChallengeAssignment.badge]
  - `#expect(open.badge(dueAt: due, now: after) == .late)` ... `#expect(delivered.badge(dueAt: due, now: after) == .delivered)`
- `draftPromptIDsStayUniqueAndAreNeverPosted`: Locally appended draft prompt objects get unique IDs and are discarded on post. [uncovered: AO3ChallengeSignUpForm]
  - `form.offers.append(AO3ChallengePrompt(id: form.nextDraftPromptID, kind: .offer))` ... `#expect(Set(ids).count == ids.count)`
- `signUpTotalReadsTheLastPageAndPageLabels`: Counts sign up numbers off of last page total rows. [uncovered: AO3Client.signUpTotal]
  - `let total = try await AO3Client.signUpTotal(firstPage: page(1, rows: 20, of: 3)) { number in ... }` ... `#expect(total == 47)`
- `assignmentTemplatesPreserveDefaultAndDeliveryStates`: Assignment list parser retains fulfilled/default statuses. [uncovered: AO3Client.parseChallengeAssignmentsPage]
  - `let rows = try AO3Client.parseChallengeAssignmentsPage(html, slug: "fest", page: 1).assignments` ... `#expect(rows[1].isDefaulted && !rows[1].isCovered && !rows[1].isFulfilled)`
- `assignmentJoinFetchesEveryPageIncludingOpenAssignments`: Full assignment fetch hits every pagination list including Open Assignments. [uncovered: AO3Client.allChallengeAssignments]
  - `let assignments = try await AO3Client.allChallengeAssignments { list, page in ... }` ... `#expect(fetched == ["assignments:1", "assignments:2", "unfulfilled:1", "unfulfilled:2", "unfulfilled:3", "defaults:1", "defaults:2"])`
- `challengeSettingsParseFiveUTCDatesAndMatchingURL`: Parse captures UTC date limits and matching settings. [uncovered: AO3Client.parseChallengeSettingsForm]
  - `let form = try AO3Client.parseChallengeSettingsForm(html, slug: "fest", kind: .giftExchange)` ... `#expect(form.settings.signupsOpenAt.postedString == "2026-01-01 00:00:00")`
- `promptMemeReadsAO3sPromptBlurbs`: Parse reads prompt meme blurbs and claim capabilities correctly. [uncovered: AO3Client.parsePromptMemePage]
  - `let page = try AO3Client.parsePromptMemePage(html, slug: "meme", page: 1)` ... `#expect(anonymous.canClaim && !anonymous.isClaimed)`
- `tagSetFourFieldsAndAssociationURLHaveNoWrite`: Tag sets scrape tag limits/names correctly, no write form param generation. [uncovered: AO3Client.parseTagSet]
  - `let tagSet = try AO3Client.parseTagSet(html, id: 9)` ... `#expect(tagSet.associationOpenOnAO3.path == "/tag_sets/9/associations")`
- `ownSignUpParsesNestedRequestsAndOffers`: Sign up parsing collects requests/offers perfectly. [uncovered: AO3Client.parseChallengeSignUpForm]
  - `let form = try AO3Client.parseChallengeSignUpForm(html, slug: "fest")` ... `#expect(form.requests[0].fandoms == ["Star Wars"])`
- `promptEditsLandOnThePromptByID`: Prompt edits apply accurately against prompt ID without index drifting. [uncovered: AO3ChallengeSignUpForm.updatePrompt]
  - `var second = try #require(form.prompt(id: 22, kind: .request))` ... `form.updatePrompt(second)` ... `#expect(form.requests.map(\.promptText) == ["First", "Edited"])`


### KokoroPronunciationBackupTests
- Code: No code for Kokoro pronunciations backup
- Searches: `grep -rn -i 'kokoro' android/app/src/`
**Rules:**
- `captureReadsEveryLayer`: captures from global, fandom, work overrides. [no code: Kokoro pronunciations backup]
- `applyMergesRatherThanReplacing`: merges backup keeping local-only overrides. [no code: Kokoro pronunciations backup]
- `theArchiveWinsOnAConflict`: backup overrides local on conflict. [no code: Kokoro pronunciations backup]
- `anEmptyArchiveChangesNothing`: applying empty backup does not modify local. [no code: Kokoro pronunciations backup]
- `archivesWithoutTheKeyStillDecode`: backup without pronunciations decodes fine. [no code: Kokoro pronunciations backup]
- `manifestRoundTripsWithPronunciations`: manifest encoding and decoding preserves pronunciations. [no code: Kokoro pronunciations backup]
- `addingPronunciationsDidNotBumpTheSchemaVersion`: schema version remains 8. [no code: Kokoro pronunciations backup]
- `aManifestWithoutPronunciationsLeavesLocalCorrectionsAlone`: Android-written manifest decoding leaves local overrides intact. [no code: Kokoro pronunciations backup]


### AO3WorkFormParsingTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkForm.kt`
- Searches: `grep -rnE 'parsesWorkEditFormGroups|aWhitespaceOnlySeriesTitleIsNotPosted' android/app/src/test/`
**Rules:**
- `parsesWorkEditFormGroups`: Parses work edit form groups successfully. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormTest.kt:339`]
- `clearedWorkSkinIsStillPosted`: Work skin cleared is still posted as empty string. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormTest.kt:360`]
- `aWorkWithSeveralChaptersSendsNoChapterText`: A multi-chapter work sends no chapter text field. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormTest.kt:75`]
- `postingAWorkSendsTheWorkFormsOwnPostButton`: Posting a work sends the correct specific post button. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormTest.kt:365`]
- `missingRequiredFieldsNamesWhatPostNeeds`: Returns list of required fields missing for a post. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormTest.kt:372`]
- `publicationDateKeepsAO3sUnpaddedFormat`: Publication date keeps unpadded AO3 format for month/day. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormTest.kt:396`]
- `backdateOnPostsTheChosenDate`: Turning on backdate posts the chosen date parameters. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormTest.kt:403`]
- `backdateOffLeavesTheDateFieldsUntouched`: Turning off backdate doesn't post date override parameters. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormTest.kt:413`]
- `postConfirmationNamesWhatIsMissing`: Post confirmation alert text details exactly what is missing. [uncovered: WorkEditView.postConfirmationMessage]
  - `let two = WorkEditView.postConfirmationMessage(missing: ["Title", "Archive Warning"])` ... `#expect(two.hasPrefix("Two things are missing. Add a title"))`
- `pickingASeriesPostsOnlyThatSeries`: Picking a single series posts only that series ID. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormTest.kt:421`]
- `aWhitespaceOnlySeriesTitleIsNotPosted`: Whitespace-only new series title is not posted. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormTest.kt:427`]
- `tagRemovalIsADiffNotADeleteAPI`: Removing tags works by diffing the set, not via a deletion endpoint. [uncovered: AO3WorkTagSet.diff]
  - `let diff = current.diff(toward: desired)` ... `#expect(diff.fandomsRemoved == ["Haikyuu!!"])`
- `bulkPostCarriesOnlyUniformFieldsAndTagsMergePerWork`: Bulk edits post only uniform fields and merge tags per-work. [uncovered: AO3BulkEditChanges.parameters]
  - `let params = changes.parameters(csrfToken: form.csrfToken)` ... `#expect(dict[AO3WorkFormField.fandoms] == nil)`
- `bulkFormParsesCommentPermissionsAndSelfRemoval`: Bulk form correctly parses comment permission radio and remove self checkbox. [uncovered: AO3Client.parseBulkEditForm]
  - `changes.commentPermissions = "disable_anon"` ... `changes.removesSelfAsCreator = true` ... `#expect(dict[AO3WorkFormField.removeSelfAsCreator] == "1")`
- `parsesChapterFormAndOmitsPositionWhenAbsent`: Parses chapter form fields, omitting position parameter if none provided. [uncovered: AO3Client.parseChapterForm]
  - `let form = try #require(try? AO3Client.parseChapterForm(from: html))` ... `#expect(params[AO3WorkFormField.chapterPosition] == nil)`
- `parsesSeriesManageOrder`: Parses the series manage positions page. [uncovered: AO3Client.parseSeriesManagePage]
  - `let rows = try #require(try? AO3Client.parseSeriesManagePage(from: html))` ... `#expect(rows.map(\.isDraft) == [false, true, false])`
- `parsesCollectionRowStateOnTheBlurb`: Parses collection rows to find Open/Closed/Moderated statuses. [uncovered: AO3Client.parseCollectionOffers]
  - `let offers = try #require(try? AO3Client.parseCollectionOffers(from: html))` ... `#expect(offers[0].access.rowState == .moderated)`
- `parsesDeleteConfirmCountsWhenPresent`: Parses the delete confirmation page capturing the deletion impact stats. [uncovered: AO3Client.parseDeleteImplications]
  - `let implications = try #require(try? AO3Client.parseDeleteImplications(from: html))` ... `#expect(implications.chapters == 12)`
- `draftsURLIsItsOwnIndexNotAWorksFilter`: Drafts URL goes to a dedicated index instead of being a generic works page filter. [uncovered: AO3Client.myDraftsURL]
  - `#expect(AO3Client.myDraftsURL(username: "tester", page: 1)?.path == "/users/tester/works/drafts")`
- `previewExtractsThePreviewPane`: Parses the preview HTML extracting the pane wrapper. [uncovered: AO3Client.parsePreviewHTML]
  - `let preview = try #require(try? AO3Client.parsePreviewHTML(from: html))` ... `#expect(preview.html.contains("Hello."))`
- `missingFormThrowsParse`: Fails securely if the form doesn't exist on the page. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormTest.kt:470`]
- `namedParamKeysMatchOtwarchive`: Form param string keys exactly match AO3/otwarchive rails keys. [covered: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormTest.kt:474`]

### CanonicalWorkMergeTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/works/CanonicalWorkMerge.kt`
- Searches: `grep -rn 'CanonicalWorkMerge' android/app/src/test/`
**Rules:**
- `remoteLedPairsWorksMatchedByAO3WorkID`: Pairs works by AO3 Work ID. [covered: `android/app/src/test/java/io/github/cidy02/kudos/works/CanonicalWorkMergeTest.kt:11`]
- `remoteLedMatchesBySourceURLWhenNoStoredID`: Matches by source URL if AO3 Work ID isn't stored. [uncovered: CanonicalWorkMerge.remoteLed]
  - `let local = SavedWork(title: "URL Only", author: "Writer", sourceURL: "https://archiveofourown.org/works/7002?view_adult=true")` ... `#expect(merged[0].local?.id == local.id)`
- `remoteLedPassesUnmatchedRemoteThroughAndDropsLocalOnly`: Passes unmatched remote and drops local-only. [uncovered: CanonicalWorkMerge.remoteLed]
  - `let merged = CanonicalWorkMerge.remoteLed(remote: [summary(7004)], localLibrary: [localOnly])` ... `#expect(merged[0].local == nil)`
- `remoteLedPreservesRemoteOrder`: Output preserves the remote summary order. [uncovered: CanonicalWorkMerge.remoteLed]
  - `let merged = CanonicalWorkMerge.remoteLed(remote: [summary(7005), summary(7006), summary(7007)], localLibrary: [localB])` ... `#expect(merged.map { $0.remote?.id } == [7005, 7006, 7007])`
- `remoteLedPairsADuplicateRemoteMentionOnlyOnce`: Pairs duplicate remotes only once. [covered: `android/app/src/test/java/io/github/cidy02/kudos/works/CanonicalWorkMergeTest.kt:34`]
- `remoteOnlyDropsEntriesWithALocalTwin`: remoteOnly drops remote summaries that have a local equivalent. [uncovered: CanonicalWorkMerge.remoteOnly]
  - `let remaining = CanonicalWorkMerge.remoteOnly(remote: [summary(7009), summary(7010)], localLibrary: [local])` ... `#expect(remaining.map(\.id) == [7010])`
- `identityIndexFallsBackToRecordUUID`: Falls back to record UUID for identity match. [uncovered: WorkIdentitySnapshot.existingWork]
  - `let index = WorkIdentityIndex([local])` ... `#expect(index.existingWork(ao3WorkID: nil, sourceURL: nil, recordID: local.id)?.id == local.id)`
- `canonicalWorkIDIsStableAcrossSides`: CanonicalWork uses local ID if paired, else remote ID. [uncovered: CanonicalWork.id]
  - `let paired = CanonicalWork(local: local, remote: summary(7011))` ... `#expect(paired.id == "local-\(local.id.uuidString)")`


### NewestTombstoneWinsTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`
- Searches: `grep -rn 'lastModifiedAt' android/app/src/test/java/io/github/cidy02/kudos/backup/`
**Rules:**
- `aLaterDeletionReplacesTheEarlierTombstone`: Later deletion replaces earlier tombstone. [uncovered: BackupMergeService.merge]
  - `let peerTomb = SyncTombstone(recordID: workID, recordType: .savedWork, createdAt: Self.later)` ... `#expect(local.lastModifiedAt == Self.later)`
- `aSnapshotBetweenTheTwoDeletionsCannotResurrectTheWork`: Intermediate snapshot cannot revive work deleted later. [uncovered: BackupMergeService.merge]
  - `let staleBackup = try KudosBackupService.makeContents(works: [revived]...)` ... `#expect(works.isEmpty)`
- `theAdoptedRowStillVerifiesAndTakesTheSignedIdentity`: Adopted row verifies signature with signed identity. [uncovered: BackupMergeService.merge]
  - `#expect(TombstoneSigning.verify(payload: TombstoneSigning.payload(for: local, signerPublicKey: local.signerPublicKey), publicKeyHex: local.signerPublicKey, signatureHex: local.signature))`
- `anOlderIncomingTombstoneLeavesTheLaterOneAlone`: Older incoming tombstone leaves the current later tombstone alone. [uncovered: BackupMergeService.merge]
  - `let olderPeer = SyncTombstone(recordID: workID, recordType: .savedWork, createdAt: Self.earlier)` ... `#expect(local.lastModifiedAt == Self.later)`


### TombstoneSweepsExistingRecordsTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`
- Searches: `grep -rn "aTrustedTombstoneRemovesASearchThisDeviceStillHas" android/app/src/test/java/io/github/cidy02/kudos/`
**Rules:**
- `aTrustedTombstoneRemovesASearchThisDeviceStillHas`: A search this device still has that a trusted tombstone says was deleted elsewhere is swept. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupTrustPhase2Test.kt:638`].
- `aSearchMadeAfterTheDeletionSurvives`: A search made after the tombstone deletion survives. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupTrustPhase2Test.kt:646`].
- `replaceLibraryDoesNotSweepExistingSearches`: Replace mode does not sweep existing searches. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupTrustPhase2Test.kt:1373`].
- `aTrustedTombstoneRemovesASavedLinkButNotOneSavedAgainLater`: A trusted tombstone removes a saved link but not one saved again later. [uncovered: `bookmarkResolution`].
  - ```swift
    @Test func aTrustedTombstoneRemovesASavedLinkButNotOneSavedAgainLater() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let old = Bookmark(title: "Old", urlString: "https://archiveofourown.org/works/1")
        old.dateAdded = Date(timeIntervalSince1970: 100)
        let later = Bookmark(title: "Later", urlString: "https://archiveofourown.org/works/2")
        later.dateAdded = Date(timeIntervalSince1970: 900)
        context.insert(old)
        context.insert(later)
        try context.save()

        let snapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            tombstones: [
                signedTombstone(.bookmark, id: old.id, at: 400, key: peer),
                signedTombstone(.bookmark, id: later.id, at: 400, key: peer)
            ],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(snapshot, into: context, defaults: defaults, mode: .merge)

        #expect(try context.fetch(FetchDescriptor<Bookmark>()).map(\.title) == ["Later"])
    }
    ```
- `aTrustedTombstoneRemovesAHighlightButNotOneEditedLater`: A trusted tombstone removes a highlight but not one edited later. [uncovered: `annotationResolution`].
  - ```swift
    @Test func aTrustedTombstoneRemovesAHighlightButNotOneEditedLater() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let work = SavedWork(title: "A work", author: "Someone")
        context.insert(work)
        let gone = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: "a",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        gone.lastModifiedAt = Date(timeIntervalSince1970: 100)
        let edited = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: "b", note: "kept",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        edited.lastModifiedAt = Date(timeIntervalSince1970: 900)
        context.insert(gone)
        context.insert(edited)
        try context.save()

        let snapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            tombstones: [
                signedTombstone(.readingAnnotation, id: gone.id, at: 400, key: peer),
                signedTombstone(.readingAnnotation, id: edited.id, at: 400, key: peer)
            ],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(snapshot, into: context, defaults: defaults, mode: .merge)

        #expect(try context.fetch(FetchDescriptor<ReadingAnnotation>()).map(\.note) == ["kept"])
    }
    ```
- `aTrustedTombstoneRemovesAQueueMembershipButNotOneChangedLater`: A trusted tombstone removes a queue membership but not one changed later. [uncovered: `membershipResolution`].
  - ```swift
    @Test func aTrustedTombstoneRemovesAQueueMembershipButNotOneChangedLater() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let queue = ReadingQueue(name: "To read")
        let first = SavedWork(title: "Removed elsewhere", author: "Someone")
        let second = SavedWork(title: "Moved here since", author: "Someone")
        context.insert(queue)
        context.insert(first)
        context.insert(second)
        let gone = ReadingQueueMembership(
            queue: queue, work: first, queuedAt: Date(timeIntervalSince1970: 100)
        )
        let kept = ReadingQueueMembership(
            queue: queue, work: second, queuedAt: Date(timeIntervalSince1970: 100)
        )
        kept.lastModifiedAt = Date(timeIntervalSince1970: 900)
        context.insert(gone)
        context.insert(kept)
        try context.save()

        let snapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            tombstones: [
                signedTombstone(.readingQueueMembership, id: gone.id, at: 400, key: peer),
                signedTombstone(.readingQueueMembership, id: kept.id, at: 400, key: peer)
            ],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(snapshot, into: context, defaults: defaults, mode: .merge)

        let left = try context.fetch(FetchDescriptor<ReadingQueueMembership>())
        #expect(left.compactMap { $0.work?.title } == ["Moved here since"])
    }
    ```
- `aDeletedCopyDoesNotTakeTheOtherDevicesMarkOnTheSamePassageWithIt`: A deleted copy does not take the other device's mark on the same passage with it when swept. [uncovered: `dedupeSamePassageAnnotations`].
  - ```swift
    @Test func aDeletedCopyDoesNotTakeTheOtherDevicesMarkOnTheSamePassageWithIt() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let workID = UUID()
        let work = SavedWork(id: workID, title: "A work", author: "Someone")
        work.isSaved = true
        context.insert(work)
        let local = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: "passage", note: "deleted elsewhere",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        local.lastModifiedAt = Date(timeIntervalSince1970: 300)
        context.insert(local)
        try context.save()

        let donor = try self.context()
        let donorWork = SavedWork(id: workID, title: "A work", author: "Someone")
        donorWork.isSaved = true
        donorWork.hasEPUB = false
        donor.insert(donorWork)
        let remote = ReadingAnnotation(
            work: donorWork, kind: .highlight, locatorString: "passage", note: "made since",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        remote.lastModifiedAt = Date(timeIntervalSince1970: 100)
        donor.insert(remote)
        try donor.save()

        let snapshot = try KudosBackupService.makeContents(
            works: [donorWork], bookmarks: [], fonts: [], readingQueues: [],
            annotations: [remote],
            tombstones: [signedTombstone(.readingAnnotation, id: local.id, at: 400, key: peer)],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(snapshot, into: context, defaults: defaults, mode: .merge)

        let live = try context.fetch(FetchDescriptor<ReadingAnnotation>())
            .filter { !$0.isPendingDeletion && $0.deletedAt == nil }
        #expect(live.map(\.note) == ["made since"])
    }
    ```
- `choosingNoAccountShortcutsStaysEmpty`: Removing every Account shortcut is a choice and stays one, without restoring defaults. [uncovered: `AccountShortcuts`].
  - ```swift
    @Test func choosingNoAccountShortcutsStaysEmpty() {
        #expect(AccountShortcutStore.decode(AccountShortcutStore.encode([])).isEmpty)
        #expect(AccountShortcutStore.decode("") == AccountShortcut.defaults)
        #expect(AccountShortcutStore.decode("nothing-known") == AccountShortcut.defaults)
        #expect(AccountShortcutStore.decode(AccountShortcutStore.encode([.inbox, .works])) == [.inbox, .works])
    }
    ```
- `replaceLibraryDoesNotSweepExistingSavedLinks`: Replace mode does not sweep existing saved links. [uncovered: `bookmarkResolution`].
  - ```swift
    @Test func replaceLibraryDoesNotSweepExistingSavedLinks() throws {
        let defaults = try testDefaults()
        let peer = try trustedPeer(defaults)
        let context = try context()
        let link = Bookmark(title: "Kept by Replace", urlString: "https://archiveofourown.org/works/3")
        link.dateAdded = Date(timeIntervalSince1970: 100)
        context.insert(link)
        try context.save()

        let snapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [link], fonts: [], readingQueues: [],
            tombstones: [signedTombstone(.bookmark, id: link.id, at: 400, key: peer)],
            defaults: defaults
        )
        _ = try KudosBackupService.restore(snapshot, into: context, defaults: defaults, mode: .replaceLibrary)

        #expect(try context.fetch(FetchDescriptor<Bookmark>()).count == 1)
    }
    ```


### TombstoneTrustStoreTests
- Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/TombstoneTrustStore.kt`
- Searches: `grep -rn "fun test" android/app/src/test/java/io/github/cidy02/kudos/backup/TombstoneTrustStorePairingTest.kt`
**Rules:**
- `testRoundTripAddRemove`: Can add and remove a trust record roundtrip. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/TombstoneTrustStorePairingTest.kt:95`].
- `testOwnDeviceAlwaysTrusted`: Own device's pub is always trusted inherently. [uncovered: `isTrusted`].
  - ```swift
    @Test func testOwnDeviceAlwaysTrusted() {
        let ownDevicePub = TombstoneSigning.publicKeyHex()
        #expect(TombstoneTrustStore.isTrusted(ownDevicePub))
    }
    ```
- `testMigrationFromUserDefaults`: [no code: iCloud KVS migration].
- `testOutOfBandWriteIsReflected`: [no code: iCloud KVS syncing].
- `testUserDefaultsWriteAfterKeychainItemExistsIsIgnored`: [no code: iCloud KVS migration].
- `testEmptyFirstLaunchPlantsSentinelAndIgnoresLaterUserDefaults`: [no code: iCloud KVS migration].
- `testUnavailableKeychainDoesNotWipeUserDefaults`: [no code: iCloud KVS migration].
- `testNormalizedPublicKeyAppliedOnEveryPath`: KVS and trust paths apply normalized validation and reject non-hex keys. [uncovered: `trust`].
  - ```swift
    @Test func testNormalizedPublicKeyAppliedOnEveryPath() {
        #expect(!TombstoneTrustStore.add("not-a-key"))
        #expect(!TombstoneTrustStore.remove("gg"))
    ```
- `testAddPublishesOnlyOwnPubUnderItsOwnKey`: [no code: iCloud KVS syncing].
- `testMergeAdoptsUnionOfAllPublishedDevicePubs`: [no code: iCloud KVS syncing].
- `testDisappearingPublishedPubDoesNotUntrust`: [no code: iCloud KVS syncing].
- `testStolenRevokePropagatesAndUntrustsOnOtherDevices`: [no code: iCloud KVS syncing].
- `testMergingARemoteRevocationUntrustsAndDenylistsLocally`: [no code: iCloud KVS syncing].
- `testDenylistedKeyCannotBeReimportedByAddOrMerge`: [no code: iCloud KVS syncing].
- `testRetiredRevokeUntrustsAndPropagatesButDoesNotDenylist`: [no code: iCloud KVS syncing].
- `testEmptyRemoteIsANoOpAndOwnKeyStaysTrusted`: [no code: iCloud KVS syncing].
- `testMalformedRemoteValuesAreRejectedNotCrashed`: [no code: iCloud KVS syncing].
- `testTrustedDevicesListsOnlyPeersWithLabel`: Trusted devices list contains only peers with a label, not the own implicitly trusted device. [weaker: lacks explicit assertion that own device is not included].
  - ```swift
        #expect(!devices.contains { $0.publicKeyHex == TombstoneSigning.publicKeyHex() })
    ```
- `testRenameUpdatesLabelOnly`: Renaming a trust record updates its label. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/TombstoneTrustStorePairingTest.kt:86`].
- `testRemoveClearsMetadata`: Removing a trust record clears its local metadata. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/TombstoneTrustStorePairingTest.kt:95`].
- `testUndoTrustRevertsWithinWindowButNotAfter`: Undo trust reverts trusting within window but not after. [covered: `android/app/src/test/java/io/github/cidy02/kudos/backup/TombstoneTrustStorePairingTest.kt:139`].
- `testMergedPeerGetsMetadataToo`: [no code: iCloud KVS syncing].
- `testRemoteRevocationClearsMetadataOnMerge`: [no code: iCloud KVS syncing].
- `testReMergeDoesNotResetExistingMetadata`: [no code: iCloud KVS syncing].


## Summary Table

| Suite | Tests | Covered | Weaker | Uncovered | No Code |
|---|---|---|---|---|---|
| AO3CommentsParseTests | 5 | 3 | 0 | 2 | 0 |
| AO3InboxParseTests | 17 | 9 | 1 | 7 | 0 |
| AO3NamedSubscriptionsParseTests | 5 | 4 | 1 | 0 | 0 |
| AO3PreferencesParseTests | 3 | 0 | 1 | 1 | 1 |
| AO3ReadingsParsingTests | 8 | 0 | 0 | 8 | 0 |
| AO3SubscriptionsParseTests | 5 | 1 | 1 | 3 | 0 |
| AO3UserStatsParsingTests | 5 | 0 | 0 | 0 | 5 |
| CustomFontBackupCompatibilityTests | 6 | 4 | 0 | 2 | 0 |
| KudosBackupFontRestoreTests | 15 | 8 | 1 | 6 | 0 |
| KudosBackupTests | 16 | 9 | 0 | 6 | 1 |
| PreReplaceBackupNamingTests | 5 | 0 | 0 | 3 | 2 |
| ReadiumProgressPersistenceTests | 14 | 5 | 0 | 9 | 0 |
| EqualSizeEPUBStillSyncsTests | 2 | 1 | 0 | 0 | 1 |
| FailedRestoreKeepsEPUBsTests | 2 | 1 | 0 | 0 | 1 |
| MergeMissingEPUBRecoveryTests | 2 | 2 | 0 | 0 | 0 |
| ReadingAnnotationBackupTests | 7 | 7 | 0 | 0 | 0 |
| BackupLazyReadTests | 7 | 0 | 0 | 0 | 7 |
| CrossPlatformBackupTests | 1 | 1 | 0 | 0 | 0 |
| ExactColourBackupTests | 3 | 1 | 1 | 1 | 0 |
| FolderSyncBackgroundTaskTests | 1 | 0 | 0 | 0 | 1 |
| FolderSyncTests | 23 | 15 | 0 | 6 | 2 |
| IncompleteBackupReportingTests | 3 | 0 | 0 | 1 | 2 |
| OriginalsTravelInBackupsTests | 4 | 4 | 0 | 0 | 0 |
| PersistenceSyncTests | 24 | 13 | 0 | 10 | 1 |
| ReadingLogBackupTests | 6 | 1 | 1 | 4 | 0 |
| ReadingLogRestoreDefectTests | 6 | 0 | 1 | 5 | 0 |
| StaleSyncUpKeepsRemoteAssetsTests | 1 | 1 | 0 | 0 | 0 |
| AO3CollectionParsingTests | 17 | 0 | 0 | 7 | 10 |
| AO3ChallengeParsingTests | 18 | 0 | 0 | 18 | 0 |
| KokoroPronunciationBackupTests | 8 | 0 | 0 | 0 | 8 |
| AO3WorkFormParsingTests | 22 | 12 | 0 | 10 | 0 |
| CanonicalWorkMergeTests | 8 | 2 | 0 | 6 | 0 |
| NewestTombstoneWinsTests | 4 | 0 | 0 | 4 | 0 |
| TombstoneSweepsExistingRecordsTests | 9 | 3 | 0 | 6 | 0 |
| TombstoneTrustStoreTests | 24 | 4 | 1 | 2 | 17 |

## Priority List of Uncovered Rules

1. [Merge/Loss] `AO3InboxParseTests.adminHiddenRowBecomesATombstoneInsteadOfBeingDropped`: tombstone parsing. (uncovered)
2. [Merge/Loss] `AO3InboxParseTests.rowMalformedAThirdWayFoldsIntoATombstoneRatherThanVanishing`: fallback parsing. (uncovered)
3. [Merge/Loss] `AO3ReadingsParsingTests.readsADeletedWorkRow`: parses deleted work row. (uncovered)
4. [Merge/Loss] `CustomFontBackupCompatibilityTests.aPathInTheNameIsRefused`: A path in the font name is refused. (uncovered)
5. [Merge/Loss] `CustomFontBackupCompatibilityTests.everyRefusalExplainsItself`: Every font rejection reason explains itself to the user. (uncovered)
6. [Merge/Loss] `KudosBackupFontRestoreTests.unreadableLocalBytesAndOrphanSuffixArePreserved`: Unreadable local bytes and orphan suffix are preserved. (weaker)
7. [Merge/Loss] `KudosBackupFontRestoreTests.zipRestorePreservesAmbiguousCaseFoldedRowsAndFiles`: Zip restore preserves ambiguous case folded rows and files. (uncovered)
8. [Merge/Loss] `KudosBackupFontRestoreTests.restorePreservesOneRowAndTwoCaseVariantFilesWhenIncomingMatchesOrphan`: Restore preserves one row and two case variant files when incoming matches orphan. (uncovered)
9. [Merge/Loss] `KudosBackupFontRestoreTests.restoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile`: Restore treats two local files as ambiguous when incoming matches database file. (uncovered)
10. [Merge/Loss] `KudosBackupFontRestoreTests.legacyDirectoryRestorePreservesAmbiguousCaseFoldedRowsAndFiles`: Legacy directory restore preserves ambiguous case folded rows and files. (uncovered)
11. [Merge/Loss] `KudosBackupFontRestoreTests.zipRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile`: Zip restore treats two local files as ambiguous when incoming matches database file. (uncovered)
12. [Merge/Loss] `KudosBackupFontRestoreTests.legacyDirectoryRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile`: Legacy directory restore treats two local files as ambiguous when incoming matches database file. (uncovered)
13. [Merge/Loss] `KudosBackupTests.failedRestoreLeavesNoSwiftDataMutationsVisibleAfterCallerAutosave`: Failed restore leaves no database mutations visible. (uncovered)
14. [Merge/Loss] `KudosBackupTests.restoreMergesByAO3WorkIDBeforeUUID`: Restore merges by AO3 Work ID before UUID. (uncovered)
15. [Merge/Loss] `KudosBackupTests.restoreMergesByCanonicalAO3URLBeforeUUID`: Restore merges by canonical AO3 URL before UUID. (uncovered)
16. [Merge/Loss] `KudosBackupTests.restoreSkipsMembershipReferencingMissingWork`: Restore skips membership referencing missing work. (uncovered)
17. [Merge/Loss] `KudosBackupTests.streamedExportMatchesTheInMemoryArchive`: Streamed export matches the in-memory archive. (uncovered)
18. [Merge/Loss] `KudosBackupTests.exportRefusesArchivesTheReaderWouldReject`: Export refuses archives the reader would reject. (uncovered)
19. [Merge/Loss] `PreReplaceBackupNamingTests.twoCopiesOnTheSameDayDoNotShareAName`: different hour/min shouldn't overwrite. (uncovered)
20. [Merge/Loss] `PreReplaceBackupNamingTests.theCopyIsNamedAsAnImportableBackup`: file has correct backup extension and prefix. (uncovered)
21. [Merge/Loss] `PreReplaceBackupNamingTests.writingRefusesToOverwriteAnExistingCopy`: write must refuse rather than overwrite. (uncovered)
22. [Merge/Loss] `ReadiumProgressPersistenceTests.progressionNoiseBelowThresholdIsNeverWritten`: noise filter prevents micro-progressions from writing. (uncovered)
23. [Merge/Loss] `ReadiumProgressPersistenceTests.progressionPastThresholdIsWrittenAfterInterval`: valid progression passes the filter. (uncovered)
24. [Merge/Loss] `ReadiumProgressPersistenceTests.flushIsNilWhenNothingChanged`: flushing an empty buffer does nothing. (uncovered)
25. [Merge/Loss] `ReadiumProgressPersistenceTests.emptyLocatorIsIgnored`: blank locators are not recorded. (uncovered)
26. [Merge/Loss] `ReadiumProgressPersistenceTests.seedPreventsRewriteOfIdenticalOpenLocator`: prevents re-writing identical locator on book open. (uncovered)
27. [Merge/Loss] `ReadiumProgressPersistenceTests.firstDifferentLocatorAfterSeedCanWrite`: actual progression post-open gets written. (uncovered)
28. [Merge/Loss] `ReadiumProgressPersistenceTests.identicalStringAfterSeedDoesNotWriteEvenWithProgression`: re-reporting same locator string doesn't write. (uncovered)
29. [Merge/Loss] `ReadiumProgressPersistenceTests.noiseDoesNotArmATrailingWrite`: below-threshold movement doesn't arm trailing write timer. (uncovered)
30. [Merge/Loss] `ReadiumProgressPersistenceTests.meaningfulChangeInsideWindowArmsTrailingWrite`: valid move inside window sets up trailing timer. (uncovered)
31. [Merge/Loss] `ExactColourBackupTests.archivedQueueCarriesColorHexAndOlderArchivesDecode`: Archived queue carries colorHex. (uncovered)
32. [Merge/Loss] `ExactColourBackupTests.restoreBringsBackExactQueueAndCollectionColours`: Restore brings back exact queue and collection colours. (weaker)
33. [Merge/Loss] `FolderSyncTests.syncDownPreservesEveryCaseFoldedDatabaseRow`: sync down preserves every case folded database row. (uncovered)
34. [Merge/Loss] `FolderSyncTests.syncDownTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile`: sync down treats two local files as ambiguous when incoming matches database file. (uncovered)
35. [Merge/Loss] `FolderSyncTests.syncDownMissingFileIsNoop`: sync down missing file is noop. (uncovered)
36. [Merge/Loss] `FolderSyncTests.foldConflictContentsDoesNotAdoptIncomingUnsignedTombstones`: fold conflict contents does not adopt incoming unsigned tombstones. (uncovered)
37. [Merge/Loss] `FolderSyncTests.folderSyncResultAbsorbsAnotherResultsCountsRatherThanDiscardingThem`: folder sync result absorbs another results counts rather than discarding them. (uncovered)
38. [Merge/Loss] `FolderSyncTests.removedCollectionMembershipIsNotResurrectedByStaleSync`: removed collection membership is not resurrected by stale sync. (uncovered)
39. [Merge/Loss] `IncompleteBackupReportingTests.theStreamingExporterNamesWhatItCouldNotInclude`: exporter reports skipped entries. (uncovered)
40. [Merge/Loss] `PersistenceSyncTests.progressMergeDoesNotRegressToOlderSnapshot`: Merging progress keeps the higher spine or newer progress. (uncovered)
41. [Merge/Loss] `PersistenceSyncTests.backupRestoreKeepsNewerLocalProgress`: Restoring backup should keep newer local progress. (uncovered)
42. [Merge/Loss] `PersistenceSyncTests.clearedMacPercentIsExportedAsNull`: Export cleared mac percent as null in JSON. (uncovered)
43. [Merge/Loss] `PersistenceSyncTests.manifestWithoutTheMacPercentKeyDecodesItAsNil`: Missing key decodes as nil. (uncovered)
44. [Merge/Loss] `PersistenceSyncTests.deletingWorkCreatesTombstone`: Work deletion creates a tombstone. (uncovered)
45. [Merge/Loss] `PersistenceSyncTests.deletingWorkThenImportingOlderBackupDoesNotResurrectIt`: Older backup does not resurrect a deleted work. (uncovered)
46. [Merge/Loss] `PersistenceSyncTests.newestTombstoneDecidesSuppressionWhenSeveralShareAO3Identity`: Several tombstones sharing AO3 identity suppress properly. (uncovered)
47. [Merge/Loss] `PersistenceSyncTests.membershipChangesUpdateQueueFreshnessSignal`: Membership changes update queue freshness signal. (uncovered)
48. [Merge/Loss] `PersistenceSyncTests.freshInstallRestoreAdoptsArchivedFlagsWithNoExistingLocalRecord`: Fresh install restore adopts archived flags. (uncovered)
49. [Merge/Loss] `PersistenceSyncTests.tombstoneSurvivesBackupRoundTripIntoFreshInstall`: Tombstone survives backup round trip. (uncovered)
50. [Merge/Loss] `ReadingLogBackupTests.keepInProgressOverrideDecodesNilWhenAbsent`: Omitted boolean key decodes as nil. (weaker)
51. [Merge/Loss] `ReadingLogBackupTests.v7AndV8ArchivesWithoutNewKeysStillImport`: Older backup manifests missing new tables still import. (uncovered)
52. [Merge/Loss] `ReadingLogBackupTests.tombstoneSuppressesResurrectionOfAnOlderArchive`: Tombstones suppress old reading log entities. (uncovered)
53. [Merge/Loss] `ReadingLogBackupTests.replaceOmissionMintsTombstonesAndALaterMergeDoesNotResurrect`: Replace mints tombstones and doesn't resurrect. (uncovered)
54. [Merge/Loss] `ReadingLogBackupTests.addingReadingLogDidNotBumpTheSchemaVersion`: Reading log tables didn't bump backup schema version from 8. (uncovered)
55. [Merge/Loss] `ReadingLogRestoreDefectTests.replaceLibraryKeepsFavoritesAndWatermarksMatchedByTarget`: Replace library keeps entities matched by target. (weaker)
56. [Merge/Loss] `ReadingLogRestoreDefectTests.replaceLibraryStillDropsRecordsTheArchiveDoesNotHave`: Replace library drops unmatched records. (uncovered)
57. [Merge/Loss] `ReadingLogRestoreDefectTests.repeatingAnIdenticalReplaceLibraryIsNotDestructive`: Repeating an identical replace library is idempotent. (uncovered)
58. [Merge/Loss] `ReadingLogRestoreDefectTests.historyAndStarsFollowAWorkMergedIntoAnExistingCopy`: History and favorites attach to existing work UUID after merge. (uncovered)
59. [Merge/Loss] `ReadingLogRestoreDefectTests.historyForAWorkThatIsNotHereStaysDetachedRatherThanBeingDropped`: History for missing work is preserved. (uncovered)
60. [Merge/Loss] `ReadingLogRestoreDefectTests.aDeletionOnAnotherDeviceRemovesTheLocalCopy`: Deletion tombstone on another device removes local copy during merge. (uncovered)
61. [Merge/Loss] `AO3WorkFormParsingTests.tagRemovalIsADiffNotADeleteAPI`: Removing tags works by diffing the set, not via a deletion endpoint. (uncovered)
62. [Merge/Loss] `AO3WorkFormParsingTests.bulkPostCarriesOnlyUniformFieldsAndTagsMergePerWork`: Bulk edits post only uniform fields and merge tags per-work. (uncovered)
63. [Merge/Loss] `AO3WorkFormParsingTests.parsesDeleteConfirmCountsWhenPresent`: Parses the delete confirmation page capturing the deletion impact stats. (uncovered)
64. [Merge/Loss] `CanonicalWorkMergeTests.remoteLedMatchesBySourceURLWhenNoStoredID`: Matches by source URL if AO3 Work ID isn't stored. (uncovered)
65. [Merge/Loss] `CanonicalWorkMergeTests.remoteLedPassesUnmatchedRemoteThroughAndDropsLocalOnly`: Passes unmatched remote and drops local-only. (uncovered)
66. [Merge/Loss] `CanonicalWorkMergeTests.remoteLedPreservesRemoteOrder`: Output preserves the remote summary order. (uncovered)
67. [Merge/Loss] `CanonicalWorkMergeTests.remoteOnlyDropsEntriesWithALocalTwin`: remoteOnly drops remote summaries that have a local equivalent. (uncovered)
68. [Merge/Loss] `CanonicalWorkMergeTests.identityIndexFallsBackToRecordUUID`: Falls back to record UUID for identity match. (uncovered)
69. [Merge/Loss] `CanonicalWorkMergeTests.canonicalWorkIDIsStableAcrossSides`: CanonicalWork uses local ID if paired, else remote ID. (uncovered)
70. [Merge/Loss] `NewestTombstoneWinsTests.aLaterDeletionReplacesTheEarlierTombstone`: Later deletion replaces earlier tombstone. (uncovered)
71. [Merge/Loss] `NewestTombstoneWinsTests.aSnapshotBetweenTheTwoDeletionsCannotResurrectTheWork`: Intermediate snapshot cannot revive work deleted later. (uncovered)
72. [Merge/Loss] `NewestTombstoneWinsTests.theAdoptedRowStillVerifiesAndTakesTheSignedIdentity`: Adopted row verifies signature with signed identity. (uncovered)
73. [Merge/Loss] `NewestTombstoneWinsTests.anOlderIncomingTombstoneLeavesTheLaterOneAlone`: Older incoming tombstone leaves the current later tombstone alone. (uncovered)
74. [Merge/Loss] `TombstoneSweepsExistingRecordsTests.aTrustedTombstoneRemovesASavedLinkButNotOneSavedAgainLater`: A trusted tombstone removes a saved link but not one saved again later. (uncovered)
75. [Merge/Loss] `TombstoneSweepsExistingRecordsTests.aTrustedTombstoneRemovesAHighlightButNotOneEditedLater`: A trusted tombstone removes a highlight but not one edited later. (uncovered)
76. [Merge/Loss] `TombstoneSweepsExistingRecordsTests.aTrustedTombstoneRemovesAQueueMembershipButNotOneChangedLater`: A trusted tombstone removes a queue membership but not one changed later. (uncovered)
77. [Merge/Loss] `TombstoneSweepsExistingRecordsTests.aDeletedCopyDoesNotTakeTheOtherDevicesMarkOnTheSamePassageWithIt`: A deleted copy does not take the other device's mark on the same passage with it when swept. (uncovered)
78. [Merge/Loss] `TombstoneSweepsExistingRecordsTests.choosingNoAccountShortcutsStaysEmpty`: Removing every Account shortcut is a choice and stays one, without restoring defaults. (uncovered)
79. [Merge/Loss] `TombstoneSweepsExistingRecordsTests.replaceLibraryDoesNotSweepExistingSavedLinks`: Replace mode does not sweep existing saved links. (uncovered)
80. [Merge/Loss] `TombstoneTrustStoreTests.testOwnDeviceAlwaysTrusted`: Own device's pub is always trusted inherently. (uncovered)
81. [Merge/Loss] `TombstoneTrustStoreTests.testNormalizedPublicKeyAppliedOnEveryPath`: KVS and trust paths apply normalized validation and reject non-hex keys. (uncovered)
82. [Merge/Loss] `TombstoneTrustStoreTests.testTrustedDevicesListsOnlyPeersWithLabel`: Trusted devices list contains only peers with a label, not the own implicitly trusted device. (weaker)
83. [Parse Drop] `AO3CommentsParseTests.ownAccountRoleOverridesWorkAuthorAndUsesUsernameNotPseud`: parses role overrides. (uncovered)
84. [Parse Drop] `AO3CommentsParseTests.missingCommentsRegionThrowsParse`: fails without ol. (uncovered)
85. [Parse Drop] `AO3InboxParseTests.visibleWorkMetadataDeduplicatesInScreenOrder`: deduplicates work IDs. (uncovered)
86. [Parse Drop] `AO3InboxParseTests.anonymousCreatorAlwaysResolvesToAuthorRole`: anonymous creator role. (uncovered)
87. [Parse Drop] `AO3InboxParseTests.inboxPillsArePresetsOverAO3sOwnFilters`: builds filter pills. (uncovered)
88. [Parse Drop] `AO3InboxParseTests.unrecognizedMarkupThrowsInsteadOfFabricatingEmpty`: throws on missing ol. (weaker)
89. [Parse Drop] `AO3InboxParseTests.countsOnlyCommentsTheReaderCanStillAnswer`: count active replies. (uncovered)
90. [Parse Drop] `AO3InboxParseTests.headerLineMarksThePageOnlyCount`: builds header string. (uncovered)
91. [Parse Drop] `AO3NamedSubscriptionsParseTests.aNonAuthorLinkInASeriesRowIsNotACreator`: only rel=author is creator. (weaker)
92. [Parse Drop] `AO3PreferencesParseTests.parsesTogglesSelectsTextAndWebLinks`: parses toggles, selects, text inputs, strips question marks. (weaker)
93. [Parse Drop] `AO3PreferencesParseTests.missingFormThrowsParseError`: throws on missing form. (uncovered)
94. [Parse Drop] `AO3ReadingsParsingTests.readsEveryRowInPageOrder`: basic metadata parsing. (uncovered)
95. [Parse Drop] `AO3ReadingsParsingTests.readsVisitCounts`: parses visit count. (uncovered)
96. [Parse Drop] `AO3ReadingsParsingTests.visitCountReadsTheWayTheBoardDraws`: formats visit count string. (uncovered)
97. [Parse Drop] `AO3ReadingsParsingTests.readsTheVersionNote`: parses version status. (uncovered)
98. [Parse Drop] `AO3ReadingsParsingTests.lastVisitedKeepsAO3sOwnWordingAndOnlyAgoesADuration`: formats last visited string. (uncovered)
99. [Parse Drop] `AO3ReadingsParsingTests.readsMarkedForLaterAndFlaggedToSkip`: parses later/skip flags. (uncovered)
100. [Parse Drop] `AO3ReadingsParsingTests.aPageWithNoReadingsIsEmptyNotAFailure`: empty page returns empty list. (uncovered)
101. [Parse Drop] `AO3SubscriptionsParseTests.readsTitleAndAllBylineAuthors`: Co-authored works list every byline pseud. (weaker)
102. [Parse Drop] `AO3SubscriptionsParseTests.usesLargestPaginationNumberForTotal`: Uses the largest pagination number for the total pages. (uncovered)
103. [Parse Drop] `AO3SubscriptionsParseTests.readsTheUnsubscribeActionBesideEachWork`: Reads the unsubscribe action beside each work. (uncovered)
104. [Parse Drop] `AO3SubscriptionsParseTests.aWorkWithoutAnUnsubscribeFormKeepsTheRowAndOmitsThePath`: A work without an unsubscribe form keeps the row and omits the path. (uncovered)
105. [Parse Drop] `AO3CollectionParsingTests.fourIndependentCollectionFlagsParseTogether`: Parses the four independent collection flags (closed, moderated, unrevealed, anonymous) correctly. (uncovered)
106. [Parse Drop] `AO3CollectionParsingTests.existingParseCollectionsStillReadsNameTitleAndMaintainers`: Parse collections still reads name, title, maintainers without flags. (uncovered)
107. [Parse Drop] `AO3CollectionParsingTests.collectionsIndexReadsOwnerClassCountsAndPageCount`: Parse collections index with owner class, works counts, and page numbers. (uncovered)
108. [Parse Drop] `AO3CollectionParsingTests.collectionPeopleParse`: Collection participants parsed correctly. (uncovered)
109. [Parse Drop] `AO3CollectionParsingTests.collectionShowParsesExactWorksAndBookmarksStats`: Parsed stats exactly from header element. (uncovered)
110. [Parse Drop] `AO3CollectionParsingTests.collectionShowReadsTotalsFromItsOwnNavLinks`: Parsed stats from nav links when absent from header. (uncovered)
111. [Parse Drop] `AO3CollectionParsingTests.collectionSegmentParsersKeepEachPager`: Works and bookmarks page parsers read pagination properly. (uncovered)
112. [Parse Drop] `AO3ChallengeParsingTests.utcDateRoundTripDoesNotDrift`: UTC date round trip does not drift. (uncovered)
113. [Parse Drop] `AO3ChallengeParsingTests.challengeDatesStayInTheChallengesOwnZone`: Challenge dates must be preserved in the challenge's own timezone. (uncovered)
114. [Parse Drop] `AO3ChallengeParsingTests.signUpIndexCountsEachRowsRequestsAndOffers`: Sign-up index groups request and offer counts by participant. (uncovered)
115. [Parse Drop] `AO3ChallengeParsingTests.signUpJoinsAssignmentMatchedState`: Sign-ups are successfully joined with their matched assignments. (uncovered)
116. [Parse Drop] `AO3ChallengeParsingTests.signUpMatchStateIsUnknownWithoutAssignments`: Match state remains unknown if assignments haven't been fetched. (uncovered)
117. [Parse Drop] `AO3ChallengeParsingTests.emptyAssignmentListsLeaveMatchStateUnknown`: Missing assignment rows from empty pages leaves match state unknown. (uncovered)
118. [Parse Drop] `AO3ChallengeParsingTests.failedLoadMoreKeepsRowsAndRetriesThePage`: Pager keeps loaded rows on failure and retries on loadNext. (uncovered)
119. [Parse Drop] `AO3ChallengeParsingTests.ownSignUpMatchesBylineOrPseudWithLogin`: Correctly maps user logins to their pseud line. (uncovered)
120. [Parse Drop] `AO3ChallengeParsingTests.assignmentBadgeDerivesLateFromWorksDue`: Infers late or delivered status from the deadline. (uncovered)
121. [Parse Drop] `AO3ChallengeParsingTests.draftPromptIDsStayUniqueAndAreNeverPosted`: Locally appended draft prompt objects get unique IDs and are discarded on post. (uncovered)
122. [Parse Drop] `AO3ChallengeParsingTests.signUpTotalReadsTheLastPageAndPageLabels`: Counts sign up numbers off of last page total rows. (uncovered)
123. [Parse Drop] `AO3ChallengeParsingTests.assignmentTemplatesPreserveDefaultAndDeliveryStates`: Assignment list parser retains fulfilled/default statuses. (uncovered)
124. [Parse Drop] `AO3ChallengeParsingTests.assignmentJoinFetchesEveryPageIncludingOpenAssignments`: Full assignment fetch hits every pagination list including Open Assignments. (uncovered)
125. [Parse Drop] `AO3ChallengeParsingTests.challengeSettingsParseFiveUTCDatesAndMatchingURL`: Parse captures UTC date limits and matching settings. (uncovered)
126. [Parse Drop] `AO3ChallengeParsingTests.promptMemeReadsAO3sPromptBlurbs`: Parse reads prompt meme blurbs and claim capabilities correctly. (uncovered)
127. [Parse Drop] `AO3ChallengeParsingTests.tagSetFourFieldsAndAssociationURLHaveNoWrite`: Tag sets scrape tag limits/names correctly, no write form param generation. (uncovered)
128. [Parse Drop] `AO3ChallengeParsingTests.ownSignUpParsesNestedRequestsAndOffers`: Sign up parsing collects requests/offers perfectly. (uncovered)
129. [Parse Drop] `AO3ChallengeParsingTests.promptEditsLandOnThePromptByID`: Prompt edits apply accurately against prompt ID without index drifting. (uncovered)
130. [Parse Drop] `AO3WorkFormParsingTests.postConfirmationNamesWhatIsMissing`: Post confirmation alert text details exactly what is missing. (uncovered)
131. [Parse Drop] `AO3WorkFormParsingTests.bulkFormParsesCommentPermissionsAndSelfRemoval`: Bulk form correctly parses comment permission radio and remove self checkbox. (uncovered)
132. [Parse Drop] `AO3WorkFormParsingTests.parsesChapterFormAndOmitsPositionWhenAbsent`: Parses chapter form fields, omitting position parameter if none provided. (uncovered)
133. [Parse Drop] `AO3WorkFormParsingTests.parsesSeriesManageOrder`: Parses the series manage positions page. (uncovered)
134. [Parse Drop] `AO3WorkFormParsingTests.parsesCollectionRowStateOnTheBlurb`: Parses collection rows to find Open/Closed/Moderated statuses. (uncovered)
135. [Parse Drop] `AO3WorkFormParsingTests.draftsURLIsItsOwnIndexNotAWorksFilter`: Drafts URL goes to a dedicated index instead of being a generic works page filter. (uncovered)
136. [Parse Drop] `AO3WorkFormParsingTests.previewExtractsThePreviewPane`: Parses the preview HTML extracting the pane wrapper. (uncovered)