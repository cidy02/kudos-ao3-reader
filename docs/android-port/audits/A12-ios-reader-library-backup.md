# Audit A12: bug hunt in iOS's reader, library and backup

**Read-only.** Change no source file anywhere. Do not build, commit, push, switch branches,
sign in or contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A12-result.md`. No helper scripts left behind.

The code to audit is the iOS app (Swift, SwiftUI, SwiftData) at
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, with its tests at
`/Users/cidy02/kudos-ios-polish/KudosTests/`. The rules it must keep are in
`/Users/cidy02/kudos-ios-polish/docs/DATA_AND_PERSISTENCE_INVARIANTS.md`,
`docs/KUDOSBACKUP_FORMAT.md` and `docs/REGRESSION_TEST_MATRIX.md`. You are hunting for **bugs
a reader meets**: a crash, lost reading progress, a lost or duplicated highlight, note or
bookmark, a work that will not open or opens at the wrong place, a backup or sync that loses
or resurrects something.

## What to audit

- `Features/ReaderReadium/` and `Features/Reader/`, `Reading/`: opening a work, saving and
  restoring the position, the position card and its scrubber, annotations, the note editor,
  Find in Work, the chapter list, read aloud's control of position
- `Services/ReaderProgressBridge.swift`, `Services/ReadingProgress*.swift`,
  `Services/ReadingLogService.swift`, `Services/WorkLifecycle.swift`,
  `Services/PreservedWorkService.swift`
- `Features/Library/`: section lists, filters, selection and bulk actions, queues and their
  membership, collections, Recently Deleted
- `Services/KudosBackup*.swift`, `Services/FolderSyncService.swift`, `Services/SyncMerge*.swift`,
  the tombstone files: merge, replace, file merge, restore of assets, folder sync

## What counts as a finding

1. **Lost or wrong progress**: a position not saved on leaving, backgrounding or termination;
   a save that races a later one and wins; a position restored into the wrong chapter or
   work; progress regressing on reopen; finished state set or cleared when it should not be.
2. **Annotations**: a highlight, note or bookmark lost, duplicated, misattached after a work
   is rebuilt or updated, or not removed with its work.
3. **Backup and sync**: a newer local value overwritten by an older incoming one or the
   reverse of the documented rule; a deleted row resurrected; a tombstone ignored or applied
   to the wrong row; a half-finished restore that leaves the store and the files disagreeing
   in a way the next run does not repair; a field the manifest carries that a round trip
   loses.
4. **Crashes and hangs**: a force unwrap or `try!` on data that can be absent, an index out
   of range, SwiftData used off its actor, work on the main actor that can be long (a whole
   chapter, a whole library), a continuation resumed twice or never.
5. **State and concurrency**: a view drawing from a value it does not observe; a task that
   outlives its view and writes state; a result applied after its view moved to another
   work; a `.task(id:)` keyed on the wrong thing.
6. **Destructive actions**: a delete with no confirmation, a bulk action applied to rows the
   reader did not select or can no longer see (a selection that survives a filter change).
7. **Tests that prove nothing** (name the test and what would still pass if the rule broke).

Not findings: formatting, naming, "could be simpler", anything the three documents above
record as intended, the two failing backup tests already known
(`failedRestoreLeavesNoSwiftDataMutationsVisibleAfterCallerAutosave`,
`invalidBackupEPUBLeavesValidLocalEPUBUnchanged`: but do say **why** they fail if you can
tell from the code).

## The result file

Start with a table: id, severity (P1 loses data or sends something wrong to AO3; P2 wrong
behaviour a user meets; P3 the rest), file and line, one-line statement. Then one section per
finding: the exact code (quote it, with `path:line`), **a concrete failing case** (inputs or taps, then what happens and what should),
and the smallest fix you would make. If you could not confirm a suspicion by reading, put it
under "Unconfirmed" with what would confirm it; do not present it as a finding. End with what
you did not read.

Quality over count. Twenty real findings with exact lines are worth more than a hundred
guesses; a wrong file or line makes the whole report untrustworthy.
