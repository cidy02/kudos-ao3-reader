# Brief 3gv result

Status: test fixes ready for Claude to compile and run on `android/agent-codex-3gv`.

Created this result file before changing tests and updated it during the investigation. No Gradle runs, commits, pushes, branch switches, sign-ins, AO3 requests, or `TASKS.md` edits. The pre-existing untracked `3gv-flaky-tests.md` is untouched.

## Reader highlight editor

Test: `ReaderHighlightEditorTest.newSelectionMarksImmediatelyAndOffersOneTapColourRefinement`.

- Race found in the test harness: `Dispatchers.setMain(UnconfinedTestDispatcher())` does not confine resumptions to one thread. Real Room queries and invalidation flows can resume on different executor threads. `ReaderViewModel.observeAnnotations`, the settings collectors, and `annotateSelection` all call `updateReading`, which reads `_state.value`, copies it, then assigns the copy. With unconfined Main, a collector can read the old state before the selection publishes its colour-bar id and then overwrite that id with its older copy. The predicate can then wait forever; this is not fixed by a longer timeout. The app runs these coroutine resumptions serially on Android Main.
- Fix: install one `StandardTestDispatcher` as Main for this class. `awaitReading` runs its unchanged StateFlow predicate with `runTest` on that dispatcher, so Main is actively driven while the real Room work finishes. `runTest(timeout = 5.seconds)` retains a five-second wall-clock failure bound; there is no virtual `withTimeout` that could expire before Room returns. The helper still returns the matching Reading state.
- Why the race is removed: Room completions now enqueue Main work rather than executing state transformations concurrently on query threads. Every read/copy/assign runs to completion before another scheduled Main continuation runs. All original highlight identity, locator, colour, editor routing, original-row preservation, and dismissal assertions remain.
- Harness follow-through: teardown cancels **and joins** the ViewModel root job inside `runTest` on the same dispatcher, before closing Room or resetting Main. In `rapidColourThenDonePreservesBothFields`, explicitly run queued Colour work up to its existing deferred read gate before invoking Done. This preserves that test's intended Colour-then-Done ordering after removing unconfined eager launch behavior.
- Production assessment: the concurrent state-write interleaving is introduced by the test's unconfined replacement of Main. No production change is needed for this race.

## Account row 47

Test: `Brief3caScreenTest.row47NonemptyAccountPageFilteredToZeroHasClearWhichOnlyChangesLocalFilters`.

- Race found: the test waited for a work title in the body, then assumed the shell toolbar was ready. `AccountWorksListScreen` supplies its Filter button through `ProvidePushedShellChrome`; that composable registers the trailing-content lambda in a `SideEffect`. The test shell's separate `Row` must then recompose to display it. Seeing the loaded body is not an observation of that toolbar publication.
- Fix: after the existing title/request-count checks, wait for exactly one merged semantics node with content description `Filter`, then perform the original click. The wait uses the class's existing 15-second readiness budget.
- Why the race is removed: the click is conditional on the actual control's presence in the shell, after registration and composition. The test still opens the real filter sheet, filters the nonempty fixture to zero, checks the empty-state copy and clipping, clears filters, recovers the original work, and checks exactly one GET and zero POSTs. No local filter or network assertions were removed.

## Work detail rebuild confirmation

Test: `WorkDetailShareTest.rebuildAsksBeforeWritingAndShowsTheImporterFailure`.

- Race found: `RebuildOriginalDialog` initially returns without creating an AlertDialog while `checking` is true. Its `LaunchedEffect` calls `WorkImporter.conversionIsStale`, which reaches `WorkFileStore.originalExists` on real `Dispatchers.IO`. Compose idleness alone does not wait for that IO. The immediate title assertion could query before the dialog was ready. The reported unmerged-tree hint is compatible with the dialog appearing between the failed merged query and the later diagnostic query; it does not justify switching assertions to an unmerged tree.
- Fix: wait for exactly one `Rebuild this work?` node in the **merged** semantics tree, retain the original title assertion, and assert the Rebuild button is enabled before clicking. The readiness wait uses the same five-second budget as this test's existing importer-error wait; no timeout was raised.
- Why the race is removed: the confirmation title is rendered only after the stale-conversion check completes. The test now observes that completion before checking that no successful rebuild occurred and invoking Rebuild. It still requires the importer failure title, the exact missing-original message, no successful rebuild callback, and dismissal through OK. The fake client still rejects any network request.

## Verification and handoff

- `git diff --check`: passed.
- Static inventory: all 12 reader, 23 account, and 2 work-detail test methods are retained; counts of every existing assertion kind are retained. Rebuild gains an enabled-button assertion.
- Reviewed every reader `awaitReading` caller and asynchronous editor operation for the dispatcher change, including the gated Colour-then-Done ordering and cancel/join teardown.
- Confirmed exactly the three requested test files have tracked changes; no production or `TASKS.md` changes. The result Markdown has no trailing whitespace. The branch remains `android/agent-codex-3gv`.
- Claude should run the three focused classes, then the full `:app:testDebugUnitTest` suite under load. No compilation, runtime test pass, or reproduction of the original failures is claimed here; the race analysis is based on the inspected source paths above.
