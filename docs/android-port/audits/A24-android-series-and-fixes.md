# Audit A24: the series form, and the fixes of 2026-10-09

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A24-result.md`. No helper scripts left behind.

You are hunting for **bugs**, not style. iOS is the reference for behaviour: read it at
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` and change nothing there.

## What to audit

What landed on Android on 2026-10-09 (`git log --oneline a5cfb152^..HEAD -- android/app/src/main`
lists it). None of it has been reviewed, and **none of it has been seen on an emulator**.
Audits A22 and A23 (`audits/A22-result.md`, `audits/A23-result.md`, with their triage)
covered the code before it: read their tables so you do not re-file.

- **The series form** (brief `briefs/3bw-series-edit.md`, result and landing note
  `briefs/3bw-result.md`): `network/ao3/writing/AO3SeriesForm.kt`, `AO3SeriesFormParser.kt`,
  `AO3SeriesFormRepository.kt`; `writing/WritingSeriesScreen.kt`, `WritingSeriesState.kt`;
  `AO3WriteRepository.saveSeries`, `reorderSeries`, `removeWorkFromSeries`,
  `changeSeriesWorks`; the entrances in `app/SeriesWorksScreen.kt`,
  `author/AuthorProfileScreen.kt`, `writing/WritingAssociationPickers.kt` and
  `writing/WritingWorkFormScreen.kt`; the demo's answers in `network/ao3/DemoNetwork.kt`.
  **Read each request against iOS's line by line** (`Features/Writing/SeriesEditView.swift`,
  `SeriesReorderDestination.swift`, `Services/AO3WorkActions.swift`,
  `Services/AO3Client+Works.swift`, `Models/AO3WritingModels.swift`): the address, every
  field and its order, what is sent for an empty value, where the token comes from, the
  verdict. Then: who is offered Edit, Reorder and Remove (only the owner; how ownership is
  decided, and what a co-creator or a stranger sees); what a reorder does when the series
  changed on AO3 meanwhile; what Remove does to the last work; whether anything can be sent
  twice, after a session change, or after Back; what a child screen's Back keeps and loses.
- **The hand merge in `writing/WritingWorkFormScreen.kt`**: Edit tags (3bt) and the series
  reorder (3bw) each added a screen that takes the form's place. Is every early return still
  reached in the right order, and is any state now shared that should not be?
- **Claude's fixes of the day**, each with a comment naming the audit finding it answers:
  - `comments/CommentsViewModel.kt` (a reload leaves an open composer's reply or edit target
    alone; one load at a time; an Inbox row's thread loaded first and only),
    `comments/CommentsScreen.kt`, `network/ao3/comments/AO3CommentRepository.kt`
    (`useCache`, no cache for a focused thread), `CommentCache.readOnly`;
  - `home/HomeViewModel.kt` (subscriptions asked again after the session moves on);
  - `backup/BackupMergeService.kt`: `applyReplaceWork`, the tag-list unions in `mergeWork`,
    and the second pass over collection memberships at the end of `mergeCollections`;
  - `network/ao3/writing/AO3WorkFormEncoder.kt` (the Edit tags filter) and
    `writing/WritingEditTagsScreen.kt` (chip remove);
  - `account/AccountMoreOnAO3Screen.kt` (`MoreOnAO3`: every address against iOS's
    `Features/Account/AccountMoreOnAO3View.swift` and `AccountExternalNavCard.swift`),
    `app/KudosApp.kt` and `app/MainScaffold.kt` ("Show in Library"),
    `ui/components/KudosPaginationBar.kt` (the Nearby tiles),
    `author/AuthorProfileScreen.kt` ("Share Profile").
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
