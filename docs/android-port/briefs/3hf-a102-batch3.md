# 3hf: Android fixes from the parity verification, batch 3 (A102), plus one 3he correction

Same setup as 3he (`docs/android-port/briefs/3he-a102-batch12.md`):
- **Worktree and branch:** `/Users/cidy02/kudos-agent-codex`, branch `android/agent-codex-3he`, which now holds 3he
  as commit `ef99bb6b` (Claude-Code committed it and made three corrections on review).
- **Reference:** iOS at `/Users/cidy02/kudos-ios-polish`, committed `HEAD` (`git show HEAD:<path>`).
- **Rules:** no Gradle, no sign-in or AO3 traffic, no schema or backup changes, never revert anyone's work.
- **Committing:** if your sandbox again can't write the git index, leave the edits uncommitted and say so;
  Claude-Code commits them.
- **Report:** write `docs/android-port/audits/3hf-result.md` in the same shape as 3he's.

**The wash rule, corrected.** The 3he brief said only iOS's coloured editor sheets draw a wash. That was too
broad. Android should match iOS sheet by sheet. These iOS sheets draw a wash:

| iOS sheet | Wash palette |
|---|---|
| `Features/Account/AccountInboxFilterSheet.swift:66` | app (Android already matches) |
| `Features/Account/AO3CollectionsFilterPanel.swift:48` | app |
| `Features/Library/QueueTagSheet.swift:92` | one queue's own colour, or the app's for several (`:55–58`) |
| `Features/Search/SaveSearchSheet.swift:92` | the search name's colour |
| `Features/Library/NewReadingQueueSheet.swift:139`, `NewCollectionSheet.swift:79` and `:288` | the picked colour |
| Comment composer (`Features/Comments/CommentsView.swift:1462`) | the comments page's palette, `subjectWash(palette, height: 320)` |
| Formatting tray (`Features/Comments/CommentMarkup.swift:405`) | app, `subjectWash(theme.scopePalette, height: 320)` |

These iOS sheets are flat: Add to Queue, Add to Collection, the bookmark form, the series prompt, bulk Tag
(`UIComponents/WorkBulkTagSheet.swift`), the collection's details, Library filters, and the AO3 filter panel.

iOS's `subjectWash` is a wash that leaves the sheet's own header and buttons alone, unlike `subjectScreenWash`. Its
`height` is the wash's height in points; use the same number in dp.

## 1. Restore the queue tag sheet's wash (3he regression)
3he made `SharedTagContent` (`library/QueueTags.kt`) flat, with the app palette for its controls. That's right for
`WorkBulkTagSheet` (iOS's flat `WorkBulkTagSheet`) but wrong for `QueueTagSheet`. iOS `QueueTagSheet` washes with its
palette and tints its controls with it (`.screenTint(palette)`, `:99`). Android's `QueueTagSheet` callers already
pass the right palette (`QueueOrganizerScreen`, `QueueSettingsScreen`, `QueuePageScreen`); check each passes the
queue's colour for one queue and the app's for several, as iOS `:55–58` does.

Give `SharedTagSheet`/`SharedTagContent` a parameter for the two variants:
- the queue variant washes with `palette`, and its controls take `palette`, as before 3he;
- the bulk-work variant stays flat on `formSheetGround`, with `LocalAppPalette`, as 3he made it.

Update `library/Parity3heSheetsTest.kt` to pass the bulk variant explicitly. Add a check that the queue variant
keeps its wash and its palette's ink on Done.

## 2. The comment composer and the formatting tray take their iOS washes
- **Composer:** `comments/CommentComposerSheet.kt` (`ModalBottomSheet` at `:122`, `containerColor = tokens.background`)
  is flat. iOS washes the composer with the comments page's palette, 320 pt high. Android's composer already gives
  Cancel that palette, so use the same palette for the wash.
- **Formatting tray:** `comments/CommentMarkup.kt` (`ModalBottomSheet` at `:280`) is flat. iOS washes it with the
  app palette, 320 pt high.

In both, the wash sits behind the header and the content, as iOS's does. Measured on the iPhone: the composer in
Dark starts at (42,29,63) and fades to the ground by about 40% of the screen. The tray in Dark starts at (64,7,8).

## 3. The AO3 Collections filter sheet takes its wash
`account/AO3CollectionsFilterPanel.kt` (`ModalBottomSheet` at `:60`) is flat. iOS washes it with the app palette.
The iPhone shows the wash only in Light. That's an iPhone bug, fixed separately; Android should draw it in every
theme, as the inbox filter sheet already does.

## 4. My Copy's download-date picker uses the work's colours
`works/detail/WorkDetailMyCopySheet.kt:530–551` `DownloadedDateEditorDialog` is a bare Material `DatePickerDialog`, so it
takes the shell's Material colours. The selected day is cream (240,232,208) in Dark and OLED and red in Light, and
Save and Cancel are red. On the iPhone, this editor is the work's colour (purple Save over a purple My Copy).

Pass the My Copy sheet's `palette` in and use it:
- the selected day's fill is the palette's exact `tint`, with `SubjectPalette.label(tint)` for its number;
- today's ring, the year and month controls and the Save/Cancel text use the readable ink
  (`theme.accentInk(tint)`), as `SubjectPaletteTheme` defines it;
- the dialog's container is the theme's sheet ground, not Material's tonal surface.

Prefer `DatePickerDefaults.colors(...)` plus `SubjectPaletteTheme` over hand-drawing anything.

## 5. Customize Theme's status bar
In Dark and OLED, the status bar's clock and icons are dark on the dark Customize Theme sheet: faint in Dark,
invisible in OLED. The sheet opens over the reader (`reader/CustomizeThemeSheet.kt`), and the reader's system-bar
setting (light icons for a light reading page, or similar) seems to stay in force. While the sheet is up, the status
bar should read on the sheet's own ground, then return to the reader's setting when it closes.

Find where the reader sets the status-bar appearance and fix it there, for every sheet over the reader:
- Contents, Find, Display (Customize Theme), Read Aloud and Note;
- any other reader sheet whose ground differs from the reading page.

The `compose` sheet over Comments keeps white icons correctly; use it as the model.

## 6. Smaller items
- **Composer counter:** "10,000 left" is `FontFamily.Monospace` (`comments/CommentComposerSheet.kt:314`). iOS draws it
  in the default font (`CommentsView.swift:1507`). Use the default family; tabular figures are fine if you want the
  number to stay still.
- **My Copy's Downloaded row:** it opens the date editor (`WorkDetailMyCopySheet.kt:484`) but shows no disclosure
  chevron. iOS shows "Not recorded ›". Give the row the same trailing chevron that other tappable `MyCopyValueRow`s or
  `SubjectFormRow` use.
- **Header double inset:** `library/CollectionReorderSheet.kt:157` draws `SubjectHeaderBlock` with its default gutter
  inside a `LazyColumn` already padded 16 dp (`:153`). The header then sits further in than "Reading order" and the
  rows; the iPhone aligns them. Pass `gutter = 0.dp` there.

  Then audit every `SubjectHeaderBlock(` call (about 60) for the same pattern: default gutter inside a horizontally
  padded container. Fix each one where the header ends up inset from the content below it, and list every site you
  checked, changed or not, in the report.

## Tests
- Follow 3he's tests (`Parity3heSheetsTest`, `Parity3heControlsTest`) and the Compose test lessons in 3he's brief.
- Add a focused test for each of items 1–4: a pixel or colour check that fails with the fix reverted. Say how you
  checked that by reading.
- Item 5 may be impractical under Robolectric; if so, say so, and say what Claude-Code should check on the emulator.
