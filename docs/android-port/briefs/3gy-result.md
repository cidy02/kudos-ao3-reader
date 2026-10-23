# Brief 3gy result

Status: all sixteen holds removed; source review complete, awaiting Claude's runs.

Scope: this worktree, branch `android/agent-codex2-3gy`. No Gradle, commits,
pushes, branch changes, sign-in, or AO3 requests. `TASKS.md` is unchanged.
The pre-existing untracked `3gy-held-tests.md` is preserved.

## Verification

Builds and test execution are reserved for Claude. No test is claimed green.
The regression/mutation outcomes below are source-based expectations, not
executed results. Revert the specified **3gx behavioral hunk**, retaining the
new content extraction and test access; reverting an entire file would remove
the test seam and cause a compilation failure instead of exercising the rule.

Completed static checks: `git diff --check` passed. An inventory compared all
eight edited classes with HEAD: their test method names/order are unchanged,
exactly sixteen held annotations were removed, and no `@Ignore("3gx` remains
under `android/app/src/test`. `TASKS.md` has no diff. The branch is unchanged.

## Per-test findings

All sixteen failures are test setup/selector/window problems based on source
inspection and Claude's emulator evidence. No product behavior has been changed
to accommodate an assertion. Production edits extract shared content and add a
test tag to the existing challenge choice list. The app still presents its
existing dialogs and sheets.

Paths below are relative to `android/app/src/test/java/io/github/cidy02/kudos/`.

| # | Test | Finding and correction | Expected failure with the relevant app behavior reverted |
| --- | --- | --- | --- |
| 1 | `writing/WritingSeriesScreenTest.reorderRowsHaveHandlesAndDraftBesideTheTitle` | **Test:** `SubjectStateBadge` clears Text semantics and speaks `Draft` as a content description. Query that description in the unmerged tree. Retain three handle checks and horizontal placement; also check vertical overlap with the title. | Remove the 3gx handles or return Draft below the title: handle count or title-row geometry fails. |
| 2 | `app/Brief3gxParityTest.singleFandomKeepsUnknownCountsUnknownAndShowsRealDownloadCounts` | **Test:** `FandomLibraryIndex` explicitly takes lowercased keys; `Known` never matched. Supply `known`, inspect the visible count in the unmerged tree, and also require `123 downloaded`. | Restore the 99 cap: `123` is absent. Restore invented zero counts: the no-zero assertion fails. Remove works speech: `50 works` is absent. |
| 3 | `app/Brief3gxParityTest.fandomAliasesWrapAndLargeTextMovesTheFiguresBelowTheTitle` | **Test:** the clickable family header merges its title, aliases and count. Layout/geometry queries now target individual unmerged Text nodes, rather than the merged header's first layout or shared bounds. Original wrap, no-ellipsis, all-alias and strict below-title assertions remain. | Restore `.take(2)`, one-line aliases, or side-by-side large-text count: third alias, wrapping, or strict count-below-title check fails. |
| 4 | `app/Brief3gxParityTest.saveSearchNameRemainsLabelledAndLongSummariesScroll` | **Test/window:** extract `SaveSearchContent` from the modal and test that exact production body in the activity at 2×. Require the fiftieth chip to start offscreen, then become displayed by scrolling; retain the nonempty Name field's spoken label. | Remove 3gx scroll modifier: scrolling has no scroll parent/reachable last chip. Remove Name semantics: field lookup fails. |
| 5 | `app/Brief3gxParityTest.formattingCanApplyTwoTilesWithoutClosing` | **Test:** tiles have visible `Bold`/`Italic` text, with decorative icons, not icon descriptions. Scroll to and click those labelled controls, retaining both markup checks and both non-dismissal checks. | Restore `onDismiss()` after applying a tile: the first dismissal assertion fails before the second tile. |
| 6 | `browse/FandomFilterSheetParityTest.showTagsStaysVisibleAtLargestTextAndAppliesTheChoices` | **Test:** the label is not the switch. Scroll to the `Favourited only` control, require off→on, then reach the last grouping switch. With no favourites the count really is zero. Require `Show 0 tags` still displayed and apply it; retain applied-draft assertion. The existing dismiss test now also toggles the real switch. | Restore the pre-3gx unpinned/non-scrolling layout: reaching the last control or pinned-button visibility fails at 2×. Remove draft application: applied flag fails. |
| 7 | `browse/FandomResultsParityTest.pagingKeepsUsableRowsClearsSelectionAndKeepsThemAfterFailure` | **Test:** request count increments before background parsing publishes rows. Wait for the loaded row. Prove selection was set, hold page two, check old row/cleared selection/disabled pager, then wait for the actual refusal text and check old row/enabled pager. | Restore replacing Loaded with Loading: old row vanishes while held; remove selection reset: `Select works` fails; discard prior page on failure: final row fails. |
| 8 | `browse/FandomResultsParityTest.aFailedFandomIndexRefreshKeepsTheExistingRows` | **Test fixture:** use AO3-style double-quoted classes accepted by the deliberately lightweight fandom parser. Pull within the lazy list; hold the refresh and assert rows both during it and after the refusal completes. | Restore unconditional Loading/Error on refresh: retained-row assertion fails during/after the refused request. |
| 9 | `browse/FandomResultsParityTest.aGenericTagsFilterOffersTheFandomPicker` | **Test:** wait for the loaded row and scroll the tagged lazy filter form to `Fandoms`, rather than calling `performScrollTo` on an item not composed yet. Click it and require the picker’s own empty-search instructions. All reads use the in-process fake; no autocomplete request is issued. | Restore `showFandomPicker = false` for generic tags: the lazy form cannot find Fandoms, and the picker cannot open. |
| 10 | `account/AO3ChallengeSettingsEditScreenTest.limitValidationErrorPrecedesTheLimitsPanel` | **Test:** 20 is beyond the choice list's composed viewport. Tag that existing lazy list and scroll to 20 before choosing. Let validation's own scroll settle, reach the error, and compare unmerged error/Requests geometry. Retain no-POST assertion. | Restore field errors below Requests: geometry reverses (or Requests is no longer in the error's viewport); invalid form must still send nothing. |
| 11 | `account/PreferenceHelpSelection3gxTest.helpBodyAndFooterOfferCopyAfterSelection` | **Robolectric graphics/window:** extract the exact `PreferenceHelpContent` used by the modal and host it in the activity. Use legacy graphics to avoid native `Surface.destroy`; still perform real long-press selection separately on body and footer and require each selection's Copy callback. No substitute marker assertion. | Remove either 3gx `SelectionContainer`: the corresponding long-press offers no Copy callback. |
| 12 | `library/LibraryForms3gxTest.collectionPickerShowsNewestCreatedFirst` | **Robolectric dialog:** extract `AddToCollectionContent`, including its actual Room membership load and sorted checklist, from AlertDialog. Pass a stable collection list, wait for an enabled checklist row (membership load finished), then compare Zulu/Alpha bounds. | Restore alphabetical ordering: Alpha is above Zulu and strict order assertion fails. |
| 13 | `library/TagSheetParityTest.mergeChoicesSpeakTheirScopeAndConfirmationRepeatsIt` | **Robolectric dialog:** `QueueTagEditContent` owns the same editor, rename lookup, controls and merge confirmation; its presenter is AlertDialog in the app and an inline frame in tests. Click the real spoken target and require independent literal scope copy inside the confirmation frame; also check zero-work copy independently. | Remove target scope speech: target lookup fails. Restore generic undo-only confirmation (or wrong scope helper): independent scope-copy assertion fails. |
| 14 | `library/TagSheetParityTest.aConflictingRenameCannotBeSavedAndCopyNeedsAnotherQueue` | **Robolectric dialog:** retain real manager/menu checks for both scoped counts and disabled Copy. Then host the shared editor inline to test the same Name field, lookup, conflict warning, and disabled Save before/after the lookup. | Restore Copy always enabled, remove count speech, or allow exact-name conflict renames: the corresponding assertion fails. |
| 15 | `library/TagSheetParityTest.editTagPutsMergeBeforeTheRemoveSection` | **Robolectric dialog:** host the exact editor inline. Preserve Name→Merge→Remove-section→Remove-action bounds checks and click Remove; use the same extracted small `QueueTagRemovalDialog` that the manager invokes to verify its scope confirmation. | Restore Remove before Merge or omit the Remove section: ordering/node lookup fails. Change zero-work removal title: scope-title assertion fails. |
| 16 | `library/TagSheetParityTest.aQueuePagesSelectedWorksOpenWorkTagsInsteadOfQueueVocabulary` | **Test:** `Tag` also exists behind the opened dialog. Scope the title query to a dialog ancestor. Retain selecting both actual works, adding Comfort, checking both work memberships and checking the queue vocabulary remains empty. | Restore QueueTagSheet for selected works: work-sheet title/footnote is absent and Comfort does not attach to the works; queue vocabulary assertion would also fail. |

## Shared-content boundaries

- `QueueTags.kt`: the production `QueueTagEditDialog` still supplies AlertDialog
  for both the editor and merge confirmation. Tests supply inline frames to the
  same stateful `QueueTagEditContent`; validation, button enablement, merge
  targets and copy are not reimplemented in tests. The small removal confirmation
  is extracted unchanged and shared with `QueueTagManager`.
- `WorkMembershipDialogs.kt`: the checklist, creation action, membership load,
  toggles and sort all live in `AddToCollectionContent`, used by the existing
  AlertDialog and test.
- `SaveSearchSheet.kt` and `AO3PreferencesScreen.kt`: modal wrappers delegate to
  the exact scrolling/selection content that the activity-hosted tests exercise.
  These tests intentionally do not certify modal window sizing or gestures.
- `FandomResultsParityTest` now removes its composition before closing Room,
  preventing background flow collection from outliving the database.

## Claude handoff

Run the eight edited test classes, starting with `TagSheetParityTest`,
`LibraryForms3gxTest`, and `PreferenceHelpSelection3gxTest` in isolation. Then run
the lane's normal build/test gate and behavioral mutations in the table. No
Gradle or runtime/mutation tests were run here. Native modal positioning,
selection handles and the extracted wrappers still need the emulator check;
this pass does not claim visual verification.
