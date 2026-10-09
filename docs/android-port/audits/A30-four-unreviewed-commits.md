# Audit A30: four commits nobody has reviewed (the comments fixes, the fifteen small rows, the Privacy screen, iOS T-371)

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A30-result.md`. No helper scripts left behind.

You are hunting for **bugs**, not style. iOS is the reference for Android's behaviour: read it
at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` and change nothing there. Item 4 audits
iOS itself.

Read `audits/A28-result.md` with its triage first (it is yours); do not re-file what is there.

## What to audit

1. **`84778078`** (`git show 84778078 -- android/app/src/main`): Claude's fixes for your A28-1
   to A28-4 in `comments/CommentsViewModel.kt` and `comments/CommentsScreen.kt`:
   `loadChapterComments` (one operation owned by `loadJob`), `retry`, `openOnChapter`, the
   draft guard in `present`. For each of A28-1 to A28-4 say whether the case you named is
   closed on every path, and what the fix breaks. Then: Try Again after each kind of failed
   load (a page, a focused thread, Chapter Comments at each of its two reads); `lastPage` and
   `pendingChapterComments` across `load`, `setTarget`, `setScope`, `selectChapter`, a
   refresh and a page change; the selected chapter and scope label when the thread names a
   chapter the index later lists with a different position or title; a thread whose root and
   focused reply name different chapters; what `reloadPageOnScreen` and a posted reply do
   while Chapter Comments is pending; whether a draft can still land in the wrong composer.
2. **`f0940037`** (brief `briefs/3ca-fifteen-small-rows.md`, result and landing note
   `briefs/3ca-result.md`): fifteen small behaviours, each against the iOS lines its result
   quotes. **And the change that is not one of the rows:** `AO3AuthorRepository` and
   `AO3SearchRepository` no longer read a page a second time without the session when the
   signed-in read fails. Find every caller of both and say, for each kind of failure (session
   expired, 403, 404, 5xx, offline, a page the signed-in viewer may not see), what the screen
   showed before and shows now, what iOS shows, and whether any screen now fails where it
   used to work for a reason that is not the reader's session. Does a signed-out reader still
   make exactly one anonymous read? Is `authenticatedClient.username() != null` the right test
   of "signed in" while a session is being restored?
3. **`51b4eada`** (brief `briefs/3bz-privacy-screen.md`, result and landing note
   `briefs/3bz-result.md`): `settings/PrivacyDataScreen.kt`, `settings/LocalDataFootprint.kt`,
   the notice in `auth/AO3AuthRepository.kt`, the demo rows in `app/DemoLibrary.kt`. Against
   iOS `Features/Account/PrivacyDataView.swift`, `Services/LocalDataFootprint.swift`,
   `Services/LocalDataClearing.swift`. Each Clear: exactly which works, files and rows it
   touches, against iOS's selection, and **anything it deletes that iOS keeps** (a kept,
   queued, favourited, imported or unavailable work; a work's only copy; a reading position of
   a work being read). The measuring: symlinks, a file deleted mid-scan, a directory that does
   not exist, a very large library on the main thread or not. The notice: when is it cleared,
   can a stale "Logged out" or "session expired" sentence sit under a signed-in account, and
   can it name or leak anything. The demo: does it write outside the app's own directories,
   and does anything it adds reach a non-demo launch.
4. **iOS `53c552ce`, T-371** (`git -C /Users/cidy02/kudos-ios-polish show 53c552ce`; its
   `TASKS.md` row says what it claims; `audits/A27-result.md` with its triage is what it
   answers): the annotation pass moved before the dedupe in `Services/KudosBackup.swift`
   (`removeDeletedElsewhere`, `dedupeSamePassageAnnotations(excluding:)`): is every case A27-3
   named closed, in Merge, reconcile and Replace, including an archive that lists no
   annotations, a soft-deleted loser, and a row both swept and referenced later in the same
   restore (is a deleted model ever read or written after `context.delete`)? The draft
   hand-over in `Services/AO3AuthService.swift` `restore` (which generation's drafts does it
   move, and can it hand one account's drafts to another?). Search's filter revert without
   the phase check (`Features/Search/SearchView.swift`: can it now undo an Apply, or revert
   while the first search is still loading?). `AccountShortcutStore` (`none`). The scroll to
   the result in `Features/Writing/SeriesEditView.swift` (`ScrollViewReader`, the `id` on two
   rows). The two `catch AO3WorkWriteError.unconfirmed` arms.

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
