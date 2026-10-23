# A88c: Re-shot Screens Audit (Gemini)

## Counts

- **Total screens reviewed**: 41
- **Match**: 33 (`readercontents`, `readerfind`, `readerdisplay`, `readernote`, `customizetheme`, `formattingtray`, `chapterpicker`, `pronunciationedit`, `seriesedit`, `seriesremove`, `authorworksfilter`, `colitems`, `chsignupdetail`, `chapters`, `tagseditor`, `seriespicker`, `creatorspicker`, `bulkedit`, `bulktagstate`, `backupimport`, `queuetags`, `fandomworks`, `tagworks`, `newqueue`, `editqueue`, `collectiondetails`, `pagejump`, `pronunciations`, `seriesreorder`, `revokedevice`, `colsfilter`, `tagset`, `tagseteditor`)
- **Minor**: 6 (`addworks`, `texteditor`, `collectionsgifts`, `parentpicker`, `newcollection`, `collectionreorder`)
- **Differs**: 2 (`readerspeech`, `chsettingsedit`)
- **Capture problems**: 4 (`formattingtray`, `pronunciationedit`, `pronunciations`, `revokedevice`)

## Differs

- **`readerspeech`**: Largest column, iPhone — truncates the `Sample Text` picker value in the middle to `Plain...rration` (while Android stacks `Sample Text` and `Plain Narration` in full), and in the Light and Sepia columns on iPhone the selected `1.0x (default)` speed pill draws near-white text on a pale fill, making it nearly illegible (A88's Android Home capture problem is gone).
- **`chsettingsedit`**: All columns, Android (pre-3ha tile) — iPhone's AX5 capture problem is gone and all five iPhone columns render `Challenge settings` cleanly, while the pair in this tile still differs against the pre-3ha Android columns (`Save changes` is an unpinned left-aligned card row on Android instead of iPhone's pinned filled button, the subtitle omits `· 4 sign-ups`, and Android's 2.0× column omits the `SIGN-UP INSTRUCTIONS` and `SCHEDULE` sections).

## Minor

- **`addworks`**: All columns, Android — work bylines omit the leading `by` and colour the second author (`undertow`) in the accent while the first (`uncle_iroh_fan`) is grey (A88's iPhone largest-column byline and title truncations and Android's Light capture problem are gone).
- **`texteditor`**: All columns, Android — the top bar still displays a truncated `Chapter ...` / `Cha...` title where iPhone has no bar title (naming the field in the kicker below), and on iPhone in the largest column the editor viewport above the recovery footer is one line tall (A88's missing `Done` `✓` button at 2.0× on Android and Dark/OLED ANR capture problems are gone).
- **`collectionsgifts`**: Dark, Light, Sepia, and OLED columns, Android — a gift recipient's remove icon is a red `×` instead of iPhone's red `⊖` (A88's Android Dark ANR, Sepia Home, and incomplete collection-list capture problems are gone).
- **`parentpicker`**: Largest column, iPhone — the wrapped URL inside the `SOURCE WORK` `URL` text field still inserts a system hyphen mid-domain (`https:// / archiveo- / fourown.org/ / works/1`) while Android wraps without hyphenation, so A88's minor hyphenation difference on iPhone is not gone (the header subtitle above `SOURCE WORK` has no hyphen, and A88's Android Light capture problem is gone).
- **`newcollection`**: All columns, Android — separates `NAME` and `DESCRIPTION` with subheaders above outlined fields and places the colour swatches on the page below instead of iPhone's single `COLLECTION` card (A88's 2.0× `New collect…` bar-title truncation and swatch-opacity difference on Android are gone).
- **`collectionreorder`**: All columns, Android — draws each numbered work row as its own separate card instead of iPhone's single grouped card with dividers (A88's `⌃`/`⌄` move-button difference on Android is gone, now using drag handles).

## Capture problems

- **`formattingtray`**: Sepia column, Android — shows the `New comment` composer sheet without the `Formatting` tray open (A88's Dark, Light, and 2.0× Android capture problems are gone).
- **`pronunciationedit`**: Largest column, iPhone — stayed on `Settings › Listening` without opening `Pronunciations` or `Add Pronunciation` (A88's Android OLED capture problem is gone).
- **`pronunciations`**: Largest column, iPhone — stayed on `Settings › Listening` without opening `Pronunciations` (A88's iPhone Light capture problem is gone).
- **`revokedevice`**: OLED column, Android — stayed on `Sync Folder` without the `Revoke Demo reading tablet?` dialog open (Android was not re-shot for this tile).

## Per-screen verdicts

1. **`readercontents`**: **match** — A88's Android Home capture problem and A82's inline `Bookmark` / `Add Note` row buttons (which crushed chapter titles at 2.0× on Android) are gone.
2. **`readerfind`**: **match** — A88's Android Home capture problem and A82's 2.0× blank-screen capture problem on Android are gone.
3. **`readerdisplay`**: **match** — A88's Android Home capture problem is gone.
4. **`readernote`**: **match** — A88's Android Home capture problem and A82's Dark/2.0× capture problems on Android are gone.
5. **`readerspeech`**: **differs** — Largest column, iPhone: truncates the `Sample Text` picker value to `Plain...rration` (while Android stacks `Sample Text` and `Plain Narration` in full), and in the Light and Sepia columns on iPhone the selected `1.0x (default)` speed pill draws near-white text on a pale background, making it nearly illegible; A88's Android Home capture problem is gone.
6. **`addworks`**: **minor** — All columns, Android: work bylines omit the leading `by` and draw the second author (`undertow`) in the accent colour while the first (`uncle_iroh_fan`) is grey; A88's iPhone largest-column byline and title truncations and Android's Light capture problem are gone.
7. **`customizetheme`**: **match** — All four A88 Android capture problems (Dark ANR dialog, Light blank black preview box, and missing sheets in OLED and 2.0×) and A82's rectangular swatch-bar difference are gone.
8. **`formattingtray`**: **match** — A88's minor difference (missing `Done` button in the tray header on Android) and A88's Dark, Light, and 2.0× Android capture problems are gone. Capture problem: Sepia column, Android — shows the `New comment` composer without the `Formatting` tray open.
9. **`chapterpicker`**: **match** — A88's minor difference (separate cards per row on Android instead of one grouped card), A88's Android OLED capture problem, and A82's iPhone largest-column truncation are gone.
10. **`pronunciationedit`**: **match** — A88's Android OLED capture problem and A82's duplicate field labels on Android are gone (Android's footer notes are decided). Capture problem: largest column, iPhone — stayed on `Settings › Listening` without opening `Pronunciations` or `Add Pronunciation`.
11. **`seriesedit`**: **match** — A88's Android Dark and Sepia capture problems are gone.
12. **`seriesremove`**: **match** — A88's Android Sepia capture problem and stray Light-column `Save` button are gone (Android's `words · date` line is decided).
13. **`authorworksfilter`**: **match** — A88's Android Dark, Sepia, and OLED capture problems and A82's extra `Direction` label on Android are gone.
14. **`colitems`**: **match** — A88's iPhone card-footer creator truncation (`AO3_Reader…`) and Android's Dark ANR capture problem are gone.
15. **`chsignupdetail`**: **match** — A88's Android 2.0× ANR capture problem is gone.
16. **`chapters`**: **match** — A88's Android capture problems across all five columns are gone.
17. **`tagseditor`**: **match** — A88's Android Dark, Light, and OLED ANR capture problems are gone.
18. **`texteditor`**: **minor** — All columns, Android: the top bar still shows a truncated `Chapter ...` / `Cha...` title (where iPhone has no bar title, naming the field in the kicker below), and on iPhone in the largest column the editor viewport above the recovery footer is one line tall; A88's missing `Done` (`✓`) button at 2.0× on Android and Dark/OLED ANR capture problems are gone.
19. **`seriespicker`**: **match** — A88's Android Dark capture problem is gone.
20. **`collectionsgifts`**: **minor** — Dark, Light, Sepia, and OLED columns, Android: a gift recipient's remove icon is a red `×` instead of iPhone's red `⊖`; A88's Android capture problems (Dark ANR, Sepia Home, and Dark/OLED listing only 2 of 5 collections) are gone.
21. **`creatorspicker`**: **match** — A88's Android 2.0× capture problem is gone.
22. **`parentpicker`**: **minor** — Largest column, iPhone: the wrapped URL inside the `SOURCE WORK` `URL` text field still inserts a system hyphen mid-domain (`https:// / archiveo- / fourown.org/ / works/1`), so A88's minor hyphenation difference on iPhone is not gone; A88's Android Light capture problem is gone.
23. **`bulkedit`**: **match** — A88's Android Dark and 2.0× capture problems are gone.
24. **`bulktagstate`**: **match** — A88's Android capture problems in Dark, Light, Sepia, and OLED are gone.
25. **`backupimport`**: **match** — A88's Android Light ANR capture problem is gone.
26. **`queuetags`**: **match** — A88's difference on Android (collapsed `Unused` rows and un-indented footnotes) is gone.
27. **`fandomworks`**: **match** — Both A88's difference (`Doctor Who` filter chip and `1 FILTERS` count on Android) and A88's minor wash-colour difference on Android are gone.
28. **`tagworks`**: **match** — A88's minor wash-colour difference on Android is gone.
29. **`newcollection`**: **minor** — All columns, Android: separates `NAME` and `DESCRIPTION` with subheaders above outlined input boxes and places the colour swatches on the page below, whereas iPhone groups `Name`, `Description`, and the swatches inside one `COLLECTION` card; A88's 2.0× title truncation (`New collect…`) and A88's minor swatch-opacity difference on Android are gone.
30. **`newqueue`**: **match** — A88's minor swatch-opacity difference on Android is gone.
31. **`editqueue`**: **match** — A88's minor swatch-opacity difference on Android is gone.
32. **`collectiondetails`**: **match** — A88's minor swatch-opacity difference on Android is gone.
33. **`pagejump`**: **match** — A88's minor `Nearby` tile colour and OLED fill differences on Android are gone.
34. **`pronunciations`**: **match** — A88's minor empty-state card/icon difference on Android and A88's iPhone Light capture problem are gone (Android's footer paragraph is decided). Capture problem: largest column, iPhone — stayed on `Settings › Listening` without opening `Pronunciations`.
35. **`collectionreorder`**: **minor** — All columns, Android: renders each numbered work row as its own separate card instead of iPhone's single grouped card with dividers; A88's minor `⌃`/`⌄` button difference on Android is gone (now using drag handles).
36. **`seriesreorder`**: **match** — A88's missing `Save` button in the 2.0× top bar on Android is gone.
37. **`revokedevice`**: **match** — A88's iPhone title truncation is gone (now rendered in full as a card heading). Capture problem: OLED column, Android — stayed on `Sync Folder` without the `Revoke Demo reading tablet?` dialog open.
38. **`colsfilter`**: **match** — A88's difference on iPhone in the largest column (`Unrevealed` overlapping/showing through the pinned `Reset` button) is gone.
39. **`chsettingsedit`**: **differs** — All columns, Android (pre-3ha tile): iPhone's AX5 capture problem is gone and all five iPhone columns render `Challenge settings` cleanly, while the pair in this tile still differs against the pre-3ha Android columns (`Save changes` is an unpinned left-aligned card row instead of iPhone's pinned filled button, the subtitle omits `· 4 sign-ups`, and Android's 2.0× column omits `SIGN-UP INSTRUCTIONS` and `SCHEDULE`).
40. **`tagset`**: **match** — iPhone's A88 AX5 capture problem is gone (all five iPhone columns open `Tag set`), and the pair does not differ.
41. **`tagseteditor`**: **match** — iPhone's A88 AX5 capture problem is gone (all five iPhone columns open `Add tags`), and the pair does not differ.
