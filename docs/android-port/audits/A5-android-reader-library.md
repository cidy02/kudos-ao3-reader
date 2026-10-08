# Audit A5: bug hunt in Android's reader and library

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A5-result.md`. No helper scripts left behind.

You are hunting for **bugs a reader meets**: a crash, lost reading progress, a lost or
duplicated highlight, note or bookmark, a reading session counted wrongly, a work that will
not open or opens at the wrong place. iOS is the reference for behaviour, at
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (change nothing there):
`Features/ReaderReadium/`, `Features/Library/`, `Services/ReadingLogService.swift`,
`Services/WorkLifecycle.swift`, `Services/ReadingProgress*.swift`.

## What to audit

Under `android/app/src/main/java/io/github/cidy02/kudos/`:

- `reader/` (all of it: opening a work, the Readium navigator, position and progress saving,
  the position card, annotations, the note editor, Find in Work, read aloud, reading
  sessions, the chapter list, settings)
- `library/` (queries, the section lists, filters, sort, selection and bulk actions, queues
  and their membership, collections, Recently Deleted, statistics)
- `works/` where it opens the reader or changes a work's state (finished, favourite, delete,
  rebuild from original)
- `home/` where it resumes reading

## What counts as a finding

1. **Lost or wrong progress**: a position not saved on leaving, on backgrounding, on process
   death or on rotation; a save that races a later one and wins; a position restored into the
   wrong chapter or the wrong work; progress regressing when a work is reopened; finished
   state set or cleared when it should not be (compare iOS's rules line by line).
2. **Annotations**: a highlight, note or bookmark lost, duplicated, attached to the wrong
   text after the work is rebuilt or updated, or not removed with its work; an edit that
   overwrites a newer one.
3. **Reading sessions and statistics**: a session never closed, closed twice, counted across
   a pause, or attributed to the wrong day; a number on Reading Insights or a queue page that
   can disagree with iOS for the same data.
4. **Crashes**: a `!!`, an unchecked index or cast, a `first()` on what can be empty, a
   lateinit read before it is set, an API above `minSdk` 26, a file read on the main thread
   that can be large, a Compose state read from a background thread.
5. **State and concurrency**: a composable that draws from a value it does not observe; a
   coroutine that outlives its screen and writes state; a flow collected twice; an effect
   keyed on the wrong thing; a list that is not lazy and can be long.
6. **Destructive actions**: a delete with no confirmation where iOS has one, a bulk action
   applied to rows the reader did not select (a selection that survives a filter change), a
   soft delete that hard-deletes.
7. **Tests that prove nothing** (name the test and what would still pass if the rule broke).

Not findings: formatting, naming, "could be simpler", anything recorded as a decision in
`docs/android-port/DECISIONS.md` or as left out in a brief's result
(`docs/android-port/briefs/*-result.md`: read aloud's engine limits, Pronunciations and the
Kokoro rows are known).

## The result file

Start with a table: id, severity (P1 loses data or sends something wrong to AO3; P2 wrong
behaviour a user meets; P3 the rest), file and line, one-line statement. Then one section per
finding: the exact code (quote it, with `path:line`), the iOS code it is checked against
(`path:line`), **a concrete failing case** (inputs or taps, then what happens and what should),
and the smallest fix you would make. If you could not confirm a suspicion by reading, put it
under "Unconfirmed" with what would confirm it; do not present it as a finding. End with what
you did not read.

Quality over count. Twenty real findings with exact lines are worth more than a hundred
guesses; a wrong file or line makes the whole report untrustworthy.
