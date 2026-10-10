# A45: Android writes for works, chapters and series, and whether the screen that opened each is told

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A45-result.md`. **Leave no other file behind**: no dumps, no helper
scripts, nothing at the root of the worktree.

Android only: `android/app/src/main/java/io/github/cidy02/kudos/`.

Background. One fault has now been found four times, each time by hand: a screen writes to AO3,
goes back, and the screen it goes back to shows what it showed before the write, because
nothing told it. The last one: `writing/WritingOwnWorkScreen.kt` passed `onSaved = onBack` for
"edit", so the writer's list kept a work that had just been deleted (fixed: it now calls
`onChanged()` too). An earlier index (A39) looked only at reads through `AO3PageCache` and
called that path sound. This job asks the question the other way round, from every write.
Claude will check every row, so what helps is an **index of where to look**: every row quotes
the Kotlin with `path:line`. A row without a quote is worth nothing: leave it out. Never write
"none" without naming the files and the words you searched for.

Do this, in order, and stop where you run out of time (say where):

1. **The writes: only these.** An earlier run (A42) listed all 46 and ran out of time, so this job
   takes one group. In `network/ao3/writes/AO3WriteRepository.kt` unless said otherwise:
   `saveSeries`, `reorderSeries`, `removeWorkFromSeries`, `bulkEditWorks`, `deleteWorks`, `saveWork`, `editWorkTags`, `postWork`, `deleteWork`, `saveChapter`, `updateWorkTotals`, `deleteChapter`. Give each one's `path:line`. Do not list or trace any other write.
2. **The callers.** For each write: every state holder, view model or composable that calls it
   (`path:line`), and **the exact lines that run when it succeeds**. Follow the success to the
   composable that shows that state holder, and say which is true, with the quote:
   (a) the screen reads its own page again from AO3 (quote the read, and say whether it passes
   `bypassCache = true`);
   (b) it calls a lambda handed to it (`onSaved`, `onChanged`, `onDeleted`, `onLeft`,
   `onWithdrawn`, `onBack`, `onClose`: name it) — then list **every place that composable is
   called** (`path:line`) and quote **exactly what each caller passes for that lambda**. A
   caller that passes only something that navigates back (`{ x = null }`, `onBack`,
   `navController.popBackStack()`) and nothing that reloads is the thing this job is looking for;
   (c) it changes its own state by hand and stays;
   (d) it only shows a message.
3. **The screen behind.** For every (b) whose caller only goes back, and every (d): the screen
   the reader is returned to, what on it the write changed (a title, a count, a row, a badge, a
   button's label), and where that data lives: `remember { mutableStateOf(...) }` inside a
   `sharedComposable(...)` route of `app/AppNavHost.kt` (**read again when the reader comes
   back**: say so, it is not a fault), a view model (`viewModel(...)`: kept), state hoisted in
   the same composable that showed the form in place of itself (`if (editing != null) { Form();
   return }`: **kept, and the most likely fault**), or a `savedStateHandle` revision. Quote it.

End with a table, most suspicious first: number, the write (`path:line`), the caller
(`path:line`), what the screen behind goes on showing and where its state lives (`path:line`),
(a) to (d), one line. Start the file with two numbers: writes traced to the end, rows you think are faults. **Trace every
write in the group before writing the table**; if you cannot, say which you did not reach.
