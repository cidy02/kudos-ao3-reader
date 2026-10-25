# A102 / 3he: Android parity fixes, batches 1 and 2

Branch: `android/agent-codex-3he`, based on `53649f26`. Owner: Codex.
Reference: `/Users/cidy02/kudos-ios-polish`, committed iOS `HEAD` **`1e5d3d44`**, read with `git show HEAD:<path>`; its uncommitted Duo work was not used.

Android production paths below are relative to `android/app/src/main/java/io/github/cidy02/kudos/`; test paths are relative to `android/app/src/test/java/io/github/cidy02/kudos/`. iOS paths are relative to `kudos-ao3-reader/` in that reference checkout.

**3hf correction:** queue tags are washed and use their queue palette (app palette for several), while bulk-work tags stay flat/app-coloured. See [3hf’s correction and caller audit](3hf-result.md). The flat queue-tag description below records 3he’s historical regression.

## Verification and handoff

- **Passed:** `android/Scripts/check-invariants.sh`; `git diff --check`; Kotlin compiler 2.3.21 PSI syntax parsing of every changed/new Kotlin file, using the cached compiler directly, without Gradle. This checks syntax, **not types or Compose behavior**.
- **Not run:** Gradle, builds, JVM/Compose tests, screenshots or live AO3 interactions. The owner expressly assigned the Gradle gate to Claude-Code. No sign-in or AO3 traffic occurred.
- **10 focused tests added**, described below. Reversion sensitivity was checked **by reading the before/after source and assertions**, not by executing mutations. No claim that the tests pass yet.
- **No commits or push:** the first explicit-path `git add` failed before staging anything: `Unable to create '/Users/cidy02/AO3_App_OpenSource/.git/worktrees/kudos-agent-codex/index.lock': Operation not permitted`. The linked worktree's index is outside the sandbox's writable roots. Approval is unavailable in this session. All edits remain in this worktree for Claude-Code to gate, commit with explicit paths and the required Codex trailer, and push. No other branch needs porting; integration into the Android lane is pending.
- Before integration: run the focused suites and the lane's full gate; obtain adversarial review and fresh five-column screenshots. Sheet backgrounds, the new glyphs and largest-text wrapping still need visual verification. No schema, migration, backup key, Apple project or network implementation changed.

## 1. Flat sheets and scope controls

- `works/detail/WorkDetailForms.kt:62`: the shared form explicitly takes `LocalAppPalette`, uses a flat form ground at `:66`, and no longer washes its list at `:88`. This reaches Bookmark (`:139`), Preserve Series (`:179`) and Add to Queue (`:221`).
- `ui/subject/KudosTokens.kt:135`: `formSheetGround` distinguishes iOS's Dark `appBaseBackground` (0.086, 0.086, 0.105, approximately **22,22,27**) from `cardBackdrop` (11,11,13). Light uses the existing white sheet ground; Sepia/OLED use their theme ground. This is separate from `sheetGround`, preserving preference help's explicit card backdrop.
- `library/QueueTags.kt:183,198,202`: shared work/queue tag sheets use the app palette and flat form ground. Done (`:213`), plus (`:224`), Add (`:248`), coverage marks (`:280`), values (`:296`) and checks (`:300`) use it, including when opened over a purple queue. Text/icons use `accentInk(app.tint)`, rather than deriving another red/brown; fills retain the exact tint. The text field also inherits that palette. The queue tag manager at `:456` is a pushed page and keeps its wash.
- `library/CollectionEditorSheet.kt:162`: edit/details is flat; creation retains its chosen-colour wash. Existing `SubjectPaletteTheme` at `:154` still gives Done and switches the collection colour.

**iOS:** `Features/Library/ReadingQueues.swift:438,554` (`AddToQueueView`); `Features/WorkDetail/AO3WorkActionsModel.swift:189,228` (bookmark composer); `Features/WorkDetail/WorkDetailView.swift:1228,1276` (series prompt); `Features/Library/Collections.swift:282,289,572` (details and inherited tint); `UIComponents/WorkBulkTagSheet.swift:60`; `Features/Reader/ReaderStyle.swift:83,124` (form ground versus `UIComponents/AppThemeSurface.swift`'s darker card backdrop).

**Already flat, left intact:** My Copy (`works/detail/WorkDetailMyCopySheet.kt:139`) has no wash and deliberately uses the card-page background, matching `WorkDetailView.swift:417–434`. Its download-date editor (`WorkDetailMyCopySheet.kt:530`) is a plain Material date dialog, also without a wash; iOS `Features/WorkDetail/WorkDetailSections.swift:572` uses a flat Form. The date editor and My Copy do **not** call the shared `DetailForm`.

**Test:** `library/Parity3heSheetsTest.kt:31`, `bulkTagsAreFlatAndUseTheAppPaletteEvenOverAColouredPage`: actual rendered ground and Done text across all themes over an explicit purple provider. Reverting the wash/app-palette fix yields a purple ground/Done; the Dark ground assertion also catches dropping the app-base distinction. The existing `app/Brief3hbContentTest.bulkTagAddAlsoUsesDisabledInkAndKeepsItsSubmitAction` now expects app-accent ink for Add and retains its disabled/action assertions. No separate modal screenshot test was added for each Work Details form or collection edit: their common modifiers were traced, and real-window presentation remains part of the screenshot gate.

## 2. Author Subscribe fill

`author/AuthorProfileComponents.kt:180`: explicit `ButtonDefaults.buttonColors` uses `tokens.scopePalette.tint` and `SubjectPalette.label` on that exact fill. Subscribe and Unsubscribe share this button; their disabled behavior remains Material's.

**iOS:** `Features/Authors/AuthorProfileComponents.swift:125–141`, `.borderedProminent`, `.accentFill()`, `.prominentLabel()`.

**Test:** `app/Parity3heControlsTest.kt:64`, `subscribeUsesTheExactPageFillAndItsContrastingLabelInEveryTheme`: reads the current palette inside content, waits for idle, checks label colour and pixels of the real hero button. Without the fix, Dark/OLED use the cream Material fill and wrong label; the fill-pixel count and label check fail. The fixture hero has no avatar URL and makes no network request.

## 3. Exact switch fills

`ui/subject/SubjectToggle.kt:36`: the default uses `scopePalette.tint`, including palette overrides, rather than a raw app token. Explicit text-accent callers were corrected:

| Call site | Change |
| --- | --- |
| `library/QueueSettingsScreen.kt:304` | The queue details offline switch uses its exact queue tint. |
| `writing/WritingWorkFormScreen.kt:486` | Shared work/chapter `WorkFormToggle` uses scope tint. |
| `account/AO3ChallengeSignUpScreen.kt:166` | “Any of these is fine” uses subject tint. |
| `account/AO3ChallengeSettingsEditScreen.kt:349` | Edit switches use scope tint. |
| `account/AO3ChallengeSettingsScreen.kt:234,236` | Both read-only layouts take subject tint; disabled opacity remains intentional. |
| `browse/FandomListChrome.kt:530,533,536,541,544,558` | All six filter-switch calls, including positional colour arguments, pass tint. |
| `account/AO3CollectionItemsScreen.kt:377–378` | The remaining Material switch uses tint for its checked track and border. |
| `works/detail/WorkDetailMyCopySheet.kt:864` | The custom on/off row's filled check-circle takes tint. This is a check indicator, not a sliding switch. |

**Already exact:** `library/QueueEditorSheet.kt:213` and `library/CollectionEditorSheet.kt:324,344` explicitly pass `palette.tint`; A77 W09 was already resolved here. The author works filter uses the default shared toggle through `LibraryFilterPanel` and remains exact.

**iOS:** T-348's `SubjectPalette.controlColor`, `.accentFill()` in writing forms and the bookmark composer, plus the brief's owner Q19 fill/text distinction. Derived palettes still use their own derived tint; picked/app colours remain exact. Disabled controls retain their existing dimming rather than looking enabled.

**Test:** `app/Parity3heControlsTest.kt:87`, `defaultWritingAndColouredSheetSwitchesUseExactFillsInEveryTheme`: samples checked tracks for the default switch, actual `WorkFormToggle` and a picked green sheet. Reverting the writing call yields the brief's derived red/brown instead of exact red/brown. Reverting the default loses the green palette override. Other switches are covered by the shared contract and the explicit call-site audit below, not separate screen tests.

## 4. Coloured-sheet header actions

- `library/CollectionReorderSheet.kt:116`: supplies `SubjectPaletteTheme` to the whole content, including Cancel at `:130`; Done at `:145` uses the same readable ink from `palette.tint`, with disabled ink while saving.
- `search/SaveSearchSheet.kt:84`: another sheet with its own palette lacked inheritance. Its Cancel and Save now inherit the name-derived palette, matching iOS `Features/Search/SaveSearchSheet.swift:100`.
- **Already correct:** new/edit queue (`library/QueueEditorSheet.kt:139,155,163`) and new/edit collection (`library/CollectionEditorSheet.kt:154,389`) already wrap the header in `SubjectPaletteTheme`. Their Cancel actions need no source change. Editing a collection has Done only, as iOS does. Queue tags now have their app palette under item 1; challenge detail/editor sheets inherit the collection palette through their enclosing providers.

**iOS:** `Features/Library/NewCollectionSheet.swift:186,288` (reorder wash and toolbar), `Features/Library/Collections.swift:572` (sheet inheritance); `NewCollectionSheet.swift:79` and `NewReadingQueueSheet.swift:139` keep creation washes. These coloured editors retain their washes.

**Test:** `library/Parity3heSheetsTest.kt:64`, `reorderAndCollectionEditorHeadersTakeTheSheetsColour`: Cancel and Done/Create against picked green in all themes. Reverting the reorder provider restores red/cream Cancel; reverting Done restores its derived colour rather than picked green. Collection creation is an additional guard for the already-correct header. Save Search shares the same provider; no separate modal test added.

## 5. Manage-page palette inheritance

The existing `SubjectPaletteTheme` supplies `LocalSubjectPalette`, exact fill tokens, readable ink and `scopePaletteOverride`. Reused it for:

- `account/AO3CollectionMaintainersScreen.kt:64`;
- `account/AO3ChallengeSettingsScreen.kt:70`;
- `account/AO3CollectionModerationScreen.kt:74`;
- `account/AO3TagSetScreen.kt:72`.

Their existing detailed Material schemes are retained inside the provider. Choice values, required markers and nested subject controls now see the same palette as the page.

**Checked, no gap:** `ProvideCollectionPalette` in `account/AO3ChallengeSignUpsScreen.kt:45` already wraps sign-ups (`:59`), sign-up (`AO3ChallengeSignUpScreen.kt:44`), assignments (`AO3ChallengeAssignmentsScreen.kt:47`), prompts (`AO3PromptMemeScreen.kt:50`) and challenge settings edit (`AO3ChallengeSettingsEditScreen.kt:40`). The AO3 collection settings form (`AO3CollectionFormScreen.kt:69`) intentionally uses the app scope palette, as iOS `Features/Account/AO3CollectionFormView.swift:238`; it does not create a collection palette needing a new provider.

**iOS:** `Features/Challenges/CollectionMaintainersView.swift:317–327` (“Invite as”, `.screenTint(palette)`) and corresponding collection/challenge pages' `.screenTint`.

**Test:** `account/AO3CollectionMaintainersTest.kt:301`, `inviteRoleChoiceUsesTheCollectionPalette`: real fixture-backed screen, actual Moderator text layout colour, expected palette built with the composition's current `LocalKudosTokens` theme after idle. Without the provider it is app red, so this fails. Client records no POST. The other three providers were checked structurally; no fabricated per-page test claims.

## 6. Account-header margin

`author/AuthorProfileScreen.kt:736`: `gutter = 0.dp` in the loaded `usesAccountHeader` branch avoids adding the header's own gutter to the list's 16dp padding. Error handling already uses zero at `:704` and is unchanged. This shared branch covers account About and Bookmarks (and the other account content headers).

**iOS:** `Features/Authors/AuthorProfileView.swift:304–320`, `accountHeader` with one account gutter and an outer zero-gutter body row.

**Test:** `author/AuthorProfileSortScreenTest.kt:109`, `accountAboutHeaderSharesTheListsMargin`: actual loaded account About header against Bio's margin, accounting for Bio's intentional 4dp label inset. Reverting the fix adds the header gutter and fails the position comparison. Bookmarks uses the same branch; no second duplicate margin test.

## 7. Serif editors and formatting letters

- `settings/SettingsChrome.kt:158,165`: optional `textStyle` merges into the existing text/placeholder style. Other callers retain their defaults and colours.
- `account/AO3ChallengeSignUpScreen.kt:180`: prompt text **and placeholder** use serif at **14sp**, iOS `Features/Challenges/ChallengeSignUpView.swift:22,350,357`.
- `account/AO3ChallengeSettingsEditScreen.kt:179`: instructions and placeholder use serif at **14sp**, iOS `ChallengeSettingsEditView.swift:40,273,280`.
- `comments/CommentMarkup.kt:225`: one shared glyph renderer replaces the sans icon outlines with serif **B/I/U/S at 16sp**, **Aa at 11sp**, retaining bold/italic/underline/strike styling. Used in the quick bar at `:199` and full tray at `:347`; quick-bar action descriptions remain present. Other icon glyphs and tray labels keep their existing styles. iOS `Features/Comments/CommentMarkup.swift:324–330,534–550`.

**Already correct / brief correction:** Android's native writing text field is already serif (`writing/WritingNativeTextField.kt:31`), with the editor setting **15.5sp** at `WritingTextEditorScreen.kt:152`. iOS native editing uses the same 15.5 base and serif in `Features/Writing/WritingTextEditor.swift:18` and `WritingNativeTextView.swift:97–105`. The brief's `WritingTextEditor.swift:629` is the rendered **preview**, not the editing field. No speculative preview-font change was made: its existing Android comment records the effective iOS rich-text body's font overriding the outer preview modifier. Preview's effective appearance remains a screenshot check.

**Tests:** `account/AO3ChallengeSignUpScreenTest.kt:65`, `promptAndPlaceholderUseFourteenSpSerif`; `account/AO3ChallengeSettingsEditScreenTest.kt:67`, `instructionsAndPlaceholderUseFourteenSpSerif`; `comments/CommentFormattingTrayScreenTest.kt:47`, `formattingLettersUseIosSerifSizes`. They inspect actual text layouts and sizes. Removing either field style leaves the default family/14.5sp and fails; reverting the tray glyphs removes the B/I/U/S/Aa text nodes entirely. Both filled and empty field states are checked. No artificial “fix” or fail-before test was added for an input that was already serif.

## 8. Collections “Order by” choice

`account/AO3CollectionsFilterPanel.kt:96`: `showsChoice = true` on the existing row, retaining its value button/menu. `ui/subject/SubjectForm.kt:226` tags the existing shared choice indicator for the focused test; its appearance and accessibility description are unchanged.

**iOS:** `Features/Account/AO3CollectionsFilterPanel.swift:78–81`, Order by Picker.

**Test:** `account/CollectionsChoice3heTest.kt:21`, `orderByShowsAChoiceIndicatorAndStillOpensItsMenu`: requires the indicator specifically under Order by and opens the menu from AO3 order. Removing `showsChoice` removes that indicator and fails. Android retains its existing down-chevron vocabulary; this item adds the missing choice affordance, not a new icon system.

## Remaining switch call-site audit

Every `SubjectToggle(` call and the Material `Switch(` was searched. The changed explicit calls are listed in item 3. These are the full shared-toggle call sites, including default users that need no source edit; line numbers point to the call, not the colour argument:
- `account/AO3ChallengeSettingsEditScreen.kt:349`.
- `account/AO3ChallengeSettingsScreen.kt:234`, `account/AO3ChallengeSettingsScreen.kt:236`.
- `account/AO3ChallengeSignUpScreen.kt:166`.
- `account/AO3CollectionFormScreen.kt:155`.
- `account/AO3CollectionsFilterPanel.kt:174`.
- `account/AO3PreferencesScreen.kt:315`.
- `account/BugReportScreen.kt:149`.
- `backup/BackupScreen.kt:488`, `backup/BackupScreen.kt:500`.
- `backup/PairingSheet.kt:408`.
- `browse/FandomListChrome.kt:613`.
- `library/CollectionEditorSheet.kt:324`, `library/CollectionEditorSheet.kt:344`.
- `library/LibraryFilterPanel.kt:206`.
- `library/QueueEditorSheet.kt:213`.
- `library/QueueSettingsScreen.kt:296`.
- `reader/CustomizeThemeSheet.kt:225`, `reader/CustomizeThemeSheet.kt:234`, `reader/CustomizeThemeSheet.kt:256`.
- `reader/ReaderScreen.kt:1165`, `reader/ReaderScreen.kt:1176`.
- `search/SearchFilterSheet.kt:190`, `search/SearchFilterSheet.kt:385`.
- `settings/SettingsListeningPage.kt:195`.
- `settings/SettingsPages.kt:75`, `settings/SettingsPages.kt:168`, `settings/SettingsPages.kt:180`, `settings/SettingsPages.kt:212`, `settings/SettingsPages.kt:229`.
- `settings/SettingsPages2.kt:112`, `settings/SettingsPages2.kt:121`, `settings/SettingsPages2.kt:264`, `settings/SettingsPages2.kt:283`, `settings/SettingsPages2.kt:434`, `settings/SettingsPages2.kt:700`.
- `works/detail/WorkDetailForms.kt:120`, `works/detail/WorkDetailForms.kt:123`.
- `writing/WritingWorkFormScreen.kt:486`.

The additional switch-role Group variants chip (`browse/FandomListChrome.kt:152`) is intentionally a tinted chip, not an opaque selected pill (A88); its fill already comes from the exact tint via `SubjectChip`. No switch fill in the audit still explicitly receives `scopePalette.accent` or `palette.accent`.
