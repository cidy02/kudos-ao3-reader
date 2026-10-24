# A98 — A97 Android differences

Status: implementation and tests written; awaiting Claude's build, test run and visual verification.
Base: `82626348`, branch `android/agent-codex-a98`. This brief was the first file written.
No Gradle, commits, pushes, branch switches, sign-in, AO3 requests, or TASKS.md changes.
The pre-existing untracked `A98-a97-android-brief.md` is untouched.

Path keys below: **iOS** = `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read only);
**Android** = `android/app/src/main/java/io/github/cidy02/kudos/` in this worktree.

## Item ledger

1. **Current speed pill — real.** iOS `Features/ReaderReadium/ReaderSpeechAuditionHarness.swift:88`
   uses `RatePillStyle` and disables the selected rate; `:198` makes that disabled pill primary ink
   on a neutral quaternary fill. Android `settings/SettingsListeningPage.kt:273` now uses primary ink
   and a neutral glass fill for the current rate, without enabling it. Other rates keep their
   accent and remain selectable. This one component reaches Settings › Listening and the reader's
   speech sheet (`reader/ReaderSpeechSettingsSheet.kt:41` hosts the same Listening content).

2. **Sample Text value — real at normal text size; accessibility already matched.** iOS
   `Features/ReaderReadium/ReaderSpeechAuditionHarness.swift:45` chooses the system `Picker` at
   normal sizes (`:132`, no explicit value tint). At accessibility sizes its custom menu label
   explicitly uses `.tint` (`:155`). The A97 tile confirms primary value/accent caret normally,
   accented value at AX5. Android `settings/SettingsListeningPage.kt:133` now follows that branch.
   `ui/subject/SubjectForm.kt:147` adds an optional value ink override; its choice arrow keeps the
   palette accent (`:221`). Other Listening menus keep their existing accent.

3. **Page jump Last — real.** iOS `Features/Search/SearchPaginationBar.swift:320` resolves the
   page's palette for its tiles; `:477`/`:485` explicitly draws the end buttons in `Color.primary`,
   rather than the app accent. Android `ui/components/KudosPaginationBar.kt:286` and `:292` now
   give both First and Last primary ink. Palette-based nearby tiles and staged confirmation stay
   intact. This follows the actual source rather than making the Last label a subject accent.

4. **Library filters — real menu treatment/palette propagation; literal purple is demo/theme.**
   iOS `Features/Library/LibraryFilterPanel.swift:53` uses an accent-filled Done;
   `:74` uses Pickers for menu values, and `:201` uses the inherited tint for checks.
   `Features/Library/LibrarySectionListView.swift:298` explicitly uses `themeManager.scopePalette`:
   Reading Now has no hardcoded purple identity. Android `library/LibraryFilterPanel.kt:83` now
   uses `SubjectPaletteTheme` so Done, Reset, toggles and checks inherit its supplied/default scope
   palette; `:254` uses the shared choice treatment for menu values instead of grey disclosure
   values. Queue and collection callers pass their actual palettes at
   `library/QueuePageScreen.kt:469` and `library/CollectionDetailScreen.kt:582`.
   No Reading Now hue was invented or forced to the screenshot's purple.

5. **Challenge settings edit — real missing palette; subtitle/hue identity are demo data.**
   iOS `Features/Challenges/ChallengeSettingsEditView.swift:76` hues from `effectiveTitle`,
   defined at `:82` as title unless empty, then slug. Its subtitle at `:177` uses that same
   effective title and the known sign-up count. Read-only Settings (`ChallengeSettingsView.swift:48`),
   Sign-ups (`ChallengeSignUpsView.swift:60`) and Assignments (`ChallengeAssignmentsView.swift:83`)
   use the same title/slug rule. Android's subtitle already matches it at
   `account/AO3ChallengeSettingsEditScreen.kt:145`; it stays unchanged. The edit page now wraps its
   content with `ProvideCollectionPalette` (`:40`). The existing shared helper at
   `account/AO3ChallengeSignUpsScreen.kt:45` now delegates to `SubjectPaletteTheme` (`:50`) so the
   token, shared-control and Material palettes agree throughout all its challenge pages.
   A real title yields the title's hue; an empty title yields the slug's teal. No extra read.

6. **Recovery — real timestamp precision; warning is the demo's state.** iOS
   `Features/Writing/WritingTextEditor.swift:384` uses default `Date.formatted()` for the main
   saved-copy sentence (A97 confirms no seconds); `:385` shows the warning exactly when
   `originalDigest != digest(original)`. Android `writing/WritingTextEditorScreen.kt:328` now
   requests localized SHORT date and SHORT time, preserving the Foundation epoch conversion and
   omitting seconds. `writing/WritingEditorSession.kt:101` already compares the same digests,
   and `writing/WritingTextEditorScreen.kt:287` already renders the exact same warning. Those
   remain unchanged, with a selected-copy predicate regression test. This respects A88's decision
   that the extra paragraph's presence in its demo is not itself a fault.

7. **My Works — real toolbar order; subtitle is the demo's available data.** iOS
   `Features/Authors/AuthorProfileView.swift:336` falls back to the account's display name if the
   scoped count cache has no value; `:349` explicitly describes its totals subtitle and `:354`
   adds words/kudos when stats exist. Android's equivalent is already
   `author/AuthorProfileScreen.kt:1178` (name without a count; count/name without stats;
   totals when available), used at `:732`. Keeping it avoids deleting real information to copy a
   demo fallback. iOS's `:831` orders New Work, filter, select, more. Android
   `author/AuthorProfileScreen.kt:463` now puts New Work first; selection-mode controls are unchanged.

8. **Chapter picker — real glyph silhouette.** iOS
   `Features/Comments/CommentsView.swift:1062` uses SF Symbols `book` (outline). Android's former
   `Outlined.MenuBook` still has a solid page in the A97 tile. The existing shared
   `comments/CommentsScreen.kt:757` icon is now Material `Icons.Outlined.ImportContacts`, a hollow
   open book, used by both the chapter-scope control (`:521`) and chapter rows (`:898`). No custom
   vector or dependency. Confirmed that the chosen icon exists in the installed 1.7.8 AAR.

9. **Preference help — real.** iOS `Features/Account/AO3PreferencesView.swift:288` uses the inline
   navigation title (`:290`), the system semibold title seen in A97. Android
   `account/AO3PreferencesScreen.kt:499` now explicitly sets `FontWeight.SemiBold` on the sheet
   heading. Body text and the existing Done action are unchanged.

## Verification

New tests are in `android/app/src/test/java/io/github/cidy02/kudos/app/BriefA98ContentTest.kt`.
They follow A96's Robolectric/Compose real-content style, including `GetTextLayoutResult` and
native view drawing. All fixtures are local; fake clients fail on unbundled requests and never
use a socket. Ellipsis checks use `isLineEllipsized`.

The revert failures below are **expected assertions from source inspection**, not executed
mutation-test results. Per instruction, no Gradle or test/build command was run.

| Test (line in A98 test file) | Check | Expected failure with its production change reverted |
| --- | --- | --- |
| `currentSpeedHasPrimaryInkNeutralFillAndRemainsDisabledInEveryThemeAndSize` (`:111`) | Primary current-rate text, neutral fill pixels, disabled semantics, other-rate accent, no ellipsis, and changing rate; all four themes at 1x/2x. | Old faint current-rate ink fails exact primary comparison; old neutral fill fails sampled RGB. |
| `samplePickerUsesPrimaryInkNormallyAndAccentAtLargeTextOnBothListeningSurfaces` (`:131`) | Production Settings page and reader sheet share primary normal-size value/current pill; accessibility value stays accent and readable, all themes. | Restoring the unqualified accented Sample Text value fails the 1x ink assertion; reverting the rate fix fails the current-pill assertion. |
| `jumpEndsUsePageInkAndOnlyStageTheChosenPage` (`:157`) | Last/First ink across themes, staging Last sends nothing, confirm selects exactly page 3. | Default Material accent fails the enabled end-button primary-ink assertion. |
| `libraryChoicesInheritTheSuppliedPaletteAndStillApplyLive` (`:174`) | Default scope and explicit teal palette in all themes; menu selection updates sort, Done calls apply. | Grey disclosure value fails the accent assertion; dropping the supplied theme fails explicit teal. |
| `challengeEditUsesTheTitlePaletteOrSlugFallbackAndPreservesKnownCountWithoutExtraReads` (`:196`) | Real edit screen's Save fill pixels for title and empty-title slug fallback, subtitle with known count, opening reads only, no writes; all themes. | Removing the palette wrapper returns Save to app purple/brown and fails expected subject RGB. |
| `recoveryTimestampOmitsSecondsInDifferentLocalesAndKeepsTheCorrectInstant` (`:218`) | US/UK/Japan localized date/time, fixed New York zone, correct Foundation epoch, seconds don't affect label; restores globals. | Default MEDIUM time includes seconds and fails both the expected SHORT text and seconds-invariance assertion. |
| `recoveryWarningFollowsTheSelectedCopiesOriginalDigestRatherThanItsEditedText` (`:234`) | Select a copy from an older form → warning; select edited copy begun from same form → no warning, text still present. | Existing behavior needed no change, so A98 revert should still pass. Removing the digest predicate/warning or comparing edited copy text instead causes one of these assertions to fail. |
| `myWorksKeepsRealTotalsAndOrdersNewFilterSelectMore` (`:256`) | Fixture-backed own Works toolbar positions New/filter/select/more; totals and both missing-count/missing-stats fallbacks. | Old filter-before-plus order fails the left-to-right bounds assertion. Subtitle assertions intentionally pass on baseline. |
| `chapterRowsUseTheHollowOpenBookAndRemainSelectable` (`:295`) | Actual shared icon identity plus selecting a chapter row. | Old MenuBook identity fails the icon assertion. |
| `preferenceHelpTitleIsSemiboldWhileBodyRemainsRegularInEveryTheme` (`:305`) | Real help title's weight/primary ink and unchanged body weight in all themes. | Default regular `titleLarge` fails semibold comparison. |

Two existing assertions were updated to reflect these fixes, rather than leaving known failures:
`app/Brief3hcContentTest.kt:350` expects the hollow Material book; and
`account/AO3ChallengeSettingsEditScreenTest.kt:82` compares Save to its actual title-derived
palette instead of assuming it is red. Paths here are under `android/app/src/test/java/io/github/cidy02/kudos/`.

Checked here: `git diff --check` passes; source/caller review; installed Material icon availability.
The original A97 reader-speech and chapter-picker tiles were inspected to resolve the normal/AX
value-color distinction and the misleading `Outlined.MenuBook` silhouette. No post-change UI
was rendered, and no build/test success is claimed.

Claude next: run the A98 class and the affected 3hc/challenge/listening/library suites plus the
normal gate, then re-shoot the nine surfaces in Dark/Light/Sepia/OLED/largest text. In particular,
check the sheet-window filter checkmark tint and the new book silhouette on a device.
Material date fields, card dates, iPhone faults, and settled DECISIONS/A88 items were left alone.
