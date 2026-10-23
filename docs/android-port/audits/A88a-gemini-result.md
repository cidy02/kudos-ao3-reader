# A88a: First 36 Screens Re-Audit

## Counts

- **Match**: 23 (`queuesettings`, `newqueue`, `editqueue`, `queuetag`, `queuetags`, `queuetagedit`, `bulktag`, `queuestorage`, `collectiondetails`, `collectionreorder`, `addtocollection`, `tagworks`, `fandomfilter`, `savesearch`, `pagejump`, `languagepicker`, `tagpicker`, `downloaddate`, `bookmarkform`, `customizetheme`, `formattingtray`, `chapterpicker`, `inboxfilter`)
- **Minor**: 3 (`libpicker`, `fandomlist`, `seriespreserve`)
- **Differs**: 6 (`addworks`, `addtoqueue`, `newcollection`, `fandomworks`, `pronunciations`, `pronunciationedit`)
- **Skipped (no verdict)**: 4 (`readercontents`, `readerfind`, `readerdisplay`, `readernote`)
- **Capture problems**: 6 evaluated screens (`addworks`, `pronunciations`, `pronunciationedit`, `customizetheme`, `formattingtray`, `chapterpicker`), plus the 4 skipped screens (`readercontents`, `readerfind`, `readerdisplay`, `readernote`)

## Differs

- **`addworks`**: Largest-text column (Sepia big), iPhone — truncates the first author line (`by un-\ncle_iroh...`) while Android shows `uncle_iroh_fan` in full; in all open columns, iPhone puts `Cancel`, a mature-filter eye icon, and `Add` in the top bar with `Search your library` at the bottom, whereas Android puts `Show mature` text and `Search your library` at the top and `Cancel` / `Add` at the bottom (the A82 work-title truncation and regular-size header truncation on iPhone are gone; iPhone's cut largest-text title `Add to Neon...` is excluded).
- **`addtoqueue`**: All columns, Android — includes a `Series` (`Also add works from this AO3 series`) section below `Queues` not present on iPhone (the A82 Sepia theme bug on iPhone, missing leading queue-row icons on Android, and two-line `New queue` / `Add` row on Android are gone).
- **`newcollection`**: Largest-text column (Sepia big), Android — truncates the header title `New collection` to `New collect...` while iPhone shows `New collection` in full (of A82's minor difference, Android removed the `COLOUR` subheader under `COLLECTION`, while keeping `NAME` and `DESCRIPTION` subheaders above separate input boxes instead of iPhone's single grouped card).
- **`fandomworks`**: All columns, both apps — iPhone shows `1 FILTERS` and a `Doctor Who` filter chip below the stats grid whereas Android shows `0 FILTERS` and no filter chip (the A82 crushed `Date Updated` sort control in largest text on Android is gone).
- **`pronunciations`**: Dark, Sepia, and OLED columns (and Light and largest-text on Android), Android — includes a second paragraph below the empty state (`Corrections are saved and included in backups and sync. The current Android Kokoro Voice Pack and device voice cannot apply them yet.`) and omits iPhone's speech-bubble `A` empty-state card icon (the A82 inline `Add Pronunciation`, `Paste Corrections`, and `Copy All` rows on Android are gone, moved to the top-right `⋮` menu).
- **`pronunciationedit`**: Dark, Light, Sepia, and largest-text columns, Android — shows two Android-specific voice-engine limitation paragraphs in the footer (`This Android voice engine cannot convert syllables...` and `Corrections are saved and included in backups and sync...`) compared to iPhone's single Kokoro syllable note (the A82 duplicate floating `Word` and `Pronunciation` labels inside the input boxes on Android are gone).

## Minor

- **`libpicker`**: All columns, both apps — the `Filter Fandoms` search field sits at the top below the sheet header on Android and floats at the bottom of the sheet on iPhone (the A82 minor difference remains).
- **`fandomlist`**: All columns, both apps — Android places the `Search TV Shows` field at the top below the sort chips and omits the leading icon on `Group variants`, whereas iPhone floats the search bar at the bottom and includes an icon on `Group variants` (the A82 minor difference remains).
- **`seriespreserve`**: All columns, both apps — iPhone shows the unknown-count prompt (`Kudos couldn't check how many works are in this series…`) while Android shows the known-count prompt (`This series has 4 works. Download every work in the series?`) (the A82 minor difference remains).

## Capture problems

- **`addworks`**: Light column, Android — stayed on `Home` (`Add to Neon reread` sheet did not open).
- **`pronunciations`**: Light and largest-text (Sepia big) columns, iPhone — Light stayed on the `AO3_Reader` Account screen and largest-text stayed on `Listening` settings (`Pronunciations` did not open).
- **`pronunciationedit`**: Largest-text column (Sepia big) on iPhone and OLED column on Android — both stayed on `Listening` settings (`Add Pronunciation` sheet did not open).
- **`customizetheme`**: Dark, Light, OLED, and largest-text (Sepia big) columns, Android — Dark stayed on `Appearance` with a `Kudos isn't responding` system dialog, Light rendered the preview card inside `Customize Theme` as a blank black box, and OLED and largest-text stayed on `Appearance` (`Customize Theme` sheet opened cleanly only in Sepia on Android).
- **`formattingtray`**: Dark, Light, OLED, and largest-text (Sepia big) columns, Android — Dark and largest-text show the `Comments` loading skeleton, Light shows the `New comment` composer without opening the `Formatting` tray, and OLED has the software keyboard covering the bottom half of the `Formatting` tray.
- **`chapterpicker`**: OLED column, Android — stayed on the `Comments` screen (`Browse Comments by Chapter` sheet did not open).

## Per-screen verdicts

1. **`libpicker`**: **minor** — All columns, both apps: the `Filter Fandoms` search field sits at the top below the header on Android and floats at the bottom of the sheet on iPhone (the A82 minor difference remains).
2. **`queuesettings`**: **match** — The A82 difference is gone (Android now wraps `HOME › QUEUES › QUEUE DETAILS` onto two lines in largest text instead of truncating it).
3. **`newqueue`**: **match**
4. **`editqueue`**: **match**
5. **`addworks`**: **differs** — Largest-text column (Sepia big), iPhone: truncates the first author line (`by un-\ncle_iroh...`) while Android shows `uncle_iroh_fan` in full; in all open columns, iPhone places `Cancel`, a mature-filter eye icon, and `Add` in the top bar with `Search your library` at the bottom, whereas Android places `Show mature` text and `Search your library` at the top and `Cancel` / `Add` at the bottom (the A82 work-title truncation and regular-size header truncation on iPhone are gone; iPhone's cut largest-text title `Add to Neon...` is excluded). Capture problem on Android in Light column: stayed on `Home` (`Add to Neon reread` sheet did not open).
6. **`queuetag`**: **match** — The A82 minor difference is gone (Android no longer displays `All` next to the checkmark on selected tags).
7. **`queuetags`**: **match**
8. **`queuetagedit`**: **match** — The A82 difference is gone (Android now places `MERGE INTO ANOTHER TAG` above `REMOVE` / `Remove from this queue` to match iPhone).
9. **`bulktag`**: **match** — The A82 difference is gone (Android now opens the bulk-tag sheet with `Tag`, `Your changes apply to all 5 selected works.`, and leading selection circles).
10. **`addtoqueue`**: **differs** — All columns, Android: includes a `Series` (`Also add works from this AO3 series`) section below `Queues` that is not present on iPhone (the A82 Sepia theme bug on iPhone, missing leading queue-row icons on Android, and two-line `New queue` / `Add` row on Android are all gone).
11. **`queuestorage`**: **match**
12. **`collectiondetails`**: **match** — The A82 difference is gone (Android now titles the sheet `Comfort reads`, omits the `NAME` field, and places `COLOUR` above `DESCRIPTION` to match iPhone).
13. **`newcollection`**: **differs** — Largest-text column (Sepia big), Android: truncates the header title `New collection` to `New collect...` while iPhone shows `New collection` in full (of A82's minor difference, Android removed the `COLOUR` subheader under `COLLECTION`, while keeping `NAME` and `DESCRIPTION` subheaders above separate input boxes instead of iPhone's single card).
14. **`collectionreorder`**: **match** — The A82 difference is gone (iPhone now wraps `Unanswered Is Not Unread` in largest text without truncation).
15. **`addtocollection`**: **match** — The A82 difference is gone (iPhone now draws the `Add to Collection` sheet in Sepia in the Sepia and largest-text columns).
16. **`fandomlist`**: **minor** — All columns, both apps: Android places the `Search TV Shows` field at the top below the sort chips and omits the leading icon on `Group variants`, whereas iPhone floats the search bar at the bottom and shows an icon on `Group variants` (the A82 minor difference remains).
17. **`fandomworks`**: **differs** — All columns, both apps: iPhone shows `1 FILTERS` and a `Doctor Who` filter chip below the stats grid whereas Android shows `0 FILTERS` and no filter chip (the A82 crushed `Date Updated` sort control in largest text on Android is gone).
18. **`tagworks`**: **match** — The A82 difference is gone (Android now wraps the `Date Updated` sort control below the tag name in largest text instead of crushing it at the right edge).
19. **`fandomfilter`**: **match** — The A82 difference is gone (Android now shows the full sheet with `YOURS`, `GROUPING`, and the pinned bottom `Show 5 tags` button).
20. **`savesearch`**: **match** — The A82 difference is gone (iPhone now displays the `Save Search` header title and pre-fills the search name).
21. **`pagejump`**: **match** — The A82 difference is gone (Android now displays the `Go to page` header title and omits the extra readout, caption, and slider).
22. **`languagepicker`**: **match**
23. **`tagpicker`**: **match** — The A82 difference is gone (Android now shows `Type above to search AO3 fandoms.` under `RESULTS` when the query is empty instead of pre-populating a list of fandoms).
24. **`downloaddate`**: **match** — The A82 difference is gone (iPhone now draws the `Downloaded` sheet in Sepia in the Sepia and largest-text columns).
25. **`seriespreserve`**: **minor** — All columns, both apps: iPhone shows the unknown-count prompt (`Kudos couldn't check how many works are in this series…`) while Android shows the known-count prompt (`This series has 4 works. Download every work in the series?`) (the A82 minor difference remains).
26. **`bookmarkform`**: **match** — The A82 difference is gone (iPhone now displays the full `Bookmark on AO3` title in the largest-text column without truncation).
27. **`readercontents`**: _skipped (capture fault on Android showing Home; no verdict)_
28. **`readerfind`**: _skipped (capture fault on Android showing Home; no verdict)_
29. **`readerdisplay`**: _skipped (capture fault on Android showing Home; no verdict)_
30. **`readernote`**: _skipped (capture fault on Android showing Home; no verdict)_
31. **`pronunciations`**: **differs** — Dark, Sepia, and OLED columns (and Light and largest-text on Android), Android: includes a second paragraph below the empty state (`Corrections are saved and included in backups and sync. The current Android Kokoro Voice Pack and device voice cannot apply them yet.`) and omits iPhone's speech-bubble `A` empty-state card icon (the A82 inline `Add Pronunciation`, `Paste Corrections`, and `Copy All` rows on Android are gone, moved to the top-right `⋮` menu). Capture problem on iPhone in Light column (stayed on `Account`) and largest-text column (stayed on `Listening` settings).
32. **`pronunciationedit`**: **differs** — Dark, Light, Sepia, and largest-text columns, Android: shows two Android-specific voice-engine limitation paragraphs in the footer (`This Android voice engine cannot convert syllables...` and `Corrections are saved and included in backups and sync...`) compared to iPhone's single Kokoro syllable note (the A82 duplicate floating `Word` and `Pronunciation` labels inside the input boxes on Android are gone). Capture problem on iPhone in largest-text column and on Android in OLED column (both stayed on `Listening` settings, `Add Pronunciation` sheet did not open).
33. **`customizetheme`**: **match** — The A82 difference is gone (Android now uses the four circular `Aa` theme swatches matching iPhone, and the scrollable theme preview is decided). Capture problem on Android in Dark (`Kudos isn't responding` system dialog over `Appearance`), Light (preview card inside `Customize Theme` is a blank black box), and OLED and largest-text columns (stayed on `Appearance`, `Customize Theme` sheet did not open).
34. **`formattingtray`**: **match** — Capture problem on Android in Dark and largest-text columns (`Comments` loading skeleton shown), Light column (`New comment` composer shown without `Formatting` tray open), and OLED column (software keyboard covers the bottom half of the `Formatting` tray).
35. **`chapterpicker`**: **match** — The A82 difference is gone (iPhone now wraps `Chapter 1` in the largest-text column instead of truncating it to `Chapt...`). Capture problem on Android in OLED column: stayed on `Comments` (`Browse Comments by Chapter` sheet did not open).
36. **`inboxfilter`**: **match** — The A82 minor difference is gone (iPhone now displays the `Inbox Filters` header title in the Light and Sepia columns, and Android opens the sheet in all columns).
