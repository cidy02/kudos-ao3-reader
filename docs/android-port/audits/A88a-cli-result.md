# A88a (CLI second opinion): the first 36 A82 screens after the fixes

*Done, 2026-10-23.*
- The second opinion beside Gemini's A88a, from the tiles in `/Users/cidy02/kudos-tools/pairs/tiles-a88/`. Read only: no other file changed.
- 32 screens judged. The four reader screens (`readercontents`, `readerfind`, `readerdisplay`, `readernote`) were skipped as asked.

## Counts

**Match 16 · minor 12 · differs 4 · capture problems on 6 of the 32** (the four skipped not counted).

Of A82's 21 "differs" in this half, 17 were judged here; 16 of those are gone. Only `fandomworks` still differs in the same way, the page's fandom chip and filter count. `addworks` keeps the iPhone's largest-size byline cut that A82 also saw. `queuetags` and `newcollection` were not raised by A82. At least `queuetags` is older than the fixes (see its entry).

## Differs

- **queuetags:** Android, all columns. The Unused rows have collapsed to no height, and both footnotes run from the screen edge. Not a regression: the A82 Android shot is pixel-identical (checked by Claude), so A82 missed it.
- **fandomworks:** Android, all columns. There's no chip naming the page's fandom, and the strip says "0 FILTERS", where the iPhone has "Doctor Who" and "1 FILTERS". Unchanged from A82.
- **addworks:** iPhone, largest column. Bylines break mid-word and end in "…" ("by un- / cle_iroh…"). (The sheet title cut is excluded.)
- **newcollection:** Android, 2.0× column. The bar title is cut to "New collect…".

## Minor

- **Swatch tones (newqueue, editqueue, collectiondetails, newcollection):** Android's colour swatches are the same mid tones in every theme. The iPhone's darken in Dark and OLED and pale in Light and Sepia.
- **Wash colour (tagworks; also fandomworks):** the page wash is green on Android, peach/brown on the iPhone.
- **libpicker, fandomlist:** the search field is at the top on Android and at the bottom on the iPhone. fandomlist's Group variants chip also has no icon on Android.
- **bulktag:** Android's page carries the queue's purple wash, and its header reads "YOUR TAGS" against "Your tags".
- **collectionreorder:** Android has ⌃/⌄ buttons where the iPhone has drag handles. It's a match if those buttons are decided.
- **pagejump:** Android's current Nearby tile is purple, not tan, and its OLED tiles have no fill.
- **pronunciations:** Android's empty state has no card or icon.
- **formattingtray:** Android's tray has no Done (it closes by dragging down).
- **chapterpicker:** Android draws each row as its own card, not one grouped list.

## Capture problems (not verdicts)

- **addworks:** Android Light shows Home.
- **pronunciations:** the iPhone's Light column shows Account, and its largest column shows Settings › Listening.
- **pronunciationedit:** the iPhone's largest column shows Settings › Listening, and Android OLED shows no sheet.
- **customizetheme:** Android Dark shows "Kudos isn't responding". Android OLED and 2.0× show Appearance with no sheet. Android Light's preview is a blank black box (suspected; re-shoot).
- **formattingtray:** Android Dark and 2.0× show Comments loading, and Android Light shows New comment without the tray.
- **chapterpicker:** Android OLED shows no sheet.

## Per-screen verdicts (written as I go)

- **libpicker: minor (unchanged from A82).** The Filter Fandoms field is at the top on Android and floats at the bottom on iPhone, in all columns. Each is its platform's own search placement; it may be worth adding to the decided list. Nothing else differs.
- **queuesettings: match.** A82's difference is gone: Android's breadcrumb now wraps onto two lines at the largest size ("HOME › QUEUES › QUEUE / DETAILS"), as the iPhone's does.
- **newqueue: minor.** The colour swatches don't follow the theme on Android. The iPhone's are darkened in Dark and OLED and paled in Light and Sepia; Android's are the same mid tones in every column. Also, Android's Start From radio labels sit tight against their circles. A82 called this screen a match, so this went unnoticed then rather than being new.
- **editqueue: minor.** The same swatch tones as newqueue (all columns, Android). Otherwise a match.
- **addworks: differs, plus a capture problem.**
  - **Capture:** Android's Light column shows Home; the sheet did not open.
  - **Differs (iPhone, largest column):** the bylines break mid-word and end in "…" ("by un- / cle_iroh…", "by under- / tow"), while Android wraps them whole. A82's byline cut is not gone. (The cut sheet title is excluded, being fixed in I12.)
  - **Minor (Android, all columns):** the bylines drop "by", and the second one ("undertow") is drawn in the accent while the first is grey.
- **queuetag: match.** A82's minor is gone: Android's selected rows show only the check, without "All". Android draws a full page where the iPhone has a sheet over the queue (decided).
- **queuetags: differs (Android, all columns). A82 missed it and called this screen a match.**
  - The Unused rows have lost their height: "Long fic 0 ⋮" and "Rereads 0 ⋮" are squeezed together with no padding.
  - Both footnotes ("Unused tags stay here…" and "A tag you use here…") start at the screen's edge instead of the page gutter.
  - The iPhone draws full-height rows inside the gutter.
  - Corrected after Claude's check: this isn't 3gx's doing. The A82 Android shot is pixel-identical, so the difference predates the fixes.
- **queuetagedit: match.** A82's difference is gone: both now read Name, then Merge into another tag, then Remove. Android's dialog against the iPhone's sheet is decided. A small one: Android's merge target ("Long fic · 0") is a plain line, where the iPhone's is a row in a card.
- **bulktag: minor.** A82's difference is gone: Android now opens the bulk Tag sheet ("Your changes apply to all 5 selected works.", leading circles).
  - Left over (Android, all columns): the page carries the queue's purple wash where the iPhone's sheet is the plain theme.
  - The group header reads "YOUR TAGS" against the iPhone's "Your tags".
- **addtoqueue: match.** A82's differences are gone:
  - the iPhone's sheet is Sepia in Sepia and at the largest size;
  - Android has the leading queue icons;
  - New queue and Add share one row.
  - Android's Series section is demo data (its demo work has a series), and its red icons follow the wash under the sheet (decided). At 2.0×, Android's Done drops below the title (chrome).
- **queuestorage: match.** Android draws a page with a SETTINGS kicker where the iPhone has a sheet (decided). The iPhone's "Queue" badges are demo data (Android's demo has no queue-only works). Android's creator names are in the accent; the iPhone's are grey.
- **collectiondetails: minor.** A82's difference is gone: the title is the collection's name, there's no Name field, and Colour sits above Description.
  - Left over (Android, all columns): the swatch tones don't follow the theme (as newqueue), and the swatch row sits on the page where the iPhone puts it in a card.
  - Android's multi-line Description is decided.
- **newcollection: differs (Android, largest column).** Android's bar title is cut: "New collect…" between Cancel and Create, where the iPhone shows "New collection" whole.
  - Also minor, unchanged from A82 except the gone COLOUR heading: Android lays out separate NAME and DESCRIPTION labels over outlined fields, with the swatches below. The iPhone has one COLLECTION card holding Name, Description and the swatches. The swatch tones are as newqueue.
- **collectionreorder: minor.** A82's difference is gone: the iPhone now wraps "Unanswered Is Not Unread" in full at the largest size.
  - New to note (Android, all columns): each row has ⌃/⌄ move buttons where the iPhone has drag handles (≡). A82 didn't raise it. If Android's buttons are the decided accessible alternative, this is a match.
- **addtocollection: match.** A82's difference is gone: the iPhone's sheet is Sepia in Sepia and at the largest size. Android's dialog with checkboxes is decided, and the two collections' order is the decided demo-instant order.
- **fandomlist: minor (unchanged from A82).**
  - Android's Group variants chip has no leading icon (all columns).
  - The search field is at the top on Android and at the bottom on iPhone, as libpicker.
  - Both clip the chip row at the largest size. Android now stacks the family figures below the names at 2.0×.
- **fandomworks: differs (Android, all columns).**
  - **Gone from A82:** at the largest size, Android's Date Updated sort control now sits under the heading instead of being crushed into a column.
  - **Still there (A82 noted it):** the iPhone shows the page's fandom as a filter chip ("Doctor Who") and counts "1 FILTERS". Android shows "0 FILTERS" and no chip, so nothing on Android's page says which fandom it is for; the heading is the fixture's "Star Wars - All Media Types" on both.
  - **Minor (all columns):** the page wash is green on Android, the Browse page's colour, but peach/brown on the iPhone.
- **tagworks: minor.** A82's difference is gone: the sort control sits under the heading at the largest size. The same wash difference as fandomworks (Android green, iPhone peach/brown) remains, in all columns.
- **fandomfilter: match.** A82's difference is gone: Android's sheet opens at full height, with the Show 5 tags button pinned at the bottom in every column, including 2.0×. Android's chips for Minimum works against the iPhone's segmented control is chrome.
- **savesearch: match.** A82's difference is gone: the iPhone now has its "Save Search" title and pre-fills the name ("Star Wars"). The searches differ (Star Wars against Doctor Who) only because of what each shot opened, and Android's sheet sits over its Filters sheet (decided).
- **pagejump: minor.** A82's difference is gone: Android is now the iPhone's sheet (page number "of 3", Nearby, First page / Last (3)); the slider and big readout are gone.
  - Left over (Android): the current Nearby tile is purple in Dark, OLED and Light where the iPhone's is the tan page colour.
  - In OLED, Android's other Nearby tiles have no fill, while the iPhone's have dark tiles.
- **languagepicker: match.** Android's stacked sheet over Filters, where the iPhone pushes a page in its sheet, is decided.
- **tagpicker: match.** A82's difference is gone: with nothing typed, Android's Results now says "Type above to search AO3 fandoms." instead of listing the library's fandoms.
  - Not comparable here: the iPhone's Selected group. Android's shot has no fandom chosen (its Filters read "Fandoms Any"), so the two are in different states, not different designs.
  - Small: Android's note is a compact bubble, where the iPhone's is a full-width row.
- **downloaddate: match.** A82's difference is gone: the iPhone's sheet is Sepia in Sepia and at the largest size. Android's date dialog over My copy, against the iPhone's sheet with a compact date, is decided dialog chrome. The dates are demo data.
- **seriespreserve: match.** A82's minor was demo data: the iPhone's preview couldn't count the series, while Android's counted 4 works, and both prompts are the same code path. Android's red band is the wash under the sheet (decided).
- **bookmarkform: match.** A82's difference is gone: the iPhone's "Bookmark on AO3" title is whole at the largest size, and both stack Private and Recommend above their switches there. Android's shot opens an existing bookmark ("Edit Bookmark on AO3", "Test bookmark", Private on), which is demo state.
- **pronunciations: minor, plus capture problems.**
  - **Capture:** the iPhone's Light column shows the Account page, and its largest column shows Settings › Listening. The Pronunciations page didn't open in either.
  - **Gone from A82:** the inline Add, Paste and Copy rows are now in Android's ⋮ menu.
  - **Minor (Android, Dark, Sepia, OLED and 2.0×):** the empty state is plain centred text. The iPhone draws it in a card with a speech-bubble icon.
  - Android's extra paragraph ("Corrections are saved and included in backups and sync. The current Android Kokoro Voice Pack and device voice cannot apply them yet.") is its own true information, so it is not reported.
  - A side note: behind Android's sheet, the Listening page's "Audition Voice / Sample Text" draws under the status bar's clock.
- **pronunciationedit: match, plus capture problems.**
  - **Capture:** the iPhone's largest column shows Settings › Listening, and Android's OLED column shows the Listening page with no sheet open.
  - **Gone from A82:** Word and Pronunciation now appear once each, as section labels over the fields.
  - Android's two footer notes about what its engine can't do are its own information. Cancel and Save at the sheet's foot are chrome.
- **customizetheme: match in the one usable column (Sepia); four capture problems.**
  - **Capture (Android):** the Dark column shows "Kudos isn't responding" over Settings › Appearance, and OLED and 2.0× show Appearance with no sheet open.
  - **Suspected, re-shoot (Android, Light):** the sheet opened, but its preview is a blank black box.
  - **In Sepia, A82's differences are gone:** four round "Aa" swatches with the current one checked, and the preview card. Android's extra third paragraph is the decided scrollable preview.
- **formattingtray: minor; capture problems in three columns.**
  - **Capture (Android):** Dark and 2.0× show the Comments page loading, with no tray. Light shows the New comment sheet without the tray.
  - **Minor (Android, Sepia and OLED):** the tray's header is "Formatting" alone, while the iPhone's has a Done button (`comments/CommentMarkup.kt:268-274` draws only the title). Dragging the sheet down closes it, so nothing is lost.
  - The tiles and groups match.
- **chapterpicker: minor; a capture problem.**
  - **Capture:** Android's OLED column shows the comments page with no sheet.
  - **Gone from A82:** at the largest size the iPhone now wraps "Chapter / 1" instead of cutting it to "Chapt…".
  - **Minor (Android, all usable columns):** each row (All Comments, Chapter 1–3) is its own card, where the iPhone has one grouped card with dividers. Android's chapter icons are small page glyphs, not the iPhone's open book.
  - Which row is checked differs by shot state (iPhone on Chapter 1, Android on All Comments).
- **inboxfilter: match.** A82's minor is gone: the iPhone's sheet has its "Inbox Filters" title (I9b). At AX5 the iPhone moves each checkmark under its label; Android keeps it at the right. Both show the same groups, in the same order, with the same checks.
