# A82a: First 35 Screens Side-by-Side Audit

## Counts

- **Match**: 9 (`newqueue`, `editqueue`, `queuetags`, `queuestorage`, `languagepicker`, `readerfind`, `readerdisplay`, `readernote`, `formattingtray`)
- **Minor**: 5 (`libpicker`, `queuetag`, `newcollection`, `fandomlist`, `seriespreserve`)
- **Differs**: 21 (`queuesettings`, `addworks`, `queuetagedit`, `bulktag`, `addtoqueue`, `collectiondetails`, `collectionreorder`, `addtocollection`, `fandomworks`, `tagworks`, `fandomfilter`, `savesearch`, `pagejump`, `tagpicker`, `downloaddate`, `bookmarkform`, `readercontents`, `pronunciations`, `pronunciationedit`, `customizetheme`, `chapterpicker`)
- **Capture problems**: 7 screens (`readerfind`, `readernote`, `pronunciations`, `pronunciationedit`, `customizetheme`, `formattingtray`, `chapterpicker`)

## Differs

- **`queuesettings`**: Largest-text column (Sepia big), Android — breadcrumb is truncated (`HOME › QUEUES › QUEUE DETAI...`) while iPhone wraps it onto two lines.
- **`addworks`**: All columns, iPhone — header title is truncated (`Add to Neon rer...` / `Add to Ne...`) and in largest text work titles and authors are truncated (`Tea in the Jasmine...`, `by uncle_ir...`) while Android shows the full title and wraps work titles; iPhone puts `Cancel`, a mature-filter eye icon, and `Add` in the top bar with search at the bottom, whereas Android puts `Show mature` text and the search bar at the top and `Cancel` / `Add` at the bottom.
- **`queuetagedit`**: All columns, both apps — section order differs (`MERGE INTO ANOTHER TAG` is above `REMOVE` / `Remove from this queue` on iPhone, whereas `Remove from this queue` is above `MERGE INTO ANOTHER TAG` without a `REMOVE` header on Android).
- **`bulktag`**: All columns, Android — opens the single-queue tag sheet (`Tags`, `ADD` header, `A tag you use here is the same tag on your works.`, trailing `All ✓`) instead of iPhone's bulk-tag sheet (`Tag`, `Your changes apply to all 2 selected works.`, leading selection circles).
- **`addtoqueue`**: Sepia and largest-text columns, iPhone — sheet is drawn in Light theme instead of Sepia; in all columns, Android adds a `Series` (`Also add works from this AO3 series`) section not on iPhone, omits iPhone's leading queue-row icons, and stacks `New queue` and `Add` on two lines.
- **`collectiondetails`**: All columns, both apps — Android titles the screen `Details` and includes a `COLLECTION` / `NAME` field with `DESCRIPTION` above `COLOUR`, whereas iPhone titles the sheet `Comfort reads`, has no `NAME` field, and places `COLOUR` above `DESCRIPTION`.
- **`collectionreorder`**: Largest-text column (Sepia big), iPhone — first work title is truncated (`Unanswere\nd Is Not U...`) while Android wraps the full title (`Unanswered Is Not Unread`).
- **`addtocollection`**: Sepia and largest-text columns, iPhone — sheet is drawn in Light theme instead of Sepia.
- **`fandomworks`**: Largest-text column (Sepia big), Android — the `Date Updated` sort control is crushed into a 1-character-wide vertical column (`D/a/t/e/ /U/p/d/a/t/e/...`) at the right edge while iPhone wraps it below the fandom name; in all columns, iPhone also shows `1 FILTERS` and a `Doctor Who` filter chip where Android shows `0 FILTERS`.
- **`tagworks`**: Largest-text column (Sepia big), Android — the `Date Updated` sort control is crushed into a 1-character-wide vertical column (`D/a/t/e/ /U/p/d/a/t/e/...`) at the right edge while iPhone wraps it below the tag name.
- **`fandomfilter`**: All columns, Android — lacks the pinned bottom `Show 5 tags` button shown on iPhone (and opens at half height with the `YOURS` and `GROUPING` sections below the fold).
- **`savesearch`**: All columns, iPhone — sheet header omits the `Save Search` title and leaves the `Name` field empty (with `Save` disabled) despite the caption "The name comes from your search", whereas Android displays the title and pre-fills the search name.
- **`pagejump`**: All columns, Android — omits the `Go to page` header title and adds a large centered `1 / of 3` readout, an `Enter a page from 1 to 3` caption, and a horizontal slider above `Nearby` not present on iPhone.
- **`tagpicker`**: All columns, both apps — with an empty search query, iPhone shows a `Selected` section (`+ Star Wars`) and `Type above to search AO3 fandoms.` under `Results`, whereas Android omits `Selected` and pre-populates `RESULTS` with a list of fandoms.
- **`downloaddate`**: Sepia and largest-text columns, iPhone — sheet is drawn in Light theme instead of Sepia.
- **`bookmarkform`**: Largest-text column (Sepia big), iPhone — sheet title is truncated (`Bookmark on A...`) while Android displays the full title (`Edit Bookmark on AO3`).
- **`readercontents`**: All columns, Android — adds inline `Bookmark` and `Add Note` buttons to each chapter row in `Contents`, which in the largest-text column (Sepia big) crushes and truncates the chapter titles on the left (`Pref\nace`, `Ch\na...`) while iPhone shows only the chapter title and percentage without truncation.
- **`pronunciations`**: Light, Sepia, OLED, and largest-text columns, Android — shows `Add Pronunciation`, `Paste Corrections`, and `Copy All` as inline rows under `No corrections yet` plus an extra capability paragraph (`Corrections are saved and included in backups and sync...`), whereas iPhone puts those actions in the top-right `•••` menu and shows an icon empty-state card.
- **`pronunciationedit`**: Dark column, Android — repeats the `Word` and `Pronunciation` labels inside the input boxes in addition to the section headers above them and shows two Android-specific voice-engine limitation paragraphs in the footer compared to iPhone's single Kokoro syllable note.
- **`customizetheme`**: OLED column, Android — preview card displays a third paragraph (`She traced the last line...`) not shown on iPhone, and theme selection uses a rectangular 4-segment bar instead of iPhone's four circular `Aa` swatches.
- **`chapterpicker`**: Largest-text column (Sepia big), iPhone — the selected `Chapter 1` row is truncated to `Chapt... ✓` while Android displays `Chapter 1` in full (with `All Comments` selected).

## Minor

- **`libpicker`**: All columns, both apps — the `Filter Fandoms` search field is placed at the top below the sheet header on Android and floats at the bottom of the sheet on iPhone.
- **`queuetag`**: All columns, Android — selected tag rows display `All` next to the checkmark (`All ✓`) whereas iPhone displays only the checkmark (`✓`).
- **`newcollection`**: All columns, Android — separates `NAME`, `DESCRIPTION`, and `COLOUR` with individual subheaders under `COLLECTION`, whereas iPhone groups them into one `COLLECTION` card without a `COLOUR` header.
- **`fandomlist`**: All columns, both apps — Android places the `Search TV Shows` field at the top below the sort chips and omits the leading icon on `Group variants`, whereas iPhone floats the search bar at the bottom and includes an icon on `Group variants`.
- **`seriespreserve`**: All columns, both apps — iPhone shows the unknown-count prompt ("Kudos couldn't check how many works are in this series…") while Android shows the known-count prompt ("This series has 4 works. Download every work in the series?").

## Capture problems

- **`readerfind`**: Largest-text column (Sepia big), Android — blank sepia screen (neither the reader nor the `Find in Work` sheet is drawn; in OLED on Android, the software keyboard also covers the bottom third).
- **`readernote`**: Dark and largest-text (Sepia big) columns, Android — shows the reader loading skeleton and the `Add Note` sheet did not open.
- **`pronunciations`**: Largest-text column (Sepia big) on iPhone stayed on the `Listening` settings screen (`Plain...rration` truncated there), and Dark column on Android stayed on the root `Settings` screen (`Pronunciations` did not open).
- **`pronunciationedit`**: Largest-text column (Sepia big) on iPhone stayed on `Listening` settings, and Light, Sepia, OLED, and largest-text columns on Android stayed on `Read Aloud` settings (`Add Pronunciation` sheet opened only in Dark on Android).
- **`customizetheme`**: Dark, Light, Sepia, and largest-text (Sepia big) columns, Android — stayed on the `Appearance` settings screen (`Customize Theme` sheet opened only in OLED on Android).
- **`formattingtray`**: Dark, Light, Sepia, and OLED columns, Android — Dark stayed on `Home`, Light and OLED show the `Comments` loading skeleton, and Sepia shows the `New comment` sheet without opening the `Formatting` tray (only largest-text opened `Formatting` on Android).
- **`chapterpicker`**: Dark and OLED columns, Android — shows the `Comments` loading skeleton and the `Browse Comments by Chapter` sheet did not open.

## Per-screen verdicts

1. **`libpicker`**: **minor** — All columns, both apps: the `Filter Fandoms` search field sits at the top below the header on Android and floats at the bottom of the sheet on iPhone.
2. **`queuesettings`**: **differs** — Largest-text column (Sepia big), Android: breadcrumb is truncated to `HOME › QUEUES › QUEUE DETAI...` while iPhone wraps it onto two lines.
3. **`newqueue`**: **match**
4. **`editqueue`**: **match**
5. **`addworks`**: **differs** — All columns, iPhone: header title is truncated (`Add to Neon rer...` / `Add to Ne...`) and in largest text work titles and authors are truncated (`Tea in the Jasmine...`, `by uncle_ir...`) while Android shows the full header and wraps titles; iPhone places `Cancel`, an eye icon, and `Add` in the top bar with search at the bottom, while Android places `Show mature` text and the search field at the top and `Cancel` / `Add` at the bottom.
6. **`queuetag`**: **minor** — All columns, Android: displays `All` beside the checkmark on selected tags (`Long fic`, `Rereads`) while iPhone displays only the checkmark.
7. **`queuetags`**: **match**
8. **`queuetagedit`**: **differs** — All columns, both apps: section order differs (`MERGE INTO ANOTHER TAG` is above `REMOVE` / `Remove from this queue` on iPhone, whereas `Remove from this queue` is above `MERGE INTO ANOTHER TAG` without a `REMOVE` header on Android).
9. **`bulktag`**: **differs** — All columns, Android: shows the single-queue tag sheet (`Tags`, `ADD` header, `A tag you use here is the same tag on your works.`, trailing `All ✓`) instead of iPhone's bulk-tag sheet (`Tag`, `Your changes apply to all 2 selected works.`, leading radio circles).
10. **`addtoqueue`**: **differs** — Sepia and largest-text columns, iPhone: sheet is drawn in Light theme instead of Sepia; in all columns, Android includes a `Series` (`Also add works from this AO3 series`) section not present on iPhone, omits iPhone's leading queue-row icons, and stacks `New queue` and `Add` vertically.
11. **`queuestorage`**: **match**
12. **`collectiondetails`**: **differs** — All columns, both apps: Android titles the screen `Details` and includes a `COLLECTION` / `NAME` field with `DESCRIPTION` above `COLOUR`, whereas iPhone titles the sheet `Comfort reads`, omits the `NAME` field, and places `COLOUR` above `DESCRIPTION`.
13. **`newcollection`**: **minor** — All columns, Android: separates `NAME`, `DESCRIPTION`, and `COLOUR` with individual subheaders under `COLLECTION`, while iPhone groups them into a single `COLLECTION` card without a `COLOUR` header.
14. **`collectionreorder`**: **differs** — Largest-text column (Sepia big), iPhone: truncates the first work title (`Unanswere\nd Is Not U...`) while Android wraps the full title (`Unanswered Is Not Unread`).
15. **`addtocollection`**: **differs** — Sepia and largest-text columns, iPhone: sheet is drawn in Light theme instead of Sepia.
16. **`fandomlist`**: **minor** — All columns, both apps: Android places the `Search TV Shows` field at the top below the sort chips and omits the leading icon on `Group variants`, whereas iPhone floats the search bar at the bottom and shows an icon on `Group variants`.
17. **`fandomworks`**: **differs** — Largest-text column (Sepia big), Android: crushes the `Date Updated` sort control into a 1-character-wide vertical column (`D/a/t/e/ /U/p/d/a/t/e/...`) at the right edge while iPhone wraps it to the next line; in all columns, iPhone also shows `1 FILTERS` with a `Doctor Who` filter chip not present on Android (`0 FILTERS`).
18. **`tagworks`**: **differs** — Largest-text column (Sepia big), Android: crushes the `Date Updated` sort control into a 1-character-wide vertical column (`D/a/t/e/ /U/p/d/a/t/e/...`) at the right edge while iPhone wraps it to the next line.
19. **`fandomfilter`**: **differs** — All columns, Android: lacks the pinned bottom `Show 5 tags` button present on iPhone (and opens at half height with `YOURS` and `GROUPING` below the fold).
20. **`savesearch`**: **differs** — All columns, iPhone: omits the `Save Search` title from the sheet header and leaves the `Name` field blank (with `Save` disabled) despite the caption "The name comes from your search", whereas Android shows the title and pre-fills the search name.
21. **`pagejump`**: **differs** — All columns, Android: omits the `Go to page` header title and adds a large centered `1 / of 3` readout, an `Enter a page from 1 to 3` caption, and a horizontal slider above `Nearby` not present on iPhone.
22. **`languagepicker`**: **match**
23. **`tagpicker`**: **differs** — All columns, both apps: with an empty search query, iPhone shows a `Selected` section (`+ Star Wars`) and `Type above to search AO3 fandoms.` under `Results`, whereas Android omits `Selected` and pre-populates `RESULTS` with a list of fandoms.
24. **`downloaddate`**: **differs** — Sepia and largest-text columns, iPhone: sheet is drawn in Light theme instead of Sepia.
25. **`seriespreserve`**: **minor** — All columns, both apps: iPhone shows the unknown-count prompt ("Kudos couldn't check how many works are in this series…") while Android shows the known-count prompt ("This series has 4 works. Download every work in the series?").
26. **`bookmarkform`**: **differs** — Largest-text column (Sepia big), iPhone: truncates the sheet title (`Bookmark on A...`) while Android shows the full title (`Edit Bookmark on AO3`).
27. **`readercontents`**: **differs** — All columns, Android: adds inline `Bookmark` and `Add Note` buttons to each chapter row in `Contents`, which in the largest-text column (Sepia big) crushes and truncates the chapter titles on the left (`Pref\nace`, `Ch\na...`) while iPhone shows only the title and percentage without truncation.
28. **`readerfind`**: **match** — Capture problem on Android in largest-text column (Sepia big): blank sepia screen.
29. **`readerdisplay`**: **match**
30. **`readernote`**: **match** — Capture problem on Android in Dark and largest-text (Sepia big) columns: reader loading skeleton shown, `Add Note` sheet did not open.
31. **`pronunciations`**: **differs** — Light, Sepia, OLED, and largest-text columns, Android: shows `Add Pronunciation`, `Paste Corrections`, and `Copy All` as inline rows under `No corrections yet` plus a second footer paragraph (`Corrections are saved and included in backups and sync...`), whereas iPhone puts those actions in the top-right `•••` menu and shows an icon empty-state card. Capture problem in largest-text column on iPhone (stayed on `Listening`) and Dark column on Android (stayed on `Settings`).
32. **`pronunciationedit`**: **differs** — Dark column, Android: repeats the `Word` and `Pronunciation` labels inside the input boxes in addition to the section headers above them and shows two Android-specific voice-engine limitation paragraphs in the footer compared to iPhone's single Kokoro syllable note. Capture problem in largest-text column on iPhone (stayed on `Listening`) and Light, Sepia, OLED, and largest-text columns on Android (stayed on `Read Aloud`, `Add Pronunciation` sheet did not open).
33. **`customizetheme`**: **differs** — OLED column, Android: preview card shows a third paragraph (`She traced the last line...`) not shown on iPhone, and theme selection uses a rectangular 4-segment bar instead of iPhone's four circular `Aa` swatches. Capture problem in Dark, Light, Sepia, and largest-text columns on Android (stayed on `Appearance`, `Customize Theme` sheet did not open).
34. **`formattingtray`**: **match** — Capture problem in Dark, Light, Sepia, and OLED columns on Android: Dark stayed on `Home`, Light and OLED show the `Comments` loading skeleton, and Sepia shows `New comment` without the `Formatting` tray open.
35. **`chapterpicker`**: **differs** — Largest-text column (Sepia big), iPhone: truncates the selected `Chapter 1` row to `Chapt... ✓` while Android shows `Chapter 1` in full (with `All Comments` selected). Capture problem in Dark and OLED columns on Android (`Comments` loading skeleton shown, sheet did not open).
