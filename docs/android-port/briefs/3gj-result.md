# Brief 3gj result

Implementation complete; validation handoff to Claude. Builds and app test runs are reserved for Claude; no commits, pushes, branch changes, sign-in, Gradle, xcodebuild, or AO3 requests were performed.

## Items

- Finding 2 (both apps, File Merge): fixed — Android edits and checked iOS patch.
- Finding 3 (Android, collection work IDs): fixed.
- Finding 4 (Android, deleted collection names): fixed.
- Finding 5 (Android, compact row selection): fixed; rendering verification left.
- Finding 6 (Android, deleted comments): fixed.
- Finding 1: not real — supplied triage: iOS also gives a timestamp tie to the tombstone.
- Finding 8: not real — supplied triage: iOS also uses `.frame(maxWidth: .infinity)`.
- Finding 7: left — Claude owns the iOS fix.

### Finding 3 — fixed

- Android: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt:1360` remaps and deduplicates the absent collection's members through the existing `remapWorkId` map.
- iOS followed: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift:2677` resolves each archived member through `restoredWorksByArchivedID`; no iOS change for this finding.
- Test added: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupMergeParityTest.kt:131`, `absentDeletedCollectionRemapsItsMembersToTheExistingLocalWork`, exercises Merge and Reconcile with distinct UUIDs for the same AO3 work. Undoing the copy/remap leaves `[OTHER]` instead of asserted `[WORK]` in the deleted collection. Test execution deferred to Claude (no Gradle).

### Finding 4 — fixed

- Android: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt:1355` preserves an archived deleted collection's name verbatim and `:1363` only reserves names for live inserts.
- iOS followed: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift:2583` / `:2603` creates the archived collection and assigns its archived name without a uniqueness contest; no iOS change for this finding.
- Test added: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupMergeParityTest.kt:146`, `deletedCollectionsNeverContestOrReserveALiveCollectionName`, checks both archive orders and an existing live namesake in Merge and Reconcile. Undoing the fix renames either the live or deleted row to `Favorites (Restored)`, failing exact-name assertions. Test execution deferred to Claude.

### Finding 6 — fixed

- Android: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParser.kt:179` returns a deleted, non-guest placeholder with the `li`'s text when `h4.heading.byline` is absent. Existing thread assembly retains replies; no network behavior changed.
- iOS followed: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/AO3Client+Comments.swift:294`, the missing-byline guard and verbatim placeholder text. No iOS change for this finding.
- Test added: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParserTest.kt:45`, `deletedCommentParsesAsTombstoneAndKeepsItsReplies`, models the sibling reply wrapper after a bare deleted `li` and an unrelated earlier comment. Undoing the guard fails the deleted/non-guest/empty-author/exact-body assertions (old result is Guest and `Deleted or hidden comment.`); reply ownership and depth are also checked. Test execution deferred to Claude.

### Finding 2 — fixed (Android edits + iOS patch)

- Android: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt:203`, `:1382`, `:1728` only un-park a deleted work/collection/queue in File Merge when `archived.isDeleted != true`. Deleted archive copies retain the local deletion fields, deadline and work tombstones.
- iOS changed only in `docs/android-port/briefs/3gj-ios.patch`: guards against `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift:2359`, `:2558`, `:2789` implement the same rule. The target tree was read, never edited. `git -C /Users/cidy02/kudos-ios-polish apply --check /Users/cidy02/kudos-agent-codex/docs/android-port/briefs/3gj-ios.patch` passed.
- Android tests: `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupMergeParityTest.kt:82`, `repeatedFileMergeKeepsArchivedDeletionsAndTheirLocalRecoveryDeadlines`, first imports all three deleted record kinds, then repeats File Merge twice and asserts all deletion dates/deadlines and a local work tombstone stay intact. Undoing any corresponding guard makes that record live and clears its deadline; undoing the work guard also retracts the tombstone. `:109`, `repeatedFileMergeStillUndoesReplaceParkingForAllThreeRecordKinds`, actually parks all three via an empty Replace, then merges the live archive twice and verifies all three return with cleared deletion fields. Existing work-tombstone identity tests remain in place.
- iOS tests in the patch: `/Users/cidy02/kudos-ios-polish/KudosTests/KudosBackupTests.swift:1827` adds `repeatedFileMergeKeepsArchivedDeletionsAndLocalRecoveryDeadlines` with the same three record kinds, repeated imports, recovery-deadline and tombstone checks. Undoing any guard fails that kind's pending-deletion/date/deadline assertions (and the work's tombstone check). The previous `fileMergeUndeletesPendingDeletionCollectionsAndQueues` test at original `:1858` is extended/renamed to `repeatedFileMergeUndoesReplaceParkingForWorksCollectionsAndQueues`, parks works too, and checks all three across two live Merge imports. It protects Replace undo while the new regression catches the old resurrection.
- No schema/migration/manifest-version changes. Tests added but not run; Claude owns builds and app suites.

### Finding 5 — fixed; rendering verification left to Claude

- Android: `android/app/src/main/java/io/github/cidy02/kudos/ui/subject/WorkLibraryComponents.kt:160` puts the card fill, selected border, click handling and privacy semantics on the outer container. The checkbox is a sibling of the blurred work-content box (`:178`), shared by both normal and accessibility layouts. All title/fandom/metadata/progress/status content stays inside the blur. Selection uses the leading checkbox pattern already in Android `ui/components/SensitiveWorkRow.kt:234`.
- iOS followed: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Privacy/MatureContent.swift:140`–`:187` keeps the outline on the enclosing card and overlays selection outside blurred content. No iOS change for this finding.
- Tests added: `android/app/src/test/java/io/github/cidy02/kudos/ui/subject/WorkLedgerRowSelectionTest.kt:37` / `:39`, `selectionChromeStaysSharpAtNormalTextSize` and `selectionChromeStaysSharpAtAccessibilityTextSize`. Native-graphics Robolectric captures compare the selected border and checkbox before/after obscuring the same row, with nonempty/accent reference checks. Undoing the layout fix puts both under the blur, changing the pixels and failing the sharp-border/checkbox comparisons. These rendering tests have not been run; Claude must verify native screenshot support and inspect both layouts on an emulator. No visual correctness claim is made here.

### Triage retained

- Finding 1 — **not real**, as supplied by Claude and confirmed in `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/PersistenceSync.swift:624`: only a strictly newer snapshot beats the tombstone; a tie suppresses. No code or test added for the rejected finding.
- Finding 8 — **not real**, as supplied by Claude and confirmed in `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/UIComponents/SubjectSurface.swift:901`: each cell takes the available width, including an odd accessibility row. No code or test added for the rejected finding.
- Finding 7 — **left to Claude**, `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift:2928`; this patch does not touch the Saved for Later membership-clock logic.

### Verification / handoff

- Passed: iOS patch applicability (`git apply --check`) against the supplied tree; tracked-diff whitespace check (`git diff --check`); standalone whitespace checks on every changed/new source and result file; rejected Android regex-token scan on the three edited production files (no new regex flags).
- All regression-test undo/failure descriptions above are expected failures derived from source review, **not executed mutation-test results**. Per the brief, no Gradle, xcodebuild, app tests, sign-in, or AO3 contact occurred. Claude must run the new/existing backup and comment tests and both row rendering tests, then inspect normal/accessibility selection on an emulator before landing.
- Android changes are uncommitted on `android/agent-codex-3gj`. No branch changes, commits, pushes, TASKS.md edits, Room migrations, or backup manifest version changes. The pre-existing untracked A73 audit and 3gj input brief are preserved.
