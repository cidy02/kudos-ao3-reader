# Audit A26: the chapter form, the shortcuts editor, the author sort, and the later fixes of 2026-10-09

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A26-result.md`. No helper scripts left behind.

You are hunting for **bugs**, not style. iOS is the reference for behaviour: read it at
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` and change nothing there.

## What to audit

What landed on Android after audit A24 was sent (`git log --oneline c417e8a4^..HEAD --
android/app/src/main` lists it). None of it has been reviewed or seen on an emulator. Read
`audits/A24-result.md` with its triage first; do not re-file what is there.

- **The chapter form** (brief `briefs/3bu-chapter-form.md`, result and landing note
  `briefs/3bu-result.md`): `network/ao3/writing/AO3ChapterForm.kt`, `AO3ChapterFormParser.kt`;
  `writing/WritingChapterFormScreen.kt`, `WritingChapterFormState.kt`, the changes in
  `WritingChaptersScreen.kt`, `WritingTextEditorScreen.kt`, `WritingWorkFormScreen.kt` and
  `WritingWorkFormState.kt`; `AO3WriteRepository.saveChapter`, `previewChapter`,
  `updateWorkTotals`, `deleteChapter`, `postWriting`; `network/ao3/DemoWritingChapters.kt`.
  **Read each request against iOS's line by line** (`Features/Writing/AddChapterView.swift`,
  `WritingChaptersView.swift`, `WritingPreviewView.swift`, `Services/AO3WorkActions.swift`,
  `Services/AO3Client+Works.swift`, `Models/AO3WritingModels.swift`): the address, every
  field and its order, what is sent for an empty value, where the token comes from, the
  verdict. Then: a new chapter previewed and then saved (does the second write update the
  draft AO3 just created, or create another?); Post from the preview; Delete; what the work
  form reads afterwards and how many times; what Back keeps and loses from each screen; what
  can be sent twice.
- **The Account shortcuts editor and an author's works sort** (brief
  `briefs/3by-account-shortcuts-and-author-sort.md`, result `briefs/3by-result.md`):
  `account/AccountShortcuts*.kt`, the grid in `account/AccountScreen.kt`, the store in
  `data/preferences/SettingsRepository.kt`; `author/AuthorWorksSortFields.kt` and the sort
  in `author/AuthorProfileScreen.kt` with `network/ao3/author/AO3AuthorUrls.kt`. Against
  `Features/Account/AccountShortcuts.swift` and the works sort in
  `Features/Search/AO3FilterPanel.swift` with `Services/AO3AuthorProfileService.swift`: the
  stored value for every case (default, a choice, none, an unknown id), the request for
  every sort, direction and completion, one read per Apply, and a dismissed sheet.
- **Three hand merges** where two features added something in the same place: `app/Routes.kt`
  (two route lists), `app/AppNavHost.kt` (the author profile's arguments),
  `writing/WritingWorkFormScreen.kt` (the screens that take the form's place: Edit tags, the
  series reorder, the chapter form). Is every branch still reached, in an order that makes
  sense, and is any route missing from a list its neighbours are in?
- **Claude's later fixes of the day**:
  - `network/ao3/writes/AO3WriteRepository.kt`: `movedOnAfterWrite`, used after every POST
    in place of a cancellation. For **each** of its call sites say what the caller's screen
    now shows, and whether any caller still words a sent write as "not saved". Is there a
    write whose POST can have gone out and whose caller still throws or reports a
    cancellation (look for `requireCollectionSession` after a POST, and at
    `AO3AuthenticatedClient.postAuthenticatedInSession` itself)?
  - `network/ao3/writing/AO3SeriesForm.kt` (the token and method always in the body),
    `writing/WritingSeriesScreen.kt`, `app/SeriesWorksScreen.kt`;
  - `backup/BackupMergeService.kt`: the collection membership pass, now only for collections
    the archive carries;
  - `account/AccountInboxPane.kt` ("Chapter Comments").
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
