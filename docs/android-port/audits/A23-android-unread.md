# Audit A23: what audit A22 did not read, and its open suspicions

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A23-result.md`. No helper scripts left behind.

You are hunting for **bugs**, not style. iOS is the reference for behaviour: read it at
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` and change nothing there.

## What to audit

Audit A22 (`audits/A22-result.md`, with its triage) ran out of room. This audit is the part
it lists under "Not read" and "Unconfirmed". Read A22's table and triage first; do not
re-file what is there. Everything is under `android/app/src/main/java/io/github/cidy02/kudos/`.

**Read line by line against iOS**, which is the reference
(`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`):

- `backup/BackupMergeService.kt` in full, against `Services/KudosBackup.swift`'s restore and
  merge (brief `briefs/3bs-result.md` lists the seven rules that were changed and why):
  every field's merge rule, every tombstone check, what Replace, Merge and File Merge each do
  to works, annotations, queues, collections, saved links, saved searches and sessions; a
  record that can come back after it was deleted; a record that can be lost when both sides
  changed it; a date compared in the wrong direction.
- `works/detail/WorkDetailForms.kt` and the series preservation loop in
  `library/ReadingQueueRepository.kt` with `WorkImporter.preserveQueuedWork`, against
  `Services/ReadingQueueService.swift:476-600` (brief `briefs/3bn-result.md`).
- `writing/WritingChaptersScreen.kt` and `account/WritingDraftsScreen.kt` with their state
  classes (briefs `3bm-result.md`, `3az-result.md`).
- `network/ao3/writing/AO3WorkFormEncoder.kt` and `network/ao3/account/AO3ChallengeSignUp.kt`:
  the request each builds, field for field and in order, against `Models/AO3WritingModels.swift`
  and `Services/AO3ChallengeActions.swift`.
- `reader/EndOfWorkActions.kt` and `reader/ReaderViewport.kt` (brief `3br-result.md`).

**Settle each of A22's open suspicions** by reading, as a finding with a failing case or
closed with the reason:

1. Right-to-left paginated end: what Readium Kotlin's `pageIndex` means in an RTL
   publication (read the library's source in the Gradle cache if it is there:
   `~/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/`), and whether
   `ReadiumNavigatorHost`'s `totalPages - pageIndex` is then right.
2. `ReaderProgressSaver.onProgress` after the reader's last flush: can a position be lost?
3. `AnnotationRepository.deleteAnnotation` stores `recordID = id.lowercase()`: what case
   does iOS's tombstone record id use (`Services/SyncTombstones.swift`), and what does each
   side compare with?
4. Edit tags: two chip removes before the next composition
   (`writing/WritingEditTagsScreen.kt:168`).
5. Edit tags when AO3's page carries its token only in the `<meta>` tag: is it still sent in
   the body, and does iOS send it there (`Services/AO3WorkActions.swift`, `editTags`)?

## What counts as a finding

1. **Wrong behaviour against iOS**: a rule, a word, an order, a default or an edge case that
   differs from the Swift code and is not recorded as a decision in
   `docs/android-port/DECISIONS.md` or the brief's result file (`docs/android-port/briefs/3b*-result.md`).
2. **Data loss or corruption**: text a writer typed that can be lost or replaced (the editor,
   checkpoints, recovery, the form's state across screens, rotation, process death, a session
   change); a payload that would change a work the writer did not touch.
3. **Network**: a read or write `docs/AO3_NETWORKING_POLICY.md` does not allow; a request that
   is repeated, retried, made on opening when it should wait, or made for a viewer AO3 will
   refuse; a POST to an address that is not AO3's; a token reused where iOS reads a fresh one.
4. **State and concurrency**: a composable that draws from a value it does not observe (a
   function reading a flow's `.value`); a coroutine that outlives its screen and writes state;
   a race between a load and a session change; an effect keyed on the wrong thing; a list
   that is not lazy and can be long.
5. **Crashes**: a `!!`, an unchecked index, a parse of AO3's HTML that throws on a page the
   fixtures do not cover, an API above `minSdk` 26.
6. **Tests that prove nothing**: a test whose assertion cannot fail, or that does not exercise
   the rule its name states. Name the test and say what would still pass if the rule broke.

Not findings: formatting, naming, missing comments, "could be simpler", anything already
listed as left out or as a decision.

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
