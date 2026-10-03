# Brief 2x result: cross-platform backup parity

Manifest version remains **8**. No UI or archive-format change was made.

## Status legend

- **Asserted**: the golden tests compare this field against the shared
  `expected-values.json` after restore and after the platform's real exporter runs.
- **Policy**: the value is intentionally recomputed by the existing iOS safety rule,
  rather than copied byte-for-byte.
- **Absent**: device-local data is deliberately omitted, and both exporters are checked.

The four field columns below are implemented assertions. Full suite execution is still
pending because this sandbox cannot start Gradle's file-lock socket or Xcode/SwiftPM's
manifest sandbox; see Verification.

## Field matrix

| Record | Field(s) | iOS → Android | Android → iOS | Android round trip | iOS round trip |
|---|---|---:|---:|---:|---:|
| Manifest | `version` | Asserted | Asserted | Asserted | Asserted |
| Manifest | `exportedAt`, Android `exportedBy` | Regenerated metadata | Regenerated metadata | Normalized | Normalized |
| Work | `id`, `title`, `author`, `summary`, `sourceURL` | Asserted | Asserted | Asserted | Asserted |
| Work | `dateAdded`, `createdAt`, `lastModifiedAt` | Asserted | Asserted | Asserted | Asserted |
| Work | `deletedAt`, `isDeleted` | Asserted | Asserted | Asserted | Asserted |
| Work | `permanentDeletionScheduledAt` | Policy | Policy | Policy | Policy |
| Work | `assetIdentifier`, `epubDigest` | Asserted | Asserted | Asserted | Asserted |
| Work | `isFavorite`, `hasGivenKudos`, `isSaved`, `isFinished` | Asserted | Asserted | Asserted | Asserted |
| Work | `keepInProgressOverride`, `hiddenFromHistoryAt` including explicit `null` | Asserted | Asserted | Asserted | Asserted |
| Work | `hasEPUB` plus both `Works/<UUID>.epub` byte payloads | Asserted | Asserted | Asserted | Asserted |
| Work | `isComplete`, `rating`, `language`, `wordCount`, `chapters` | Asserted | Asserted | Asserted | Asserted |
| Work | `datePublished`, `dateUpdated` | Asserted | Asserted | Asserted | Asserted |
| Work | `kudos`, `comments`, `bookmarks`, `hits` | Asserted | Asserted | Asserted | Asserted |
| Work | `workWarnings`, `workCategories` | Asserted | Asserted | Asserted | Asserted |
| Work | `seriesTitle`, `seriesPosition`, `seriesURL`, `ao3SeriesID` | Asserted | Asserted | Asserted | Asserted |
| Work | `lastSpineIndex`, `lastScrollFraction`, `lastReadDate`, `progressModifiedAt` | Asserted | Asserted | Asserted | Asserted |
| Work | `knownChapterCount`, `lastUpdateCheck` | Asserted | Asserted | Asserted | Asserted |
| Work | `workTags`, `workFandoms`, `workCharacters`, `workRelationships`, `workFreeforms`, `workTagsFetched` | Asserted | Asserted | Asserted | Asserted |
| Work | `ao3Unavailable`, `isQueuedForLater` | Asserted | Asserted | Asserted | Asserted |
| Work | `epubPreservationStatusRaw`, `metadataSyncStatusRaw`, `preservedAt`, `lastPreservationAttemptAt` | Asserted | Asserted | Asserted | Asserted |
| Work | `lastAvailabilityCheck`, `ao3WorkID` | Asserted | Asserted | Asserted | Asserted |
| Work | `readiumLocator`, `legacyReaderProgress` including explicit `null` | Asserted | Asserted | Asserted | Asserted |
| Work | `userTags` | Asserted | Asserted | Asserted | Asserted |
| Work | Android-derived `collectionIDs` and locator envelope metadata | Derived from shared records | Ignored by iOS | Normalized | Normalized |
| Work | `freedAt`, `authorIdentitiesJSON` | Absent | Absent | Absent | Absent |
| Bookmark | `id`, `title`, `urlString`, `dateAdded` | Asserted | Asserted | Asserted | Asserted |
| Collection | `id`, `name`, `dateAdded`, `createdAt` | Asserted | Asserted | Asserted | Asserted |
| Collection | `workIDs`, `description`, `sortOrder` | Asserted | Asserted | Asserted | Asserted |
| Collection | `lastModifiedAt`, `syncStatusRaw`, `isDeleted`, `deletedAt` | Asserted | Asserted | Asserted | Asserted |
| Collection | `permanentDeletionScheduledAt` | Policy | Policy | Policy | Policy |
| Collection | `hue`, `colorHex`, `keepsWorksOffline`, `showsOnHome`, `workOrderRaw` | Asserted | Asserted | Asserted | Asserted |
| Reading queue | `id`, `name`, `kindRaw`, `sortOrder` | Asserted | Asserted | Asserted | Asserted |
| Reading queue | `dateCreated`, `dateUpdated`, `lastMembershipChangedAt` | Asserted | Asserted | Asserted | Asserted |
| Reading queue | `isDeleted`, `deletedAt` | Asserted | Asserted | Asserted | Asserted |
| Reading queue | `permanentDeletionScheduledAt` | Policy | Policy | Policy | Policy |
| Reading queue | `hue`, `colorHex`, `tagNames`, `isPinned`, `keepsWorksOffline`, `notes` | Asserted | Asserted | Asserted | Asserted |
| System Saved for Later queue | stable `kindRaw` and memberships | Asserted; local UUID normalized | Asserted; local UUID normalized | Asserted | Asserted |
| Queue membership | `id`, `queueID`, `workID`, `queuedAt`, `lastModifiedAt`, `sortOrderInQueue`, `note` | Asserted | Asserted | Asserted | Asserted |
| Annotation | `id`, `workID`, `kindRaw`, `colorRaw`, `locatorString` | Asserted | Asserted | Asserted | Asserted |
| Annotation | `selectedText`, `note`, `progression`, `spineIndex`, `chapterTitle` | Asserted | Asserted | Asserted | Asserted |
| Annotation | `createdAt`, `lastModifiedAt`, `deletedAt`, `isPendingDeletion` | Asserted | Asserted | Asserted | Asserted |
| Saved search | `id`, `name`, `dateAdded` | Asserted | Asserted | Asserted | Asserted |
| Saved-search filters | `query`, `title`, `creators`, `fandom`, `characters`, `relationships`, `additionalTags` | Asserted | Asserted | Asserted | Asserted |
| Saved-search filters | `excludedFandoms`, `excludedCharacters`, `excludedRelationships`, `excludedAdditionalTags` | Asserted | Asserted | Asserted | Asserted |
| Saved-search filters | `rating`, `ratingMatch`, `includeNotRated`, `completion`, `crossover`, `language.id`, `chapterCount` | Asserted | Asserted | Asserted | Asserted |
| Saved-search filters | `wordsFrom`, `wordsTo`, `hitsFrom`, `hitsTo`, `kudosFrom`, `kudosTo` | Asserted | Asserted | Asserted | Asserted |
| Saved-search filters | `commentsFrom`, `commentsTo`, `bookmarksFrom`, `bookmarksTo` | Asserted | Asserted | Asserted | Asserted |
| Saved-search filters | `dateFrom`, `dateTo`, `updated`, `sort`, `sortDirection` | Asserted | Asserted | Asserted | Asserted |
| Reading session | `id`, `workID`, `ao3WorkID`, `sourceURL`, `workTitle` | Asserted | Asserted | Asserted | Asserted |
| Reading session | `startedAt`, `endedAt`, `durationSeconds`, `lastModifiedAt` | Asserted | Asserted | Asserted | Asserted |
| Reading session | `lastSpineIndex`, `chapterTitle`, `endingProgress`, `wordCount`, `chapterCountAtVisit`, `didFinish` | Asserted | Asserted | Asserted | Asserted |
| Reading favorite | `id`, `kindRaw`, `targetKey`, `displayName`, `createdAt`, `lastModifiedAt` for all four kinds | Asserted | Asserted | Asserted | Asserted |
| Fandom watermark | `id`, `fandomName`, `lastVisitedAt`, `newestWorkIDSeen`, `newestWorkTitleSeen`, `lastModifiedAt` | Asserted | Asserted | Asserted | Asserted |
| Settings | `readerFontID` | Asserted | Policy: iOS keeps the local reader font | Asserted | Policy |
| Settings | `readerMode`, `readerTwoPage`, `readerCustomize`, `readerBoldText` | Asserted | Asserted | Asserted | Asserted |
| Settings | `readerFontPt`, `readerLineHeight`, `readerLetterSpacing`, `readerWordSpacing`, `readerMargin`, `readerJustify` | Asserted | Asserted | Asserted | Asserted |
| Settings | `confirmBeforeDelete`, `hideMatureContent`, `matureContentMode`, `requireBiometricToReveal` | Asserted | Asserted | Asserted | Asserted |
| Settings | `appTheme`, `readerTheme`, `matchAppReaderTheme`, `accentColorHex` | Asserted | Asserted | Asserted | Asserted |
| Settings | `autoPreserveSmallSeriesOnSaveForLater`, `autoPreserveSeriesWorkThreshold` | Asserted | Asserted | Asserted | Asserted |
| Tombstone | `id`, `recordID`, `recordTypeRaw`, `createdAt`, `lastModifiedAt` | Asserted | Asserted | Asserted | Asserted |
| Tombstone | `sourceURL`, `ao3WorkID`, `deletedOnDeviceID`, `deletionReason` | Asserted | Asserted | Asserted | Asserted |
| Tombstone | `signerPublicKey`, `signature` with a deterministic valid Ed25519 signature | Asserted | Asserted | Asserted | Asserted |

Custom fonts and pronunciation dictionaries were not added to this brief's seed: the
requested seed explicitly covers two EPUBs and the records above. Their existing backup
paths are unchanged.

## Fixes made

1. Android now persists and re-exports iOS work `createdAt`,
   `metadataSyncStatusRaw`, and `ao3WorkID` instead of decoding and dropping them.
2. Android now persists and re-exports collection `createdAt` and `syncStatusRaw`.
3. Android now persists the two iOS auto-preservation settings even though Android has
   no UI for them. This follows iOS's pass-through rule instead of inventing defaults.
4. iOS now carries Android's `knownChapterCount` and `lastUpdateCheck` through
   `KudosBackupWork` and applies the existing newest/non-empty merge rules.
5. iOS archive restore accepts both Swift's uppercase UUID EPUB names and Android's
   canonical lowercase UUID EPUB names. This fixes the actual Android → iOS byte-loss
   path without changing the archive format.
6. Android Room schema 12 adds the five pass-through columns, with an additive 11 → 12
   migration and registration in production and migration tests.
7. Golden writers are opt-in only: `KUDOS_WRITE_GOLDEN=1` on iOS and
   `-Dkudos.writeGolden=true` on Android. Ordinary runs only read and validate fixtures.

## Fixtures and tests

- iOS test: `KudosTests/CrossPlatformBackupTests.swift`
- Android test: `android/app/src/test/java/io/github/cidy02/kudos/backup/CrossPlatformRestoreTest.kt`
- Shared values: `android/app/src/test/resources/cross-platform/expected-values.json`
- iOS archive: `android/app/src/test/resources/cross-platform/ios-export.kudosbackup`
- Android archive: `KudosTests/Fixtures/cross-platform/android-export.kudosbackup`

The checked-in archives are structurally valid bootstrap fixtures matching the
deterministic seed. The designated unrestricted runner must regenerate each one through
the real exporter flags above before treating this matrix as executed proof.

## Verification

- Passed: Swift parser for the changed backup service and new iOS test.
- Passed: `Scripts/lint.sh` (existing repository warnings only).
- Passed: JSON parse, ZIP CRC/integrity for both archives, and deterministic tombstone
  Ed25519 signature verification.
- Blocked: Android Gradle test launch fails before configuration with
  `java.net.SocketException: Operation not permitted` from Gradle's
  `FileLockContentionHandler`.
- Blocked: Xcode/SwiftPM package evaluation fails with
  `sandbox-exec: sandbox_apply: Operation not permitted`; CoreSimulator is also
  unavailable in this sandbox.

Required unrestricted run order: generate the iOS golden, run Android with its golden
flag, then rerun both suites without flags to prove ordinary runs are read-only.
