# T-419 iOS result

Implementation ready for Claude's app build, full suite and visual review. Left uncommitted as dispatched.

- Worktree: `/Users/cidy02/kudos-agent-ios`, branch `claude/agent-ios-t419`, starting at `83626d46`.
- Report is in the authorized iOS root; Android lane is read-only. Existing untracked `docs/android-port/` files are untouched.
- No commit, push, branch switch, sign-in, xcodebuild, AO3 contact, TASKS.md edit or project-file edit.

## Choice and behavior

The root tint is **readable ink**. `.accentTint(_:on:)` supplies that tint plus separate ink/fill environment colours. `.accentFill()` restores the exact accent on native fill controls; `.fill(.accentFill)` does so for custom shapes. Bordered buttons keep the exact translucent fill and use `.foregroundStyle(.accentInk)` for their labels. Automatic text buttons, plain/borderless tint-based labels, links and existing `.foregroundStyle(.tint)` use the native readable tint path without new view parameters or a replacement ButtonStyle. Neutral plain buttons that explicitly use primary/secondary colours retain those colours.

This is the smaller correct implementation for the native text controls: replacing explicit foregrounds alone misses automatic text-button labels, while a global replacement ButtonStyle risks changing menus, swipe actions and toolbar behavior. The mechanically broad fill call-site updates keep each control's fill explicit and preserve existing local tint overrides. Root, presented sheets, subject washes, hero washes, the independent reader theme and toolbar/window fallback tint all use the same role split. Native toggles, sliders, progress, date pickers, steppers, segmented selections, prominent/glass-prominent buttons, sidebar selection and custom selection/chip/badge fills keep exact accents. Existing explicit semantic tints remain in place.

`SubjectPalette.accent` and `SubjectPalette.controlColor` are unchanged. A subject screen's existing tint is checked with the same rule; already-readable tones are returned unchanged. Prominent labels now derive contrast from the exact fill environment, so changing the foreground tint does not change their black/white label choice.

## Android parity and tests

Read Android's `SubjectColor.kt` and `KudosTokens.kt` in the read-only lane. `Color.readable(on:minimum:)` reuses WCAG relative luminance, mixes the **original** colour toward white at `step / 20f` for at most 20 steps, and reproduces Compose's Float arithmetic and sRGB-byte rounding. Already-readable colours are returned as themselves.

The comparison page is `cardBackdrop`: **Dark #0B0B0D**, not reader background #16161A; OLED #000000. Independent Float/byte arithmetic and execution of the actual Swift helper agree:

| Accent | Page | First passing step | Ink | Contrast |
|---|---|---|---|---|
| #990000 | Dark #0B0B0D | 8 (40% white) | **#C26666** | 5.0437559:1 |
| #990000 | OLED #000000 | 7 (35% white) | **#BD5959** | 4.7369685:1 |

Added `KudosTests/AccentInkTests.swift` with five tests: Dark/OLED contrast and exact fills; already-readable identity; unchanged Light/Sepia tint; Android hex parity and the previous Dark step failing; ThemeManager ink/fill separation across all four themes. The ThemeManager test restores the UserDefaults keys it changes. Updated the architecture map and regression matrix with the new roles and manual checks.

## Verification / remaining work

- Shared helper + ShapeStyle/environment/modifier code: standalone macOS SDK type-check passed, including usage probes.
- Actual shared Color helper compiled and ran in a standalone macOS smoke executable: both hex values/contrast thresholds passed, as did unchanged already-readable colours. This is not an app build or the KudosTests suite.
- Changed Swift sources and the new test file: syntax parse passed (91 files).
- `Scripts/check-invariants.sh`: passed.
- `git diff --check`: passed.
- `Scripts/lint.sh` hit a sandbox cache-write permission error; reran the same SwiftLint gate with `swiftlint lint --quiet --no-cache kudos-ao3-reader`: **exit 0, 127 warnings**. The new helper/style files have no lint warnings. No bulk formatting was applied.
- Shared helper + ShapeStyle/environment/modifier code: standalone **iOS Simulator SDK type-check passed** too.
- Native fill audit: all **164** Toggle/Slider/ProgressView/Gauge/DatePicker/Stepper call sites have an explicit tint or `.accentFill()`; none missing. Bordered/prominent/segmented/custom-fill call sites were checked separately.
- SwiftLint reports no warnings on the changed source lines; the 127-warning total is recorded as observed, without claiming a clean warning baseline.

**Claude still needs** the app builds and full suite (Packages and Vendor are absent here), adversarial review, and visual verification before landing. Inspect Dark/OLED text, icons, text buttons and links in screens/sheets; compare exact fills on toggles/sliders/progress/prominent buttons/chips; check bordered labels, the date picker's own popup, selection, and an independent reader theme; spot-check Light/Sepia. No app UI was seen, so visual correctness is not claimed. Local READIUM_MIGRATION_NOTES.md is absent; reader changes are restricted to colour-role wiring, not navigation, publication or progress behavior.

## Every changed call site

Paths below are relative to the iOS worktree. Entries give the final source line and each changed call/expression or its environment wiring. The unchanged foreground `.tint` sites automatically receive the new root/screen ink. Shared helper implementations and tests are listed separately afterward.

### `kudos-ao3-reader/App/ContentView.swift`

- L22: `private var chromeTint: Color {`
- L23: `washRegistry.current.map { theme.appTheme.accentInk(for: $0) } ?? theme.accentInk`
- L79: `.accentTint(washRegistry.current ?? theme.effectiveTint, on: theme.appTheme)`
- L172: `.accentTint(theme.effectiveTint, on: theme.appTheme)`
- L176: `.accentTint(theme.effectiveTint, on: theme.appTheme)`
- L193: `.accentTint(theme.effectiveTint, on: theme.appTheme)`
- L202: `.accentTint(theme.effectiveTint, on: theme.appTheme)`
- L207: `.accentTint(theme.effectiveTint, on: theme.appTheme)`
- L213: `.accentTint(theme.effectiveTint, on: theme.appTheme)`
- L218: `.accentTint(theme.effectiveTint, on: theme.appTheme)`
- L387: `.accentFill()`

### `kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift`

- L416: `ProgressView().accentFill()`

### `kudos-ao3-reader/Features/Account/AO3CollectionFormView.swift`

- L79: `ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accentFill()`
- L359: `.accentFill()`
- L407: `.accentFill()`

### `kudos-ao3-reader/Features/Account/AO3CollectionItemsView.swift`

- L366: `ProgressView().accentFill()`
- L387: `.foregroundStyle(.accentInk)`
- L388: `.accentFill()`
- L755: `.accentFill()`

### `kudos-ao3-reader/Features/Account/AO3CollectionsFilterPanel.swift`

- L141: `.accentFill()`
- L164: `.foregroundStyle(.accentInk)`
- L165: `.accentFill()`

### `kudos-ao3-reader/Features/Account/AO3CollectionsList.swift`

- L182: `ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accentFill()`
- L192: `ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accentFill()`
- L204: `ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accentFill()`

### `kudos-ao3-reader/Features/Account/AO3PreferencesView.swift`

- L60: `.accentFill()`
- L89: `ProgressView().accentFill()`
- L235: `.accentFill()`
- L266: `.accentFill()`

### `kudos-ao3-reader/Features/Account/AccountComponents.swift`

- L335: `.accentFill()`
- L448: `.fill(.accentFill.opacity(0.16))`
- L743: `.foregroundStyle(.accentInk)`
- L744: `.accentFill()`
- L761: `.accentFill()`

### `kudos-ao3-reader/Features/Account/AccountInboxViews.swift`

- L369: `.fill(.accentFill)`

### `kudos-ao3-reader/Features/Account/AccountView.swift`

- L729: `.accentFill()`

### `kudos-ao3-reader/Features/Account/AvailabilitySweepView.swift`

- L61: `.accentTint(theme.effectiveTint, on: theme.appTheme)`
- L141: `ProgressView(value: Double(completed), total: Double(max(total, 1))).accentFill()`

### `kudos-ao3-reader/Features/Auth/AO3LoginView.swift`

- L147: `.accentFill()`

### `kudos-ao3-reader/Features/Authors/AuthorProfileComponents.swift`

- L70: `.accentFill()`
- L78: `.accentFill()`
- L103: `.accentFill()`
- L128: `.foregroundStyle(.accentInk)`
- L129: `.accentFill()`

### `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift`

- L90: `if isLoadingMore { ProgressView().controlSize(.small).accentFill() }`
- L285: `.accentFill()`
- L625: `.accentFill()`

### `kudos-ao3-reader/Features/Authors/OwnWorksBulkBar.swift`

- L21: `if isBusy { ProgressView().controlSize(.small).accentFill() }`

### `kudos-ao3-reader/Features/Bookmarks/AO3AccountWorksList.swift`

- L711: `ProgressView().controlSize(.large).accentFill()`

### `kudos-ao3-reader/Features/Bookmarks/AO3NamedSubscriptionsList.swift`

- L181: `Section { ProgressView().frame(maxWidth: .infinity).bareListRow().accentFill() }`

### `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift`

- L360: `ProgressView().controlSize(.small).accentFill()`
- L448: `.foregroundStyle(tint)`
- L565: `.accentFill()`
- L600: `.foregroundStyle(.accentInk)`
- L601: `.accentFill()`

### `kudos-ao3-reader/Features/Challenges/ChallengeSettingsEditView.swift`

- L313: `.environment(\.timeZone, TimeZone(secondsFromGMT: 0)!).accentFill()`
- L397: `.disabled(isDisabled).accentFill()`
- L651: `.accentFill()`
- L672: `.foregroundStyle(.accentInk)`
- L673: `.accentFill()`

### `kudos-ao3-reader/Features/Challenges/ChallengeSettingsView.swift`

- L362: `.accentFill()`
- L372: `.accentFill()`
- L476: `.accentFill()`
- L500: `.foregroundStyle(.accentInk)`
- L501: `.accentFill()`

### `kudos-ao3-reader/Features/Challenges/ChallengeSignUpView.swift`

- L475: `.accentFill()`
- L589: `.accentFill()`
- L610: `.foregroundStyle(.accentInk)`
- L611: `.accentFill()`

### `kudos-ao3-reader/Features/Challenges/ChallengeSignUpsView.swift`

- L339: `.accentFill()`
- L421: `.accentFill()`
- L445: `.foregroundStyle(.accentInk)`
- L446: `.accentFill()`

### `kudos-ao3-reader/Features/Challenges/CollectionMaintainersView.swift`

- L327: `.screenTint(palette)`
- L339: `.accentFill()`
- L400: `.accentFill()`
- L427: `.accentFill()`
- L451: `.foregroundStyle(.accentInk)`
- L452: `.accentFill()`

### `kudos-ao3-reader/Features/Challenges/CollectionModerationView.swift`

- L416: `.accentFill()`
- L641: `.accentFill()`
- L675: `.accentFill()`
- L703: `.accentFill()`
- L727: `.foregroundStyle(.accentInk)`
- L728: `.accentFill()`

### `kudos-ao3-reader/Features/Challenges/PromptMemeView.swift`

- L399: `.accentFill()`
- L470: `.accentFill()`
- L494: `.foregroundStyle(.accentInk)`
- L495: `.accentFill()`

### `kudos-ao3-reader/Features/Challenges/TagSetView.swift`

- L197: `.accentFill()`
- L368: `.accentFill()`
- L600: `.accentFill()`
- L624: `.foregroundStyle(.accentInk)`
- L625: `.accentFill()`

### `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift`

- L310: `.background(isEmphasized ? AnyShapeStyle(.accentFill) : AnyShapeStyle(.quaternary), in: Capsule())`
- L1217: `.foregroundStyle(theme.accentInk)`
- L1641: `shape.fill(.accentFill.opacity(0.12))`

### `kudos-ao3-reader/Features/Comments/CommentsView.swift`

- L124: `ProgressView().accentFill()`
- L689: `.accentFill()`
- L1002: `ProgressView().accentFill()`
- L1338: `ProgressView().accentFill()`
- L1558: `.foregroundStyle(.accentInk)`
- L1559: `.accentFill()`

### `kudos-ao3-reader/Features/Home/HomeCards.swift`

- L317: `Circle().fill(.accentFill)`

### `kudos-ao3-reader/Features/Home/HomeView.swift`

- L348: `.accentFill()`
- L355: `.foregroundStyle(.accentInk)`
- L356: `.accentFill()`

### `kudos-ao3-reader/Features/Library/Collections.swift`

- L257: `.accentFill()`
- L269: `.accentFill()`

### `kudos-ao3-reader/Features/Library/LibraryFilterPanel.swift`

- L43: `.accentFill()`

### `kudos-ao3-reader/Features/Library/NewCollectionSheet.swift`

- L91: `.screenTint(palette)`
- L123: `Toggle("Keep downloads", isOn: $keepsWorksOffline).labelsHidden().accentFill()`
- L127: `Toggle("Show on Home", isOn: $showsOnHome).labelsHidden().accentFill()`

### `kudos-ao3-reader/Features/Library/NewReadingQueueSheet.swift`

- L150: `.screenTint(palette)`
- L238: `Toggle("Keep works offline", isOn: $options.keepsWorksOffline).labelsHidden().accentFill()`

### `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift`

- L832: `.accentFill()`

### `kudos-ao3-reader/Features/Library/ReadingQueueSettingsView.swift`

- L229: `.accentFill()`

### `kudos-ao3-reader/Features/Library/ReadingQueues.swift`

- L484: `ProgressView().accentFill()`
- L503: `Toggle("Also add works from this AO3 series", isOn: $includeSeries).accentFill()`
- L508: `ProgressView().accentFill()`
- L524: `if preservingSeries { ProgressView().accentFill() }`

### `kudos-ao3-reader/Features/Library/WorkRow.swift`

- L355: `.foregroundStyle(.accentInk)`
- L356: `.accentFill()`

### `kudos-ao3-reader/Features/Onboarding/SyncFolderOnboardingView.swift`

- L91: `.accentFill()`
- L97: `ProgressView().frame(maxWidth: .infinity).accentFill()`
- L105: `.accentFill()`

### `kudos-ao3-reader/Features/Onboarding/WelcomeView.swift`

- L83: `.accentFill()`

### `kudos-ao3-reader/Features/Reader/CustomizeThemeView.swift`

- L68: `Toggle("Bold Text", isOn: $boldText).accentFill()`
- L79: `.accentFill()`
- L91: `Toggle("Justify Text", isOn: $justify).accentFill()`
- L254: `.accentFill()`

### `kudos-ao3-reader/Features/Reader/TextSizeSlider.swift`

- L22: `.accentFill()`

### `kudos-ao3-reader/Features/ReaderReadium/ReaderContentsSheet.swift`

- L72: `.accentFill()`

### `kudos-ao3-reader/Features/ReaderReadium/ReaderPositionCard.swift`

- L18: `@Environment(\.accentInk) private var ink`
- L166: `+ Text("\(page)").foregroundStyle(scrubValuesEmphasized ? ink : Color.primary)`
- L176: `.foregroundStyle(scrubValuesEmphasized ? ink : Color.primary)`
- L193: `.foregroundStyle(scrubValuesEmphasized ? ink : Color.secondary)`
- L201: `.foregroundStyle(scrubValuesEmphasized ? ink : Color.secondary)`

### `kudos-ao3-reader/Features/ReaderReadium/ReaderPronunciationSettingsView.swift`

- L63: `if isScanning { ProgressView().accentFill() }`

### `kudos-ao3-reader/Features/ReaderReadium/ReaderSearchView.swift`

- L326: `ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accentFill()`
- L364: `ProgressView().accentFill()`
- L386: `ProgressView().accentFill()`

### `kudos-ao3-reader/Features/ReaderReadium/ReaderSpeechAuditionHarness.swift`

- L64: `.accentFill()`
- L78: `.foregroundStyle(.accentInk)`
- L79: `.accentFill()`
- L99: `.accentFill()`

### `kudos-ao3-reader/Features/ReaderReadium/ReaderSpeechDeveloperSettingsView.swift`

- L91: `Toggle("Break at dialogue", isOn: $dialogueBarrier).accentFill()`
- L92: `Toggle("Pause at line breaks", isOn: $lineBreakPauses).accentFill()`
- L145: `.accentFill()`
- L168: `.accentFill()`

### `kudos-ao3-reader/Features/ReaderReadium/ReaderSpeechSettingsSection.swift`

- L118: `.accentFill()`
- L168: `.accentFill()`
- L182: `.accentFill()`
- L272: `ProgressView(value: progress).accentFill()`
- L347: `ProgressView(value: progress).accentFill()`
- L371: `.accentFill()`
- L405: `.accentFill()`

### `kudos-ao3-reader/Features/ReaderReadium/ReadingAnnotationColorPicker.swift`

- L6: `@Environment(\.accentFill) private var fill`
- L45: `isSelected ? fill : Color.primary.opacity(0.12),`

### `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift`

- L19: `@Environment(ThemeManager.self) private var theme`
- L23: `.accentTint(theme.effectiveTint, on: theme.readerTheme)`
- L1104: `tint: readerTheme.accentInk(for: tint),`
- L1661: `.accentTint(themeManager.effectiveTint, on: readerTheme)`

### `kudos-ao3-reader/Features/Search/AO3FilterPanel.swift`

- L206: `.accentFill()`
- L267: `.accentFill()`
- L296: `Toggle("Include Not Rated", isOn: $filters.includeNotRated).accentFill()`
- L537: `)).accentFill()`
- L544: `.labelsHidden().accentFill()`
- L663: `.accentFill()`

### `kudos-ao3-reader/Features/Search/AO3WorkRow.swift`

- L542: `.foregroundStyle(.accentInk)`
- L543: `.accentFill()`

### `kudos-ao3-reader/Features/Search/FilterRangeSlider.swift`

- L53: `.fill(.accentFill)`

### `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift`

- L172: `.accentFill()`

### `kudos-ao3-reader/Features/Support/BugReportView.swift`

- L104: `Toggle("Include a screenshot", isOn: $includeScreenshot).accentFill()`

### `kudos-ao3-reader/Features/WorkDetail/AO3WorkActionsModel.swift`

- L214: `Toggle("Private", isOn: $actions.bookmarkInput.isPrivate).accentFill()`
- L215: `Toggle("Recommend", isOn: $actions.bookmarkInput.isRec).accentFill()`
- L238: `ProgressView().accentFill()`

### `kudos-ao3-reader/Features/WorkDetail/WorkDetailComponents.swift`

- L36: `.fill(.accentFill.opacity(0.12))`
- L40: `.accentFill()`

### `kudos-ao3-reader/Features/WorkDetail/WorkDetailOverviewSections.swift`

- L202: `if queuingSeries { ProgressView().accentFill() }`

### `kudos-ao3-reader/Features/WorkDetail/WorkDetailSections.swift`

- L286: `ProgressView().controlSize(.small).accentFill()`
- L478: `ProgressView(value: progress).accentFill()`
- L562: `.fill(.accentFill.opacity(0.16))`
- L585: `DatePicker("Downloaded", selection: $date, in: ...Date(), displayedComponents: .date).accentFill()`
- L603: `.accentFill()`

### `kudos-ao3-reader/Features/WorkDetail/WorkDetailView.swift`

- L216: `.accentFill()`
- L343: `.accentFill()`
- L1215: `Toggle(prompt.autoPreserveLabel, isOn: $autoPreserveSmallSeries).accentFill()`

### `kudos-ao3-reader/Features/Writing/AddChapterView.swift`

- L270: `)).labelsHidden().accentFill()`
- L277: `.frame(maxWidth: .infinity, alignment: .trailing).accentFill()`
- L285: `Toggle("Post without preview", isOn: $postWithoutPreview).labelsHidden().accentFill()`
- L292: `.accentFill()`

### `kudos-ao3-reader/Features/Writing/EditMultipleWorksView.swift`

- L334: `.accentFill()`

### `kudos-ao3-reader/Features/Writing/EditTagsView.swift`

- L211: `.accentFill()`

### `kudos-ao3-reader/Features/Writing/SeriesEditView.swift`

- L187: `Toggle("", isOn: $form.isComplete).labelsHidden().accentFill()`

### `kudos-ao3-reader/Features/Writing/WorkAssociationPickers.swift`

- L581: `.accentFill()`
- L712: `.accentFill()`

### `kudos-ao3-reader/Features/Writing/WorkEditView.swift`

- L496: `.accentFill()`
- L508: `.frame(maxWidth: .infinity, alignment: .trailing).accentFill()`
- L515: `.accentFill()`
- L521: `.accentFill()`
- L672: `.accentFill()`

### `kudos-ao3-reader/Features/Writing/WritingChaptersView.swift`

- L47: `.accentFill()`

### `kudos-ao3-reader/Features/Writing/WritingDraftsView.swift`

- L59: `.accentFill()`
- L413: `ProgressView("Loading tags…").accentFill()`
- L464: `ProgressView("Loading \(workIDs.count) works…").accentFill()`
- L559: `ProgressView().controlSize(.large).accentFill()`

### `kudos-ao3-reader/Features/Writing/WritingPreviewView.swift`

- L106: `if busy { ProgressView().accentFill() }`

### `kudos-ao3-reader/Features/Writing/WritingTextEditor.swift`

- L96: `} else { ProgressView().accentFill() }`
- L208: `ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accentFill()`

### `kudos-ao3-reader/Services/DownloadQueue.swift`

- L199: `ProgressView().accentFill()`

### `kudos-ao3-reader/Settings/PairingSheet.swift`

- L141: `.accentTint(themeManager.effectiveTint, on: themeManager.appTheme)`
- L150: `.accentTint(themeManager.effectiveTint, on: themeManager.appTheme)`
- L342: `Toggle("I got this key from my other device", isOn: $confirmedFromOwnDevice).accentFill()`

### `kudos-ao3-reader/Settings/SettingsAccountPages.swift`

- L30: `Toggle("Hide mature content", isOn: $hideMatureContent).accentFill()`
- L36: `.accentFill()`
- L38: `Toggle("Require Face ID to reveal", isOn: $requireBiometric).accentFill()`
- L71: `.accentTint(themeManager.effectiveTint, on: themeManager.appTheme)`
- L76: `.accentTint(themeManager.effectiveTint, on: themeManager.appTheme)`

### `kudos-ao3-reader/Settings/SettingsBackupPage.swift`

- L477: `ProgressView().accentFill()`
- L487: `ProgressView().accentFill()`
- L500: `.accentFill()`

### `kudos-ao3-reader/Settings/SettingsImportPage.swift`

- L166: `ProgressView().accentFill()`

### `kudos-ao3-reader/Settings/SettingsReadingPages.swift`

- L35: `Toggle("Match App & Reader Theme", isOn: matchThemeBinding).accentFill()`
- L64: `.accentTint(themeManager.effectiveTint, on: themeManager.appTheme)`

### `kudos-ao3-reader/Settings/SettingsStoragePages.swift`

- L18: `Toggle("Keep works you read", isOn: $keepsWorksYouRead).accentFill()`
- L26: `Toggle("Download on subscribe", isOn: $downloadOnSubscribe).accentFill()`
- L70: `Toggle("Confirm before deleting", isOn: $confirmBeforeDelete).accentFill()`
- L71: `Toggle("Show zero counts", isOn: $showsZeroStats).accentFill()`
- L120: `.accentFill()`
- L126: `.disabled(!autoPreserveSmallSeriesOnSaveForLater).accentFill()`
- L143: `.accentFill()`

### `kudos-ao3-reader/Settings/SettingsSyncFolderPage.swift`

- L161: `.accentFill()`
- L206: `ProgressView().accentFill()`

### `kudos-ao3-reader/Settings/SettingsView.swift`

- L73: `.accentTint(themeManager.effectiveTint, on: themeManager.appTheme)`
- L91: `.accentFill()`
- L123: `.accentFill()`
- L131: `.accentFill()`
- L138: `Toggle("Keep screen awake", isOn: $keepScreenAwake).accentFill()`
- L432: `.accentFill()`
- L463: `.accentFill()`
- L465: `Toggle("Pause Library Sync on this device", isOn: $pauseSync).accentFill()`

### `kudos-ao3-reader/Settings/StorageUsedRow.swift`

- L26: `ProgressView().controlSize(.small).accentFill()`

### `kudos-ao3-reader/UIComponents/DownloadDateImportConfirmation.swift`

- L79: `).accentFill()`
- L109: `.accentFill()`

### `kudos-ao3-reader/UIComponents/HeroWash.swift`

- L27: `.accentTint(palette?.tint ?? themeManager.effectiveTint, on: themeManager.appTheme)`

### `kudos-ao3-reader/UIComponents/RemoteWorkSelection.swift`

- L185: `.accentFill()`

### `kudos-ao3-reader/UIComponents/SubjectSurface.swift`

- L1078: `@Environment(\.accentFill) private var fill`
- L1128: `? ThemeManager.label(on: palette?.accent ?? fill)`
- L1159: `? AnyShapeStyle(palette?.accent ?? fill)`
- L1188: `@Environment(\.accentFill) private var fill`
- L1189: `@Environment(\.accentInk) private var ink`
- L1193: `let accent = palette?.accent ?? fill`
- L1197: `.foregroundStyle(isAccented ? (palette?.accentOnFill ?? ink) : Color.primary)`
- L1361: `accentTint(palette.tint, on: palette.theme)`
- L1362: `.environment(\.screenTint, palette.tint)`
- L1374: `@Environment(\.accentFill) private var fill`
- L1377: `content.foregroundStyle(ThemeManager.label(on: fill))`

### `kudos-ao3-reader/UIComponents/TagChip.swift`

- L47: `tinted ? AnyShapeStyle(.accentFill) : AnyShapeStyle(Color(.quaternarySystemFill)),`

### `kudos-ao3-reader/UIComponents/WorkCardListControls.swift`

- L82: `.background(Circle().fill(.accentFill))`

## Shared implementation / test files

- `kudos-ao3-reader/Utilities/ColorHex.swift`: added `contrastRatio(on:)` and `readable(on:minimum:)`; the existing luminance implementation is reused.
- `kudos-ao3-reader/App/ThemeManager.swift`: added `accentInk`; clarified exact fill / readable foreground comments.
- `kudos-ao3-reader/UIComponents/AccentInk.swift` (new): theme ink derivation, separate environment values, `.accentInk` / `.accentFill` ShapeStyles, `.accentTint(_:on:)` and `.accentFill()` view modifiers.
- `KudosTests/AccentInkTests.swift` (new): the five tests described above.
- `docs/ARCHITECTURE_MAP.md` and `docs/REGRESSION_TEST_MATRIX.md`: documented roles and validation responsibility.
