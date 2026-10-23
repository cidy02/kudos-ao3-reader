# A88b: Second 36 Screens Side-by-Side Audit (Post-Fix)

## Counts

- **Match**: 26 (`authorabout`, `seriesedit`, `seriesreorder`, `authorworksfilter`, `chsignupdetail`, `prompttags`, `tagset`, `tagseteditor`, `writingpreview`, `chapters`, `chapterform`, `edittags`, `tagseditor`, `texteditor`, `seriespicker`, `collectionsgifts`, `creatorspicker`, `parentpicker`, `bulkedit`, `bulktagstate`, `prefhelp`, `availability`, `pairing`, `revokedevice`, `backupimport`, `aboutkudos`)
- **Minor**: 1 (`colsfilter`)
- **Differs**: 8 (`seriesdetail`, `seriesremove`, `colitems`, `chsettingsedit`, `recovery`, `bulknames`, `privacydata`, `authorbookmarks`)
- **Skipped**: 1 (`readerspeech` — Android shots show `Home`)
- **Capture problems**: 23 screens (`seriesedit`, `seriesremove`, `authorworksfilter`, `colitems`, `chsettingsedit`, `chsignupdetail`, `tagset`, `tagseteditor`, `chapters`, `chapterform`, `tagseditor`, `texteditor`, `recovery`, `seriespicker`, `collectionsgifts`, `creatorspicker`, `parentpicker`, `bulkedit`, `bulktagstate`, `bulknames`, `revokedevice`, `backupimport`, `authorbookmarks`)

## Differs

- **`seriesdetail`**: All columns, Android — still omits the series bookmark count (`62`), `Restricted` lock badge, and updated date (`08 Jul 2026`) from the series summary card (and zero-count comment/kudos/bookmark/hit stats from the work cards) and tints the screen wash and work cards green (A82b's moved `STAR WARS` / `COMPLETE` top pills and bottom `by Avery Writes` placement are gone).
- **`seriesremove`**: Dark, Light, OLED, and largest-text columns, Android — displays word-count and date subtitles (`21,678 words · 08 Jul 2026`, `24,000 words · 08 Jul 2026`) under the posted work titles that iPhone omits (A82b's `0 works` empty-state difference on iPhone is gone).
- **`colitems`**: Dark, Light, Sepia, and OLED columns, iPhone — truncates the bottom-left username on each item card to `AO3_Reader...` while Android shows `winterquill (Member)` in full (A82b's account-wide vs maintainer page scope and `Unrevealed`/`Anonymous` control differences are decided).
- **`chsettingsedit`**: Largest-text column (Sepia big) on Android omits the `SIGN-UP INSTRUCTIONS` and `SCHEDULE` sections between `BASICS` and `Save changes`, and in Dark, Light, Sepia, and OLED columns Android still includes an `Assignments sent` (`Manual`) row in `SCHEDULE`, omits `4 sign-ups` from the subtitle, and styles `Save changes` as a left-aligned card row instead of iPhone's pinned filled button (A82b's missing `SIGN-UP INSTRUCTIONS` section header on Android in Dark, Light, Sepia, and OLED is gone).
- **`recovery`**: All columns, iPhone — still displays a second warning paragraph (`The text on the form has changed since this copy began. Review the copy before restoring it.`) above the recovery preview text that Android omits (A82b's Light-in-Sepia theme drawing and largest-text horizontal truncations on iPhone are gone).
- **`bulknames`**: Light and OLED columns, Android — still renders `Collection name` twice on the first row (`Collection name   Collection name`) with `Add` on a separate second row, whereas iPhone uses a single `Collection name   Add` row (A82b's Light-in-Sepia rectangle on iPhone is gone).
- **`privacydata`**: Dark, Light, Sepia, and OLED columns, Android — still includes an `Imported fonts` (`12 KB`) row under `STORED ON THIS DEVICE` between `Original files kept` and `Draft recovery` that iPhone omits (unchanged from A82b).
- **`authorbookmarks`**: Sepia, OLED, and largest-text columns, Android — tints the bookmark cards in purple and green instead of iPhone's neutral card surface, omits the `Bookmarks` section header above the list, and renders `Load More` as plain text instead of a card row.

## Minor

- **`colsfilter`**: Largest-text column (Sepia big), iPhone — the floating `Reset` pill overlaps the `Unrevealed` row label at the bottom of the sheet (A82b's bright-white bottom bar in Light, Sepia, and largest-text on iPhone is gone).

## Capture problems

- **`seriesedit`**: Dark and Sepia columns, Android — Dark shows `Edit series` with a loading spinner, and Sepia shows the `Series` loading skeleton behind a `"Kudos isn't responding"` system dialog.
- **`seriesremove`**: Sepia column, Android — stayed on `Edit series` with a loading spinner (`Remove works` did not open).
- **`authorworksfilter`**: Dark, Sepia, and OLED columns, Android — Dark and OLED show the `AO3_Reader` profile skeleton without the filter sheet open, and Sepia shows the `AO3_Reader` profile page without the filter sheet open.
- **`colitems`**: Dark column, Android — `"Kudos isn't responding"` system dialog covers the screen.
- **`chsettingsedit`**: Largest-text column (Sepia big), iPhone — stayed on the `Winter Exchange 2026` collection screen instead of opening `Challenge settings`.
- **`chsignupdetail`**: Largest-text column (Sepia big), Android — `"Kudos isn't responding"` system dialog covers the screen.
- **`tagset`**: Largest-text column (Sepia big), iPhone — stayed on the `Winter Exchange 2026` collection screen instead of opening `Tag set`.
- **`tagseteditor`**: Largest-text column (Sepia big), iPhone — stayed on the `Winter Exchange 2026` collection screen instead of opening `Add tags`.
- **`chapters`**: All columns, Android — Dark and largest-text stayed on `Home`, Light and OLED show `Edit work` with a loading spinner, and Sepia shows `Chapters` with a `Loading chapters...` spinner.
- **`chapterform`**: All columns, Android — Dark, Sepia (with `"Kudos isn't responding"`), and OLED stayed on `Home`, Light shows `"Kudos isn't responding"` over `Edit chapter`, and largest-text shows `Edit chapter` with a loading spinner.
- **`tagseditor`**: Dark, Light, and OLED columns, Android — `"Kudos isn't responding"` system dialog covers the screen.
- **`texteditor`**: Dark and OLED columns, Android — `"Kudos isn't responding"` system dialog covers the screen.
- **`recovery`**: Dark column, Android — `"Kudos isn't responding"` system dialog covers the screen.
- **`seriespicker`**: Dark column, Android — stayed on `Edit work` instead of opening the `Series` picker.
- **`collectionsgifts`**: Dark and Sepia columns, Android — Dark shows `"Kudos isn't responding"` over the screen and Sepia stayed on `Home`.
- **`creatorspicker`**: Largest-text column (Sepia big), Android — stayed on `Edit work` with a loading spinner.
- **`parentpicker`**: Light column, Android — stayed on `Edit work` with a loading spinner.
- **`bulkedit`**: Dark and largest-text (Sepia big) columns, Android — stayed on the `AO3_Reader` profile skeleton instead of opening `Edit 2 works`.
- **`bulktagstate`**: Dark, Light, Sepia, and OLED columns, Android — Dark and Sepia stayed on the `AO3_Reader` profile skeleton, and Light and OLED show `Edit 2 works` with a `Loading 2 works...` spinner.
- **`bulknames`**: Dark, Sepia, and largest-text (Sepia big) columns, Android — Dark stayed on the `AO3_Reader` profile skeleton, and Sepia and largest-text show `Edit 2 works` with a `Loading 2 works...` spinner.
- **`revokedevice`**: OLED column, Android — stayed on `Sync Folder` and the `Revoke Demo reading tablet?` dialog did not open.
- **`backupimport`**: Light column, Android — `"Kudos isn't responding"` system dialog covers the screen.
- **`authorbookmarks`**: Dark and Light columns, Android — Dark shows a blank grey screen with `"Kudos isn't responding"`, and Light shows the `Bookmarks` loading skeleton.

## Per-screen verdicts

1. **`authorabout`**: **match** — A82b's capture problems on Android are gone.
2. **`seriesdetail`**: **differs** — All columns, Android: still omits the series bookmark count (`62`), `Restricted` lock badge, and updated date (`08 Jul 2026`) from the series summary card (and zero-count stats from the work cards) and tints the screen wash and work cards green; A82b's moved `STAR WARS` / `COMPLETE` top pills, bottom `by Avery Writes` placement, and Dark-column capture fault are gone.
3. **`seriesedit`**: **match** — Capture problem on Android in Dark (`Edit series` loading spinner) and Sepia (`Series` skeleton with `"Kudos isn't responding"` dialog); Light, OLED, and largest-text columns now render and match.
4. **`seriesreorder`**: **match** — Both A82b differences (iPhone largest-text work title truncation and Android's missing drag-handle icons) and the Dark/OLED capture problems on Android are gone.
5. **`seriesremove`**: **differs** — Dark, Light, OLED, and largest-text columns, Android: displays word-count and date subtitles (`21,678 words · 08 Jul 2026`, `24,000 words · 08 Jul 2026`) under the posted work titles that iPhone omits; A82b's `0 works` empty state on iPhone is gone. Capture problem on Android in Sepia (stayed on `Edit series` with a loading spinner).
6. **`authorworksfilter`**: **match** — A82b's extra `Direction` sublabel on Android is gone. Capture problem on Android in Dark and OLED (`AO3_Reader` profile skeleton without filter sheet) and in Sepia (`AO3_Reader` profile without filter sheet).
7. **`colitems`**: **differs** — Dark, Light, Sepia, and OLED columns, iPhone: truncates the bottom-left username on each item card to `AO3_Reader...` while Android shows `winterquill (Member)` in full (A82b's page-scope and `Unrevealed`/`Anonymous` control differences are decided). Capture problem on Android in Dark (`"Kudos isn't responding"` system dialog).
8. **`colsfilter`**: **minor** — Largest-text column (Sepia big), iPhone: the floating `Reset` pill overlaps the `Unrevealed` row label; A82b's bright-white bottom bar in Light, Sepia, and largest-text on iPhone is gone.
9. **`chsettingsedit`**: **differs** — Largest-text column (Sepia big) on Android omits the `SIGN-UP INSTRUCTIONS` and `SCHEDULE` sections between `BASICS` and `Save changes`, and in Dark, Light, Sepia, and OLED columns Android still includes an `Assignments sent` (`Manual`) row, omits `4 sign-ups` from the subtitle, and styles `Save changes` as a left-aligned card row instead of iPhone's pinned filled button; A82b's missing `SIGN-UP INSTRUCTIONS` section header on Android in Dark, Light, Sepia, and OLED is gone. Capture problem on iPhone in largest-text column (stayed on `Winter Exchange 2026` collection screen).
10. **`chsignupdetail`**: **match** — A82b's HTTP 403 capture fault on Android is gone in Dark, Light, Sepia, and OLED. Capture problem on Android in largest-text column (`"Kudos isn't responding"` system dialog).
11. **`prompttags`**: **match**
12. **`tagset`**: **match** — Capture problem on iPhone in largest-text column (stayed on `Winter Exchange 2026` collection screen).
13. **`tagseteditor`**: **match** — A82b's field-label casing and `Save tags` button-style differences on Android are gone. Capture problem on iPhone in largest-text column (stayed on `Winter Exchange 2026` collection screen).
14. **`writingpreview`**: **match**
15. **`chapters`**: **match** — Capture problem on Android in all columns: stayed on `Home` in Dark and largest-text, shows `Edit work` with a loading spinner in Light and OLED, and shows `Chapters` with a `Loading chapters...` spinner in Sepia.
16. **`chapterform`**: **match** — A82b's `After chapter` clipping in largest-text on iPhone is gone. Capture problem on Android in all columns: stayed on `Home` in Dark, Sepia (with `"Kudos isn't responding"` dialog), and OLED, shows `"Kudos isn't responding"` over `Edit chapter` in Light, and shows `Edit chapter` with a loading spinner in largest-text.
17. **`edittags`**: **match** — A82b's largest-text capture problem on Android is gone.
18. **`tagseditor`**: **match** — Capture problem on Android in Dark, Light, and OLED (`"Kudos isn't responding"` system dialog).
19. **`texteditor`**: **match** — All A82b differences (largest-text `Recovery copy...` truncation and `Done` overflow collapse on iPhone, Light-themed formatting bar in Sepia on iPhone, and extra body `Chapter text` heading on Android) are gone. Capture problem on Android in Dark and OLED (`"Kudos isn't responding"` system dialog).
20. **`recovery`**: **differs** — All columns, iPhone: still displays a second warning paragraph (`The text on the form has changed since this copy began. Review the copy before restoring it.`) above the recovery preview text that Android omits; A82b's Light-in-Sepia theme drawing and largest-text horizontal truncations on iPhone are gone. Capture problem on Android in Dark (`"Kudos isn't responding"` system dialog).
21. **`seriespicker`**: **match** — Capture problem on Android in Dark (stayed on `Edit work`).
22. **`collectionsgifts`**: **match** — Capture problem on Android in Dark (`"Kudos isn't responding"` system dialog) and Sepia (stayed on `Home`).
23. **`creatorspicker`**: **match** — Capture problem on Android in largest-text column (stayed on `Edit work` with a loading spinner).
24. **`parentpicker`**: **match** — All A82b truncations/clippings (`Please select a la...` and largest-text `https://archiv...` on iPhone, and clipped `URL` field on Android) are gone. Capture problem on Android in Light (stayed on `Edit work` with a loading spinner).
25. **`bulkedit`**: **match** — Capture problem on Android in Dark and largest-text columns (stayed on `AO3_Reader` profile skeleton).
26. **`bulktagstate`**: **match** — Both A82b differences (Light-themed card in Sepia and largest-text on iPhone, and missing leading selection circles / extra `Unchanged >` labels on Android) are gone. Capture problem on Android in Dark and Sepia (stayed on `AO3_Reader` profile skeleton) and in Light and OLED (`Loading 2 works...` spinner).
27. **`bulknames`**: **differs** — Light and OLED columns, Android: still renders `Collection name` twice on the first row (`Collection name   Collection name`) with `Add` on a separate second row, whereas iPhone uses a single `Collection name   Add` row; A82b's Light-in-Sepia rectangle on iPhone is gone. Capture problem on Android in Dark (stayed on `AO3_Reader` profile skeleton) and in Sepia and largest-text (`Loading 2 works...` spinner).
28. **`prefhelp`**: **match** — Both A82b's redundant `Privacy Preferences` card on iPhone and Dark-column capture fault on Android are gone.
29. **`privacydata`**: **differs** — Dark, Light, Sepia, and OLED columns, Android: still includes an `Imported fonts` (`12 KB`) row under `STORED ON THIS DEVICE` between `Original files kept` and `Draft recovery` that iPhone omits (unchanged from A82b).
30. **`availability`**: **match** — A82b's largest-text `Check Avail...` heading truncation on iPhone is gone.
31. **`pairing`**: **match** — A82b's Light-in-Sepia theme drawing on iPhone is gone (and Android's Deletion-signing pairing differences are decided).
32. **`revokedevice`**: **match** — A82b's Light-in-Sepia card background and extra `Reason` header row on iPhone are gone (and iPhone's cut title is decided/being fixed). Capture problem on Android in OLED (dialog did not open).
33. **`backupimport`**: **match** — A82b's Light-in-Sepia card backgrounds on iPhone are gone. Capture problem on Android in Light (`"Kudos isn't responding"` system dialog).
34. **`aboutkudos`**: **match** — A82b's unparsed Markdown asterisks (`**...**`) in the `License` card on iPhone are gone.
35. **`readerspeech`**: **skipped** — No verdict (Android shots show `Home`).
36. **`authorbookmarks`**: **differs** — Sepia, OLED, and largest-text columns, Android: tints the bookmark cards in purple and green instead of iPhone's neutral card surface, omits the `Bookmarks` section header above the list, and renders `Load More` as plain text instead of a card row. Capture problem on Android in Dark (blank grey screen with `"Kudos isn't responding"` dialog) and Light (`Bookmarks` loading skeleton).
