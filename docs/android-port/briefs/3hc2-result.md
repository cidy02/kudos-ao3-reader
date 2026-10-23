# Brief 3hc2 result

Implementation updated; **runtime verification blocked by the execution sandbox**.
This document was created before code edits, then updated with the findings below.
Work remains uncommitted on `android/agent-codex-3hc2`, HEAD `6c002b44533e6f34360e05394e0a8b0f11b0fd66`.
The lane's 3hc work is retained except for the corrections described here.

No commits, pushes, branch switches, sign-in, AO3 requests, TASKS.md edits, full
suite, or lint. The existing ActionParityFormsTest and Brief3caScreenTest were not
edited. Card dates remain withdrawn under Q28; SensitiveWorkRow.kt is unchanged.

## Changes by item

Android production paths below are relative to
`android/app/src/main/java/io/github/cidy02/kudos/`.

1. **Add Works bylines** — `library/AddLibraryWorksSheet.kt:189`: retains
   `includesBy = true`, passes `compact = !isAccessibilityFontScale()`, and removes
   the tint override. `works/detail/WorkDetailIdentity.kt:129` is now identical to
   HEAD: both new `tinted` parameters and their branches are gone. Registered
   linked authors use the scope accent; unlinked authors use secondary ink.
   The test uses `displayName` and `kind: registered`, checks linked tint, 12 sp
   regular text at normal scale, 15.5 sp at accessibility scale, and author routing.
   The iPhone demo's grey names are explained by its missing identities; Android's
   demo has identities. No demo-data changes.
   Reference: iOS `Features/Library/AddLibraryWorksSheet.swift:145` and
   `UIComponents/AO3AuthorNavigation.swift:196`, `:219`.

2. **3hc test repairs** —
   `android/app/src/test/java/io/github/cidy02/kudos/app/Brief3hcContentTest.kt:119`:
   uses a <22 dp gap threshold, the correct registered-author fixture, complete
   chapter display names, and drawn separator pixels rather than the pre-padding
   tag's left bound. The collection-editor failure not explained by A94 was its
   assertion of an **Auto** swatch: `ui/subject/SubjectForm.kt:248` only renders the
   five presets and Custom colour. The test now checks existing controls; it does
   not add an unrelated Auto control. Added guards for lazy composition and the
   shared queue-name field. All eight content tests are described below.

3. **Collection reorder** — `library/CollectionReorderSheet.kt:165`, `:168`, `:198`,
   `:254`: restores keyed `itemsIndexed`, uses `writingSuggestionPanel(first,last)`
   for each segment, and puts each separator inside its segment. The drag layer
   wraps the segment's fill and separator. Bounds disposal and accessibility moves
   remain keyed to each work. Restores the section spacing without adding gaps
   between works: label top 16 dp, bottom 12 dp, footnote top 16 dp.
   Reference pattern: `writing/WritingSeriesScreen.kt:126`, `:170`.

4. **Collection details ground** — `library/CollectionEditorSheet.kt:218`, `:274`,
   `:308`: provides `LocalSettingsFormGround` only when editing in Sepia, Dark, or
   OLED, and uses `settingsPanelGround()` for Colour and Behaviour. These use the
   existing `cardSurface` tokens (cream / #222228 / #1C1C1E). Light remains glass;
   new collections remain glass in every theme. New collection's existing grouped
   Name, Description, and swatches from 3hc are retained at `:227`.
   Reference: iOS `Features/Library/Collections.swift:186` and the existing
   `reader/ReaderSpeechSettingsSheet.kt:54` form-ground mechanism.

5. **New queue separator** — `library/QueueEditorSheet.kt:311`: inset is 48 dp,
   aligned with the label after Material's 24 dp radio, 13 dp padding, and 11 dp
   gap. The 3hc seed-row spacing and selection behaviour are retained.

6. **Chapter picker** — `comments/CommentsScreen.kt:850`: the unselected All
   Comments total now uses `palette.accent` at 0.6 alpha; selected uses full alpha.
   3hc's open book (`:757`) and palette accent on all labels/icons remain intact.
   Pre-existing selected-row weight/checkmark ordering was outside this correction.

7. **Card dates** — withdrawn under owner Q28. No code or test restored.

8. **Queue input gate** — `settings/SettingsChrome.kt:180`: replaces the shared
   field's clickable focus wrapper with a tap handler, leaving focus and SetText
   on the BasicTextField's own semantics node. This keeps the wide tap-to-focus
   area without a parent that merges the field's semantics. The original gate
   test is unchanged. Important scope correction: it calls
   `library/WorkMembershipDialogs.kt:176` →
   `works/detail/WorkDetailForms.kt:223` → `SubjectTextFieldRow`, **not**
   QueueEditorSheet. The 3hc QueueEditorSheet diff does not modify this path.
   The wrapper is a code-based diagnosis; runtime confirmation is still required.

9. **Account filtered-empty timeout investigation** —
   `account/AccountWorksListScreen.kt:180`, `:368`, `:509`: filters remain local
   state, the empty-state action clears that state, and the filter sheet applies
   back to it. None of that code changed in 3hc or 3hc2. The bookmark rows at
   `:872` reach PairedWorkRow/SensitiveWorkRow and the shared byline with default
   arguments; 3hc's new `tinted = true` default was behaviourally equivalent there.
   The finished shared byline file is byte-for-byte HEAD, confirmed by
   `git diff --exit-code HEAD -- .../WorkDetailIdentity.kt`.
   **The reported timeout's cause is unresolved**: Gradle cannot start here, so
   neither a with/without-byline comparison nor a passing rerun is claimed.
   No speculative account behaviour or test changes were made.

10. **Series Draft chip retained** — `writing/WritingSeriesScreen.kt:161`: 3hc's
    mixed-case neutral Draft chip remains in reorder/remove modes only.

## Tests and reverted-change behaviour

Test paths in this table are relative to
`android/app/src/test/java/io/github/cidy02/kudos/`.
**None of these runtime outcomes was observed in this session.** The failure
conditions below are source-based expectations for Claude's red/green runs, not
claims of successful mutation testing. Gradle was blocked before compilation.
Revert the named behaviour while keeping the extracted content entry points so
that a compile failure is not mistaken for a meaningful red test.

| Test (`path:line`) | Finished-code assertions | Expected result with its change reverted |
| --- | --- | --- |
| `app/Brief3hcContentTest.kt:119` — `collectionReorderRowsShareOneCardWithSeparators` | Three lazy segments, two separators, shared list ancestry, and <22 dp adjacent-row gaps. | Restore 3hc's single eager panel: segment-count assertion fails. Restore pre-3hc separate cards: separators/segment tags are absent and the old content bounds have ~28 dp gaps. |
| `app/Brief3hcContentTest.kt:157` — `collectionEditorGroupsNameDescriptionAndSwatchesInOneCardAndWrapsColourOnDetails` | Name/Description/preset/custom controls share the creation card, details swatches share the Colour card; pixels check Colour and Behaviour in all four themes, plus new-collection glass in Sepia. | Remove 3hc's grouping: panel ancestry/separator assertions fail. Restore 3hc's glass details cards only: Sepia/Dark/OLED card-surface pixel assertions fail. |
| `app/Brief3hcContentTest.kt:219` — `queueSeedRowsHaveHorizontalGapAndIndentedSeparator` | ≥10 dp radio/label gap, separator between rows, ground at x=45 dp and separator at x=51 dp, seed-selection callback. | Change 48 back to 43 dp: x=45 is incorrectly a separator pixel. Remove 3hc's separator: missing node. Remove its horizontal gap: radio/label gap assertion fails. |
| `app/Brief3hcContentTest.kt:259` — `queueNameFieldKeepsTextInputAndFocusOnTheSameSemanticsNode` | Enters Another queue through the merged-tree SetText node and checks state. | Restore the clickable parent in SubjectTextFieldRow: expected to reproduce merged SetText/focus-node input failure. Runtime confirmation pending. |
| `app/Brief3hcContentTest.kt:271` — `collectionReorderComposesOnlyVisibleRowsAndCanReachTheEnd` | A 200-work list does not compose all handles on open, then scrolls to/display its last row. | Restore 3hc's eager Column: all 200 handles compose and the first assertion fails. The pre-3hc lazy version can pass this guard; the previous test detects its separate cards. |
| `app/Brief3hcContentTest.kt:283` — `addLibraryWorksPrefixesByAndTintsLinkedAuthorsInCompactCaption` | Two by prefixes; real registered linked identity in scope accent; unlinked secondary ink; normal-scale 12 sp/regular weight; author tap dismisses/routes; accessibility scale exits compact sizing. | Remove includesBy: prefixes absent. Restore compact=false: size/weight assertions fail. Restore 3hc's tinted=false together with its parameter: linked accent assertion fails. |
| `app/Brief3hcContentTest.kt:349` — `chapterPickerUsesOpenBookIconAndPaletteAccentOnAllRowLabels` | MenuBook icon, custom-palette accent on every chapter/All Comments label, full display names, pale-accent unselected total and full-accent selected total. | Restore closed book: icon check fails. Restore old label colours: custom-palette colour checks fail. Restore grey unselected total: its colour check fails. |
| `app/Brief3hcContentTest.kt:391` — `seriesDraftBadgeRendersMixedCaseDraftInReorderAndRemoveModes` | Displays Draft and no DRAFT in reorder and remove modes. | Restore SubjectStateBadge: visible text becomes DRAFT and the mixed-case lookup fails. |
| `library/ActionParityFormsTest.kt:76` — `queuePickerTogglesAllMembersAndCreatesWithoutClosing` (unchanged) | Toggles all selected works' queue memberships, enters a name, creates a queue, and keeps the picker open. | Restore the shared field's clickable wrapper: expected original text-entry failure. Runtime confirmation pending; not attributed to QueueEditorSheet. |
| `account/Brief3caScreenTest.kt:456` — `row47NonemptyAccountPageFilteredToZeroHasClearWhichOnlyChangesLocalFilters` (unchanged) | Filters loaded bookmarks to zero, clears local filters, restores works without extra GET/POST. | No account fix was made. Shared-byline file now equals base; the reported timeout and with/without comparison still need execution. |

## Verification evidence and handoff

- Initial allowed Gradle invocation stopped at a denied home-cache lock write.
- Copied the existing Gradle cache under `/tmp` and retried the allowed **three
  classes only**, offline, in this worktree. Both baseline and finished-source
  attempts stopped before compilation:

  ```text
  Could not create service of type FileLockContentionHandler
  java.net.SocketException: Operation not permitted
  ```

  Logs: `/tmp/3hc2-baseline.log`, `/tmp/3hc2-final.log`.
  No test passed/failed counts are available. Reverted-source runs were not
  attempted after this repeatable infrastructure failure.
- Kotlin compiler PSI syntax parsing: **8 changed Kotlin files, 0 syntax errors**.
  This is syntax validation, not a type check, build, test, or visual review.
- `git diff --check`: passed. Byline, both existing gate-test files, TASKS.md,
  and the withdrawn date implementation have no diff from HEAD.
- **Next step:** run the permitted command below in a session that can create
  Gradle's local socket, execute the per-behaviour reversions above, and investigate
  row47's actual timeout location if it persists. Claude owns broader tests/lint;
  device screenshots and human visual review remain pending.

  ```sh
  cd /Users/cidy02/kudos-agent-codex2/android
  ./gradlew :app:testDebugUnitTest \
    --tests 'io.github.cidy02.kudos.app.Brief3hcContentTest' \
    --tests 'io.github.cidy02.kudos.library.ActionParityFormsTest' \
    --tests 'io.github.cidy02.kudos.account.Brief3caScreenTest'
  ```
