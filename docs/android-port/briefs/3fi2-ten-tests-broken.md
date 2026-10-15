# Brief 3fi-2: your 3fi breaks ten existing tests

Same rules as brief 3fi (`docs/android-port/briefs/3fi-a56-library-fixes.md`). Revise your 3fi
work **in place** in this worktree (`android/agent-codex-3fi`, uncommitted). Claude already
fixed one compile error in `WorkIdentityIndexTest.kt` (`SavedWork` needs an `author`; copied
into this worktree). Update `docs/android-port/briefs/3fi-result.md`.

Claude ran the gate on 3fi: 2,768 tests, **ten fail**. Before 3fi all of them passed.

| Test | Line | Assertion that now fails |
|---|---|---|
| `DemoLibraryTest.seedPopulatesExpectedWorksQueuesCollectionsAndIsIdempotent` | 354 | `assertTrue(sodiumLights.hasEpub)` |
| `DemoLibraryTest.searchFixtureHasSeparateChaptersAndOriginalSearchTermsEvenOnAnExistingDemo` | 231 | `assertEquals(9, hrefs.size)` (was 1) |
| `DemoLibraryTest.demoBookmarkPairsWithTheMatureLibraryWorkAndBlursUntilRevealed` | 200 | `assertTrue(work.hasEpub && work.isSaved && work.hasAo3WorkId)` |
| `DemoLibraryTest.installedDemoHistoryDatesUpgradeOnlyUntouchedFixturesAndRespectUndo` | 462 | `assertTrue(ReadingAbandonment.isAbandoned(upgraded, fixedNow))` |
| `DemoLibraryTest.demoLibraryShelfCountsMatchIos` | 512 | `assertEquals(3, state.continueReading.size)` (was 0) |
| `DemoLibraryTest.demoHistoryHasThreeTimeBucketsAbandonedAndReadNotFinishedWithoutAddingRows` | 485 | `assertTrue(state.any { it.title == "Abandoned" })` |
| `WorkLifecycleRepositoryTest.keepOfflineQueueDrivesDownloadedQueryAndClearsHold` | 853 | `assertTrue(kept.isDownloaded)` |
| `WorkLifecycleRepositoryTest.collectionNilDoesNotKeepButOnDoesAndClearsHold` | 874 | `assertNull(kept.freedAt)` (was 2026-06-26T12:00:00Z) |
| `LibraryHistoryScreenTest.tallyFollowsEveryGroupingAndZerosDisappear` | — | expected one "DOCTOR WHO" node, found three |
| `LocalDataFootprintTest.demoSelectionReallyGivesEveryMeasuredCategoryANonzeroValueAndReseedingPreservesIt` | — | an assertion after `DemoLibrary.seed` |

The pattern (`hasEpub`, `isDownloaded` false; a downloaded EPUB's search hrefs 1 instead of 9;
`freedAt` set) suggests the new queue normalization or acquisition path changes a work's
download state or files where it should not, possibly the demo seed going through the new
identity/acquisition path and matching works together. Find the cause of each. **Fix the
code**, not the test, unless the assertion encoded behaviour iOS does not have; for any test
you change, quote the iOS behaviour that justifies it. A reconciliation must never clear a
download flag or a file for a work whose file is present, and must never free a held copy
the tests keep. Say, for each of the ten, what caused it and what you changed.
