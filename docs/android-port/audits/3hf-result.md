# A102 / 3hf: Android parity fixes, batch 3 and queue-tag correction

Branch: `android/agent-codex-3he`, based on **`ef99bb6b`** (3he, committed by Claude-Code). Owner: Codex.
Reference: `/Users/cidy02/kudos-ios-polish`, committed iOS `HEAD` **`1e5d3d44`**, read using `git show HEAD:<path>`; no uncommitted iOS work used.

Android production paths below are relative to `android/app/src/main/java/io/github/cidy02/kudos/`; test paths are relative to `android/app/src/test/java/io/github/cidy02/kudos/`. iOS paths are relative to `kudos-ao3-reader/` in that reference checkout.

## Verification and handoff

- **Passed:** `android/Scripts/check-invariants.sh`; `git diff --check`; Kotlin 2.3.21 compiler PSI parsing of all **18** changed/new Kotlin files with cached jars, without Gradle. Syntax parsing does **not** check Kotlin types or Compose behavior. Cached Material 3 **1.4.0** bytecode was also inspected to confirm the date-picker API and bottom-sheet window ownership.
- **Not run:** Gradle, builds, JVM/Compose tests, screenshots or emulator checks. No sign-in or AO3 traffic. No schema, migration, backup, dependency, signing or Apple project changes.
- **Six focused tests added** (one in `library/Parity3heSheetsTest.kt`, five in `app/Parity3hfSheetsTest.kt`). The existing bulk test and `app/Brief3hbContentTest.kt` now explicitly request the bulk-work variant. Reversion sensitivity below was checked **by reading the pre-change implementation and assertions**, without executing test mutations. No claim that the tests pass yet.
- **No commit or push:** the explicit-path staging attempt failed before staging anything: `Unable to create '/Users/cidy02/AO3_App_OpenSource/.git/worktrees/kudos-agent-codex/index.lock': Operation not permitted`. The linked worktree’s shared Git index is outside the sandbox’s writable roots; approval is unavailable. All 21 changed/new files remain in this worktree for Claude-Code to gate and commit with explicit paths and the required Codex co-author trailer. No other-branch port required; Android-lane integration remains pending.
- **Next:** Claude-Code runs the focused suites and full Android gate, performs adversarial review, then checks fresh theme screenshots and the reader-window transitions listed under item 5 before committing/pushing/integrating. No open product question.
- The referenced `docs/android-port/briefs/3he-a102-batch12.md` and local-only `READIUM_MIGRATION_NOTES.md` are absent in this worktree (and not present at the same paths in the iOS checkout). Used the owner’s complete 3hf instructions, committed iOS source, 3he’s report and existing tests; asked for any additional Android-reader constraints in the missing notes.

## 1. Queue tags regain their own wash and controls

`library/QueueTags.kt`: required `SharedTagVariant.Queue` / `.BulkWork` parameters distinguish the two shared-sheet presentations. Queue tags use the supplied palette for their local wash (380dp), Done, Add, text-field theme and tag controls. Bulk-work tags remain flat on `formSheetGround` with `LocalAppPalette`. `subjectWash` does not register a sheet as the shell’s page wash. Added the missing foundation `background` import used by the flat branch.

Caller audit:

- `library/QueueSettingsScreen.kt`: already builds `queuePalette(tokens.theme, current)` and passes it with `listOf(current)`; unchanged.
- `library/QueuePageScreen.kt`: already builds the current queue’s palette and passes it to the queue variant. Its separate work-selection branch calls `WorkBulkTagSheet`, which explicitly remains flat/app-coloured; unchanged.
- `library/QueueOrganizerScreen.kt`: **corrected** the palette at the tag-sheet call. `chosen.singleOrNull()` gets that queue’s own colour, and several queues use the organizer’s app palette. Previously even a one-queue selection received app colour. Built-in queues follow the existing `queuePalette` policy.

**iOS:** `Features/Library/QueueTagSheet.swift:55–58,92,99` (single/multiple palette, wash and screen tint); `UIComponents/WorkBulkTagSheet.swift` stays flat. This corrects the over-broad flat-sheet claim in the historical 3he report.

**Test:** `Parity3heSheetsTest.queueTagsKeepTheirWashAndDoneInkInEveryTheme` checks the real content’s top pixel and Done text layout for a picked purple across Light/Dark/Sepia/OLED. Reverting to 3he’s unconditional app palette/flat background fails both assertions. The existing bulk test explicitly passes `.BulkWork` and still checks flat ground/app Done over purple.

## 2. Comment composer and formatting tray washes

- `comments/CommentComposerSheet.kt`: actual `CommentComposerContent` column draws `subjectWash(palette, 320.dp)` behind its header and editor, using exactly the comments palette already used by Cancel. Modal presentation calls that same extracted content; reply-author navigation, draft echo handling, busy/read-only behavior and nested formatting remain wired through. The character counter now uses the default font family.
- `comments/CommentMarkup.kt`: actual `CommentFormattingContent` draws `subjectWash(LocalAppPalette.current, 320.dp)` behind header and tiles before applying its horizontal padding. It therefore takes app wash even when opened over purple comments. Formatting actions and serif glyphs are unchanged.

Both use the local wash modifier, preserving the shell’s current screen wash. The Material modal/drag-handle presentation remains intact.

**iOS:** `Features/Comments/CommentsView.swift:1462,1507`; `Features/Comments/CommentMarkup.swift:405`.

**Tests:** `Parity3hfSheetsTest.composerWashesBehindItsHeaderWithTheCommentsPalette` and `.formattingTrayUsesTheAppWashEvenOverPurpleComments` render actual production content over a deliberately purple provider across all four themes. Pixels at the content’s top edge must match the correct palette’s first wash stop composited over its ground, and pixels after 320dp must be ground. Removing either wash produces the flat/transparent top instead and fails. Using the inherited purple palette for the tray fails its app-colour top assertion. The composer test also checks the counter’s text layout is not monospace; restoring the old family fails that assertion. Exact on-device gradient appearance, modal top edge and fade placement remain screenshot checks.

## 3. AO3 Collections filter wash

`account/AO3CollectionsFilterPanel.kt`: the modal presents `AO3CollectionsFilterContent`, which draws the app’s 380dp wash behind header and filter groups, in every theme, and supplies `SubjectPaletteTheme(app)` to its controls. Existing draft/reset/apply behavior remains; modal dismissal returns the opening value, as Cancel does. The 3he Order by indicator is retained.

**iOS:** `Features/Account/AO3CollectionsFilterPanel.swift:48` and the owner’s instruction to draw the wash in all themes despite the iPhone Dark bug.

**Test:** `Parity3hfSheetsTest.collectionsFilterUsesTheAppWashInEveryTheme` checks top/faded ground pixels and Order by value ink over a purple parent. Reverting to the flat column fails the top-pixel assertion; inheriting the purple page colour fails the app-wash/ink assertions. Existing `CollectionsChoice3heTest` still drives the real modal and its menu.

## 4. My Copy download-date colours and disclosure

`works/detail/WorkDetailMyCopySheet.kt`: My Copy now passes its palette into `DownloadedDateEditorDialog`. Both `DatePickerDialog` and `DatePicker` receive the same `DatePickerDefaults.colors`:

- selected day/year fill: **exact `palette.tint`**;
- numbers on those fills: `SubjectPalette.label(palette.tint)`;
- today text/ring, navigation/month and year controls: `tokens.theme.accentInk(palette.tint)`;
- container: `tokens.formSheetGround`, with dialog tonal elevation zero;
- Save/Cancel: existing `SubjectPaletteTheme(palette)` supplies readable ink.

The future-date limit, UTC conversion helpers and repository update path are unchanged. Downloaded’s tappable `MyCopyValueRow` now opts into the existing chevron vocabulary (`ChevronRight`, tertiary ink, decorative/no duplicate accessibility label).

**iOS:** `Features/WorkDetail/WorkDetailSections.swift:572` (`DownloadedDateEditor`), inherited work tint and form ground, plus the owner’s explicit fill/text contract.

**Test:** `Parity3hfSheetsTest.downloadedDateUsesWorkFillLabelAndActionInkOnTheSheetGround` opens the real date dialog on a fixed past date (10 October 2025), checks Save/Cancel and selected-day text colours, samples the selected day’s fill beside its number, and counts sheet-ground pixels in the dialog’s own Compose view, across all themes. Reverting the provider restores shell-coloured actions; reverting the explicit colours restores Material selected-day/container colours. Each is rejected by these actual-render assertions. Today/year interaction and the Downloaded chevron still require emulator inspection.

## 5. Reader-sheet status and navigation bars

Ownership traced to `reader/ReaderScreen.kt`’s `setLightSystemBars(lightPage)` (activity/reading page) and `ui/theme/Theme.kt` (app). `reader/ReaderSystemBars.kt` owns immersion/visibility. Material’s bottom sheets instead create a **separate dialog window**: cached 1.4.0 `ModalBottomSheetDialogLayout` implements `DialogWindowProvider`; its wrapper initializes icon contrast from sheet content colour. The page’s activity flag alone cannot set a sheet’s flag.

Added `SheetSystemBars(tokens)` beside `setLightSystemBars` in `ui/theme/Theme.kt`. Called **inside** each modal’s content, it resolves that modal’s `DialogWindowProvider` and sets both bar icon appearances from its own theme ground (`!tokens.theme.isDarkFamily`) on composition. It follows live theme changes as well as opening. The activity’s reading-page flags remain underneath; dismissing the dialog reveals those flags, and dismissing Customize Theme reveals Display’s existing window flags.

Covered all eight bottom-sheet sites reachable over the reader:

- Contents, Note and Display & Themes: `reader/ReaderScreen.kt`.
- Find: `reader/ReaderSearchSheet.kt`.
- Read Aloud: `reader/ReaderSpeechSettingsSheet.kt`.
- Customize Theme (including its internal Font chooser): `reader/CustomizeThemeSheet.kt`.
- Pronunciations list and its editor: `settings/PronunciationSettings.kt` (reachable from Display/Read Aloud or reader selection; also used outside the reader, with the caller’s theme tokens).

Also inspected the reader’s voice-pack confirmation and rebuild-original alert: these are Material/Compose alert dialogs, not additional bottom sheets; no reader page-flag override was added to them. Comments’ composer works through the app’s Material content colours, consistent with the reported working white icons.

**Runtime caveat:** no Robolectric assertion of OS-rendered status icons or stacked-window restoration was added; this needs emulator/window verification and no Gradle was allowed here. Claude-Code should check:

1. App Light + reader Dark/OLED, then app Dark/OLED + reader Light/Sepia. Open each of Contents, Find, Display, Read Aloud and Note; clock and icons must read on that sheet, including after expanding it.
2. Display → Customize Theme → Font → Back → Done → dismiss Display. Verify Dark/OLED white icons at each sheet, then the reading-page appearance after closing. Repeat with Light/Sepia dark icons.
3. While Display/Customize is open, switch Light ↔ Dark ↔ OLED ↔ Sepia. Icons must update before dismissal; nested-sheet dismissal must return to the underlying sheet/page correctly.
4. Dismiss with Done, Back and swipe; hide/show reader chrome, reopen a sheet, rotate/background/foreground and leave the reader. No stuck hidden bars or wrong icon colour. Also open Pronunciations from Display/Read Aloud and its nested editor, and the editor from a reader selection; check all their icons, then inspect the voice-pack/rebuild alerts for contrast.

## 6. Header gutter audit

**All 59 production call sites checked**, including helper callers. `SubjectHeaderBlock`’s definition in `ui/subject/SubjectComponents.kt:321` supplies a default **26dp** gutter; `accountGutter` is **16dp**. Three sites needed changes: Collection Reorder, Recently Deleted and Home’s compact grid. The shared header itself is unchanged. This is a source audit; no visual alignment claim is made.

`Parity3hfSheetsTest.reorderHeaderAlignsWithItsReadingOrderLabel` compares actual text bounds in production reorder content. Restoring the default inner gutter adds 26dp to the header and fails. The other two audited fixes require screenshots (Home grid versus list; Recently Deleted).

| Site | Checked result |
| --- | --- |
| `account/AO3ChallengeAssignmentsScreen.kt:108` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AO3ChallengeSettingsEditScreen.kt:145` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AO3ChallengeSettingsScreen.kt:86` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AO3ChallengeSignUpScreen.kt:117` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AO3ChallengeSignUpScreen.kt:289` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AO3ChallengeSignUpsScreen.kt:205` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AO3CollectionDetailScreen.kt:186` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AO3CollectionItemsScreen.kt:168` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AO3CollectionMaintainersScreen.kt:90` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AO3CollectionModerationScreen.kt:116` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AO3CollectionsScreen.kt:172` | Unchanged: no horizontal padding on enclosing list/column; header owns the default 26dp gutter. |
| `account/AO3PreferencesScreen.kt:235` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AO3PromptMemeScreen.kt:106` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AO3TagSetScreen.kt:89` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AO3TagSetScreen.kt:252` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AccountInboxPane.kt:224` | Unchanged: already zero gutter inside the padded list/grid. |
| `account/AccountMoreOnAO3Screen.kt:82` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `account/AccountShortcutsEditor.kt:50` | Unchanged: no horizontal padding on enclosing list/column; header owns the default 26dp gutter. |
| `account/AccountWorksListScreen.kt:370` | Unchanged: no horizontal padding on enclosing list/column; header owns the default 26dp gutter. |
| `account/AccountWorksListScreen.kt:623` | Unchanged: already zero gutter inside the padded list/grid. |
| `account/AccountWorksListScreen.kt:824` | Unchanged: already zero gutter inside the padded list/grid. |
| `account/AccountWorksListScreen.kt:999` | Unchanged: already zero gutter inside the padded list/grid. |
| `account/AccountWorksListScreen.kt:1254` | Unchanged: already zero gutter inside the padded list/grid. |
| `account/AccountWorksListScreen.kt:1583` | Unchanged: already zero gutter inside the padded list/grid. |
| `account/WritingDraftsScreen.kt:143` | Unchanged: zero gutter inside the already padded list; tally below shares that edge. |
| `app/SeriesWorksScreen.kt:220` | Unchanged: no horizontal padding on enclosing list/column; header owns the default 26dp gutter. |
| `author/AuthorProfileScreen.kt:699` | Unchanged: zero gutter inside the existing 16dp list padding (both error and loaded account branches). |
| `author/AuthorProfileScreen.kt:722` | Unchanged: zero gutter inside the existing 16dp list padding (both error and loaded account branches). |
| `browse/FandomListChrome.kt:113` | Unchanged: both FandomListScreen callers (error and loaded) have unpadded parents. |
| `browse/FandomWorksScreen.kt:229` | Unchanged: no horizontal padding on enclosing list/column; header owns the default 26dp gutter. |
| `comments/CommentThreadScreen.kt:93` | Unchanged: no horizontal padding on enclosing list/column; header owns the default 26dp gutter. |
| `comments/CommentsScreen.kt:417` | Unchanged: no horizontal padding on enclosing list/column; header owns the default 26dp gutter. |
| `home/HomeSectionListScreen.kt:665` | **Changed:** helper accepts gutter; grid caller at :589 passes zero inside its 16dp content padding; list caller at :410 keeps default 26dp. |
| `library/CollectionDetailScreen.kt:681` | Unchanged: no horizontal padding on enclosing list/column; header owns the default 26dp gutter. |
| `library/CollectionDetailScreen.kt:710` | Unchanged: no horizontal padding on enclosing list/column; header owns the default 26dp gutter. |
| `library/CollectionReorderSheet.kt:157` | **Changed:** zero gutter inside the list’s existing 16dp horizontal padding. |
| `library/CollectionsScreen.kt:162` | Unchanged: already zero gutter inside the padded list/grid. |
| `library/FavoriteAffinityRow.kt:325` | Unchanged: no horizontal padding on enclosing list/column; header owns the default 26dp gutter. |
| `library/LibraryScreen.kt:1476` | Unchanged: no horizontal padding on enclosing list/column; header owns the default 26dp gutter. |
| `library/QueueOrganizerScreen.kt:193` | Unchanged: unpadded outer column; explicit 16dp account gutter matches the search/queue cards. |
| `library/QueuePageScreen.kt:314` | Unchanged: unpadded outer column; default 26dp header gutter. |
| `library/QueueSettingsScreen.kt:169` | Unchanged: unpadded outer column; default 26dp matches the queue details beneath it. |
| `library/QueueTags.kt:470` | Unchanged: manager page’s outer column has no horizontal padding; header owns its gutter. |
| `library/ReadingStatisticsScreen.kt:260` | Unchanged: already zero gutter inside the padded list/grid. |
| `library/RecentlyDeletedScreen.kt:517` | **Changed:** zero gutter inside 16dp list content padding; explanatory text and rows already start there. |
| `search/SearchResultsHero.kt:250` | Unchanged: subject-page hero and its Search/Browse callers add no horizontal container padding; head owns its gutter. |
| `settings/SettingsChrome.kt:115` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `settings/SettingsHubScreen.kt:100` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `works/detail/WorkDetailIdentity.kt:165` | Unchanged: explicit 26dp gutter; WorkDetailScreen identity caller (:1582) adds no side padding. |
| `writing/WritingAO3PreviewScreen.kt:56` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `writing/WritingAssociationPickers.kt:76` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `writing/WritingBulkEditScreen.kt:179` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `writing/WritingChapterFormScreen.kt:82` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `writing/WritingChaptersScreen.kt:71` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `writing/WritingEditTagsScreen.kt:91` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `writing/WritingSeriesScreen.kt:118` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `writing/WritingTagsEditorScreen.kt:111` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `writing/WritingWorkFormScreen.kt:232` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
| `writing/WritingWorkFormScreen.kt:501` | Unchanged: unpadded list/column; explicit 16dp account gutter matches separately padded body sections. |
