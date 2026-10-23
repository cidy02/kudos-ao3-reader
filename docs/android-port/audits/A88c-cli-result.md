# A88c result: the re-shot screens (Claude, CLI)

*Done, 2026-10-23.*
- Read only: no file changed but this one. Tiles in `/Users/cidy02/kudos-tools/pairs/tiles-a88c/`. Crops and pixel samples were made from `~/kudos-tools/pairs/shots/` into my scratchpad.
- The "Decided, not changed" list in `A88-triage.md` isn't reported.

## Counts

**Match 22 · minor 15 · differs 4 · capture problems on 4 of the 41.**

- **A88's differences:** all nine in this set are gone or decided: addworks, newcollection, fandomworks, queuetags, texteditor, colsfilter, colitems, seriesreorder (timing), and seriesremove (decided). seriesdetail isn't in this set (3ha's follow-up).
- **A88's capture problems:** gone on every screen but three.
  - The iPhone's AX5 pronunciations and pronunciationedit still show Listening.
  - Android's OLED revokedevice still shows no dialog.
  - One new one: formattingtray's Android Sepia column.
- **New pairs judged for the first time:** readercontents, readerfind, readerdisplay, readernote, readerspeech and chapters.
- **I15 can't be judged:** the iPhone `parentpicker` shots (10:06–10:07) predate I15 (10:15), so they show I14's hyphen.

## Differs

- **tagseditor and collectionsgifts** (Android, all columns). The wash restarts at the pinned field: there's a hard edge, then a second band of wash.
  - Cause: both pinned headers draw their own `.subjectWash(palette, SubjectMetrics.defaultWashHeight)` as an opaque ground (`writing/WritingTagsEditorScreen.kt:126-130`, `writing/WritingAssociationPickers.kt:131-133`).
  - In since `531a11a9` (7 Oct), so A88's shots had it too and A88 missed it.
  - One fix shape for both: an opaque ground only once the field is pinned.
- **readerspeech** (iPhone, AX5). The Sample Text picker's value is cut to "Plain…rration". Android's is whole. The same section appears on Settings › Listening, where the iPhone's AX5 shots show the same cut.
- **chsettingsedit** (Android's pre-3ha column). Save changes is a plain row. The iPhone side is now right, and 3ha's shots should settle it.

## Minor

- **Cards in Android's sheets are darker than the sheet in Sepia** (readerdisplay, readernote, pronunciations, backupimport). They're also darker in Light where the iPhone's cards are white (pronunciations, backupimport). The iPhone's are lighter: cream #FBF0D9 or white.
  - That fits Android's `panelFill` (`theme.glassFill(0.09)`, an ink overlay, `ui/subject/KudosTokens.kt:148`), though I didn't trace which modifier each sheet uses.
- **queuetags:** Add looks enabled with an empty field. The explicit `color = palette.accent` overrides the disabled colour (`library/QueueTags.kt:458`, `:225-226`).
- **texteditor:** Android's bar title is cut in every column ("Chapter …", "Cha…"), and the kicker already names the field. The iPhone's AX5 editor is still one line tall.
- **customizetheme:** uppercase section headers; no chevron on Font; and at 2.0× the preview text grows, though the reader's text doesn't.
- **pagejump:** the current Nearby tile is the red accent, not the page's tan (Dark, Light, OLED).
- **parentpicker:** the iPhone's AX5 hyphen. These shots predate I15, so re-shoot it after T-440.
- **Left over from A88:**
  - addworks: Android's bylines drop "by", and one is in the accent.
  - chapterpicker: page glyphs, not an open book; the row labels' colour.
  - newcollection and collectiondetails: the swatches aren't in a card.
  - newqueue: the radio labels are tight.
  - collectionreorder: a card per row.
  - collectionsgifts: ✕ against ⊖.
- **Small, not counted:**
  - "DRAFT" against "Draft".
  - The works pages' pager arrow in red and their date format ("09 Jul 2026" against "07/09/2026").
  - Android's reader sheets open at full height with the keyboard up.

## Capture problems

- **pronunciations, pronunciationedit:** the iPhone's largest column still shows Settings › Listening (shot at 10:02 and 10:04 today).
- **revokedevice:** Android's OLED column still shows Sync Folder with no dialog.
- **formattingtray:** Android's Sepia column shows the New comment sheet without the tray.

## Per-screen verdicts

- **readercontents: match.** The capture fault is gone: Android shows the reader with its Contents sheet in every column.
  - **Gone from A82:** Android's inline Bookmark and Add Note buttons. Each row is the title and its percentage, as on the iPhone, and at 2.0× the titles are whole ("Preface 0%", "Chapter 1 11%"), no longer crushed to "Pref / ace".
  - Same title, Done ✓, and Contents / Bookmarks / Highlights segments.
  - The books differ (demo data). The iPhone's glass sheet at its half-height detent, against Android's sheet on the theme's ground, is chrome.
  - Small (Android, Sepia and 2.0×): the Done ✓ is dark grey, where the iPhone's is the Sepia accent. Android has no dividers between rows.
- **readerfind: match.** The capture fault is gone (A82's blank 2.0× column, A88's Home): every Android column shows the Find in Work sheet.
  - Same title, Done ✓, search field and empty state ("Find in Work / Search the text of this work. Tap a result to jump to that passage.").
  - Android opens the sheet at full height with the field focused and the keyboard up. The iPhone opens at half height and waits for a tap. That's a behaviour note, not a lost item.
- **readerdisplay: minor (Android, Sepia).** The capture fault is gone. The part both show matches.
  - The iPhone's half-height sheet shows Appearance (Light / Sepia / Dark / OLED, Customize Theme…), Text Size and Reading (Scrolled / Paged); Android's opens taller and shows the same three in the same order.
  - Android's further rows (Keep screen awake, the "Choose whether you turn pages…" note, Audition Voice) are on the iPhone too, below its fold (`Settings/SettingsView.swift:54-59`, `:138-145`), in the same order.
  - Android's dotted stepped sliders against the iPhone's plain ones are chrome.
  - **Minor (Android, Sepia):** the cards are a darker tan than the sheet (#E0D3B7 on #ECDEC1), where the iPhone's are lighter cream (#FBF0D9, sampled). The check and "Customize Theme…" are dark grey, not the Sepia brown.
- **readernote: minor (Android, Sepia).** The capture fault is gone (A82's loading skeleton in Dark and 2.0×, A88's Home): every Android column shows Add Note.
  - Same order: Cancel, Add Note, ✓; the Highlighted quote with its yellow rule; the Note field; Colour with five swatches and None.
  - Android opens at full height with the note focused and the keyboard up; the iPhone opens at half height (behaviour, as readerfind). The quotes are demo data. Cancel as text against the iPhone's capsule is chrome.
  - **Minor (Android, Sepia):** the same darker-tan cards as readerdisplay, where the iPhone's are lighter cream.
- **readerspeech: differs (iPhone, AX5).** New pair; A88 had no verdict (Android showed Home). Android now shows the sheet in every column.
  - **Differs (iPhone, largest column):** the Sample Text picker's value is cut in the middle to "Plain…rration" (checked in a crop). Android's 2.0× shows "Plain Narration" whole under its label. It's the system menu picker's own truncation (`Features/ReaderReadium/ReaderSpeechAuditionHarness.swift:133-138`, a plain `Picker` in the form). A label that wraps, or the value under the label at accessibility sizes, would avoid it.
  - Otherwise the same order: Audition Voice (Sample Text, Speed with Default (1.0x), the 0.9x / 1.0x (default) / 1.1x buttons, Play Sample, the footnote), then Kokoro Neural Engine. The iPhone's half-height sheet stops there; Android's taller one goes on to the download row, its privacy note and Read Aloud (Engine, Voice, Pronunciations).
  - The iPhone's "Done" capsule against Android's ✓ is chrome. (The iPhone's own other reader sheets use ✓.)
- **addworks: minor (Android, all columns).** The capture fault is gone: Android's Light column shows the sheet.
  - **Gone from A88 (iPhone, AX5):** the bylines are whole ("by uncle_iroh_fan"), and the circle sits under them (I13). The iPhone's title card is whole too (I12).
  - **Left over, as in A88a (Android):** the bylines drop "by", and the second ("undertow") is in the accent while the first is grey.
  - Not reported: Cancel/Add at the foot (decided); Show mature as text against the iPhone's eye (chrome). At AX5 the iPhone's floating search field sits over the second byline, which scrolls clear.
- **customizetheme: minor.** All four capture problems are gone: every Android column shows the sheet, and Light's preview is drawn.
  - A82's differences stay gone in all columns: four round "Aa" swatches with the current one ringed and checked, and the preview card.
  - **Minor (Android):**
    - The section headers are uppercase ("TEXT", "ACCESSIBILITY & LAYOUT"), where the iPhone's are "Text" and "Accessibility & Layout". Android's own reader sheets use title case.
    - The Font row has no chevron after "System".
    - At 2.0× the preview's text grows with the font scale ("A Study in / Starlight" over two lines), though Android's reader text doesn't (readercontents' 2.0× reader is the usual size). The iPhone's preview stays at the reader's size at AX5, so it still previews the page.
  - Android's extra third paragraph is the decided scrollable preview.
- **formattingtray: match; a capture problem.**
  - **Capture (Android, Sepia):** the New comment sheet is open but the tray isn't ("Drag the sheet taller" and the inline toolbar show).
  - **Gone from A88:** the capture problems in Dark, Light and 2.0× (all now show the tray), and the missing Done: Android's tray header now has Done (3gz).
  - The same tiles in the same groups and order (Text, Blocks & Links, h1–h6), one per row at the largest size on both.
  - Android's glyphs differ in places (X² for A², тT for Aa, a quote mark, an eye for Spoiler), and Done is text against a capsule: chrome. Android's tray sits over the New comment sheet; the iPhone's shot shows it over the page.
- **chapterpicker: minor (Android, all columns).** The OLED capture problem is gone.
  - **Gone from A88:** Android now draws one grouped card with dividers (3gz), not a card per row. The iPhone's "Chapter 1" stays whole at AX5.
  - **Left over:** the chapter icons are small page glyphs, not the iPhone's open book. The iPhone's row labels are all in the page's purple; Android's are plain, with only the chosen row in red.
  - Which row is checked is shot state (iPhone on Chapter 1, Android on All Comments), as is the work behind.
- **pronunciations: minor; a capture problem.**
  - **Capture (iPhone, largest column):** still Settings › Listening, not Pronunciations (shot at 10:02 today, so the re-shoot didn't reach it at AX5). The iPhone's Light column now shows Pronunciations: that capture problem is gone.
  - **Gone from A88:** Android's empty state is now a card with the speech-bubble icon, as the iPhone's.
  - **Minor (Android, Light and Sepia):** the card is darker than its ground: #E6E6EA on #F2F2F7 in Light, a darker tan on tan in Sepia. The iPhone's is white on #F2F2F7 and cream on tan (sampled). The same inversion is on Android's reader sheets (see Minor).
  - Not reported: Android's sheet over Listening with ⋮ and Done, against the iPhone's pushed page with ⋯ (chrome); its footnote (decided voice-engine note). Behind Android's sheet, the Listening page still draws "Audition Voice" under the status bar's clock, as A88a noted.
- **pronunciationedit: match; a capture problem.**
  - **Capture (iPhone, largest column):** still Settings › Listening (shot at 10:04 today). Android's OLED capture problem is gone.
  - Word and Pronunciation once each, as labels over their fields, then the note, on both. Android's two notes are the decided voice-engine notes; Cancel and Save at the foot are chrome.
  - Android's sheet opens over Listening, the iPhone's over Pronunciations (shot route).
  - The iPhone's AX5 Listening page behind shows the same "Plain…rration" cut as readerspeech: it's the same Audition Voice section.
- **seriesedit: match.** The capture problems are gone (Dark's spinner, Sepia's "isn't responding"): every Android column shows Edit series.
  - The same sections, rows and order (Series, State, Works, Delete) with the same footnotes. The title and summary are demo data; Save as text against a capsule is chrome.
- **seriesremove: match.** Sepia's capture problem is gone, and Light's stray greyed Save too.
  - Both open with "The Dawn Cycle · 3 works" and list the three works with the footnote. Android's "words · date" line is decided.
  - Small (Android): the remove icons are a dark red where the iPhone's are bright red, and the badge reads "DRAFT" against "Draft".
- **authorworksfilter: match.** The capture problems are gone (Dark, Sepia and OLED showed the author page): every Android column shows the sheet.
  - The same order: reset, Sort and filter, ✓; "3 of the 3 works on this page match"; Sort by with Ascending / Descending; Completion chips and their note; Rating and Include Not Rated; Warnings.
  - At 2.0× Android turns Ascending / Descending into chips and puts "Date Updated, 9 fields" under Sort by, all whole. The reset's place (in the title, against a bar button) and the menu glyphs are chrome.
- **colitems: match.** The Dark capture problem is gone.
  - **Gone from A88 (iPhone, all columns):** the creator line is whole, "AO3_Reader (Member)" on its own line above Remove from collection and the date (I14).
  - Android keeps creator, Remove and the date on one row, all whole. Its switches against the iPhone's Off / On, and which page each app opens (Awaiting collection against Awaiting you), are decided.
- **chsignupdetail: match.** The 2.0× capture problem is gone.
  - The same request and offer groups, each a card of labelled rows with the prompt's description last. The person, tags, wash and kicker are demo data: the iPhone's DEBUG push passes no title, so its kicker is the slug ("WINTER_EXCHANGE"), as A92 found for the edit page.
- **chapters: match.** A88 had no verdict (every Android column was a capture problem). All five Android columns now show Chapters.
  - The same page: AO3 ACCOUNT, Chapters, "work · N chapters", then one card of Chapter rows with date and chevron. Both put the date under the title at the largest size. The work and its chapters are demo data.
- **tagseditor: differs (Android, all columns). A88 missed it.** The capture problems (Dark, Light, OLED) are gone.
  - **The wash restarts at the field (checked in crops):** under the subtitle there's a hard horizontal edge, and from the "Add a tag" field down the wash starts again at full strength (a pink band in Light, red in Dark and OLED, darker tan in Sepia). The iPhone's wash fades once, with no seam.
  - **Not new:** A88's Sepia and 2.0× Android shots have the same edge; I missed it in A88b.
  - **Cause:** the pinned field's `stickyHeader` draws its own `.subjectWash(palette, SubjectMetrics.defaultWashHeight)` as an opaque ground (`writing/WritingTagsEditorScreen.kt:126-130`), to keep scrolled chips out from under the field, so a second wash begins at the field's top.
  - **Fix:** give the field an opaque ground only once it's pinned (the header item scrolled away), or paint the page's ground at that offset rather than a fresh wash.
  - Otherwise a match: the field, the chips with ✕ and the footnote. The tags are demo data.
- **texteditor: minor.** Dark and OLED's capture problems are gone.
  - **Gone from A88 (Android, 2.0×):** Done (✓) is back in the bar; the title now gives way to the buttons.
  - **Minor (Android, all columns):** that bar title is cut in every column ("Chapter …", "Cha…" at 2.0×), so it never reads in full on a phone. The kicker below already names the field in full ("CHAPTER 13 · 14 words"), and the iPhone's bar has no title. Dropping it would lose nothing.
  - **Left over, as in A88b (iPhone, AX5):** the footer, tag bar and AO3 note leave the editor one line tall. It scrolls.
  - The texts are demo data; Done as text against ✓ is chrome.
- **seriespicker: match.** The Dark capture problem is gone.
  - The same groups in the same order: Your series, the footnote, Position in…, Reorder the series, New series. The state differs (Android's work is already in its series), and ✓ against a filled circle is chrome.
- **collectionsgifts: differs (Android, all columns), the same seam as tagseditor. A88 missed it.** The capture problems (Dark, Sepia) and the timing problem (two of five collections) are gone: every column lists all five.
  - **The wash restarts at the Search card (checked in crops):** a hard edge under "YOUR COLLECTIONS", then a fresh band of wash (pink in Light, red in Dark). Same cause: the pinned search's `stickyHeader` draws `.subjectWash(palette, SubjectMetrics.defaultWashHeight)` (`writing/WritingAssociationPickers.kt:131-133`). Both have been there since `531a11a9` (7 Oct), so they predate A88.
  - **Left over, as in A88b (Android):** a gift recipient's remove is a red ✕, against the iPhone's red ⊖.
  - Otherwise the same order: Search, collections with their states, the footnote, Gift recipients with Add, Also on this work. Android's placeholder wraps to two lines ("Search all collections by / name"); nothing is cut.
- **creatorspicker: match.** The 2.0× capture problem is gone. Your pseuds and Invite a co-creator match the iPhone's, footnote included, and both put each switch under its name at the largest size. The pseud names are demo data.
- **parentpicker: minor (iPhone, AX5); I15 can't be judged from this shot.** Android's Light capture problem is gone.
  - **The hyphen is still there (checked in a crop):** the field reads "https:// / archiveo- / fourown.org/ / works/1". But the iPhone shots were taken at 10:06–10:07, and I15's `URLTextField` was written at 10:15, so this is the I14 build. Re-shoot `parentpicker` at AX5 once T-440 lands.
  - The rest as in A88b: the same rows and order. The URLs, titles and languages are demo data; Android's URL label above its value is chrome.
- **bulkedit: match.** The capture problems (Dark and 2.0× showed the author page) are gone.
  - The same order: the note, Tags to add, Tags to remove, Change on all, with the same rows and "None" / "Leave as is". The count (2 against 3 works) is demo data. Cancel and Save against ✕ and ✓, and the iPhone's Rating menu against Android's row, are chrome.
- **bulktagstate: match.** All four capture problems are gone: every Android column shows Archive warnings.
  - The two options with their circles and the three-state footnote match. At the largest size both wrap the options in full.
  - As in A88b: Android's AO3 ACCOUNT header and wash against the iPhone's plain bar title is a page against a pushed view.
- **backupimport: minor (Android, Light and Sepia).** The Light capture problem is gone.
  - The same counts, Merge's "It removes nothing" note and Replace Library… with its note, in the same order.
  - **Minor:** the in-sheet card inversion: Android's cards are #E6E6EA on a #F2F2F7 sheet in Light (the iPhone's are white on #F2F2F7, sampled), and darker tan on tan in Sepia.
  - Cancel at the right against the left is chrome.
- **queuetags: minor (Android, all columns).**
  - **Gone from A88:** the Unused rows have their height back, and both footnotes start at the page gutter (3gz).
  - **Minor:** with the field empty, Android's Add is drawn in full purple, where the iPhone's is pale (disabled). The button is disabled (`enabled = draft.isNotBlank()`), but the explicit `Text("Add", color = palette.accent)` overrides the disabled colour (`library/QueueTags.kt:458`, and `:225-226`). So it looks tappable and does nothing.
  - Android's page with Done, against the iPhone's sheet, is decided.
- **fandomworks: match.**
  - **Gone from A88:** Android now has the page's fandom chip ("Doctor Who") and counts "1 FILTERS", as the iPhone does (3gz). Its wash is now the iPhone's peach/brown, not green.
  - The same order: heading, sort, the four figures, the chip, the pager, the cards.
  - Small (Android): the pager's next button is the red accent in Dark, Light and OLED, where the iPhone's is the page's brown. The card dates read "09 Jul 2026" against "07/09/2026" (the same date, formatted differently).
- **tagworks: match.** A88's wash difference is gone: the page is peach/brown on both. "0 FILTERS" and no chip on both, as a tag page should. The same small pager colour and date format as fandomworks.
- **newcollection: minor (Android, all columns).**
  - **Gone from A88:** at 2.0× the bar title wraps whole ("New / collection") instead of "New collect…" (3gz). The swatches now follow the theme: dark in Dark and OLED, pale in Light and Sepia.
  - **Left over, as in A88a:** Android has separate NAME and DESCRIPTION labels over outlined fields, with the swatches below. The iPhone has one COLLECTION card holding Name, Description and the swatches.
- **newqueue: minor (Android, all columns).**
  - **Gone from A88:** the swatch tones now follow the theme, as on the iPhone.
  - **Left over, as in A88a:** the Start From radio circles sit tight against their labels ("◉Empty"), with no divider between the two rows; the iPhone spaces them and divides the rows. Android's Name is an outlined field against the iPhone's filled one.
- **editqueue: match.** A88's minor is gone: the swatches follow the theme. The same order (Name, Colour with its note, Tags, Offline). Android's outlined Name field and text Cancel / Save are chrome.
- **collectiondetails: minor (Android, all columns).**
  - **Gone from A88:** the swatches follow the theme.
  - **Left over, as in A88a:** the swatch row sits on the page, where the iPhone puts it in a card. Android's multi-line Description is decided.
- **pagejump: minor (Android, Dark, Light and OLED).**
  - **Gone from A88:** in OLED the other Nearby tiles now have a dark fill, as the iPhone's.
  - **Partly left over:** the current Nearby tile is no longer purple, but it's the red accent (dark red in Dark and OLED, pink in Light), where the iPhone's is the page's tan in every theme (checked in a crop). Sepia matches.
  - First page / Last (3) as text buttons against the iPhone's filled ones, and the outlined number field, are chrome.
- **collectionreorder: minor (Android, all columns).**
  - **Gone from A88:** Android now has drag handles (≡), not ⌃/⌄ buttons (3gz).
  - **Minor:** each row is its own card with gaps between, where the iPhone's three rows are one card with dividers (as chapterpicker was before 3gz).
- **seriesreorder: match.** A88's suspected difference is gone: Android's 2.0× column has Save in the bar, so it was timing.
  - The same rows (number, title, Draft, handle) in one card with dividers, and the same footnote. Small: "DRAFT" against "Draft".
- **revokedevice: match; a capture problem.**
  - **Capture (Android, OLED):** still the Sync Folder page with no dialog, as in A88b. The re-shoot didn't reach it.
  - **Gone from A88 (iPhone):** the full device name is now a heading card, "Revoke Demo reading tablet", whole at AX5 too (I12). The iPhone's AX5 reason wraps as "compro- / mised", a normal word break, nothing cut.
  - Android's dialog (title whole with "?", the reason radios, Revoke and Cancel) against the iPhone's sheet is decided dialog chrome.
- **colsfilter: match.**
  - **Gone from A88 (iPhone, AX5):** "Unrevealed" no longer shows through Reset. The bar is opaque up to the button, with a short fade above it (checked in a crop; I14).
  - The same order on both: Sort by (Order by AO3 order), Show only (four switches), the two notes, Reset at the foot. Android's Reset is grey (nothing to reset); the iPhone's capsule is pale. Chrome.
- **chsettingsedit (iPhone re-shot; Android predates 3ha): the iPhone side is right; the pair still differs until 3ha's shots.**
  - **iPhone:** the AX5 capture problem is gone; it shows Challenge settings. The pinned filled Save changes sits over the scrolling rows, with the rows fading out beneath it, in every column. At AX5 the rows wrap whole. The "winter_exchange · 4 sign-ups" subtitle is the DEBUG push without a title (A92).
  - **Still differs (Android's pre-3ha column):** Save changes is a plain row at the foot, not pinned and filled. 3ha changes that.
- **tagset (iPhone re-shot; Android predates 3ha): match.** The iPhone's AX5 capture problem is gone; it shows Tag set, wrapping its rows whole. Ownership, Tags and Nominations still match row for row; the counts (0 against 7 tags) and the switch states are demo data.
- **tagseteditor (iPhone re-shot; Android predates 3ha): match.** The iPhone's AX5 capture problem is gone; it shows Add tags. Both now show the four labelled fields with placeholders, the note and a filled Save tags in the wash's colour. The button's capsule against a rounded rectangle is chrome.
