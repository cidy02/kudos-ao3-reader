# Brief 3fs result

Branch: `android/agent-codex2-3fs`; starting tree clean. No Gradle, network, git mutations, or TASKS.md edits.

## Source rules confirmed
- iOS `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift:615–691`: exact stored-locator matching; Highlight toggles same colour, recolours another, creates immediately then shows colour bar; Add Note opens the existing/new mark's editor.
- iOS `Features/ReaderReadium/ReadingAnnotationColorPicker.swift:87–98`: last-used colour is UserDefaults `readerHighlightColor`; absent from `Services/KudosBackup.swift:1570` settings manifest. Android already has device-only SharedPreferences `reader-annotations/lastHighlightColor` (retained).
- iOS `Features/Reader/CustomizeThemeView.swift:58–112,140–177,256–269`: sample → four themes → Font, Bold Text → Customize, Line Spacing, Character Spacing, Word Spacing, Margins, Justify Text → Reset Theme. Customize gates layout only; font and bold always apply. Reset leaves theme and text size alone.
- iOS `Features/Reader/ReaderStyle.swift:236–252`: reset line spacing 1.65, margin 28; spacing 0, justify/bold/customize false, font system. Ranges: line 1.2–2.4, character 0–0.12 em, word 0–0.6 em, margins 8–64 pt.

## Implementation
All Android paths below start at `android/app/src/main/java/io/github/cidy02/kudos/`.
- `reader/AnnotationRepository.kt:118`, `reader/ReaderViewModel.kt:279`, `reader/ReaderScreen.kt:414`: immediate selection mark/toggle/recolour; new and existing Add Note go to the full editor. New notes use iOS's highlight-with-note representation; existing Android `note` records remain supported.
- `reader/ReaderHighlightColorBar.kt:22`, `reader/ReaderNoteEditor.kt:138`: shared accessible swatches including Underline; one tap recolours and dismisses; the bar stacks above the position card (iOS `ReadiumReaderView.swift:1062`). Existing device-only last-used preference retained. Existing editor draft preservation, Cancel, colour undo and delete remain intact. Old annotation dialog removed.
- `reader/CustomizeThemeSheet.kt:65`, `reader/ReaderThemePreview.kt:10`: shared reading-text modal with iOS sample, four themes, all built-in/imported fonts, Bold Text, Customize, four layout sliders, Justify Text and Reset Theme. Sample is local HTML with JavaScript, network, file and content access disabled; selected local font is embedded.
- `settings/SettingsPages.kt:198`, `reader/ReaderScreen.kt:963`: both Customize Theme entries route to that sheet. Accent presets are now directly under Accent Color. Existing Appearance sliders, Settings Reader controls, and reader Text Size / Reading / Read Aloud / Font sections retained. Only the reader's inline Bold Text / Letter spacing / Word spacing expansion moves into the shared sheet: iOS `Settings/SettingsView.swift:32–61,70` puts them there instead. New sheet uses iOS slider ranges; stored older values are retained.
- `data/preferences/SettingsRepository.kt:263,274`: atomic Reset Theme writes only customize=false, bold=false, system font, line=1.65, character/word=0, margins=28, justify=false; preserves text size/theme/mode/accent. Theme picks preserve the app/reader link, following iOS `CustomizeThemeView.swift:183` and `App/ThemeManager.swift:121` starting from `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.
- `reader/settings/ReaderSettingsMapper.kt:30`, `reader/ReaderRepository.kt:82`, `reader/ReaderViewModel.kt:113`: resolved layout follows Customize, bold/font/size always apply, and saved changes update the open book. All built-in font declarations are registered up front so changing the font does not rebuild the navigator at the original restore location. No Room or backup schema edits.

## Tests added / adjusted
Paths relative to `android/app/src/test/java/io/github/cidy02/kudos/`.
- `reader/ReaderHighlightEditorTest.kt:275`: six new cases cover same-colour removal with tombstone, different-colour in-place recolour, immediate new mark/colour-bar routing, same text at different locators, Add Note for new/existing marks, empty-locator nonmatching, and live theme/reset updates.
- `reader/CustomizeThemeSheetTest.kt:45`: four new cases exercise the real Appearance and reader display entries, shared controls/reset, Customize-off gating with bold still active, and resolved sample CSS.
- `reader/ReaderHighlightColorBarTest.kt:27`: every swatch is named; one tap selects Underline and dismisses.
- `data/preferences/SettingsRepositoryTest.kt:77`: two new cases check exact reset defaults with unrelated settings preserved, and linked/unlinked theme writes.
- `reader/settings/ReaderSettingsMapperTest.kt:85`: Customize-off resolves only layout; restoring Customize restores stored choices; margins span 8–64pt; font declarations are stable across built-ins. Existing default/font declaration assertions and `ReaderRepositoryTest` updated for the new behavior.

## Validation / handoff
Preview height shrinks in compact landscape windows so form controls remain reachable. Preview uses the existing Android font/size/margin mapping; exact cross-toolkit typography calibration remains a device check.
`git diff --check` passes. Kotlin compiler PSI parsed all 21 touched Kotlin files with **zero syntax errors** (no Gradle); this does not establish type correctness. Tests are added but **not run**: Gradle/build/tests and device screenshot checks are reserved for Claude, as requested. No commit/push/branch switch/sign-in/AO3 request/TASKS.md edit. No Fix Pronunciation menu item added. Remaining: Claude must compile/run the new and existing suites, then verify Light/Sepia/Dark/OLED, small-screen/large-text sheet layout, local font preview, live reader reflow, native selection toggles/colour bar and Add Note draft retention. No claim of visual correctness.
