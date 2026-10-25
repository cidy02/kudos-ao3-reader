# A102: the verification pairs, judged adversarially (Claude-CLI)

Brief: `~/kudos-android-lane/docs/android-port/audits/A102-brief.md`. Tiles: `~/kudos-tools/pairs/tiles-verify/`.
iPhone at polish `1e5d3d44` (clean worktree), Android at the lane's `7b2f69f4`. Columns: Dark, Light, Sepia, OLED,
Sepia at the largest text ("big"); iPhone on top. Pixel values are sRGB from the raw shots in `~/kudos-tools/pairs/shots/`.

Not reported (decided): DECISIONS.md (D7, D8, round 3 and earlier entries), A76's "Decided, not to report", the
"Decided, not changed" section of `audits/A88-triage.md`, demo data, and owner question Q28 (card dates).

## Counts

| Batch | Screens | Match | Minor | Differs | Capture problems |
|---|---|---|---|---|---|
| 1 (aboutkudos to bulktagstate) | 17 | 4 | 6 | 7 | 1 screen, 2 columns (also counted in its verdict) |
| 2 (chapterform to comments) | 20 | 12 | 2 | 6 | none |
| 3 (compose to newcollection) | 21 | 13 | 2 | 6 | none |
| 4 (newqueue to readernote) | 20 | 14 | 4 | 2 | none (OCR scan clean; prefhelp's DIFF flags are a lower sheet detent in Sepia, content fine) |
| 5 (readerspeech to tagseditor) | 20 | 11 | 4 | 5 | none (OCR: only revokedevice's known flags) |
| 6 (tagset to writingpreview) | 11 | 10 | 0 | 1 | none (OCR: tagworks Light flag is noise) |
| **Total, the 109 screens** | 109 | 64 | 18 | 27 | 1 screen, 2 columns (`author`, iPhone Sepia and OLED) |

| Settings pages (s_appearance to s_about) | 14 | 13 | 1 | 0 | none (OCR flags on the iPhone's s_backup, s_queues and s_sync checked by eye: fine) |
| Main screens (home to ao3colls) | 20 | 16 | 2 | 2 | none |
| **Total, all 143** | 143 | 93 | 21 | 29 | none open: `author`'s iPhone Sepia and OLED re-shot at 06:26, both fine |

Android's Settings shots are tonight's (05:0x); the iPhone's are from 00:39, the same clean polish build.

All these shots predate tonight's fixes (3he to 3hh, I21, I22). The differs above are what those fixes must close, and
the gate's re-shoot of the touched screens is what proves it.

Follow-up on four A102 minors not in the first re-shoot lists (Claude-Code checked them in code):
- `availability`: decided (DECISIONS 2026-10-08), so not a finding.
- The other three are real and go into Android 3hj, followed by a gate run and a re-shoot of those three:
  - `collectionsgifts`: the field is capped at 55% (`SubjectTextFieldRow`); fixed at `WritingAssociationPickers.kt:126`.
  - `bulkedit`: Rating and Language become choice rows (iOS `EditMultipleWorksView.swift:251`, `:271`).
  - `bulktagstate`: the "tri" mode goes flat; the large title stays by D7's reasoning.

Batch 3 was judged by Claude-CLI alone; Claude-Code paused at its usage limit and merges it later.

The side in brackets after "differs" is the app that leaves the shared rule. Three of batch 1's seven differs are on the iPhone only.

## Differs

Two patterns cover most of batch 1. Each is listed once here, then named on its screens.

- **G1, a sheet's controls take the hue of the screen underneath, on the iPhone.** On `addtocollection`, `addtoqueue`,
  `addworks` and `bookmarkform`, the iPhone's tick, Done, Cancel and Save are purple in every column (the work's or
  Neon reread's hue). Android's are the app accent: red, or brown in Sepia. This is I20's leak (DECISIONS, round 3,
  `libraryfilters`), but I20 fixed only the Library and Home section filter sheets. I can't tell whether these sheets
  are meant to follow the screen underneath, so I'm reporting it. If they aren't, the iPhone is the side to fix.
- **G2, Android draws a wash inside a sheet; the iPhone's sheets are flat.**
  - `addtoqueue` (Dark, Light, OLED) and `bookmarkform` (Dark, Light, OLED): a red band behind the field and the first
    cards. At 20% height, Android Dark is (62,7,8) and OLED (65,0,0); the iPhone Dark sheet is (22,22,27) all the way
    down. Android's cards there are red-tinted, (63,31,32) against the iPhone's (34,34,40).
  - `bulktag` (all five columns, Light and Sepia included): a purple wash.
  - No decision covers a wash inside these sheets. A77's W06 and C10 cover only New Collection's picked colour.
- `addtocollection` [iPhone]: G1. The iPhone's ticks and Done are purple; Android's checkbox and Done are red (brown in
  Sepia). The collections' order is decided (demo data).
- `addtoqueue` [both]: G2 on Android; G1 on the iPhone (purple tick against Android's red). Also, Android's queue glyphs
  are red and the iPhone's are neutral grey (Dark, Light, OLED).
- `addworks` [iPhone]: G1. The iPhone's Cancel and eye toggle are Neon reread's purple. Android's "Show mature" is red,
  or brown in Sepia, although Android's page underneath is purple too.
- `author` [Android]: in Dark and OLED, Android's Subscribe is a cream fill (244,232,215) with red text. The iPhone's is
  the exact accent (153,0,0) with white text, and so is Android Light's. Q19 says "fills keep the exact accent".
- `authorworksfilter` [iPhone]:
  - In Dark and OLED, the iPhone's selected Completion pill ("Any") is a lightened accent (219,114,114) with dark text.
    Android's is the exact (153,0,0) with white text, which is what Q19 asks for. The selected "All" fandom pill on
    `author`'s iPhone Dark shows the same.
  - In Sepia and big, the iPhone's sheet header band (title, Reset, subtitle) is white (255,255,255) above a Sepia body
    of (236,222,193). Android's Sepia is one ground. In Light the band is white on (242,242,247), so it shows only as a
    white strip on Sepia.
- `bookmarkform` [both]: G2 on Android; G1 on the iPhone (purple Cancel and Save against Android's red). The title
  "Edit Bookmark on AO3" on Android against "Bookmark on AO3" on the iPhone is demo state: both apps use the same rule
  (iOS `AO3WorkActionsModel.swift:229`, Android `WorkDetailForms.kt:138`), and Android's demo work is already
  bookmarked.
- `bulktag` [both]: G2. Android has a purple wash, a purple Done (184,112,216) and a purple "+". The iPhone's sheet is
  flat with an amber Done: (216,168,112) in Dark and (128,80,32) in Light. Neither is the app accent; each takes a
  subject hue. Which subject gives the hue may be demo data, but the wash is not.

### Batch 2

- **G3 [Android], confirmed from Claude-Code's finding.** The writing forms' switches use the lightened text accent.
  - `chapterform`'s "Set a different publication date" measures (216,112,112) in Dark and OLED, (128,32,32) in Light
    and (120,80,48) in Sepia (8-step buckets). The iPhone's is the exact (152,0,0), or (152,96,48) in Sepia.
  - `colsettings`' switches measure exact on both apps: (152,0,0) and (152,96,48). So G3 is limited to the writing
    forms, which fits Claude-Code's cause, `WorkFormToggle` passing `scopePalette.accent`.
- **G5 [iPhone], new: at the largest text, the secondary button of a bottom pair is clear glass over the list.**
  - On `chassign`, `chmysignup` and `chsignups` (the big column), the list's text shows through "Report a default" and
    "Your sign-up" and runs into their labels. Examples: "Bob (bob…" is drawn across "Your", and "Recipient a…" across
    "Report".
  - The filled primary button beside it is opaque and fine. Android pins both buttons on an opaque bar.
  - Only the big column shows it, because only there does the list reach the buttons.
- `chapterform` [Android]: G3. The date row's form is decided (D7).
- `chassign` [iPhone]: G5. Android's "Load more defaulted assignments" is decided (A76's paged assignments list).
- `chmysignup` [iPhone]: G5. Also G4, below.
  - "1 request · 1 offer" on the iPhone against "Request 1 of 3 · Offer 1 of 2" on Android is demo data. Both apps
    print "N of max" only when the challenge has limits (iOS `ChallengeSignUpView.swift:211`, Android
    `AO3ChallengeSignUpScreen.kt:86-88`), and only Android's demo challenge has them.
  - The same goes for Android's longer limits paragraph.
- `chsignups` [iPhone]: G5.
- `collectionreorder` [Android]: Android's Cancel is the app accent (white in Dark and OLED, red in Light, brown in Sepia
  and big), while its Done is the collection's green. The iPhone draws both Cancel and Done in green.
  - DECISIONS 2026-10-22 (3go) says "a coloured sheet's own controls take its colour"; Cancel doesn't here.
  - A77's D12 named the same leak for `QueueEditorSheet.kt:110`.
- `colmaint` [Android]: "Invite as: Moderator" is red, (216,112,112) in Dark and (128,32,32) in Light, on a teal page.
  The iPhone's is the page's teal, (112,192,216) and (32,112,128).
  - Likely cause: `SubjectFormRow` colours a choice value with `LocalSubjectPalette.current.accent`
    (`ui/subject/SubjectForm.kt:153`). The maintainers screen gives its teal only to `LocalKudosTokens` and
    `MaterialTheme` (`account/AO3CollectionMaintainersScreen.kt:54-72`). It never provides `LocalSubjectPalette`, so the
    row falls back to the shell's palette.
  - Other `showsChoice` callers that also compute a local palette may show the same. Grep:
    `AO3ChallengeSettingsEditScreen`, `AuthorProfileComponents`, `WritingAssociationPickers`. `chsettingsedit`'s olive
    dates look right, so not all of them do.

### Batch 3

From here on, patterns are named in words, not numbers (Claude-Code's request).

- **Sheet controls taking the hue of the screen underneath, on the iPhone (batch 1's pattern), seen again.**
  - `languagepicker` [iPhone]: "Any language"'s tick is the search page's amber in every column: (216,168,112) in
    Dark, (128,80,32) in Light and (120,80,48) in Sepia. Android's is the app accent: (192,96,96) lightened text ink
    in Dark, (152,0,0) in Light, brown in Sepia.
  - The amber is the same hue as batch 1's `bulktag` Done, so that amber probably also comes from the page underneath.
  - I21's list (Work Details' sheets, Add Works, bulk Tag, series preserve) doesn't name the Search filter sheet or
    its language page.
- **Sheet washes the other way round: the iPhone washes, Android is flat.**
  - `compose` [Android]: the iPhone's New comment sheet has the comments page's purple wash at its top. In Dark it's
    (75,58,103) fading to (26,22,34); in Light (239,224,255). Android's sheet is flat ground: (11,11,13) and
    (242,242,247).
  - `formattingtray` [Android]: the iPhone's Formatting sheet has an app-red band behind its header, (65,7,8) in Dark
    and (68,0,0) in OLED, pink in Light. Android's tray is flat.
  - Which side is right depends on the rule 3he follows for "sheet washes where iOS is flat". If iOS's sheets are the
    reference, Android is missing these two.
- `customizetheme` [Android]: in Dark and OLED, the status bar's clock and icons are dark on the dark sheet and its
  scrim: barely visible in Dark, invisible in OLED. Light, Sepia and big are fine.
  - Probably the reader underneath sets dark status-bar icons and the sheet doesn't override them.
  - `compose` and `formattingtray` keep white icons in Dark, so it's the reader's sheet. The reader sheets in later
    batches (`readerdisplay` and others) are worth a look for the same.
- `downloaddate` [Android]: the Downloaded date picker is the shell's Material colours, not the work's.
  - In Light, the selected day and Save/Cancel are red (152,0,0); in Sepia they're brown. In Dark and OLED the
    selected day is a cream fill (240,232,208), the same cream as batch 1's Subscribe.
  - My copy behind it is the work's purple, and the iPhone's Save is the work's purple: (152,112,216) in Dark,
    (64,32,128) in Light. Claude-Code's I21 note says "My Copy and the download date keep the work's colour".
  - Cause: `DownloadedDateEditorDialog` (`works/detail/WorkDetailMyCopySheet.kt:543-551`) draws a bare
    `DatePickerDialog` with no palette.
  - The dialog against the iPhone's sheet with a date pill is the D7 date-picker idiom, not reported.

### Minor, batch 3

- `compose` [Android]: "10,000 left" is monospace (`comments/CommentComposerSheet.kt:314`, `FontFamily.Monospace`).
  The iPhone's is the body font (`CommentsView.swift:1507`).
- `mycopy` [Android]: the Downloaded row ("Not recorded") opens the date editor (`WorkDetailMyCopySheet.kt:486`) but
  draws no chevron. The iPhone's has "›". Progress "—" and the missing Progress row are demo data: Android draws the
  row only when there's progress (`:491`).
- `myseries` [Android]: the header inset again (Claude-Code's "header inset"), kicker and title about 18 dp further
  in than the cards. The own-works totals line is decided.
- `formattingtray` [Android]: the B, I, U and S glyphs are sans (Claude-Code's serif finding covers it), and Done is
  plain accent text against the iPhone's glass pill (Android chrome).

### Batch 4

I measured the switches and filled controls in this batch. `newqueue`'s and `queuesettings`' switches are exact on
both apps: (152,0,0) or the queue's purple (184,112,216), (96,32,128) in Light.

- `queue` [Android]: the In Line grid draws only its left column in Dark, Light, Sepia and OLED. Both apps say
  "IN LINE 4".
  - The iPhone shows Sodium Lights and a blurred "Tap to reveal" card in row 1, then Frozen and Hades in row 2.
  - Android shows Sodium Lights, then Winter Garden directly below it. Its right column is empty, so the obscured
    mature card and Hades are missing.
  - The code should draw pairs: `library/QueuePageScreen.kt:396-418` uses `inLine.chunked(2)` in a `Row` of fixed-size
    `SubjectWorkCoverCard`s. I couldn't find the cause read-only. It needs a look on the emulator (Compact mode).
- `queuetagedit` [Android]: Edit tag is a Material dialog. The dialog form is the same idiom as D7's
  `revokedevice`.
  - Its Cancel is the app accent on the purple queue: (152,0,0) in Light, brown in Sepia, white in Dark and OLED.
  - The iPhone's Edit tag sheet is washed in the queue's purple with purple Cancel and Save.
  - This is the "coloured sheet's Cancel" finding (batch 2's `collectionreorder`) on a different component. Check
    that 3he's fix reaches this dialog too.

### Minor, batch 4

- `readernote` [Android]: Add Note's Done tick is primary ink, white in Dark and black in Light. Find, Contents and
  Display & Themes draw theirs in the accent on both apps, and so does the iPhone's Add Note.
  - Cause: `reader/ReaderNoteEditor.kt:100-102`, `ToolbarCircleButton { Icon(Icons.Filled.Check) }` with no tint.
    The Contents sheet passes `tint = tokens.accentInk` (`:104` of `ReaderContentsSheet.kt`).
- `pronunciations`, `pronunciationedit` [Android]: behind the sheet, the Listening page is scrolled under a
  transparent status bar and top bar. "Audition Voice" sits under the clock, and the back arrow sits over
  "Sample Text", in every column.
  - It's behind the scrim, so only a minor here. If the Listening page itself scrolls without its top bar taking a
    container colour, it's the same collision in plain view. Worth checking on `readerspeech` or the Settings
    Listening page in a later batch.
- `prefhelp` [Android]: in Light, the iPhone's Privacy Preferences sheet is grouped grey (240,240,245) to
  (242,242,247) with white cards. Android's is white (255,255,255) with white outlined cards.
  - DECISIONS 2026-10-23 (3ha) made the sheet "white in Light, as iOS's". This shot contradicts that premise.
  - Reported because the decision's reason doesn't hold here, not because anything is lost; the cards are outlined.

### Batch 5

Switches and fills are measured (8-step buckets).

- `savesearch` [Android]: Save Search's sheet is washed. Green on the iPhone, olive-green on Android; the hue comes from
  the search's name, which is demo. The iPhone's Cancel and Save take the sheet's green: (112,216,120) in Dark,
  (32,128,40) in Light. Android's are the app accent: (152,0,0) in Light, (152,96,48) in Sepia, white in Dark and
  OLED.
  - This is the coloured-sheet Cancel finding again (`collectionreorder`, `queuetagedit`), now on Save too. Claude-Code
    read this one as a match. Save Search is on its own list of iOS washed sheets, so its controls should follow the
    wash.
- `seriesedit` [Android], confirmed from Claude-Code's finding: "Series is complete" measures (216,112,112) in Dark and
  OLED, (128,32,32) in Light and (120,80,48) in Sepia. The iPhone's is exact, (152,0,0) or (152,96,48). Caused by
  `WorkFormToggle`; 3he fixes it.
- `seriespreserve` [both]: the known pair. The iPhone's Cancel and actions are purple (the sheet-takes-the-page-hue
  leak, which I21 covers for series preserve). Android washes the sheet red where iOS keeps it flat (Claude-Code's
  list). Also on Android, in the big column only, Cancel drops below the title. The login decision allows that for
  sign-in only.
- `sec_favorites`, `sec_reading` [iPhone]: the selected "All" chip is the text accent, not the fill. It measures
  (216,112,112) in Dark and OLED and (128,32,32) in Light. Android's is the exact (152,0,0).
  - It's batch 1's lightened-pill finding (I21, "exact-fill selected pills"), but it reaches Light as well and the
    Library section pages, not only the filter sheet.
  - Check that I21 covers both.

### Minor, batch 5

- **A destructive mark is system red on the iPhone and the text accent on Android.** I couldn't find a decision.
  - `seriesremove`: the iPhone's ⊖ is (248,56,56) to (248,64,64) in every theme. Android's is (216,112,112) in
    Dark, (128,32,32) in Light and (120,48,48) in Sepia.
  - `recovery`: the iPhone's "Delete this local copy" is (248,56,56), unlike its other actions at (152,0,0). Android's
    Delete is the same (128,32,32) as Restore and Keep.
  - The same is visible on batch 4's `queuetagedit` ("Remove from this queue").
  - In Sepia, Android's destructive actions are red-brown against the iPhone's bright red. Elsewhere it's a shade
    within the red family, so I've left it as minor.
- `searchfilters` [iPhone]: "Best Match" and "Any rating" are primary ink. Android's are the accent. Claude-Code's I22
  covers it. The switches are exact on both: (152,0,0) and (152,96,48).
- `seriespicker` [Android]: the chosen series has a bare ✓ and the others an empty radio. The iPhone uses a filled
  check circle and empty circles. Claude-Code found this independently, and it's in 3hg.
- Checked and not reported:
  - `recovery`'s Light sheet is white (255,255,255) on both, so the `prefhelp` ground question doesn't apply here.
  - `readerspeech` is the reader's Read Aloud sheet, not the Settings Listening page, so it couldn't answer the
    pronunciation pages' status bar. Claude-Code traced that one to the shot route: `ShellChromeState.isScrolled` is
    set only by nested-scroll deltas, and the route scrolls in code.

### Batch 6

- `works` [both]: two known patterns, nothing new.
  - The iPhone's selected "Works" and "All" chips are the text accent, not the fill: (216,112,112) in Dark and OLED,
    (128,32,32) in Light. Android's are the exact (152,0,0). Claude-Code says I21 fixes this through
    `SubjectChip.pill`.
  - Android has the header inset: "Works" and its subtitle sit further in than the chips and cards. 3hf covers it.
  - The own-works totals line is decided.

Nothing else in batch 6 differs. Both apps' tag set switches are read-only (iOS `TagSetView.swift:201-203`
`.disabled(true)`, Android `ChallengeReadOnlyToggle`), and their on or off state is demo.

### Settings pages

None of the 14 Settings pages differs. One minor:
- `s_account` [Android]: Log Out is the text accent: (216,112,112) in Dark and OLED, (128,32,32) in Light, brown in
  Sepia. The iPhone's is system red, (248,56,56) to (248,64,64), in every theme. It's the destructive-red finding;
  3hh's token covers it.
- Seen on `s_sync` but not counted: Android's demo has a paired tablet with Rename and Revoke; the iPhone's has none
  ("No other devices paired yet", demo). Android's Revoke is a red, (176,32,24) in Light, so 3hh's audit should bring
  it to the same token.

### Main screens

- `insights` [Android]: Reading Insights' cards are neutral on Android: the Your Library card is (33,33,35) in Dark
  and (230,230,234) in Light. The iPhone tints them in the page's palette, (69,24,28) in Dark and (237,210,210) in
  Light, through `.subjectCard(palette:)` on every card (`ReadingInsightsView.swift:186`, `:280`, `:341`, `:421`,
  `:448`, `:484`). That's a colour-family difference on every card of the page. A92's `neutralCard` decision covers
  series works and author bookmarks only.
- `inbox` [iPhone]: the selected "Unread" pill is the text accent, (216,112,112) in Dark and OLED and (128,32,32) in
  Light, against Android's exact (152,0,0). It's the known lightened-pill pattern. The Inbox rail is
  `SubjectChip(style: .pill, palette: theme.scopePalette)` (`AccountInboxScreen.swift:141-144`), so I21's
  `SubjectChip.pill` fix covers it.
- `author` re-shot: the iPhone's Sepia and OLED columns are right now. The earlier verdict stands: Android's cream
  Subscribe in Dark and OLED (3he) and the iPhone's lightened "All" chip (I21).

### Minor, main screens

- `insights` [Android]: words read is "202.6K" on Android and "203K" on the iPhone. Android's `formatCompactNumber`
  (`library/ReadingStatisticsScreen.kt:767-788`) says it matches iOS's `.number.notation(.compactName)`, but it keeps
  a decimal where Apple's formatter drops it at this size. Nothing is lost.
- `dashboard`, `deleted` [Android]: the header inset again (kicker and title further in than the chips and cards). 3hf
  covers it.
- Checked and not counted:
  - `subs`: the iPhone's demo has no updated subscriptions, so the "New since you last looked" section, the
    "Chapters 4-5 new" line and the "with new chapters" subtitle show only on Android. Both apps draw them from the
    same data (iOS `AO3SubscriptionsWorksBrowser.swift:32`, `:101-110`, `:148-163`).
  - Not sure this is decided: Android draws a visible Unsubscribe button on each updated row, where iOS has a trailing
    swipe (`:365-372`). Android keeps the action reachable without a swipe, and DECISIONS 2026-10-11 (3cn) mentions
    "the footer under a subscribed work". I couldn't find a line that decides the button itself.
  - `history`: Android's "This month" after "Earlier" is the fixture's order. Both apps group consecutive rows in
    AO3's page order (iOS `AO3Client+Readings.swift:315-346`, Android `AO3HistoryVisit.kt`).
  - `search`: Android shows its demo's saved search; the iPhone has none, so it shows the empty prompt
    (`SearchView.swift:421-449`, the same rule).
  - `account`: Android's "6+" on Subscriptions is a cached count the iPhone's demo doesn't have. iOS prints it too
    (`AccountShortcuts.swift:67`).
  - `drafts`: different demo drafts; the subtitle rule is shared (`WritingDraftsView.swift:180`).

## Minor

- **G4 [Android], confirmed from Claude-Code's finding.** The iPhone sets prompt and instruction editors in serif and
  Android in sans. `chmysignup`'s Prompt and `chsettingsedit`'s Sign-up instructions show it. Read-only prompt text
  is serif on both (`chsignupdetail`).
- `chsettingsedit` [Android]: G4. Olive against teal is shot-route input (Claude-Code's check; D8).
- `collectionsgifts` [Android]: in all five columns, the search row's placeholder wraps to two lines, right-aligned
  ("Search all collections by / name"). The iPhone's fits on one line.
- `collectionreorder` [Android] also has batch 1's header inset: the kicker, title and subtitle sit about 18 dp further
  in than the cards. Call it G6, the Android header inset, also seen on `authorabout` and `authorbookmarks`.
- `authorabout`, `authorbookmarks`:
  - Android's header block (kicker, title, subtitle) sits about 24 dp further in than its section labels and cards, in
    every column. The iPhone aligns them all to one margin.
  - `authorabout` also has two small differences on Android: a blank line before the bio's bullets, and Joined and
    User ID in one grouped card where the iPhone has two separate cards.
- `availability`: Android's "Check Now" label is the accent; the iPhone's is primary ink. Both have an accent icon.
  This may be decided by the 2026-10-08 entry (Android's action rows use the palette's accent), which leaves "iOS's
  tinted rows" to Q19; I'm not sure, so I'm listing it.
- `bugreport` [iPhone]: "Continue on GitHub" is disabled on both while the description is empty (iOS
  `BugReportView.swift:66`, Android `BugReportScreen.kt:204`). The iPhone draws it in primary ink with a red ladybug,
  so it looks tappable; Android greys it.
- `bulkedit`: Rating's value is an accent "Leave as is ⌃⌄" menu on the iPhone and a grey "Leave as is ›" row on
  Android. The other rows match.
- `bulktagstate`: in Dark, Light and OLED, Android washes the page red and uses a large title with the "AO3 ACCOUNT"
  kicker; the iPhone is flat with a small inline title.
  - The title is D7's `bulknames` difference on a sibling page. D7 named only `bulknames`, so I'm noting it.
  - The iPhone's own `bulknames` does have the wash, so the iPhone is inconsistent with itself here.
- Seen but not counted:
  - At the largest text, the iPhone's segmented controls keep small labels (`ao3coll`, `author`,
    `authorworksfilter`, `chassign`, `chsignups`), while Android's grow. That's iOS's own control.
  - The iPhone's Light glass sheets let the page beneath show through as coloured blurs behind their lower rows
    (`chapterpicker`, `collectiondetails`). The text stays readable.
  - `compose`, iPhone Dark: the system keyboard's "slide to type" tip covers the keyboard. The app's content is all
    visible, so no re-shoot is needed.
  - `languagepicker` and `libpicker`: the iPhone pushes the page inside the filter sheet (back button); Android
    stacks a second sheet with a tick. The same choices either way.

## Capture problems (re-shoot only the column named)

- `author`: **iPhone Sepia** shows Home with loading placeholders and the tab bar. **iPhone OLED** is blank white.
  Dark, Light and big are fine.

## Per-screen verdicts

### Batch 1

| Screen | Verdict | Note |
|---|---|---|
| aboutkudos | match | Version and build line, Jsoup/Readium Kotlin rows and Help & Feedback are platform or decided |
| addtocollection | differs [iPhone] | G1 |
| addtoqueue | differs [both] | G2 red wash and red glyphs on Android; G1 purple tick on the iPhone. Series section decided |
| addworks | differs [iPhone] | G1. Layout is decided (D7, A88) |
| ao3coll | match | |
| author | differs [Android]; capture problem | Android Dark/OLED Subscribe fill; re-shoot iPhone Sepia and OLED |
| authorabout | minor | Android header inset; bio blank line; one card against two |
| authorbookmarks | minor | Android header inset. Extra demo bookmark and Load More label decided |
| authorworksfilter | differs [iPhone] | Lightened selected pill in Dark/OLED; white header band in Sepia/big |
| availability | match (decided) | Check Now's accent label is decided: DECISIONS 2026-10-08 makes `SettingsActionRow` text the palette's accent and leaves iOS's tinted rows to Q19 (Claude-Code, at the re-shoot check). Counted as minor in batch 1's totals |
| backupimport | match | |
| bookmarkform | differs [both] | G2 on Android, G1 on the iPhone; the title is demo state |
| bugreport | minor [iPhone] | Disabled Continue on GitHub looks enabled |
| bulkedit | minor | Rating value style. Count of works is demo |
| bulknames | match | D7 |
| bulktag | differs [both] | G2 purple wash on Android; the hue differs (purple against amber) |
| bulktagstate | minor | Android wash and large title (D7's sibling) |

### Batch 2

| Screen | Verdict | Note |
|---|---|---|
| chapterform | differs [Android] | G3 switch accent |
| chapterpicker | match | D8. The selected row (Chapter 1 against All Comments) is demo state |
| chapters | match | Chapter count and dates are demo |
| chassign | differs [iPhone] | G5 (big). Load more decided. Android's ↻ refresh in the top bar is Android chrome |
| chmysignup | differs [iPhone] | G5 (big); G4 serif [Android]; the subtitle is demo limits |
| chprompts | match | |
| chsettings | match | Limits are demo |
| chsettingsedit | minor [Android] | G4. Hue is route input (D8) |
| chsignupdetail | match | Hue and kicker are route input; prompt serif on both |
| chsignups | differs [iPhone] | G5 (big). List length and "closed" are demo |
| colitems | match | The shots show different scopes and tabs (route input). Both apps share the rules: subtitle (iOS `AO3CollectionItemsView.swift:252`, Android `AO3CollectionItemsScreen.kt:169`) and a switch only when editable |
| collection | match | Progress ring and completion are demo; the tab highlight is decided |
| collectiondetails | match | D7 |
| collectionreorder | differs [Android] | Cancel in the app accent, Done in green; G6 header inset |
| collectionsgifts | minor [Android] | Search placeholder wraps |
| colmaint | differs [Android] | Invite-as value red on a teal page (`LocalSubjectPalette` not provided) |
| colmod | match | Paging and submitted dates are demo; iOS prints the date when present (`CollectionModerationView.swift:314`) |
| colsettings | match | Switches exact on both |
| colsfilter | match | |
| comments | match | Hue follows the demo title (D8) |

### Batch 3

| Screen | Verdict | Note |
|---|---|---|
| compose | differs [Android] | No sheet wash where the iPhone has the purple one; monospace counter (minor) |
| creatorspicker | differs [Android] | Corrected after Claude-Code's merge; I first called it a match by eye. The pseud switch is the lightened red: (216,112,112) in Dark and OLED, (128,32,32) in Light, (120,80,48) in Sepia. The iPhone's is exact, (152,0,0) or (152,96,48). The writing-form switch finding again (`WorkFormToggle`, fixed by 3he). Names are demo |
| customizetheme | differs [Android] | Dark/OLED status bar icons dark on dark |
| downloaddate | differs [Android] | Date picker in the shell's red/cream, not the work's purple; dialog form is D7's idiom |
| draftedit | match | Rating/Language ⌄ against ⇕ is Android's choice mark (DECISIONS, 3cr) |
| editqueue | match | Outlined name field is D7 (`newqueue`) |
| edittags | match | Selected rating and warning are demo |
| fandomfilter | match | Pills against the segmented control are Android chrome |
| fandomlist | match | Search at the top is decided (A88) |
| fandomworks | match | Bottom pager (Android) is the page's own; OCR's DIFF score was noise. Card dates are Q28 |
| formattingtray | differs [Android] | No red header band where the iPhone has one; the iPhone's shot opens the tray alone, Android's over the composer (route) |
| hsec_reading | match | Progress rings and the unfold control are decided Android extras |
| hsec_updated | match | |
| inboxfilter | match | Both sheets wash red |
| languagepicker | differs [iPhone] | Tick in the search page's amber, not the app accent |
| libpicker | match | Search placement decided |
| libraryfilters | match | Both use the app accent now (I20 landed in this build); the extra categories past the frame are decided |
| login | match | Sheet colour, "Use alternative method" and big-column Cancel are decided (2026-10-22) |
| mycopy | minor [Android] | Downloaded row has no chevron; Progress is demo |
| myseries | minor [Android] | Header inset; OCR's DIFF score was noise |
| newcollection | match | Outlined fields are D7 |

### Batch 4

| Screen | Verdict | Note |
|---|---|---|
| newqueue | match | Switch exact on both. Outlined field D7 |
| pagejump | match | D8 |
| pairing | match | No "Scan a QR Code" on Android and its own intro line are decided (Android is QR-generate-only). Android also shows the key under Advanced (extra information) |
| parentpicker | match | URLs, title and the chosen language are demo |
| prefhelp | minor [Android] | Light sheet ground white where the iPhone's is grouped grey (3ha's premise) |
| privacydata | match | "Imported fonts" decided; sizes are demo |
| prompttags | match | Hue (olive against teal) is route input as on `chsignupdetail`; filled values are demo. Android pushes a page where the iPhone shows a sheet; same fields |
| pronunciationedit | minor [Android] | Listening page behind collides with the status and top bars. Sheet form and footnote decided (D7, A88) |
| pronunciations | minor [Android] | Same collision behind. Sheet form decided (D7) |
| queue | differs [Android] | In Line grid's right column missing (obscured card and Hades) |
| queuesettings | match | Switch exact. "Last read" and KB are demo |
| queuestorage | match | The iPhone's sheet is the shot route's workaround (`SettingsStoragePages.swift:192-193`). Android's linked names are the decided verified links. Counts are demo |
| queuetag | match | Both washed in the queue's purple; 3he must keep Android's (Claude-Code's 3hf restores it). Outlined field inside the Add row is D7's idiom |
| queuetagedit | differs [Android] | Dialog's Cancel in the app accent on the purple queue |
| queuetags | match | Android's extra Done loses nothing |
| reader | match | Different books (decided) |
| readercontents | match | Chapter list is the demo book's |
| readerdisplay | match | D7. Android's Keep screen awake and Read Aloud group are decided (2026-10-22) |
| readerfind | match | Keyboard decided (A93: the iPhone hides it with a hardware keyboard) |
| readernote | minor [Android] | Done tick primary ink, not accent |

### Batch 5

| Screen | Verdict | Note |
|---|---|---|
| readerspeech | match | Stepped slider (D7) and the full-height sheet are decided; Sample Text's ⌄ is Android's choice mark |
| recovery | minor [Android] | Delete in the same accent as the other actions (destructive red finding). Date style D8; second paragraph demo (A88). Light ground white on both |
| revokedevice | match | D7 dialog. OCR flags are the dialog over Sync Folder |
| savesearch | differs [Android] | Cancel and Save in the app accent on the green sheet |
| searchfilters | minor [iPhone] | Picker values in primary ink (I22). Switches exact |
| sec_downloaded | match | Unfold control, progress rings and linked names are decided Android extras |
| sec_favorites | differs [iPhone] | Selected "All" chip in the text accent in Dark, OLED and Light. Android's big column stacks the segments (loses nothing); 75% against 0% is demo |
| sec_finished | match | Order and the third work are demo |
| sec_history | match | 11 against 12 works and Yesterday against Today are demo; big-column stacked segments as above |
| sec_later | match | |
| sec_reading | differs [iPhone] | Selected "All 2" chip in the text accent, as `sec_favorites` |
| seriesdetail | match | Android's labelled stats are extra words; card dates Q28 |
| seriesedit | differs [Android] | Switch in the lightened accent (`WorkFormToggle`). Title and summary are demo |
| seriespicker | minor [Android] | Bare ✓ against a filled check circle. "This work is in it" is an Android extra; titles are demo |
| seriespreserve | differs [both] | Purple controls (iPhone); red wash (Android); big-column Cancel below the title (Android). The count is demo (A88) |
| seriesremove | minor [Android] | ⊖ in the text accent, not system red. Words and dates are decided (A88) |
| seriesreorder | match | |
| synconb | match | Checkbox decided (A76); platform wording decided; Material icons |
| tagpicker | match | Android draws "Selected" when something is (`search/FilterTagPicker.kt:157`); its demo has nothing chosen. The sheet over Filters is the route |
| tagseditor | match | Tags are demo |

### Batch 6

| Screen | Verdict | Note |
|---|---|---|
| tagset | match | Read-only switches on both; their state and the tag counts are demo |
| tagseteditor | match | Save tags fill identical: (216,168,112), (128,88,32) and (120,88,48) |
| tagworks | match | Bottom pager is the page's own; big-column pager label D7; card dates Q28 |
| texteditor | match | The iPhone edits a summary and Android a chapter (route); both serif; Android's plain toolbar glyphs are its chrome |
| thread | match | D8 (label and hue from the demo work) |
| welcome | match | Icon art decided (A76) |
| whatsnew | match | Version and platform words are the build's; title weight is fonts (A76) |
| workdetail | match | Resume card ("Content", 0% against Chapter 2, 75%) is the demo book and position; linked author decided |
| workedit | match | ⌄ against ⇕ is Android's choice mark (3cr) |
| works | differs [both] | The iPhone's selected chips in the text accent (I21); Android's header inset (3hf) |
| writingpreview | match | A draft on the iPhone and a posted work on Android (demo); same rows |

### Settings pages

| Screen | Verdict | Note |
|---|---|---|
| s_appearance | match | Android's System theme and stepped slider decided (A76, D7) |
| s_font | match | Android's imported "Demo font" and footer decided (A76) |
| s_reader | match | |
| s_listening | match | Stepped slider D7; the voice-engine footnote is Android's own (A88); big-column speed pills stacked, nothing lost |
| s_downloads | match | Storage used is demo |
| s_preservation | match | |
| s_queues | match | Queue Storage glyph is Material; the stepper is Android's own |
| s_library | match | Switches exact |
| s_backup | match | Backup's notes and Deletion signing decided (A76) |
| s_sync | match | The paired tablet is Android's demo; platform wording decided |
| s_import | match | |
| s_account | minor [Android] | Log Out in the text accent, not system red (destructive finding, 3hh) |
| s_privacy | match | "Require biometric" decided (platform wording) |
| s_about | match | Software Update decided (A76); version is the build's |

### Main screens

| Screen | Verdict | Note |
|---|---|---|
| home | match | Queue cards and the floating iOS tab bar are each platform's |
| library | match | Selected "All" is the hero's amber on both: (216,168,112) and (128,80,32) |
| browse | match | "Jump back in" 3 against 4 is demo; Android's one-line facts row loses nothing |
| search | match | Saved search is demo; same idle rule |
| account | match | Default user icon decided (A76); "6+" is demo cache |
| drafts | match | Demo drafts; shared subtitle rule |
| dashboard | minor [Android] | Header inset (3hf) |
| inbox | differs [iPhone] | Selected pill in the text accent (I21 covers it) |
| prefs | match | |
| more | match | Both have "Your account" (iOS `AccountMoreOnAO3View.swift:110`); the iPhone's frame ends above it |
| settings | match | |
| queues | match | Sizes are demo |
| collections | match | |
| insights | differs [Android] | Neutral cards where the iPhone's take the palette; 202.6K against 203K (minor) |
| deleted | minor [Android] | Header inset (3hf). Dates and days left are demo |
| bookmarks | match | Android's extra demo bookmark decided (A76) |
| history | match | Same consecutive grouping; group order is the fixture's |
| subs | match | Updated rows only in Android's demo. The visible Unsubscribe button is decided by precedent (Claude-Code at the merge): DECISIONS 2026-10-11 (3co, step 2) "Delete stays a button (iOS: a swipe)" on the same account works lists, and the 10-05 Unsubscribe entry. It will be recorded explicitly |
| later | match | Unmark glyph is Material |
| ao3colls | match | |
| author (re-shoot) | (counted in batch 1) | Capture problem closed; batch 1's differs stands |

## Post-fix re-shoot, the iPhone half (claude/parity-i21 @ ad64c65d, gated; shot 08:19–09:01; `tiles-post/`)

Claude-CLI read all 38 iPhone rows. The Android rows in these tiles are still the pre-fix shots, judged when they're
re-shot.

**Every A102 iPhone differ is gone.**
- Scope sheets (`addtocollection`, `addtoqueue`, `bookmarkform`, `seriespreserve`, `addworks`, `bulktag`): the tick,
  Done, Cancel, Save and actions are the app accent in every column, brown in Sepia; no purple or amber.
- Selected pills and chips are the exact fill in Dark, OLED and Light on `author`, `authorworksfilter`, `works`,
  `sec_favorites`, `sec_reading`, `hsec_*`, `colitems`, `inbox`, `queues`, `ao3colls`, `bookmarks`, `history`,
  `subs` and `later`.
- `authorworksfilter`'s Sepia and big header band is Sepia.
- `colsfilter`'s and `formattingtray`'s washes show in Dark, Sepia and OLED.
- `languagepicker`'s tick is the app accent.
- `bugreport`'s disabled Continue on GitHub is grey.
- The big column's bottom pairs (`chassign`, `chmysignup`, `chsignups`; also `chprompts`, `chsettingsedit`) sit on
  scroll-edge glass, and the labels are clean over the blurred list.

**Nothing newly broken** in the 38: no clipped text, no wrong colour family and no lost control.

**Still open, not new:** `searchfilters`' picker values ("Best Match", "Any rating") are still primary ink with an
accent ⌃⌄. The Light shot samples the same before and after. That was A102's batch 5 minor (Android draws the values
in the accent), which I22 was expected to cover; I22 fixed `languagepicker`'s tick, not these values. Claude-Code
calls it an iPhone-internal inconsistency with `authorworksfilter`'s red values; it's the same finding seen from
the other side. Minor; it doesn't block landing.

Verdict: the iPhone half is confirmed. I21 and I22 can land.
