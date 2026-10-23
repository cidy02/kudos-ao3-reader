# A82a2: First 35 Screens Side-by-Side Audit

## Counts

- **Match**: 12
- **Minor**: 3
- **Differs**: 20
- **Capture problems**: 7 screens (`readerfind`, `readernote`, `pronunciations`, `pronunciationedit`, `customizetheme`, `formattingtray`, `chapterpicker`)

## Differs

- **`queuesettings`**: In the big (largest text) column, Android truncates the breadcrumb to `HOME › QUEUES › QUEUE DETAI…` on a single line while iPhone wraps the full `HOME › QUEUES › QUEUE DETAILS`.
- **`addworks`**: In all five columns, iPhone truncates the sheet title to `Add to Neon rer…` (`Add to Ne…` in big), and in the big column iPhone truncates the work titles and `by <author>` subtitles with `…` (`Tea in the Jasmine…` / `by uncle_ir…`), whereas Android shows the full heading and wraps the work rows without the `by ` prefix (and uses a `Show mature` text button instead of iPhone's eye icon).
- **`queuetagedit`**: In all five columns, Android places `Remove from this queue` (with no section header) above `MERGE INTO ANOTHER TAG`, whereas iPhone places `MERGE INTO ANOTHER TAG` above a `REMOVE` section containing `Remove from this queue`.
- **`bulktag`**: In all five columns, Android opens the queue-tag screen (`Tags`, `ADD` header, caption `A tag you use here is the same tag on your works.`, trailing `All ✓`) instead of iPhone's bulk-tag sheet (`Tag`, caption `Your changes apply to all 2 selected works.`, leading selection circles).
- **`addtoqueue`**: In the Sepia and big (Sepia largest-text) columns, iPhone draws the sheet in Light theme instead of Sepia, and in all five columns Android includes an extra `Series` section (`Also add works from this AO3 series` toggle and caption) not present on iPhone (plus stacks `Add` below `New queue` and omits iPhone's leading queue icons).
- **`collectiondetails`**: In all five columns, Android includes a `COLLECTION` / `NAME` field (`Comfort reads`) omitted on iPhone and orders `DESCRIPTION` above `COLOUR`, whereas iPhone orders `COLOUR` above `DESCRIPTION`.
- **`collectionreorder`**: In the big (largest text) column, iPhone splits mid-word and truncates the first work title (`Unanswere` / `d Is Not U…`), whereas Android wraps the full `Unanswered Is Not Unread`.
- **`addtocollection`**: In the Sepia and big (Sepia largest-text) columns, iPhone draws the `Add to Collection` sheet in Light theme instead of Sepia.
- **`fandomworks`**: In the big (largest text) column, Android crushes the `Date Updated` sort control into a single-character vertical column (`D/a/t/e/ /U/p/d/a/t/e/…`) along the right edge beside `Star Wars - All Media Types`, whereas iPhone wraps `Date Updated` onto the next line.
- **`tagworks`**: In the big (largest text) column, Android crushes the `Date Updated` sort control into a single-character vertical column (`D/a/t/e/ /U/p/d/a/t/e/…`) along the right edge beside `Star Wars - All Media Types`, whereas iPhone wraps `Date Updated` onto the next line.
- **`savesearch`**: In all five columns, iPhone omits the `Save Search` title from the sheet header and leaves the `Name` field blank (`Save` disabled) instead of pre-filling it from the search as Android does.
- **`pagejump`**: In all five columns, Android adds a large `1 / of 3` header readout, an `Enter a page from 1 to 3` caption, and a horizontal page-scrubber slider (omitting iPhone's `Go to page` title), whereas iPhone shows only the `PAGE NUMBER` field and `NEARBY` buttons.
- **`tagpicker`**: In all five columns, with an empty search query iPhone shows a `Selected` section (`+ Star Wars`) and `Type above to search AO3 fandoms.` under `Results`, whereas Android omits `Selected` and immediately populates `RESULTS` with fandom rows.
- **`downloaddate`**: In the Sepia and big (Sepia largest-text) columns, iPhone draws the `Downloaded` sheet in Light theme instead of Sepia, and in all five columns iPhone shows a collapsed `Downloaded   Oct 21, 2026` pill row whereas Android shows an expanded month calendar grid.
- **`bookmarkform`**: In the big (largest text) column, iPhone truncates the sheet title to `Bookmark on A…` whereas Android shows the full `Edit Bookmark on AO3`.
- **`readercontents`**: In all five columns, Android adds inline `Bookmark` and `Add Note` buttons to each chapter row, and in the big (largest text) column those buttons crush the chapter titles on Android into two-character lines ending in `…` (`Pref / ace`, `Ch / a…`).
- **`pronunciations`**: Across the captured columns (Dark, Light, Sepia, OLED on iPhone; Light, Sepia, OLED, big on Android), iPhone shows a centered empty-state card (`No corrections yet`) and keeps actions in the top-right `···` menu, whereas Android lists `Add Pronunciation`, `Paste Corrections`, and `Copy All` inline under a `No corrections yet` header and adds a second footer paragraph about Android voice-pack support.
- **`pronunciationedit`**: In the Dark column (the only column captured on both apps), Android repeats the `Word` and `Pronunciation` labels inside the text boxes as well as above them and adds a second footer paragraph about Android voice-pack support.
- **`customizetheme`**: In the OLED column (the only column where Android opened the sheet), Android shows a third paragraph in the `A Study in Starlight` preview card (which iPhone clips with a fade after two paragraphs) and uses a text segmented bar (`Light | Sepia | Dark | OLED`) instead of iPhone's four circular `Aa` theme buttons.
- **`chapterpicker`**: In the big (largest text) column, iPhone truncates `Chapter 1` to `Chapt…` beside the checkmark whereas Android shows the full `Chapter 1`.

## Minor

- **`queuetag`**: In all five columns, Android shows `All` beside the checkmark (`All ✓`) on selected tags whereas iPhone shows only `✓`.
- **`fandomlist`**: In all five columns, iPhone's `Group variants` chip has a leading icon and lighter tint while Android's has no icon and solid green fill (and in the big column, the `Group variants` chip clips at the right edge on both apps).
- **`fandomfilter`**: In all five columns, iPhone shows a sticky bottom `Show 5 tags` button whereas Android's half-sheet omits it (with `5 tags in 4 fandoms` visible on the page above the sheet).

## Capture problems

- **`readerfind`**: In the big column on Android, the screen is blank and the `Find in Work` sheet did not open.
- **`readernote`**: In the Dark and big columns on Android, the reader is still on its loading skeleton and the `Add Note` sheet did not open.
- **`pronunciations`**: In the big column on iPhone the app stayed on `Listening` settings, and in the Dark column on Android the app stayed on the main `Settings` page instead of opening `Pronunciations`.
- **`pronunciationedit`**: In the big column on iPhone the app stayed on `Listening` settings, and in the Light, Sepia, OLED, and big columns on Android the app stayed on `Read Aloud` settings without opening `Add Pronunciation`.
- **`customizetheme`**: In the Dark, Light, Sepia, and big columns on Android, the app stayed on `Appearance` settings and did not open the `Customize Theme` sheet.
- **`formattingtray`**: In the Dark column on Android the app is on `Home`, in the Light and OLED columns it is on the `Comments` loading skeleton, and in the Sepia column it is on `New comment` without the `Formatting` tray open.
- **`chapterpicker`**: In the Dark and OLED columns on Android, the `Comments` screen is still on its loading skeleton and the `Browse Comments by Chapter` sheet did not open.

## Per-screen verdicts

1. **`libpicker`**: **match**
2. **`queuesettings`**: **differs** — In the big (largest text) column, Android truncates the breadcrumb to `HOME › QUEUES › QUEUE DETAI…` on a single line while iPhone wraps the full `HOME › QUEUES › QUEUE DETAILS`.
3. **`newqueue`**: **match**
4. **`editqueue`**: **match**
5. **`addworks`**: **differs** — In all five columns, iPhone truncates the sheet title to `Add to Neon rer…` (`Add to Ne…` in big), and in the big column iPhone truncates the work titles and `by <author>` subtitles with `…` (`Tea in the Jasmine…` / `by uncle_ir…`), whereas Android shows the full heading and wraps the work rows without the `by ` prefix (and uses a `Show mature` text button instead of iPhone's eye icon).
6. **`queuetag`**: **minor** — In all five columns, Android shows `All` beside the checkmark (`All ✓`) on selected tags whereas iPhone shows only `✓`.
7. **`queuetags`**: **match**
8. **`queuetagedit`**: **differs** — In all five columns, Android places `Remove from this queue` (with no section header) above `MERGE INTO ANOTHER TAG`, whereas iPhone places `MERGE INTO ANOTHER TAG` above a `REMOVE` section containing `Remove from this queue`.
9. **`bulktag`**: **differs** — In all five columns, Android opens the queue-tag screen (`Tags`, `ADD` header, caption `A tag you use here is the same tag on your works.`, trailing `All ✓`) instead of iPhone's bulk-tag sheet (`Tag`, caption `Your changes apply to all 2 selected works.`, leading selection circles).
10. **`addtoqueue`**: **differs** — In the Sepia and big (Sepia largest-text) columns, iPhone draws the sheet in Light theme instead of Sepia, and in all five columns Android includes an extra `Series` section (`Also add works from this AO3 series` toggle and caption) not present on iPhone (plus stacks `Add` below `New queue` and omits iPhone's leading queue icons).
11. **`queuestorage`**: **match**
12. **`collectiondetails`**: **differs** — In all five columns, Android includes a `COLLECTION` / `NAME` field (`Comfort reads`) omitted on iPhone and orders `DESCRIPTION` above `COLOUR`, whereas iPhone orders `COLOUR` above `DESCRIPTION`.
13. **`newcollection`**: **match**
14. **`collectionreorder`**: **differs** — In the big (largest text) column, iPhone splits mid-word and truncates the first work title (`Unanswere` / `d Is Not U…`), whereas Android wraps the full `Unanswered Is Not Unread`.
15. **`addtocollection`**: **differs** — In the Sepia and big (Sepia largest-text) columns, iPhone draws the `Add to Collection` sheet in Light theme instead of Sepia.
16. **`fandomlist`**: **minor** — In all five columns, iPhone's `Group variants` chip has a leading icon and lighter tint while Android's has no icon and solid green fill (and in the big column, the `Group variants` chip clips at the right edge on both apps).
17. **`fandomworks`**: **differs** — In the big (largest text) column, Android crushes the `Date Updated` sort control into a single-character vertical column (`D/a/t/e/ /U/p/d/a/t/e/…`) along the right edge beside `Star Wars - All Media Types`, whereas iPhone wraps `Date Updated` onto the next line.
18. **`tagworks`**: **differs** — In the big (largest text) column, Android crushes the `Date Updated` sort control into a single-character vertical column (`D/a/t/e/ /U/p/d/a/t/e/…`) along the right edge beside `Star Wars - All Media Types`, whereas iPhone wraps `Date Updated` onto the next line.
19. **`fandomfilter`**: **minor** — In all five columns, iPhone shows a sticky bottom `Show 5 tags` button whereas Android's half-sheet omits it (with `5 tags in 4 fandoms` visible on the page above the sheet).
20. **`savesearch`**: **differs** — In all five columns, iPhone omits the `Save Search` title from the sheet header and leaves the `Name` field blank (`Save` disabled) instead of pre-filling it from the search as Android does.
21. **`pagejump`**: **differs** — In all five columns, Android adds a large `1 / of 3` header readout, an `Enter a page from 1 to 3` caption, and a horizontal page-scrubber slider (omitting iPhone's `Go to page` title), whereas iPhone shows only the `PAGE NUMBER` field and `NEARBY` buttons.
22. **`languagepicker`**: **match**
23. **`tagpicker`**: **differs** — In all five columns, with an empty search query iPhone shows a `Selected` section (`+ Star Wars`) and `Type above to search AO3 fandoms.` under `Results`, whereas Android omits `Selected` and immediately populates `RESULTS` with fandom rows.
24. **`downloaddate`**: **differs** — In the Sepia and big (Sepia largest-text) columns, iPhone draws the `Downloaded` sheet in Light theme instead of Sepia, and in all five columns iPhone shows a collapsed `Downloaded   Oct 21, 2026` pill row whereas Android shows an expanded month calendar grid.
25. **`seriespreserve`**: **match**
26. **`bookmarkform`**: **differs** — In the big (largest text) column, iPhone truncates the sheet title to `Bookmark on A…` whereas Android shows the full `Edit Bookmark on AO3`.
27. **`readercontents`**: **differs** — In all five columns, Android adds inline `Bookmark` and `Add Note` buttons to each chapter row, and in the big (largest text) column those buttons crush the chapter titles on Android into two-character lines ending in `…` (`Pref / ace`, `Ch / a…`).
28. **`readerfind`**: **match** *(capture problem: in the big column on Android, the screen is blank and the `Find in Work` sheet did not open)*
29. **`readerdisplay`**: **match**
30. **`readernote`**: **match** *(capture problem: in the Dark and big columns on Android, the reader is still on its loading skeleton and the `Add Note` sheet did not open)*
31. **`pronunciations`**: **differs** — Across the captured columns (Dark, Light, Sepia, OLED on iPhone; Light, Sepia, OLED, big on Android), iPhone shows a centered empty-state card (`No corrections yet`) and keeps actions in the top-right `···` menu, whereas Android lists `Add Pronunciation`, `Paste Corrections`, and `Copy All` inline under a `No corrections yet` header and adds a second footer paragraph about Android voice-pack support. *(capture problem: in the big column on iPhone the app stayed on `Listening` settings, and in the Dark column on Android the app stayed on the main `Settings` page)*
32. **`pronunciationedit`**: **differs** — In the Dark column (the only column captured on both apps), Android repeats the `Word` and `Pronunciation` labels inside the text boxes as well as above them and adds a second footer paragraph about Android voice-pack support. *(capture problem: in the big column on iPhone the app stayed on `Listening` settings, and in the Light, Sepia, OLED, and big columns on Android the app stayed on `Read Aloud` settings without opening `Add Pronunciation`)*
33. **`customizetheme`**: **differs** — In the OLED column (the only column where Android opened the sheet), Android shows a third paragraph in the `A Study in Starlight` preview card (which iPhone clips with a fade after two paragraphs) and uses a text segmented bar (`Light | Sepia | Dark | OLED`) instead of iPhone's four circular `Aa` theme buttons. *(capture problem: in the Dark, Light, Sepia, and big columns on Android, the app stayed on `Appearance` settings and did not open the `Customize Theme` sheet)*
34. **`formattingtray`**: **match** *(capture problem: in the Dark column on Android the app is on `Home`, in the Light and OLED columns it is on the `Comments` loading skeleton, and in the Sepia column it is on `New comment` without the `Formatting` tray open)*
35. **`chapterpicker`**: **differs** — In the big (largest text) column, iPhone truncates `Chapter 1` to `Chapt…` beside the checkmark whereas Android shows the full `Chapter 1`. *(capture problem: in the Dark and OLED columns on Android, the `Comments` screen is still on its loading skeleton and the `Browse Comments by Chapter` sheet did not open)*
