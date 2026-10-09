# Audit A28: the fixes of audit A26 (`8ca34595`), the tests written on 2026-10-09, and four leads nobody has traced

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A28-result.md`. No helper scripts left behind.

You are hunting for **bugs**, not style. iOS is the reference for behaviour: read it at
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` and change nothing there.

## What to audit

Read `audits/A26-result.md` with its triage first, and `audits/A24-result.md` with its
triage; do not re-file what is there.

1. **Commit `8ca34595`** (`git show 8ca34595 -- android/app/src/main`), Claude's fixes for A26,
   which nobody has reviewed. For each, say whether it closes the case its comment names, on
   every path, and what it breaks:
   - `network/ao3/writes/AO3WriteRepository.kt`: `movedOnAfterWrite(generation, answer)` (AO3's
     login page in answer to a POST is returned as it is), `postWriting(judgedByCaller)`,
     `previewChapter` (a preview is returned even when the session has moved on), the series
     read-back that no longer rethrows a cancellation (does a closed screen still cancel? can
     the read-back now run, or its result be applied, for a session that is no longer the
     writer's?).
   - `writing/WritingChapterFormState.kt` (`sentNothing`, a preview adopted when `active`, a
     save or delete finished when `active`), `writing/WritingWorkFormState.kt` (the result
     shown without a generation test), `writing/WritingSeriesState.kt`. After each of these, **can
     a form that belongs to a session that has ended still send anything, or show another
     account something it should not?** What does a `saved`/`finished` state do next (which
     reads, on which session)?
   - `account/AO3CollectionFormState.kt` (`sentUnderAnEarlierSession`; the catch that now shows
     "Not saved" whenever the state is active).
   - `comments/CommentsViewModel.kt` (`openOnChapter`, `showChapterIncluding`, `present`),
     `comments/CommentsScreen.kt` (the two effects), `network/ao3/chapters/
     AO3ChapterIndexRepository.kt`, `account/AccountInboxPane.kt`, `app/AppNavHost.kt`: the
     Inbox's "Chapter Comments". Against iOS `Features/Comments/CommentsModel.swift`
     (`loadFocusedThread`, `chapterPage(_:including:focusedRootID:)`) and `CommentsView.swift`.
     Count the reads for one opening. What happens when the thread read fails, when the chapter
     index fails, when the reader changes scope or page while the two reads are out, when the
     screen is left and come back to, when the comment is a reply, when the comments screen for
     the same work was already open underneath? Is a draft restored into the wrong target?
   - `network/ao3/writing/AO3ChapterForm.kt` (the token and method always in the body: can
     either now be sent twice, or a `_method` sent for a form that should be a plain POST?).
   - `writing/WritingSeriesScreen.kt` (the scroll to the result).
2. **The tests written on 2026-10-09**, for "tests that prove nothing" (finding kind 6 below),
   which A26 said it did not read: `AO3ChapterFormTest`, `WritingChapterReadTest`,
   `WritingChapterFormStateTest`, `WritingChapterSaveTest`, `WritingChapterDeleteTest`,
   `WritingChapterRefreshTest`, `WritingChapterFormScreenTest`, `AO3ChapterDispatchTest`,
   `DemoWritingChaptersTest`, `AccountShortcutsScreenTest`, `AuthorWorksSortTest`,
   `AuthorProfileSortScreenTest`, `DemoAuthorWorksSortTest`, `WritingSeriesTest`,
   `WritingSeriesScreenTest`, `AO3CollectionFormTest` (the two session tests),
   `CommentsViewModelDraftTest` (`chapterCommentsFromTheInboxPutTheInboxThreadFirstAndReadItOnce`).
   Name each test whose assertion cannot fail or does not exercise the rule its name states, and
   say what would still pass if the rule broke. Also name a rule of the chapter form, the series
   form or the write repository that **no** test pins.
3. **Four leads, each to confirm or dismiss by reading:**
   - A caller cancelled in the instant a POST returns (`withContext(NonCancellable)` around
     `postAuthenticatedInSession`, then code that suspends or checks cancellation): for which
     writes can the screen end up saying nothing, or "session changed", about a write that went
     out? Trace `WritingWorkFormScreen`'s scope into the chapter form (does Back during a save
     cancel it?).
   - The comments view model is keyed by work id (`CommentsScreen.kt`, `viewModel(key = …)`):
     after an Inbox thread for a work, is the same model reused when that work's comments are
     opened another way, and does it then show the thread instead of the page?
   - A top-level comment draft restored by a load that finishes while a reply composer is open
     (`present` in `CommentsViewModel.kt`): can it land in the reply?
   - `AO3WorkFormParser.writeErrorMessage` and `workWriteError` look for AO3's error anywhere
     on the page where iOS looks inside `#main`: name a real AO3 page on which that difference
     turns a success into a refusal or the reverse.

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
