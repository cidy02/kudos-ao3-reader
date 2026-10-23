# Screens redesigned without a mockup

**54** of A81's 146 screens have no mockup (no artboard draws them).
Compared side by side: **21 matched** (A76, A80), **28 A82 pending** (in A82's list, being shot now), **5 not compared** (4 have no Android screen, 1 needs AO3).
**45** of the 54 were restyled on Android without a mockup (entries R1–R27 below; R19 covers the 14 Settings pages). The other 9 have no entry: 4 have no Android screen, and for 5 no restyle is on record.

Owner, 2026-10-20: *"if there are any screens that are not redesigned in the mockup, feel free to
do a best effort redesign and document it. the goal is visual and UX parity with no lost
features or information"*, and *"document in a separate .md any screens without a mockup that
you redesign"*.

The mockup is `docs/design/Final_Redesign_Spec.dc.html` (index
`.claude-overnight/polish/artboards.tsv` in the integrate tree, 86 rows, and `INVENTORY.md`
beside it). Brought up to date 2026-10-22 from A81's 146 screens (`audits/A81-result.md`),
A82's list (`audits/A82-shots.md`), the side-by-side audits A69–A80, `DECISIONS.md` and the
Android lane's history (`android/redesign-parity`).

**How "no mockup" was decided.** A screen has a mockup when `INVENTORY.md` maps its Swift type
to an artboard, or an artboard's label in `artboards.tsv` names it. Another type in the same file
as a drawn screen does not count. Two exceptions to INVENTORY: the Settings artboard (1ab)
draws the hub, so its 14 pages are counted here (this file's first version did the same); and
INVENTORY's Library filter panel "(1an style)" names a style, not an artboard. Judgement calls
counted as *drawn* because INVENTORY files them under an artboard: the collection page and its
reorder sheet (under 1bk, which draws the new/edit sheets), the editor's recovery sheet (part of
`WritingTextEditor`, 1bv), the preferences help sheet (part of `AO3PreferencesView`, 1z) and the
tag-set editor (part of `TagSetView`, 1ch). If the owner counts them as without a mockup, they
are `collection` (matched, A76), and `collectionreorder`, `recovery`, `prefhelp` and
`tagseteditor` (A82 pending). `LegalNoticesView` and the reader's fan menu, in this file's
first version, are not screens (A81: the first is never presented; the second is part of the
reader's chrome, R9).

## Rules for a best-effort redesign

- Use the shared redesign parts only: on Android `ui/subject/` (`SubjectHeaderBlock`,
  `SectionRuleHeader`, `subjectPanel`, `SubjectFormRow`, `SubjectToggle`,
  `SubjectSegmentedControl`, `subjectScreenWash`, the chips and cards); on iOS
  `UIComponents/SubjectSurface.swift`, `SubjectForm.swift`, `cardRow`.
- Keep every control, figure and line of text the screen had, in the same order unless the
  redesign's grammar elsewhere orders it differently (then say so below).
- Android's navigation and chrome stay Material 3 (owner, 2026-10-04).
- Where iOS already restyled the screen, Android follows iOS and the entry says so. Where
  neither had, both apps get the same redesign (or the entry names the side still to follow).
- Each entry: what it was, what it is now, the screen on the other app it matches, what was kept,
  the commit(s), and how it was seen (theme, text size, device).

## Screens with no artboard, and where each stands

Paths are A81's: iOS under `kudos-ao3-reader/`, Android under
`android/app/src/main/java/io/github/cidy02/kudos/`. **matched** = compared side by side in an
A-audit (named); **A82 pending** = in `audits/A82-shots.md` (its shot name), not yet compared;
**not compared** = with the reason. "R*n*" is the redesign entry below.

| Screen | iOS file | Android file | Status | Entry |
|---|---|---|---|---|
| Library filter panel | `Features/Library/LibraryFilterPanel.swift:7` | `library/LibraryFilterPanel.kt:67` | matched: A80 (minor: height, fixed in `cde116dd`) | R1 |
| Library option picker (Fandoms, Tags…) | `LibraryFilterPanel.swift:231` `LibraryOptionPicker` | `library/LibraryFilterPanel.kt:300` (sheet in `LibraryMultiSelectRow`) | A82 pending (`libpicker`) | R2 |
| Edit queue sheet | `Features/Library/NewReadingQueueSheet.swift:353` `EditReadingQueueSheet` | `library/QueueEditorSheet.kt:62` | A82 pending (`editqueue`) | R3 |
| Add works sheet | `Features/Library/AddLibraryWorksSheet.swift:13` | `library/AddLibraryWorksSheet.kt:67` | A82 pending (`addworks`) | R4 |
| Bulk tag sheet | `UIComponents/WorkBulkTagSheet.swift:15` | `library/QueueTags.kt:117` | A82 pending (`bulktag`) | R5 |
| Add to queue | `Features/Library/ReadingQueues.swift:438` `AddToQueueView` | `works/detail/WorkDetailForms.kt:196` `WorkDetailQueueForm` (work page); `ui/components/WorkBulkActionBar.kt:263` `QueuePickerDialog` (lists) | A82 pending (`addtoqueue`, on the work page) | R6 |
| Queue Storage | `Features/Library/ReadingQueues.swift:257` `ReadingQueueStorageView` | `settings/QueueStorageScreen.kt:67` | A82 pending (`queuestorage`) | R7 |
| Collections See All grid | `Features/Library/LibraryView.swift:115` (`LibraryEntityGridView`) | `library/CollectionsScreen.kt:55` | matched: A76 (`collections`) | R8 |
| Add to collection | `Features/Library/Collections.swift:600` `AddToCollectionView` | `library/WorkMembershipDialogs.kt:50` `AddToCollectionDialog` | A82 pending (`addtocollection`) | none: Android keeps its dialog; no restyle on record (`dc3d2e31` moved it unchanged) |
| Downloaded date editor | `Features/WorkDetail/WorkDetailSections.swift:571` | `works/detail/WorkDetailMyCopySheet.kt:530` `DownloadedDateEditorDialog` | A82 pending (`downloaddate`) | none: added in `d994a180` (T-353, iOS's rules); its look is not recorded |
| Series preservation prompt | `Features/WorkDetail/WorkDetailView.swift:1193` | `works/detail/WorkDetailForms.kt:168` | A82 pending (`seriespreserve`) | R6 |
| Bookmark form | `Features/WorkDetail/AO3WorkActionsModel.swift:189` `AO3BookmarkComposer` | `works/detail/WorkDetailForms.kt:125` | A82 pending (`bookmarkform`) | R6 |
| Reader, its chrome, position card, scrub | `Features/ReaderReadium/ReadiumReaderView.swift:17` | `reader/ReaderScreen.kt:140` | matched: A76 (`reader`) | R9 |
| Reader Contents (and Bookmarks & Highlights) | `Features/ReaderReadium/ReaderContentsSheet.swift:42` | `reader/ReaderContentsSheet.kt:57` | A82 pending (`readercontents`) | R10 |
| Find in Work | `Features/ReaderReadium/ReaderSearchView.swift:229` | `reader/ReaderSearchSheet.kt:98` | A82 pending (`readerfind`) | R11 |
| Display & Themes | `Settings/SettingsView.swift:15` `ReaderOptionsForm` | `reader/ReaderScreen.kt:1052` `ReaderDisplaySheet` | A82 pending (`readerdisplay`) | R12 |
| Note editor | `Features/ReaderReadium/ReaderNoteEditor.swift:8` | `reader/ReaderNoteEditor.kt:59` | A82 pending (`readernote`) | R13 |
| Read Aloud settings sheet | `Features/ReaderReadium/ReaderSpeechSettingsSheet.swift:12` | none: the settings are on Settings › Listening (paired `s_listening`); a long press on the fan opens Display & Themes | not compared: no Android sheet (A81) | none |
| Pronunciations | `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:16` | `settings/PronunciationSettings.kt:60` | A82 pending (`pronunciations`) | R14 |
| Pronunciation editor | `ReaderPronunciationSettingsView.swift:338` `ReaderPronunciationEditor` | `settings/PronunciationSettings.kt:141` | A82 pending (`pronunciationedit`) | R14 |
| Speech developer settings | `Features/ReaderReadium/ReaderSpeechDeveloperSettingsView.swift:19` | none | not compared: not ported, a recorded decision (DECISIONS 2026-10-05, Listening; `fcba3075`) | none |
| Customize Theme | `Features/Reader/CustomizeThemeView.swift:11` | `reader/CustomizeThemeSheet.kt:66` | A82 pending (`customizetheme`) | R15 |
| Comments' chapter picker | `Features/Comments/CommentsView.swift:326` | `comments/CommentsScreen.kt:752` `ChapterPickerSheet` | A82 pending (`chapterpicker`) | R16 |
| Remove works from a series | `Features/Writing/SeriesEditView.swift:441` `SeriesRemoveWorksView` | `writing/WritingSeriesScreen.kt:37` ("Remove works") | A82 pending (`seriesremove`) | R17 |
| Challenge sign-up detail | `Features/Challenges/ChallengeSignUpsView.swift:546` `ChallengeSignUpDetailView` | `account/AO3ChallengeSignUpsScreen.kt:234` `ChallengeSignUpDetail` | A82 pending (`chsignupdetail`) | none: added with the sign-ups list (`f17ed651`); its look is not recorded |
| Co-creators picker | `Features/Writing/WorkAssociationPickers.swift:516` | `writing/WritingAssociationPickers.kt:47` | A82 pending (`creatorspicker`) | R18 |
| Parent work picker | `WorkAssociationPickers.swift:627` | `writing/WritingAssociationPickers.kt:47` | A82 pending (`parentpicker`) | R18 |
| Bulk edit's name lists | `Features/Writing/BulkTagStatePicker.swift:135` `BulkNameListEditor` | inline on `writing/WritingBulkEditScreen.kt:30` (A81: no separate editor) | A82 pending (`bulknames`) | none: Android keeps them on the form (`9e1fa2a8`); no restyle on record |
| Settings › Appearance | `Settings/SettingsReadingPages.swift:9` | `settings/SettingsPages.kt:39` | matched: A76 (`s_appearance`) | R19 |
| Settings › Font | `Settings/SettingsReadingPages.swift:72` | `settings/SettingsPages2.kt:457` | matched: A76 (`s_font`) | R19 |
| Settings › Reader | `Settings/SettingsReadingPages.swift:84` | `settings/SettingsPages.kt:140` | matched: A76 (`s_reader`) | R19 |
| Settings › Listening | `Settings/SettingsReadingPages.swift:95` | `settings/SettingsListeningPage.kt:41` | matched: A76 (`s_listening`) | R19 |
| Settings › Downloads | `Settings/SettingsStoragePages.swift:8` | `settings/SettingsPages.kt:189` | matched: A76 (`s_downloads`) | R19 |
| Settings › Preservation | `Settings/SettingsStoragePages.swift:37` | `settings/SettingsPages2.kt:165` | matched: A76 (`s_preservation`) | R19 |
| Settings › Reading Queues | `Settings/SettingsStoragePages.swift:84` | `settings/SettingsPages2.kt:409` | matched: A76 (`s_queues`) | R19 |
| Settings › Library | `Settings/SettingsStoragePages.swift:63` | `settings/SettingsPages2.kt:101` | matched: A76 (`s_library`) | R19 |
| Settings › Backup | `Settings/SettingsBackupPage.swift:33` | `backup/BackupScreen.kt:59` | matched: A76 (`s_backup`) | R19 |
| Settings › Sync Folder | `Settings/SettingsSyncFolderPage.swift:8` | `settings/SettingsPages2.kt:636` | matched: A76 (`s_sync`) | R19 |
| Settings › Import Files | `Settings/SettingsImportPage.swift:7` | `settings/SettingsPages2.kt:133` | matched: A76 (`s_import`) | R19 |
| Settings › AO3 Account | `Settings/SettingsAccountPages.swift:6` | `settings/SettingsPages2.kt:188` | matched: A76 (`s_account`) | R19 |
| Settings › Privacy | `Settings/SettingsAccountPages.swift:22` | `settings/SettingsPages2.kt:242` | matched: A76 (`s_privacy`) | R19 |
| Settings › About | `Settings/SettingsAccountPages.swift:56` | `settings/SettingsPages2.kt:303` | matched: A76 (`s_about`) | R19 |
| Check Availability | `Features/Account/AvailabilitySweepView.swift:9` | `settings/AvailabilitySweepScreen.kt:54` | A82 pending (`availability`); put beside the iPhone's in 3dk (`bd3926f7`): "the same" | R20 |
| Pair a Device | `Settings/PairingSheet.swift:248` | `backup/PairingSheet.kt:277` | A82 pending (`pairing`) | R21 |
| Scan a QR Code | `Settings/PairingSheet.swift:417` `QRScannerSheet` | none | not compared: Android only shows a code, a recorded decision (DECISIONS 2026-10-11, Settings compared) | none |
| Sync Details | `Settings/SettingsSyncFolderPage.swift:229` `FolderSyncDetailsView` | none (the counts are on the Sync Folder page) | not compared: kept out, a recorded decision (DECISIONS 2026-10-11; iOS calls it development diagnostics) | none |
| Revoke a device | `Settings/PairingSheet.swift:211` `RevokeDeviceSheet` | none as its own sheet (A81) | A82 pending (`revokedevice`) | none |
| Backup import | `Settings/BackupImportSheet.swift:15` | the import step of `backup/BackupScreen.kt:59` | A82 pending (`backupimport`) | R22 |
| In-app AO3 web view | `Features/Browse/BrowseView.swift:8` `AO3WebBrowserView` | `web/AO3WebViewFallbackScreen.kt:64` | not compared: needs AO3 (A81: the demo does not serve those pages); not in A82 | R23 |
| Welcome | `Features/Onboarding/WelcomeView.swift:7` | `onboarding/WelcomeScreen.kt:50` | matched: A76 (`welcome`) | R24 |
| Sync-folder onboarding | `Features/Onboarding/SyncFolderOnboardingView.swift:8` | `onboarding/SyncFolderOnboardingScreen.kt:51` | matched: A76 (`synconb`) | R24 |
| What's New | `Features/Support/WhatsNew.swift:59` | `support/WhatsNew.kt:54` | matched: A76 (`whatsnew`) | R25 |
| Report a Bug | `Features/Support/BugReportView.swift:11` | `account/BugReportScreen.kt:83` | matched: A76 (`bugreport`) | R26 |
| About Kudos | `Settings/AboutView.swift:5` | `account/AboutScreen.kt:42` | A82 pending (`aboutkudos`) | R27 |

Android-only screens: A81 found none reachable without a counterpart. `author/AuthorWorksScreen.kt`
is registered but never opened.

## Redesigned screens

The 14 Settings pages share one entry (R19), so their one restyle is told once. "Seen" quotes the commit or audit; "not recorded" means neither says.

### R1 · Library filter panel
- **Was:** the old Material "Filter and Sort" sheet, with other filters than iOS's.
- **Now:** iOS's "Filters" panel, drawn like the other redesigned sheets. In order: Sort by and Rating; Warnings and Categories as rows to tick; Completion and Language; a word-count range; then Tags (Your Tags, Fandoms, Characters, Relationships, Additional Tags, Exclude Tags). Reset and Done are header icons, as on iOS. It now opens full height, as iOS's (its scroll area had stopped at 520dp).
- **Matches:** iOS `LibraryFilterPanel`.
- **Kept:** Android's extra controls (the file's header: "with Android's extra controls retained"). Rating, language, word count and Exclude Tags were added to Android's filtering. The red checkmark is the decided section wash, and the picker rows are Material chrome (A80 triage).
- **Commits:** `f103ad47` (3af), `cde116dd` (full height).
- **Seen:** A80 `libraryfilters`, minor (the sheet's height), fixed in `cde116dd`, which was seen on the emulator in Dark, Light, Sepia, OLED and 2.0x.

### R2 · Library option picker
- **Was:** part of the old Material sheet.
- **Now:** each Tags row opens a searchable list of what the library holds, as iOS's `LibraryOptionPicker`.
- **Kept:** not recorded.
- **Commits:** `f103ad47` (3af).
- **Seen:** not recorded. The A82 shot `libpicker` opens it.

### R3 · Edit queue sheet
- **Was:** not recorded (pre-redesign).
- **Now:** one New/Edit Queue sheet. It has five swatches and an HSV picker that stores `colorHex` exactly, plus a live wash. Since 3dy it has iOS's tag row with a "+ New tag" chip and iOS's wording ("Copy 1 work").
- **Matches:** iOS `EditReadingQueueSheet` / `NewReadingQueueSheet`.
- **Kept:** not recorded beyond the commit. The description is written as it is typed (3dy).
- **Commits:** `dc18d01b` (3c), `a9ba9fae` (3dy).
- **Seen:** on the emulator. Pictures are in `docs/android-port/shots/3dy/`.

### R4 · Add works sheet
- **Was:** a queue's picker was a bare list of titles: no search, no authors, one work per tap. A collection's picker named mature works that Hide Mature keeps out.
- **Now:** one sheet for queues and collections, as iOS's. It reads "Add to <name>" and has "Search your library" (Global Search's matching). Several works can be chosen and are added in the order shown. It uses iOS's empty states and names only works the Library may name; "Show mature" sits behind the usual lock.
- **Matches:** iOS `AddLibraryWorksSheet`.
- **Kept:** adding to both kinds of list.
- **Commits:** `cf33b96a`, `af14c5f7` (3fp part 2, menus and pickers).
- **Seen:** not recorded.

### R5 · Bulk tag sheet
- **Was:** Android could not tag several works at once. The queue's tag sheet already had this design (3c).
- **Now:** iOS's bulk tag sheet. Each tag shows whether it is on every selected work, on some, or on none. A tap puts it on the rest, or takes it off all of them when it was on all. A typed tag is added. The queue and the Library share one sheet.
- **Matches:** iOS `WorkBulkTagSheet`. The commit calls it "artboard 1af", but the index lists 1af as Reading Now's select mode, and no row names this sheet.
- **Kept:** local only, as before.
- **Commits:** `dc18d01b` (3c), `bd92c3ae` (3ck part 1).
- **Seen:** on the emulator.

### R6 · Work page sheets: Add to queue, series preservation, bookmark
- **Was:** old Material dialogs. The Auto-preserve setting and its threshold did nothing.
- **Now:** Add to Queue and the bookmark sheet use iOS's fields and words. Save for Later on a work in a series offers "Preserve Series?", or preserves a small series on its own when the setting is on. Text actions use the palette's accent.
- **Matches:** iOS `AddToQueueView`, `AO3BookmarkComposer`, `SeriesPreservationPromptSheet`.
- **Kept:** a refused bookmark keeps what was typed. The lists' Add to Queue is still `QueuePickerDialog`: `44b5fb56` made it shared, and no restyle of it is on record.
- **Commits:** `3178634a` (3bn).
- **Seen:** not recorded.

### R7 · Queue Storage
- **Was:** a Material screen with two back buttons, cards, and a pull-to-refresh that did nothing.
- **Now:** iOS's screen in the Settings design: the summary, the downloaded queued works, iOS's wording for the empty list, the footnote and the confirmation. A work in Saved for Later shows the clock.
- **Matches:** iOS `ReadingQueueStorageView`.
- **Kept:** the swipe and what it removes. A hold menu was added (Keep Download, Remove from Reading Queues), as iOS has.
- **Commits:** `32e513a6` (brief 6a).
- **Seen:** on the emulator in three themes and at the largest text, with the hold menu and the swipe's confirmation.

### R8 · Collections See All grid
- **Was:** not recorded (pre-redesign).
- **Now:** a subject header and iOS's collection cards: a glass panel holding a 2×2 mosaic of the newest works, faint empty slots, and an empty collection keeping its own colour. The toolbar "+" is glass with an accent glyph. The header lines up with the tiles (3cm), and the mosaic stays 2×2 at large text (3gm).
- **Matches:** iOS `LibraryEntityGridView`. iOS restyled it on its own side (T-308 header, T-310 cards to spec 1c).
- **Kept:** queue-only works count in a collection's preview, as on iOS.
- **Commits:** `a3d57c89` (3e), `8fa5b030`, `9f5aab91` (3cm), `1bbefdfd` (3gm).
- **Seen:** `8fa5b030` was checked against the iOS simulator, and 3cm on the emulator in Sepia (`shots/3cm/`). A76 `collections` matched in all five columns.

### R9 · Reader, chrome, position card, scrub
- **Was:** not recorded (pre-redesign).
- **Now:** iOS's chrome. A floating glass close circle; a title/author pill that opens Work Details; the fan menu with iOS's five pills (Contents, Bookmarks & Highlights, Find in Work, Comments, Themes & Settings) and round actions (Share, Kudos, Read Aloud, Rotation Lock, Bookmark). The position card shows the page within the chapter and both remaining times, and its thumb seeks within the chapter (3br). The back and fan buttons sit where every page's do (3dk, owner 2026-10-12; iOS's same fix is T-403). Read Aloud's mini-player stays when the chrome is hidden (3gf).
- **Matches:** iOS `ReadiumReaderView`, `ReaderChromeTopBar`, `ReaderPositionCard`, `ReaderChapterScrub`.
- **Kept:** reading-position code is untouched, and swipe-down-to-dismiss was restored. Mark finished moved to the work's page, as on iOS.
- **Commits:** `40dd6ff7` (3j), `925f7322` (3ao), `62f3929c` (3br), `bd3926f7` (3dk), `2c5117d5` (3gf).
- **Seen:** 3j was compared with the simulator. A76 `reader` matched in all five columns.

### R10 · Reader Contents
- **Was:** Material tabs, with no title or Done.
- **Now:** a segmented sheet with iOS's empty states, a title and Done, the app's segmented control, and where each chapter starts in the work. The Done ticks of the three reader sheets share one accent.
- **Matches:** iOS `ReaderContentsSheet`.
- **Kept:** not recorded.
- **Commits:** `40dd6ff7` (3j), `6e0ca75d` (3dl).
- **Seen:** on the emulator in the reader's Sepia and Dark and at 2.0x (`shots/3dl/`).

### R11 · Find in Work
- **Was:** the earlier search, with a 200-hit cut-off.
- **Now:** a reader-themed sheet. It searches after a pause; results are grouped by chapter with the current chapter first, the match in bold with its context, and more results as the list scrolls. A tap jumps to the passage. Swiping a result offers Go, Bookmark and Copy, which are also accessibility actions. The strings are iOS's.
- **Matches:** iOS `ReaderSearchView`. iOS has no scope choice and searches from one letter, and Android follows that.
- **Kept:** not recorded.
- **Commits:** `7328d1e9` (3ai).
- **Seen:** on the emulator. Not yet seen: a work with matches in several chapters.

### R12 · Display & Themes
- **Was:** a loose column of Material chips, sliders and a switch, titled "Display".
- **Now:** iOS's sheet: Appearance (theme, Customize Theme), Text Size, Reading (layout, keep screen awake), Read Aloud and Font. It uses the Settings pages' panels and the reader's theme, with Done. The font list offers imported fonts and Add Font (3gf).
- **Matches:** iOS `ReaderOptionsForm`.
- **Kept:** every control writes the same settings as before. The two-page spread is hidden on a phone, as on iOS. What iOS has and Android still lacks is listed in `briefs/3y-result.md`.
- **Commits:** `f29dd32e` (3y), `2c5117d5` (3gf).
- **Seen:** on the emulator (sections, a theme change, layout, fonts, Done).

### R13 · Note editor
- **Was:** tapping a highlight only toggled the chrome, a note was kept only on Done, and Add Note went through a confirm dialog.
- **Now:** tapping a highlight opens its editor (the passage, a note, the colour, Delete Highlight). Add Note opens the full editor, and Highlight marks the passage at once with a one-tap colour bar. A typed note is kept unless Cancel is tapped (3dz, both apps).
- **Matches:** iOS `ReaderNoteEditor` and `createAnnotationFromSelection`.
- **Kept:** the existing repository calls.
- **Commits:** `c28c9f56` (3ar), `b6ba98da` (3dz), `c6b0576a` (3fs).
- **Seen:** on the emulator with a real page (3ar), and the keep case (3dz).

### R14 · Pronunciations and the pronunciation editor
- **Was:** missing on Android; the backup key was only passed through.
- **Now:** iOS's word → IPA list (global, per fandom, per work) and its editor, under Settings › Listening and from the selection menu's Fix Pronunciation.
- **Matches:** iOS `ReaderPronunciationSettingsView`, `ReaderPronunciationEditor`.
- **Kept:** the backup and sync key, now read and written with iOS's merge rule. Android does not play corrections yet, because the bundled Kokoro pack ignores a lexicon; the page says so (DECISIONS).
- **Commits:** `c62201d0` (3ft).
- **Seen:** not recorded.

### R15 · Customize Theme
- **Was:** not recorded.
- **Now:** both Customize Theme rows (Appearance and the reader) open one reading-text sheet. It has iOS's sample, four themes, font, Bold Text, Customize, the four layout sliders, Justify and Reset Theme. Customize gates layout only, as on iOS.
- **Matches:** iOS `CustomizeThemeView`.
- **Kept:** accent presets stay under Accent Color.
- **Commits:** `c6b0576a` (3fs, owner Q29/Q30).
- **Seen:** on the emulator (this file's first version).

### R16 · Comments' chapter picker
- **Was:** not recorded (pre-redesign).
- **Now:** part of the redesigned Comments: the chapter and sort filter rail with its chapter picker.
- **Matches:** iOS's chapter picker sheet in `CommentsView`.
- **Kept:** pagination and every action.
- **Commits:** `5473a54a` (3k).
- **Seen:** not recorded for the picker. The A82 shot `chapterpicker` opens it.

### R17 · Remove works from a series
- **Was:** missing on Android.
- **Now:** part of iOS's series form on Android (Edit series, Reorder, Remove from series). It is offered only for a series the account owns.
- **Matches:** iOS `SeriesRemoveWorksView`.
- **Kept:** —
- **Commits:** `afdf6165` (3bw).
- **Seen:** "Not seen on the emulator" (the commit).

### R18 · Co-creators and parent work pickers
- **Was:** the form's rows opened nothing.
- **Now:** iOS's association screens: pseuds and a co-creator's byline, and the source work and its translation.
- **Matches:** iOS `WorkCreatorsPickerView`, `WorkParentWorkPickerView`.
- **Kept:** changes go into the form in memory, and nothing is sent until saved.
- **Commits:** `05f666dc` (3bj).
- **Seen:** not recorded.

### R19 · The 14 Settings pages
- **Was:** Material pages. The first port (3i) had a doubled title, and Backup was still the old Material screen.
- **Now:** each page has the Settings kicker and title below the back circle, iOS's field labels, rows and footnotes, and `SubjectSegmentedControl` for Theme, Reader and Privacy (3i-fix3). The pages sit on the plain page colour; the wash belongs to the hub (3gg). Groups are on card surfaces, as iOS's grouped form (A70).
- **Matches:** iOS `Settings/*Page*.swift`. iOS gave the same pages card rows (T-330).
- **Kept:** every old control (`SettingsStringsTest`, 3i-fix3). The A76 excluded list records Android's extras: the System theme, Backup's notes and Deletion signing (owner question 9), the imported Demo font, and About's Software Update section.
- **Seen:** 3i-fix3 compared all 13 then-existing pages with the iOS shots. A69 (Gemini, Dark, Light, Sepia, OLED and the largest text) found the wash, the doubled Backup title and Sync Folder's missing metadata row, fixed in 3gg and A70. A70b and A72 compared again, and A76 matched every page in all five columns.

| Page | Commits beyond the shared ones (`5d58945c` 3i, `ae7401da` 3i-fix3, `e306895e` 3gg, `701595c9` A70) |
|---|---|
| Appearance | `ae7401da` (accent colour well, Reset); `c6b0576a` (Customize Theme row, R15) |
| Font | none recorded |
| Reader | `ca1d4bce` (Keep screen awake, as iOS) |
| Listening | `2ca6f55b` (3ak: Audition Voice, voice pack, Read Aloud); `30358bd2` (3di: speeds side by side); `fcba3075` (3gd: Kokoro download, Engine, Pitch; Developer Settings stay out); `1bbefdfd` (3gm: "Kokoro Neural Engine") |
| Downloads | `145a2b94` (Download on subscribe, as iOS) |
| Preservation | `a4b37200` (its row opens Check Availability, R20) |
| Reading Queues | `ae7401da` (auto-preserve and series limit 2–25); `e306895e` (the disabled stepper reads in every theme) |
| Library | none recorded |
| Backup | `6c2f1609` (6b: a Settings page, import and Replace sheets, R22); `e306895e` (one header, no wash band) |
| Sync Folder | `2f00aa6a` (iOS's rows: Folder, Auto Sync, Sync Now, Change Folder, Disconnect); `e306895e` (metadata state and its action) |
| Import Files | none recorded |
| AO3 Account | `6dbbd1f7` (Log Out asks first, with iOS's confirmation); `701595c9` (Signed In row green with its check) |
| Privacy | none recorded |
| About | none recorded |

### R20 · Check Availability
- **Was:** the check started the moment the Preservation row was tapped, and the screen was a list under a Material title bar.
- **Now:** iOS's screen. It states the cost first ("Before you start": how many works, why one at a time, which cannot be checked), then Check Now, progress, the result, and the works no longer on AO3.
- **Matches:** iOS `AvailabilitySweepView` (iOS moved Done to the trailing edge in T-330).
- **Kept:** the check itself. A check stopped mid-request returns its summary.
- **Commits:** `a4b37200` (brief 6a).
- **Seen:** put beside the iPhone's in 3dk (`bd3926f7`): "the same".

### R21 · Pair a Device
- **Was:** part of the old Material Backup screen.
- **Now:** a sheet in the Settings design, from the Sync Folder page's pairing section (the page uses the Backup page's section, DECISIONS 2026-10-04).
- **Matches:** iOS `PairingSheet`.
- **Kept:** pairing works as before. Android shows a code and never scans one (decision).
- **Commits:** `6c2f1609` (6b).
- **Seen:** not recorded.

### R22 · Backup import
- **Was:** part of the old Material Backup screen.
- **Now:** an import sheet listing what the backup holds (iOS's five counts) and Merge. Replace Library has a review step of its own with iOS's five work counts, the acknowledgement, the pause-sync offer and the recovery text.
- **Matches:** iOS `BackupImportSheet`.
- **Kept:** every action calls the same repository functions with the same arguments, order and conditions (`briefs/6b-result.md`). Three guards were added and none removed.
- **Commits:** `6c2f1609` (6b).
- **Seen:** not recorded.

### R23 · In-app AO3 web view
- **Was:** without those controls (A63 F13 found them missing).
- **Now:** iOS's controls: an address/search field, Reload, Add Bookmark and Done. An EPUB downloaded in it is imported.
- **Matches:** iOS `AO3WebBrowserView`.
- **Kept:** —
- **Commits:** `72158be6` (3fq part 2, A63 F13/F14).
- **Seen:** the controls on the emulator (DECISIONS 2026-10-16). Not compared side by side, because it needs AO3.

### R24 · Welcome and sync-folder onboarding
- **Was:** text that had drifted from iOS's in almost every sentence.
- **Now:** iOS's text, with titles in bold (3dk).
- **Matches:** iOS `WelcomeView`, `SyncFolderOnboardingView`.
- **Kept:** "a cloud storage app" where iOS names iCloud Drive. Android's checkbox where iOS has a switch, and the icon art, are on A76's excluded list.
- **Commits:** `01787663` (3ax), `bd3926f7` (3dk).
- **Seen:** put beside the iPhone's in 3dk: "the same". Compared in A71 and A72; A76 matched in all five columns.

### R25 · What's New
- **Was:** missing on Android.
- **Now:** shown once after an update; it fills its sheet, with a centred title (3gh).
- **Matches:** iOS `WhatsNewView`.
- **Kept:** —
- **Commits:** `01787663` (3ax), `be73a737` (3gh).
- **Seen:** put beside the iPhone's in 3dk (`bd3926f7`): "the same". Compared in A71 and A72; A76 matched in all five columns.

### R26 · Report a Bug
- **Was:** the old Material screen: a title bar, Material buttons, an outlined text field.
- **Now:** iOS's screen. A shake also grabs the screen and offers to include it, as on iOS.
- **Matches:** iOS `BugReportView`.
- **Kept:** what it collects and what it opens. From About it is a pushed page; opened by a shake it keeps a Cancel.
- **Commits:** `75af1256` (6a), `2f00aa6a`.
- **Seen:** A76 `bugreport` matched in all five columns.

### R27 · About Kudos
- **Was:** the old Material screen.
- **Now:** iOS's screen: the identity panel with the version (and the commit, on a build that knows it), License, Open-Source Components, Help & Feedback and Disclaimer, in iOS's wording with "Android" for "Apple".
- **Matches:** iOS `AboutView`.
- **Kept:** —
- **Commits:** `75af1256` (6a).
- **Seen:** not recorded. The A82 shot `aboutkudos` opens it.
