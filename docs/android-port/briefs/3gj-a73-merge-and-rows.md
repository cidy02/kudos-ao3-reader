# Brief 3gj: A73's verified faults (both apps' File Merge; Android's restore, rows, comments)

**Write code; do not commit, push, switch branches, sign in, run Gradle or xcodebuild, or contact
archiveofourown.org.** Claude builds, tests and lands both apps. Do not edit `TASKS.md`. Create
`docs/android-port/briefs/3gj-result.md` FIRST; write each item into it as you finish it: **fixed /
not real / left**, `path:line`, the iOS code followed or changed, the test added and how it fails
with the change undone.

Grok's review is `docs/android-port/audits/A73-result.md` (finding numbers are its). Claude checked
2, 3 and 8 in iOS's code: **2 is shared by both apps** and reaches works and queues too; 3 is
Android's only (iOS maps each archived work id through `restoredWorksByArchivedID`); 8 is not a
fault (iOS's cell also has `.frame(maxWidth: .infinity)`); 1 is not a fault (iOS suppresses the
same way: a tie goes to the tombstone). 7 is iOS's and Claude fixes it.

Rules: `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` binds every change here; Room migrations additive
(none expected); backup manifest v8 unchanged; Android's ICU regex rejects some JVM flags
(`RegexPortabilityTest`). iOS is `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` and its tests
`/Users/cidy02/kudos-ios-polish/KudosTests/`: **write the iOS change as a patch file**
`docs/android-port/briefs/3gj-ios.patch` (unified diff against that tree, `git apply --check` clean),
do not edit that tree.

1. **Both apps, finding 2: File Merge un-parks a record the archive itself has deleted.** In Merge,
   a local row in Recently Deleted is restored to the library (and, for a work, its tombstone is
   retracted) without looking at the archive's own `isDeleted`. Importing the same backup twice
   brings back a work, collection or queue the first import put in Recently Deleted. Android
   `backup/BackupMergeService.kt` (~:203 works, ~:1381 collections, ~:1727 queues); iOS
   `Services/KudosBackup.swift` (~:2358 works, ~:2558 collections, ~:2789 queues). Un-park only
   when the archive's copy is live; when it is deleted too, keep the local deletion and its
   deadline (and do not retract the tombstone). Keep the case the code was written for: Merge
   undoing a Replace that parked a record the archive has live. Tests on both apps for each of
   the three, in Merge, twice in a row, and the Replace-undo case still passing.
2. **Android, finding 3:** the absent soft-deleted collection path (`toWorkCollection`, ~:1355) keeps
   the archive's work ids; map them through `remapWorkId` as the other three paths do.
3. **Android, finding 4:** a deleted archived collection takes its name in `names`/`uniqueName` and
   can push the live one to "(Restored)"; a deleted row must not consume or contest a name.
4. **Android, finding 5:** on the compact History/Favorites row (`ui/subject/WorkLibraryComponents.kt`,
   `WorkLedgerRow`), the selection border and checkbox sit under `Modifier.blur`; draw them outside
   the blur, as `SensitiveWorkRow` does.
5. **Android, finding 6:** a comment `li` with no `h4.heading.byline` is AO3's deleted comment
   ("(Previous comment deleted.)"); iOS treats it as deleted and keeps the `li`'s words
   (`Services/AO3Client+Comments.swift:273`–`:299`, test `deletedCommentParsesAsTombstoneAndKeepsItsReplies`).
   Android parses it as a Guest comment with "Deleted or hidden comment.". Match iOS, replies kept.
