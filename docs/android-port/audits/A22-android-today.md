# Audit A22: bug hunt in the Android code landed on 2026-10-08

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A22-result.md`. No helper scripts left behind.

You are hunting for **bugs**, not style. iOS is the reference for behaviour: read it at
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` and change nothing there.

## What to audit

Everything these commits added or changed under `android/app/src/main/` (run
`git log --oneline 495a1424^..HEAD -- android/app/src/main` for the list). Most of it was
written by another agent, compiled and tested, and seen on an emulator only in part. Earlier
audits (`audits/A5-result.md`, `A17-result.md`, `A18-result.md`, with their triage) covered
the code as it stood **before** these changes: read their tables so you do not re-file.

- **The work form's Save and Edit tags** (`writing/WritingWorkFormScreen.kt`,
  `WritingWorkFormState.kt`, `WritingEditTagsScreen.kt`, `WritingChaptersScreen.kt`;
  `network/ao3/writes/AO3WriteRepository.kt`: `saveWork`, `editWorkTags`, `submitWork`;
  `network/ao3/writing/AO3WorkFormEncoder.kt` and `AO3WorkFormParser.kt` for the tags form;
  `account/WritingDraftsScreen.kt`). Briefs and landing notes: `briefs/3bo-result.md`,
  `3bt-result.md`, `3bm-result.md`. **Read each request against iOS's line by line**
  (`Services/AO3WorkActions.swift`): fields, order, what is sent for an empty value, the
  token, the verdict.
- **A challenge sign-up** (`account/AO3ChallengeSignUp*`, `network/ao3/account/AO3ChallengeSignUp.kt`,
  `AO3WriteRepository.saveChallengeSignUp`; `briefs/3bl-result.md`).
- **Reading History's grouping and Favorites' scopes** (`library/LibraryHistoryGrouping.kt`,
  `ReadingAffinities.kt`, `FavoriteAffinityRow.kt`, the changes in `LibraryScreen.kt` and
  `LibraryViewModel.kt`, `WorkRepository.keepInProgress`; `briefs/3bp-result.md`,
  `3bq-result.md`). Check each rule against iOS's `Features/Library/LibraryHistoryGrouping.swift`
  and `ReadingAffinities.swift`, and that a blurred or hidden mature work cannot be told from
  an aggregate (a count, a fandom, an author).
- **The reader's finish rule and chapter scrub** (`reader/EndOfWorkActions.kt`,
  `ReaderViewport.kt`, the changes in `ReadiumNavigatorController.kt`; `briefs/3br-result.md`).
- **Work Detail's sheets and series preservation** (`works/detail/WorkDetailForms.kt`,
  `WorkImporter.preserveQueuedWork`; `briefs/3bn-result.md`).
- **The backup merge rules** (`backup/BackupMergeService.kt`; `briefs/3bs-result.md`).
- **Claude's own fixes of the day**, which no one has reviewed:
  - `network/ao3/writes/AO3AuthenticatedClient.kt` (every plain POST now goes through the
    session fence), `network/ao3/comments/CommentCache.kt` and `AO3CommentRepository.kt` (a
    per-viewer, read-only offline cache), `AO3WriteFormParser.commentWriteFailure`,
    `AO3PreferencesRepository.save`;
  - `comments/CommentsViewModel.kt` (drafts per account, an edit never in the draft store,
    the page reloaded after a reply);
  - `ui/components/SensitiveWorkRow.kt` (`hiddenMatureWorkSemantics`, the row's taps) and
    its use on every blurred surface; `search/SearchViewModel.kt` (Hide mode,
    `discardFilterEdits`); `settings/AvailabilitySweepScreen.kt`; `home/HomeViewModel.kt`
    (subscriptions and the session); `home/HomeWorkMenu.kt`;
  - `reader/ReaderProgressSaver.kt`, `reader/AnnotationRepository.kt`, `library/LibrarySelection.kt`.
  For each, say whether the fix closes the case its comment names, and what it breaks.

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
