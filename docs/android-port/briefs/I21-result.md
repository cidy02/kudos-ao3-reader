# I21 / A102 result — iPhone parity, batches 1 and 2

Branch: `claude/parity-i21`, based on `1e5d3d44`; task: T-456.
Implementation is ready for Claude-Code's deferred build/test/screenshot gates.
**Commit blocked:** explicit-path `git add -- …` failed with `Operation not
permitted` creating
`/Users/cidy02/AO3_App_OpenSource/.git/worktrees/kudos-agent-ios4/index.lock`.
This session's filesystem policy only permits writes inside the worktree and
temporary directories. Git metadata is outside those roots; elevated access is
unavailable. Nothing was staged or committed, so there is no commit SHA and no
push. Claude-Code must commit these changes on this branch with the required
`Co-Authored-By: Codex <noreply@openai.com>` trailer.
No builds, test execution, lint gates, simulator operations, sign-in, or AO3
requests were performed. `git diff --check` passes. This is not visual approval.

Source paths below are relative to `kudos-ao3-reader/` unless they begin with
`KudosTests/` or `docs/`.

## 1. Scope sheets choose the app accent

Moved and renamed `LibrarySectionFilterAccent` to `ScopeSurfaceAccent` in
`UIComponents/AccentInk.swift:71`. Its behavior is unchanged: install
`accentTint(themeManager.effectiveTint, on: themeManager.appTheme)` inside the
presentation, giving controls app ink and exact app fill instead of the inherited
work/queue hue. Definition and uses remain iOS-guarded.

Applied to:

| Scope surface | Presentation / modifier |
|---|---|
| Work Details: Add to Collection | `Features/WorkDetail/WorkDetailView.swift:215` |
| Work Details: Add to Queue | `Features/WorkDetail/WorkDetailView.swift:223` |
| Work Details: series preservation prompt | `Features/WorkDetail/WorkDetailView.swift:243` |
| Bookmark on AO3 / Edit Bookmark on AO3 | `Features/WorkDetail/AO3WorkActionsModel.swift:168` |
| Queue page: Add Works | `Features/Library/ReadingQueueBrowser.swift:325` |
| Bulk Tag, including the queue page's selection | `UIComponents/WorkBulkTagSheet.swift:72` |

Updated the existing Home and Library section presentations to the new name at
`Features/Home/HomeSectionListView.swift:217` and
`Features/Library/LibrarySectionListView.swift:249`; removed the old definition
from the top of `Features/Library/LibraryFilterPanel.swift`. The third existing
use was the T-446 test, `KudosTests/AccentInkTests.swift:83`.

Test: adapted T-446's
`sectionFiltersChooseAppAccentOverAnInheritedHeroAccent`
(`KudosTests/AccentInkTests.swift:65`) to the generalized modifier and warmed the
renderer first. It checks both exact fill and readable ink under a purple
presenter, with two user accents and all four themes. By reading: emptying the
modifier leaves both environment roles purple, failing the app-role assertions.
No mutation was executed. It tests the shared modifier, not every sheet's native
presentation; call-site wiring was checked by reading.

Left out: My Copy (`Features/WorkDetail/WorkDetailView.swift:431`) and its
nested download-date editor (`:447`) keep their existing work palette. The
series prompt's noninteractive loading fallback is unchanged. New Queue, New
Collection and other subject-coloured editors were not recoloured.

Extra reach: `WorkBulkTagSheet` chooses the app accent for every caller, including
`UIComponents/WorkBulkActionBar.swift:126` and
`UIComponents/ScopedRemovalBulkActionBar.swift:128`, so the same scope form cannot
inherit a different hero elsewhere. Those caller files were not edited. The
bookmark host modifier is shared with the macOS reader, but its new accent is
iOS-guarded; the only iOS host is Work Details.

## 2. Selected pills use exact tint and a label for that fill

Changed both the selected fill and its label calculation in
`UIComponents/SubjectSurface.swift:1130` and `:1161` from
`palette?.accent ?? fill` to `palette?.tint ?? fill`.
`ThemeManager.label(on:)` still chooses black/white from the actual fill. The
unselected, tinted, neutral and dashed chip styles are unchanged.

Test: `selectedPillsRenderTheExactTintAndItsContrastingLabel`
(`KudosTests/AccentInkTests.swift:103`) renders the real `SubjectChip`, checking
an interior fill pixel and the presence of contrasting glyph pixels.
It covers all themes, default red and a pale custom accent, palette and
no-palette paths, normal text and AX5. By reading: reverting the fill uses the
palette's derived colour instead of the expected exact tint; reverting only the
label leaves black glyphs on the exact dark-red fill, failing the lighter-ink
assertion. No test or mutation was run.

Extra reach, through the shared component (no caller files edited):

| Additional selected-pill caller | Source |
|---|---|
| Author Works/Series/Bookmarks scopes | `Features/Authors/WorksScopeAndSort.swift:33` |
| Author's named fandom selections, alongside All | `Features/Authors/AuthorProfileContentSections.swift:203` |
| Library completion filters | `Features/Library/LibraryCompletionPills.swift:22` |
| Favorite-author status and tag filters | `Features/Library/FavoriteAuthorFilterRail.swift:29`, `:66` |
| Queue organizer scopes | `Features/Library/ReadingQueueOrganizer.swift:200` |
| Home section scopes | `Features/Home/HomeSectionListView.swift:367` |
| Library dashboard scopes | `Features/Library/LibraryView.swift:646` |
| Fandom-family sort | `Features/Search/FandomFamilyRows.swift:250` |
| Subscriptions scopes | `Features/Bookmarks/AO3SubscriptionsWorksBrowser.swift:452` |
| Named subscriptions scopes | `Features/Bookmarks/AO3NamedSubscriptionsList.swift:18` |
| Bookmarks scopes | `Features/Bookmarks/AO3BookmarksWorksBrowser.swift:348` |
| History scopes | `Features/Bookmarks/AO3HistoryWorksBrowser.swift:213` |
| Marked for Later scopes | `Features/Bookmarks/AO3MarkedForLaterWorksBrowser.swift:449` |
| Collection item tabs | `Features/Account/AO3CollectionItemsView.swift:276` |
| Collections selected tab | `Features/Account/AO3CollectionsList.swift:325` |
| Inbox scopes | `Features/Account/AccountInboxScreen.swift:143` |
| Comments chapter scope | `Features/Comments/CommentsView.swift:631` |

Callers without a palette already used the environment's exact fill and retain
that behavior. No additional chip variants or colour policies were introduced.

## 3. Sepia filter header shares the form's ground

`Features/Search/AO3FilterPanel.swift:146` now applies
`WorksFilterSheetGround` (defined at `:745`) to the containing VStack, above the
Form-only themed background. In Sepia it paints `cardBackdrop` behind the match
count and safe areas, and explicitly paints/shows the iOS navigation-bar ground
with the same token. Other themes pass through untouched.

The band was outside the themed Form; there was no pinned-header system-colour
literal to replace. The navigation toolbar and count line had no Sepia ground.

Test: `worksFilterHeaderGroundIsSepiaAndOtherThemesKeepTheirGround`
(`KudosTests/AccentInkTests.swift:140`) renders the real ground modifier over a
sentinel colour. It requires Sepia's base in Sepia and the sentinel in the other
three themes. By reading: emptying the modifier leaves the sentinel visible in
Sepia, failing its pixel assertion. No mutation was run.

Left out: an automated claim about native UINavigationBar/Form compositing.
ImageRenderer's isolated ground test does not establish the actual toolbar
appearance, or AX5 title/count layout. Claude-Code must check the full sheet.
Extra reach: all AO3FilterPanel hosts receive this Sepia-only correction,
including Search/Browse panels without the refine count and the author works
sort-and-filter sheet; no host call sites were edited.

## 4. Disabled bug-report action dims text and icon

`Features/Support/BugReportView.swift:65` applies the local
`BugReportContinueLabelStyle` (`:196`). It reads `isEnabled` from the button's
existing `.disabled(trimmedSummary.isEmpty)` environment. Both roles use secondary
ink while disabled; enabled labels keep primary text and a tinted ladybug. URL
construction, opening behavior and the VoiceOver-disabled Button are unchanged.

Tracing found no app-level foreground override in this row or its presenters:
`appThemedRows` sets row backgrounds and `appThemedScroll` sets scroll ground.
The remaining native grouped-Form automatic-label path does not explicitly
supply disabled ink. That runtime diagnosis is plausible from the supplied
screenshots and code, not empirically confirmed here. The fix makes the label's
disabled roles explicit at that path. No existing shared row style needed changing.

Test: `bugReportLabelDimsBothRolesOnlyWhenDisabled`
(`KudosTests/AccentInkTests.swift:159`) substitutes solid shapes for title/icon,
renders the real label style, and samples both roles against independently
rendered secondary/primary/accent-ink swatches, enabled and disabled in all themes.
By reading: removing the disabled secondary branches restores primary/tint pixels
and fails the disabled expectations. No mutation was run.

Left out: full Form/Button rendering and keyboard/whitespace-entry interaction.
The test checks the style, not its production attachment; removing only that
attachment would not fail it. There are no other production users of this style.

## 5. Challenge bottom actions use the native scroll edge

Replaced the five bottom overlays with `safeAreaBar(edge: .bottom, spacing: 0)`:

| Page | Placement | Bar content |
|---|---|---|
| Assignments | `Features/Challenges/ChallengeAssignmentsView.swift:110` | `:693` |
| Your Sign-up | `Features/Challenges/ChallengeSignUpView.swift:122` | `:493` |
| Sign-ups | `Features/Challenges/ChallengeSignUpsView.swift:124` | `:358` |
| Prompts | `Features/Challenges/PromptMemeView.swift:107` | `:188` |
| Challenge settings | `Features/Challenges/ChallengeSettingsEditView.swift:132` | `:588` |

Removed their `bottomBarHeight` state, synthetic last list rows and full-height
hand-made gradient backgrounds. The controls keep 16pt horizontal padding and
12pt vertical padding; the native bar now reserves their intrinsic height and
safe area and supplies the scroll-edge effect. All actions, visibility conditions,
disabled states and label accessibility remain intact. There were already
background gradients, but they faded across the whole button region, allowing
list text to show through them.

Local SDK interfaces confirm availability from iOS 26/macOS 26. Both deployment
targets permit the API, so no availability fallback or new shared wrapper is
needed. The same shared views use it on macOS; that also requires Claude-Code's
later build/smoke gate.

Test: no meaningful isolated ImageRenderer test for a system scroll-edge effect
on a live List. A test asserting that a closure contains a button would not cover
the reported overlap. Manual gate: all five bars at AX5, all themes, scrolled to
the final row and with rows moving beneath the buttons. Also check the empty
conditional bars in signed-out/loading states and macOS behavior.

Left out: I10's `Features/Account/AO3CollectionsFilterPanel.swift:175` Reset
background. It is a private, theme-ground treatment for a transparent bordered
button; it is not a shared bar-placement helper. The native API removes the need
to copy or generalize that custom gradient. No other bottom-bar call sites changed.

## Brief discrepancies and remaining gates

- Item 1's exact RGB expectation for every Done/Cancel/Save/tick conflicts with
  T-446 and the existing ink/fill contract. `accentTint` gives text and glyphs
  readable ink: default red becomes `#C26666` in Dark and `#BD5959` in OLED
  (`KudosTests/AccentInkTests.swift:33`). Fills remain exact `#990000`; Sepia
  uses its exact brown. This patch preserves that existing distinction.
- Item 2's “unchanged in Light” is not true for palette-backed pills in this
  source: `SubjectPalette.accent` is also a derived colour in Light and Sepia
  (`UIComponents/SubjectSurface.swift:90`). Using `tint` fixes all four themes,
  including the explicitly requested Sepia brown. No-palette pills are unchanged.
- No builds, tests, mutation runs or simulator screenshots were performed at the
  owner's direction. Rendering tests include a warm-up pass but remain unexecuted.
  Helper/component tests do not replace presentation or native-chrome checks.
- Read-only adversarial reviewers covered palettes/ground/tests, disabled-label
  behavior, and bottom bars/cross-cutting regressions. They found one unsupported
  test colour member; it was replaced with an RGB literal and re-reviewed. No
  remaining concrete source-level defects were reported; runtime behavior remains
  unverified.
- `docs/ARCHITECTURE_MAP.md` and `docs/REGRESSION_TEST_MATRIX.md` now describe the
  shared rules, added coverage and manual residue. `project.pbxproj`, `Packages`
  and `Vendor` were not changed or staged.
- Next: Claude-Code commits the explicit changed paths (excluding the local
  `Packages`/`Vendor` symlinks), builds both platforms, runs the focused suite and required
  gates after tonight's device run, verifies the five theme columns and AX5,
  and obtains the existing human screenshot approval before integration.
  Android already implements the intended rules; no Android port is needed.
