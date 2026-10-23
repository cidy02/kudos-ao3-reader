# Brief 3hd result — A93's five P3s

Worktree: `/Users/cidy02/kudos-agent-codex`, branch `android/agent-codex-3hd`, base `6c002b44`.
This file was written first, before code edits, and completed after source review.
Implementation and regression tests are ready for Claude's build/test pass. No Gradle,
AO3 requests, real sign-in, commits, pushes, branch switches, or TASKS.md edits.
The pre-existing untracked `3hd-a93-android.md` was left untouched.

Android source paths below are relative to `android/app/src/main/java/io/github/cidy02/kudos/`;
test paths are relative to `android/app/src/test/java/io/github/cidy02/kudos/`.
iOS references were read under `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.
The historical 3hb report's pinned-field and Light-card conclusions are superseded here.

## 1. Writing fields scroll under one wash

- `writing/WritingTagsEditorScreen.kt:114` and `writing/WritingAssociationPickers.kt:123`:
  both inputs are ordinary lazy `item` rows, with no sticky header or private ground.
  Deleted `writing/WritingPinnedFieldGround.kt` after checking it had no other callers.
  Removed the pin-dependent automatic jumps on typing/answers: otherwise an ordinary
  input would scroll away while the writer was typing. Lists remain lazy.
- Retained the old invisible `Writing pinned field` test tag, so reverting the row
  change fails on scrolling behavior rather than a renamed selector.
- iOS: `Features/Writing/WritingTagsEditor.swift:110`, `:162`, and
  `Features/Writing/WorkAssociationPickers.swift:132`: normal rows under the page wash.

## 2. Pagers use their page palette

- `search/SearchScreen.kt:406`, `:429`, `:1052`, `:1092`, `:1120` thread the existing
  results palette through the empty-results header and populated results list/header.
  `:1081` and `:1153` pass it to both pager calls.
- `account/AO3CollectionDetailScreen.kt:313`: pager gets the same palette as the
  page, including a fetched title replacing the navigation title.
- `account/AO3CollectionModerationScreen.kt:181`: pager gets the collection palette.
- `account/AO3PromptMemeScreen.kt:178`: explicitly passes the page palette.
  **Base-state correction to A93:** the whole page was already title-hued in this
  exact base. `AO3PromptMemeScreen.kt:50` wraps it in `ProvideCollectionPalette`;
  `account/AO3ChallengeSignUpsScreen.kt:45` derives the title-or-slug hue and provides
  `tokens.copy(scopePaletteOverride = palette)`. `ui/subject/KudosTokens.kt:134`
  honors that override. Thus the scope palette at Prompt Meme `:73` is the title's,
  including its wash, cards and actions, rather than the global app accent. Kept
  that shared provider. The new explicit pager argument is behaviorally redundant
  there; no artificial page rewrite was needed.
- iOS: `Features/Search/SearchView.swift:604`,
  `Features/Account/AO3CollectionDetailView.swift:218`, `:535`,
  `Features/Challenges/CollectionModerationView.swift:68`, `:210`, and
  `Features/Challenges/PromptMemeView.swift:75`, `:454`.

## 3. Reader control ink in every theme

- `reader/ReaderContentsSheet.kt:104` uses `tokens.accentInk` for Done.
- `reader/ReaderScreen.kt:1074` supplies `tokens.accentInk` to Display's Done and
  Customize Theme action. Sepia remains its fixed app tint; the other themes get
  the exact picked accent, with the existing Dark/OLED readability lift.
- iOS: `Features/ReaderReadium/ReadiumReaderView.swift:1686`,
  `App/ThemeManager.swift:59`, `UIComponents/SubjectSurface.swift:84`, and
  `Features/Reader/ReaderStyle.swift:146` (effective tint and theme surfaces).

## 4. Reader cards: glass in Light; opaque in Sepia, Dark and OLED

- `reader/ReaderScreen.kt:1080`, `reader/ReaderNoteEditor.kt:83`, and
  `reader/ReaderSpeechSettingsSheet.kt:66`: form ground is false in Light and true
  in Sepia/Dark/OLED. Light returns to the existing glass shade over the sheet;
  Sepia keeps cream on tan. Dark/OLED retain the matching opaque card surfaces.
- `reader/ReaderScreen.kt:1110`, `:1150`: scope `LocalSettingsFormGround = true`
  to each segmented control itself, preserving the white selected pill in Light
  independently of the card ground. Shared segmented-control defaults are unchanged.
- `reader/ReaderSpeechSettingsSheet.kt:55`, `:61`: extracted the existing production
  content from its dialog for the pixel test. Dismissal still obtains the latest
  saved speech preferences; detents and listening-content injection are unchanged.
- Pronunciations and backup import keep their existing opaque providers.
- iOS read: `Settings/SettingsView.swift:29`, `:64`,
  `Features/ReaderReadium/ReaderNoteEditor.swift:23`, `:65`,
  `Features/ReaderReadium/ReaderSpeechSettingsSheet.swift:23`, `:30`, and
  `UIComponents/AppThemeSurface.swift:27` (explicit row surfaces outside Light).

### Screenshot samples

Inspected a contact sheet of the twelve supplied Dark/OLED shots, then sampled
original PNG pixels using Pillow. Coordinates are original-image `(x,y)`, RGB is
8-bit. iPhone card points: Display `(200,1800)`, Note `(200,2100)`, Read Aloud
`(200,2200)`; iPhone sheet point `(600,1500)`. Android card points: Display and
Note `(120,1000)`, Read Aloud `(120,830)`; Android sheet point `(540,220)`.
Files are `{i,a}_{readerdisplay,readernote,readerspeech}_{dark,oled}.png` in
`/Users/cidy02/kudos-tools/pairs/shots/`.

| Screen | iOS Dark card / sheet | Android Dark card / sheet | iOS OLED card / sheet | Android OLED card / sheet |
|---|---|---|---|---|
| Display | 34,34,40 / 22,22,27 | 33,33,35 / 11,11,13 | 28,28,30 / 0,0,0 | 23,23,23 / 0,0,0 |
| Note | 34,34,40 / 22,22,27 | 33,33,35 / 11,11,13 | 28,28,30 / 0,0,0 | 23,23,23 / 0,0,0 |
| Read Aloud | 34,34,40 / 22,22,27 | 34,34,40 / 11,11,13 | 28,28,30 / 0,0,0 | 28,28,30 / 0,0,0 |

These are the supplied historical shots, not new captures of this diff. The opaque
`cardSurface` is RGB 34,34,40 in Dark and 28,28,30 in OLED. It matches iOS exactly;
keep 3hb's opaque Display/Note cards and Read Aloud's existing opaque Dark/OLED
cards. Glass is the older Display/Note discrepancy. The different Dark sheet base
itself was not changed by this brief.

## 5. Customize Theme has opaque form cards

- `reader/CustomizeThemeSheet.kt:125`: adds `LocalSettingsFormGround provides true`
  to the existing content provider, including the nested font picker. Its groups
  now use white in Light and cream in Sepia, with the existing dark card surfaces.
- iOS: `Features/Reader/CustomizeThemeView.swift:58`, `:107`, `:110`:
  grouped form rows, themed within the reader theme's sheet.

## Regression tests and expected revert behavior

**Not executed.** The following are source-reviewed mutation expectations, not
claims of passing tests or actual revert runs. Keep tests in place when reverting
the indicated production expression/row. Every behavior change has a failure path;
existing-behavior guards are identified separately.

| Test path:line and method | What it checks; expected result with the associated production change reverted |
|---|---|
| `app/Brief3hbContentTest.kt:147` `tagsFieldScrollsAwayUnderOneContinuousWash` | Four themes, multiple gutter pixels above/beside/below the input before and after scrolling to item 20; input disappears. Restoring the sticky row fails the absence assertion and restores the flat stripe. Restoring the typing jump alone makes the input disappear immediately after typing. |
| `app/Brief3hbContentTest.kt:156` `collectionsSearchScrollsAwayUnderOneContinuousWash` | Same initial/scrolled wash sampling in four themes on collections. Restoring sticky search fails the absence assertion and brings back the flat stripe. |
| `writing/WritingTagsEditorScreenTest.kt:251` `longChosenListsStayLazyAndTypingKeepsTheFieldUntilTheReaderScrolls` | With 150 chosen tags, typing/answer keeps the input's Y position; explicit scrolling reaches the answer and removes the input. Restoring automatic jumping changes the input Y (or removes it if only that jump is restored); restoring pinning keeps the field visible after scrolling. Chosen values and zero POSTs remain checked. |
| `writing/WritingAssociationScreenTest.kt:222` `manyCollectionRowsStayLazyAndAnswersDoNotScrollTheSearchAway` | Search term matches 150 held rows while a fake answer supplies new collections. Input Y stays put until explicit scrolling to the new result. Restoring the answer-driven jump moves/removes search; restoring pinning fails its disappearance assertion. Still checks lazy rows and no POSTs. |
| `app/Brief3hdPaletteTest.kt:100` `searchHeaderAndFooterUseTheResultsSubjectInEveryTheme` | Real SearchScreen with one fictional work and two pages. Checks wash hue and painted Next ink on header and footer in four themes. Removing either pager's palette argument makes that arrow use global ink and fails its pixel check; parent threading is exercised too. |
| `app/Brief3hdPaletteTest.kt:120` `emptySearchHeaderAlsoReceivesTheResultsPalette` | Exercises SearchScreen's separate empty-results branch. Removing its palette argument/threading makes the Next ink global and fails. |
| `app/Brief3hdPaletteTest.kt:135` `collectionDetailPagerUsesTheLoadedTitlePalette` | Fixture profile replaces a stale navigation title; scrolls to the pager and checks wash hue and Next pixels in every theme. Removing the pager argument returns global ink and fails. |
| `app/Brief3hdPaletteTest.kt:156` `moderationPagerUsesTheCollectionTitlePalette` | Real moderation queue with two pages, every theme, no writes. Removing the pager palette fails Next's pixel comparison. |
| `app/Brief3hdPaletteTest.kt:173` `promptMemeWashAndPagerUseTheTitleAndFallBackToSlug` | **Existing-behavior guard:** checks the actual page wash hue and Next pixels for a title, then an empty title falling back to slug, in every theme. Removing only 3hd's explicit pager argument still passes, because the base provider already supplies that exact palette to the default. Removing the existing `ProvideCollectionPalette` wrapper fails the page hue check and returns global pager ink. |
| `app/Brief3hbContentTest.kt:362` `contentsDoneAndDisplayControlsUseAccentInkInEveryTheme` | Actual Contents and Display Done pixels plus Customize Theme text style, four themes. Reverting either ink assignment fails in Light/Dark/OLED at its control; Sepia remains a guard and still passes because appTint equals accentInk there. |
| `app/Brief3hbContentTest.kt:180` `displayCardsUseGlassInLightAndOpaqueGroundInSepiaDarkAndOled` | Samples Appearance and Reading cards. Restoring unconditional form ground produces white in Light and fails its glass comparison. Other theme halves guard the retained opaque ground. |
| `app/Brief3hbContentTest.kt:190` `noteCardsUseGlassInLightAndOpaqueGroundInSepiaDarkAndOled` | Samples quoted-text and delete-action cards. Restoring unconditional form ground fails the Light glass pixel comparisons. |
| `app/Brief3hbContentTest.kt:211` `speechCardsUseGlassInLightAndOpaqueGroundInSepiaDarkAndOled` | Invokes the same extracted production frame used by the sheet, with two injected SettingsSections. Restoring `provides true` in that frame fails its Light glass comparison. No engine or dialog window needed. |
| `app/Brief3hbContentTest.kt:202` `displayKeepsWhiteSelectedPillsInLight` | Samples selected Theme and Layout pills. Reverting either local segmented provider while retaining the Light glass-card change makes the corresponding pill glass and fails. Reverting the entire card fix returns the original white pills, so this guard alone passes that whole revert; the Display card test then fails. |
| `app/Brief3hbContentTest.kt:223` `customizeThemeUsesOpaqueCardsIncludingTheFontPicker` | Switches saved reader themes as well as the outer theme; samples Text, Accessibility/Layout, Reset and nested font-picker groups. Removing the new form provider fails in Light/Sepia, where glass differs from white/cream. |

The four `WritingTagsEditorScreenTest.kt:295`–`:298` accessibility tests now explicitly
scroll to the typed suggestion before measuring it, since it no longer jumps into
view. They retain their old wrapping/no-ellipsis/footnote checks and are guards:
restoring pinning/automatic jumping would still pass those text-fit checks. No
`hasVisualOverflow` checks were added. Theme-derived expectations read composition
locals, with idle synchronization before consuming composition-written values.

## Verification and next step

- `git diff --check`: passed.
- Reviewed all changed Kotlin call sites and test seams. A cached local Kotlin
  tree-sitter grammar parsed all 15 changed/new Kotlin files without syntax errors
  after stripping `@Composable` annotations in memory (the grammar cannot parse
  annotated function types already used by the base). This is not a compiler check.
- No Gradle, builds, unit tests, mutation runs, emulator sessions, or new UI captures.
- Claude: compile and run `Brief3hbContentTest`, `Brief3hdPaletteTest`,
  `WritingTagsEditorScreenTest`, `WritingAssociationScreenTest`, and the existing
  reader-sheet suites; run the described expression/row reverts with tests retained.
  Re-shoot the changed screens, including collection detail/moderation, and inspect
  Light selected pills plus scrolled writing washes before integration.
