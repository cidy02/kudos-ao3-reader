# Brief 3gv (Android tests only): three tests that fail under load

**Write code in this worktree only (`/Users/cidy02/kudos-agent-codex`, branch
`android/agent-codex-3gv`). Do not commit, push, switch branches, sign in, contact
archiveofourown.org, or run Gradle (Claude builds and tests).** Do not edit `TASKS.md`. Create
`docs/android-port/briefs/3gv-result.md` FIRST and fill it in as you go.

Each of these failed once in a full `:app:testDebugUnitTest` run while the Mac was also running an
iOS test suite, and passed when run alone and on the next full run. Make each one deterministic
without weakening what it checks (find the real race; do not just raise a timeout unless the wait
is genuinely for slow work, and then say why). Change test code only, unless the race is in app
code, in which case say so and fix it there minimally.

1. `reader/ReaderHighlightEditorTest.newSelectionMarksImmediatelyAndOffersOneTapColourRefinement`
   — `TimeoutCancellationException` in `awaitReading` (`withTimeout(5_000)` on
   `model.state.filterIsInstance<ReaderUiState.Reading>().first(predicate)`).
2. `account/Brief3caScreenTest.row47NonemptyAccountPageFilteredToZeroHasClearWhichOnlyChangesLocalFilters`
   — at `Brief3caScreenTest.kt:465`: "could not find any node that satisfies (ContentDescription =
   'Filter')" on `performClick`.
3. `works/WorkDetailShareTest.rebuildAsksBeforeWritingAndShowsTheImporterFailure` — at
   `WorkDetailShareTest.kt:68`: `assertExists` on text "Rebuild this work?" fails; "the unmerged
   tree contains '1' node that matches".

The suite's earlier fixes of this kind are in `briefs/3gs-result.md` (two flaky tests made
deterministic); follow their approach. For each test, write what the race was and why the fix
removes it.
