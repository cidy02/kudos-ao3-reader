# A88b (CLI second opinion): the second 36 A82 screens after the fixes

*Done, 2026-10-23.*
- The second opinion beside Gemini's A88b, from the tiles in `/Users/cidy02/kudos-tools/pairs/tiles-a88/`. Read only: no other file changed.
- 35 screens looked at. `readerspeech` was skipped as asked.

## Counts

**Match 17 · minor 10 · differs 6 · no verdict 2 (every Android column a capture problem) · capture problems on 23 of the 35.** Android's "Kudos isn't responding" alone appears in 15 columns.

Of A82's 18 "differs" in this half, 15 are gone. One is still there (`seriesdetail`: Android's card lacks the bookmark count, Restricted and the date). `colitems` keeps the iPhone's cut creator name, and `chapterform` couldn't be judged. Four screens differ in new ways (`seriesreorder`, `seriesremove`, `colsfilter`, `texteditor`).

## Differs

- **texteditor:** Android, 2.0×. Done (✓) is pushed off the bar by the "Chapter text" title added on landing (`e0162833`). It's the one that matters most: Done delivers the text.
- **colsfilter:** iPhone, AX5. The last option ("Unrevealed") shows through the top of the pinned Reset button. My I10 gradient fades from the bottom, so the button's top half sits on nearly clear ground. The fix is small: opaque up to the button, fading above it.
- **seriesdetail:** Android, all columns.
  - The card lacks the iPhone's bookmark count, Restricted and the date when the page is opened directly.
  - The work cards drop their zero figures.
  - The page and cards carry a green wash where the iPhone's are plain.
- **seriesremove:** Android, all columns. An extra "words · date" line under each title. It's extra information: add it to the decided list if kept.
- **colitems:** iPhone, all four ordinary columns. The creator name in each card's footer is cut to "AO3_Reader…" (still there from A82).
- **seriesreorder:** Android, 2.0×, suspected. No Save in the bar. Re-shoot to rule out timing.

## Minor

- **Sheet colours (prefhelp, and recovery in OLED):** Android's sheet takes Material's default surface, lavender in Light and grey in OLED. The iPhone's is the theme's white and black.
- **availability:** an orphan accent rule above the title on Android, left when 3gx removed the SETTINGS kicker.
- **privacydata:** no Account wash at the top of Android's page.
- **chsettingsedit:** Save changes is a plain row on Android, not the iPhone's pinned filled button.
- **bulknames:** Android's Add is on its own row under the field.
- **collectionsgifts:** a recipient's remove is ✕ on Android, ⊖ on the iPhone.
- **pairing:** Android's actions are separate cards without icons.
- **authorbookmarks:** Android's cards are fandom-tinted, there's no "Bookmarks" label, and Load More isn't a card.
- **parentpicker:** at AX5 the iPhone's wrapped URL gets a system hyphen ("archiveo- fourown.org").
- **recovery:** Android's OLED sheet is grey.

## Capture problems (not verdicts)

**"Kudos isn't responding" (Android):**
- seriesedit Sepia, colitems Dark, chsignupdetail 2.0×, chapterform Light and Sepia;
- tagseditor Dark, Light and OLED; texteditor Dark and OLED; recovery Dark;
- collectionsgifts Dark, backupimport Light, authorbookmarks Dark.

**The wrong screen or still loading (Android):**
- seriesedit Dark (spinner), seriesremove Sepia, authorworksfilter Dark, Sepia and OLED;
- chapters (all five), chapterform Dark, OLED and 2.0×;
- seriespicker Dark, collectionsgifts Sepia (and Dark/OLED listing only 2 of 5 collections);
- creatorspicker 2.0×, parentpicker Light, bulkedit Dark and 2.0×;
- bulktagstate Dark, Light, Sepia and OLED; bulknames Dark, Sepia and 2.0×;
- revokedevice OLED, authorbookmarks Light.

**Also:** chapterform's Android route opens **Edit** chapter (of another work), where the iPhone opens **Add** chapter.

**The wrong screen (iPhone, AX5):** chsettingsedit, tagset and tagseteditor show the collection's page.

## Per-screen verdicts (written as I go)
- **authorabout: match.** Same Bio and Account sections in every column. Android's frame ends sooner at 2.0× (decided).
- **seriesdetail: differs (Android, all columns). A82's difference is mostly not gone in this shot.**
  - **The series card:** Android shows "3 works · 45,678 words · Complete". It lacks the iPhone's bookmark count (62), Restricted and the date (08 Jul 2026).
    - 3gx carries those facts through author and dashboard navigation. This shot opens the page directly, so the facts would have to come from the page itself. The iPhone's card reads them from the same page, so either Android's parse misses those three figures or its shot fixture lacks them.
  - **The work cards:** Android drops the zero figures (0 comments, kudos, bookmarks, hits) that the iPhone shows. The byline shows the name alone in the accent, against the iPhone's grey "by Avery Writes".
  - **The page:** Android draws a green subject wash, with green-tinted cards. The iPhone's series page is the plain theme with plain cards.
  - **Gone from A82:** the fandom moved into the card ("Star Wars"), and the duplicate page title.
- **seriesedit: match, plus capture problems.**
  - **Capture (Android):** the Dark column is still loading (spinner), and the Sepia column shows "Kudos isn't responding" over the Series page.
  - Light, OLED and 2.0× match the iPhone's layout, sections and order. The title and summary are demo data.
- **seriesreorder: differs, suspected (Android, 2.0× column).** There's no Save in the bar at 2.0× (checked in a crop), though every other Android column has it. Re-shoot to rule out timing.
  - **Gone from A82:** Android has drag handles with Draft beside the title, and the iPhone wraps the titles in full at the largest size.
  - The Draft badge is uppercase on Android ("DRAFT") and title case on the iPhone.
- **seriesremove: differs (Android extra information, all usable columns); a capture problem.**
  - **Capture (Android):** the Sepia column shows Edit series still loading.
  - **Gone from A82:** both apps now open with "The Dawn Cycle · 3 works" and list the three works.
  - **Left over:** Android adds a second line under each title ("21,678 words · 08 Jul 2026") that the iPhone doesn't show. That's extra information, so it counts as differs by the brief's rule. If it is to be kept, it belongs on the decided list.
  - Also, Android's Light column shows a greyed Save in the bar where the other columns show none (probably timing).
- **authorworksfilter: match, plus capture problems.**
  - **Capture (Android):** in Dark, Sepia and OLED the sheet isn't open; they show the author page loading or loaded.
  - **Gone from A82:** in Light and 2.0×, the extra Direction label. The sheet otherwise matches the iPhone, with the same groups in the same order.
- **colitems: differs (iPhone, Dark, Light, Sepia and OLED); a capture problem.** Unrevealed and Anonymous, and which page each app opens, are decided and not reported.
  - **Capture (Android):** the Dark column shows "Kudos isn't responding".
  - **Still there from A82:** each card's footer cuts the iPhone's creator name to "AO3_Reader…", beside Remove from collection and the date. Android shows "winterquill (Member)" whole.
- **colsfilter: differs (iPhone, largest column). My fault, from I10.**
  - **Gone from A82:** the white bar. The pinned Reset bar now takes the page's ground in Light and Sepia.
  - **But at AX5,** the "Unrevealed" row scrolls under the Reset button and shows through its top half: "Unrevealed" and "Reset" overlap (checked in a crop).
  - **Cause:** I10's gradient (`Features/Account/AO3CollectionsFilterPanel.swift:172-182`) runs evenly from opaque at the bottom to clear at the top. The button sits in the middle, so its upper half is over nearly clear ground.
  - **Fix:** keep the ground opaque up to the button's top and fade only above it, with stops `[backdrop @0, backdrop @0.75, clear @1]` and some top padding. It's small; I can take it if you brief it.
  - Android matches, its Reset at the foot of the sheet.
- **chsettingsedit: minor; a capture problem.**
  - **Capture:** the iPhone's largest column shows the collection's own page (Winter Exchange 2026), not the settings.
  - **Gone from A82:** Android has the uppercase SIGN-UP INSTRUCTIONS label over its field.
  - **Left over (Android, all columns):** Save changes is a plain list row at the foot. On the iPhone it's a filled accent button pinned over the bottom of the page.
  - **Not reported:**
    - The subtitles and wash colours differ with the demo's collections (Winter Fest / "winter_exchange · 4 sign-ups" against "Winter Exchange 2026").
    - Android's Assignments sent and Works due rows sit where the iPhone's frame ends, under its pinned bar.
    - Android's one date-and-time dropdown against the iPhone's two pills is chrome.
- **chsignupdetail: match; a capture problem.**
  - **Capture (Android):** the 2.0× column shows "Kudos isn't responding".
  - The same request and offer groups in the same layout. The person, tags and wash colour are demo data, since each wash follows its page's own title.
- **prompttags: match.** The same four labelled fields, in the same order, under "REQUEST 1 / Tags / Comma-separated tag names". The iPhone's fields show placeholders, Android's the demo's values. The wash colours follow each demo's challenge, and Done against ✓ is chrome.
- **tagset: match; a capture problem.**
  - **Capture:** the iPhone's largest column shows the collection page, not the tag set.
  - Ownership, Tags and Nominations match row for row. The counts (0 against 7 tags) are demo data. Both draw the same brown wash, which bears out that a wash follows its page's title.
- **tagseteditor: match; a capture problem.**
  - **Capture:** the iPhone's largest column shows the collection page.
  - **Gone from A82:** Android's labels are uppercase inside each card ("FANDOM TAGS TO ADD" …), and Save tags is a centred filled button in the wash's colour, as on the iPhone. The iPhone's fields hold demo values, Android's show placeholders.
- **writingpreview: match.** The same order: summary, notes, then the POST group with its two actions. The work differs, and with it Post work against Update and the draft notice: a never-posted draft on the iPhone, a posted work with notes on Android.
- **chapters: no verdict (capture problems in every Android column).** Android's five columns show, in order: Home, Edit work loading, "Loading chapters…", Edit work loading, and a blurred Home. The iPhone's list (three chapters with dates) is fine.
- **chapterform: no verdict (capture problems in every Android column).**
  - Android Dark and OLED show Home, Light and Sepia show "Kudos isn't responding", and 2.0× shows Edit chapter loading.
  - Also check the shot's route: what shows behind Light's dialog is **Edit chapter** ("Lanterns Above the Mill · chapter 1"), where the iPhone opens **Add chapter** ("The Weight of Water · chapter 3").
- **edittags: match.** Rating and Archive warnings are listed and ordered the same, with the same footnote. Which options are checked is demo data.
- **tagseditor: match; capture problems.**
  - **Capture (Android):** Dark, Light and OLED show "Kudos isn't responding" over the page.
  - In Sepia and 2.0×, the field, the chips with ✕ and the footnote match the iPhone's. The tags are demo data.
- **texteditor: differs (Android, 2.0× column); capture problems.**
  - **Capture (Android):** Dark and OLED show "Kudos isn't responding".
  - **Differs (Android, 2.0×):** the bar holds "Chapter text", the eye, undo, redo and a ⋯ cut at the right edge. Done (✓), which delivers the buffer, is pushed off the screen. The other columns show it.
    - The bar's title was added on landing (`e0162833`, "the text editor names its field in the bar").
    - The iPhone's bar has no title: its content's kicker ("SUMMARY · 7 words") names the field, as Android's "CHAPTER 13 · 14 words" also does.
    - **Fix:** drop the bar title at large font scales, or let it shrink, so that ✓ stays.
  - **Gone from A82 (iPhone, AX5):** the footer "Recovery copy on this device · Save from the work form" is whole, and Done is the ✓.
  - **Minor (iPhone, AX5):** the footer, tag bar and AO3 note leave the editor itself one line tall. It scrolls, so nothing is lost. That trade came from my I10 `fixedSize`. If it matters, the AO3 note under the tag bar could go at accessibility sizes.
- **recovery: minor; a capture problem.**
  - **Capture (Android):** the Dark column shows "Kudos isn't responding".
  - **Gone from A82 (iPhone):** the sheet is Sepia in Sepia, and at AX5 the heading and paragraphs wrap in full in a scrolling sheet.
  - **Minor (Android, OLED):** the sheet is Dark's grey, not OLED black. The iPhone's is black.
  - The iPhone's second paragraph and the copy text are the demo's state, as I10 noted.
- **seriespicker: match; a capture problem.**
  - **Capture (Android):** the Dark column shows Edit work, not the series picker.
  - The same groups in the same order: Your series, the footnote, Position in…, Reorder the series, New series.
  - The state differs: Android's work is already in its series ("is part of one series", "This work is in it"), while the iPhone's is about to be added ("Saving adds …"). Android marks its series with a ✓, the iPhone with a filled circle (chrome).
- **collectionsgifts: minor; capture problems.**
  - **Capture (Android):** Dark shows "Kudos isn't responding", and Sepia shows Home.
  - **Capture, timing:** Dark and OLED list only the work's two current collections ("YOUR COLLECTIONS 2"), while Light and 2.0× list all five. The account's collections hadn't loaded yet.
  - **Minor (Android):** a gift recipient's remove is a red ✕, against the iPhone's red ⊖ (as on its own remove rows).
  - Otherwise the same order: Search, collections with their states, the footnote, Gift recipients with Add, Also on this work.
- **creatorspicker: match; a capture problem.**
  - **Capture (Android):** the 2.0× column shows Edit work loading.
  - Your pseuds and Invite a co-creator match the iPhone's, footnote included. The pseud names are demo data.
- **parentpicker: minor (iPhone, AX5); a capture problem.**
  - **Capture (Android):** the Light column shows Edit work loading.
  - **Gone from A82:**
    - the iPhone's "Language of the source" value now wraps ("Please select / a language") instead of "Please select a la…";
    - both apps' URL fields wrap instead of clipping their end (Android puts the label above the value, which is chrome).
  - **Minor (iPhone, AX5):** the wrapped URL in the field gets a system-inserted hyphen ("https:// archiveo- fourown.org/ works/1"), which reads as part of the address. Turning hyphenation off for that field would avoid it. The language values (unset against English) are demo data.
- **bulkedit: match; capture problems.**
  - **Capture (Android):** Dark and 2.0× show the author page, not the editor.
  - In Light, Sepia and OLED: the same order (the note, Tags to add, Tags to remove, Change on all), the same rows, and "None" / "Leave as is". The count (2 against 3 works) is demo data. Cancel and Save against ✕ and ✓ is chrome.
- **bulktagstate: match, in the one usable column (2.0×); capture problems in four.**
  - **Capture (Android):** Dark and Sepia show the author page, and Light and OLED show "Loading 2 works…".
  - **Gone from A82:** the iPhone's option card is Sepia in Sepia and at AX5.
  - **In 2.0×:** the two options with their circles and the three-state footnote match. Android's "AO3 ACCOUNT / Archive warnings" header block against the iPhone's bar title is a page against a pushed view.
- **bulknames: minor; capture problems.**
  - **Capture (Android):** Dark shows the author page, and Sepia and 2.0× show "Loading 2 works…".
  - **Gone from A82 (iPhone):** the field is a rounded Sepia card, not a white band, and the field and Add share one row.
  - **Minor (Android, Light and OLED):** the card has "Collection name" with its field on one row, and Add on a second row beneath. The iPhone has the field and Add side by side, as Android's own Add to Queue now does.
  - Android's header block against the iPhone's bar title is a page against a pushed view.
- **prefhelp: minor.**
  - **Gone from A82:** the iPhone's redundant title card, so the topics start at the top on both.
  - **Minor (Android, Light and OLED):** the sheet takes Material's default surface, lavender-tinted in Light and grey in OLED. The iPhone's is the theme's white and black.
  - Android's 2.0× sheet fills the screen (frame).
- **privacydata: minor.**
  - **Gone from A82:** the Imported fonts row (Android). Current iOS shows it too, only when fonts were imported, and the iPhone's demo has none (Codex's 3gx check), so it's demo data.
  - **Minor (Android, all columns):** the page has no wash. The iPhone's Privacy page has the Account's red/pink wash at the top. The sizes are demo data.
- **availability: minor.**
  - **Gone from A82:** at AX5 the iPhone's title is the inline "Check Availability" in the bar, whole (I10).
  - **Minor (Android, all columns):** a short accent rule sits alone above "Check Availability". 3gx removed the SETTINGS kicker but left the kicker's rule under where it was.
  - The work counts (1 against 2) are demo data, and Done against ← is a sheet against a page.
- **pairing: minor.**
  - **Gone from A82:** the iPhone's sheet and cards are Sepia in Sepia and at AX5.
  - **Minor (Android, all columns):** the actions are separate cards without the iPhone's leading icons. The iPhone has one card holding icon rows.
  - The iPhone's Scan a QR Code is decided out on Android, and Android says so in its own words.
- **revokedevice: match (the iPhone's cut title excluded, as asked); a capture problem.**
  - **Capture (Android):** the OLED column shows the Sync Folder page with no dialog.
  - **Gone from A82:** the iPhone's Reason card is Sepia in Sepia and at AX5.
  - Android's dialog (title whole, the reason radios, Revoke and Cancel) against the iPhone's sheet is decided dialog chrome. These iPhone shots predate I12, so its new heading can't be judged yet.
- **backupimport: match; a capture problem.**
  - **Capture (Android):** the Light column shows "Kudos isn't responding".
  - **Gone from A82:** the iPhone's This backup, Merge and Replace Library… cards are Sepia in Sepia and at AX5. Both show the same counts, Merge's "It removes nothing" note and the Replace note.
- **aboutkudos: match.**
  - **Gone from A82:** the iPhone's licence name is bold, with no asterisks (I10).
  - Android's version line carries the commit ("0.2.1 (9) · 47fbc6e"). The iPhone's Xcode-built shot has none; its IPA script adds one. Version numbers are build data, and Android's About is a page with a SETTINGS kicker where the iPhone's is a sheet.
- **authorbookmarks (new pair): minor; capture problems.**
  - **Capture (Android):** Dark shows "Kudos isn't responding", and Light is still loading (placeholder rows).
  - **Minor (Android, Sepia, OLED and 2.0×):**
    - the bookmark cards are tinted with their fandom's colour (purple, green), where the iPhone's are plain theme cards;
    - there's no "Bookmarks" group label over the list;
    - Load More is a bare row, not a card.
  - Android's extra first card (a blurred local work with its 63% ring) is its decided local-progress information, and the bookmarks listed are demo data.
