# A102, Claude-Code's verdicts (fresh pass 2026-10-24/25: iPhone polish 1e5d3d44 clean build, Android lane 7b2f69f4)

## Candidate gaps (checked in code)
- **G1 · Work Details' sheets lose the work's colour on Android** (addtoqueue, addtocollection; check bookmarkform,
  seriespreserve, downloaddate). iPhone: the sheets inherit Work Details' screen tint (Sodium Lights = purple ✓,
  toggles, no wash). Android: `WorkDetailScreen.kt` returns early when a form is open (`if (queuePickerOpen) {
  WorkDetailQueueForm(...); return }`, ~line 948), so the form composes outside `WorkDetailContent`'s
  `SubjectPalette.fromHue(workHue)`; `WorkDetailFormSheet` then washes with `tokens.scopePalette` = the app's red
  (`WorkDetailForms.kt:87`). Result: red wash + red ✓/Done/icons where the iPhone is purple with no wash.
  `showingMyCopy` already computes the palette (same file ~1003), so the fix is to provide that palette to the forms
  and drop the form wash if iOS has none. A88a called the red "following the wash under the sheet (decided)": it isn't
  the page's wash, it's the app accent.

## Merged with Claude-CLI after batch 1 (their file: ~/kudos-agent-ios/docs/android-port/briefs/A102-cli-result.md)
- G1 is the **iPhone's** side: T-446 (I20) set the rule from ThemeManager, "scope surfaces use the app accent, and Sepia
  its brown", and fixed only the Library/Home section filter sheets. Work Details' sheets (addtocollection, addtoqueue,
  bookmarkform) and Add Works still inherit the root tint that follows the hero's wash (purple). Android's red/brown is right.
- G2 is **Android's**: a wash inside sheets (addtoqueue, bookmarkform: `WorkDetailForms.kt:87` `subjectScreenWash`;
  bulktag: the queue's purple). The iPhone's sheets are flat.
- Claude-CLI caught, I missed: author's Android Dark/OLED Subscribe is a cream fill (Q19: fills keep the exact accent);
  authorworksfilter's iPhone selected pill is a lightened accent in Dark/OLED (Q19) and its header band is white over Sepia.
- bulktag: the hue is wrong on both (iPhone amber, Android purple); by the rule both should be the app accent.

- **G3 · Android's writing-form switches fill with the lightened accent** (chapterform; check workform/newwork):
  Dark/OLED (219,114,114), Light (133,37,37), Sepia (122,86,49) against the iPhone's exact (153,0,0) / Sepia
  (154,103,50). `writing/WritingWorkFormScreen.kt:486` `WorkFormToggle` passes `scopePalette.accent` (the text
  accent). The filter sheet's switch (authorworksfilter) is exact on both. Q19/3go: fills keep the exact accent.
- **G4 · iOS's editors are serif, Android's sans** (minor): iOS `design: .serif` in the sign-up prompt editor
  (ChallengeSignUpView:350/357), challenge instructions (ChallengeSettingsEditView:273/280), the writing text editor
  (WritingTextEditor:629) and the comment tray's B/I/U/S letters (CommentMarkup). Android has serif only in the
  sign-ups list, work summary, queue settings and Customize Theme. Seen on chmysignup; check chsettingsedit,
  texteditor, formattingtray.

- **G2 scope, checked in iOS code:** iOS washes only its coloured editor sheets (`NewReadingQueueSheet.swift:139`,
  `NewCollectionSheet.swift:79` new collection, `:288` reorder works), and Android matches those. The sheets iOS keeps
  flat (no `subjectScreenWash`): Add to Queue, Bookmark, bulk Tag, and the collection's details sheet
  (`Collections.swift:282` `detailsSheet`, a Form with `.appThemedScroll()` at `[.medium, .large]`). Android washes
  all four.
- **G5 · Android's coloured sheets' Cancel takes Material primary** (collectionreorder): Cancel is red in Light and
  cream in Dark, while Done is the sheet's green. On the iPhone, both are green. 10-22: "a coloured sheet's own
  controls take its colour" (A77 C38: `QueueEditorSheet.kt:110` Cancel inherits the parent's Material colour). Check
  newqueue, editqueue and newcollection.
- **G6 · Android's choice values ignore the page palette on the AO3 collection manage pages** (colmaint "Invite as
  Moderator ⌄" is red, the iPhone's is teal). `SubjectFormRow` colours a choice with `LocalSubjectPalette.current.accent`
  (`ui/subject/SubjectForm.kt:153`); `AO3CollectionMaintainersScreen.kt:64` provides tokens and Material colours from
  the teal palette but not `LocalSubjectPalette`.

- **Correction to G2 (batch 3):** "iOS washes only its coloured editor sheets" was wrong. The iOS sheets that
  draw a wash, all checked in code:
  - `AccountInboxFilterSheet:66`, app palette. Android has it.
  - `AO3CollectionsFilterPanel:48`, app palette. Visible only in Light on the iPhone itself; Android has none.
  - `QueueTagSheet:92`: one queue's colour, or the app's for several. 3he wrongly flattened Android's, because
    `SharedTagContent` is shared with bulk Tag.
  - `SaveSearchSheet:92`, `NewReadingQueueSheet:139`, `NewCollectionSheet:79/288`.
  - The comment composer (`CommentsView:1462`, `subjectWash(palette, 320)`) and the formatting tray
    (`CommentMarkup:405`, `subjectWash(scopePalette, 320)`). Android has neither.

  Flat on iOS: Add to Queue, Add to Collection, the bookmark form, the series prompt, bulk Tag
  (`WorkBulkTagSheet`), the collection's details, Library filters, and the AO3 filter panel.

## Per screen
- aboutkudos: match (sheet vs pushed Settings page decided; versions/libs platform).
- addtocollection: differs → G1 (Android red checkbox/Done vs iPhone purple ✓). Dialog+checkboxes, order: decided.
- addtoqueue: differs → G1 (red wash + red ✓). Series section decided (A88 triage).
- addworks: match. Part-height sheet, checkboxes, bottom Cancel/Add, Show mature text: decided. Minor: Android's
  "by undertow" in the accent, iPhone's bylines grey.
- ao3coll: match.
- bugreport: minor. Empty report: iPhone's disabled "Continue on GitHub" keeps white text + red bug (system), Android
  greys it; "Browse existing issues" icon grey on iPhone, red on Android. Page vs sheet decided.
- author: differs [Android] (Dark/OLED Subscribe fill, CLI's catch) + capture problem: iPhone Sepia = Home,
  iPhone OLED = blank (OCR scan confirms; re-shoot after the Android pass).
- authorabout: minor. Android's header block sits ~24 dp further in than its cards (old shots identical, so not new);
  bio blank line; Joined/User ID one card vs two.
- authorbookmarks: minor. Header inset as authorabout. Android's extra blurred first card is demo data: Android maps
  /users/AO3_Reader/bookmarks to `ao3_demo_account_bookmarks` (3 bookmarks), iOS maps every user to
  `ao3_author_bookmarks` (2) (`DemoNetwork.kt:227` vs `DemoLibrary.swift:792`).
- authorworksfilter: differs [iPhone] (CLI's catches: lightened pill, white Sepia header band). Otherwise match.
- availability: minor (Check Now's label in the accent on Android, primary on iPhone; likely the 2026-10-08 entry).
- backupimport: match.
- bookmarkform: differs [both] → G1 (iPhone purple Cancel/Save) + G2 (Android red wash). Title is demo state.
- bulkedit: minor (Rating's value: iPhone accent menu ⌃⌄, Android grey row ›). Counts demo.
- bulknames: match (D7 header).
- bulktag: differs [both] → G2 purple wash on Android; the hue is wrong on both.
- bulktagstate: minor (Android wash + large title; iPhone flat inline; iPhone's own bulknames has the wash).

## Fix notes (root causes found while waiting; fixes wait for the merged list)
- Android · author Subscribe: `author/AuthorProfileComponents.kt:176` is a bare Material `Button`; Dark/OLED
  `primary = PaperWarm` (`ui/theme/Theme.kt:55,68`) gives the cream fill. Use the pattern already in
  `library/LibraryFilterPanel.kt:117`: `buttonColors(containerColor = tokens.accent, contentColor = SubjectPalette.label(tokens.accent))`.
- Android · G2: `works/detail/WorkDetailForms.kt:87` `subjectScreenWash(tokens.scopePalette)` inside the
  `ModalBottomSheet`; other sheets that wash: CommentsScreen, CollectionDetailScreen, SaveSearchSheet, AccountInboxPane,
  AO3PreferencesScreen, WritingTextEditorScreen, WritingWorkFormScreen (to sort: page vs sheet).
- iOS · selected pill (authorworksfilter, author "All"): `SubjectSurface.swift` SubjectChip `.pill` fills with
  `palette?.accent ?? fill` (lightened on Dark/OLED); Android fills with `palette?.tint ?: tokens.accent` (exact).
  Q19: fills keep the exact accent → iOS fix.
- iOS · G1: T-446's `LibrarySectionFilterAccent` (LibraryFilterPanel.swift) gives a sheet `effectiveTint`; apply the
  same to Work Details' sheets (Add to Queue, Add to Collection, Bookmark) and Add Works.

### Batch 2
- chapterform: differs [Android] → G3 (publication-date switch). Demo work name and counts.
- chapterpicker: minor. Android's ✓ sits before the count, the iPhone's at the trailing edge; chapter glyph filled vs
  outline. The selected row (iPhone Chapter 1, Android All Comments) and the work are demo state.
- chapters: match (demo: 3 chapters vs 2).
- chassign: minor. Android's ↻ Refresh in the bar (iOS uses `.refreshable`, `ChallengeAssignmentsView.swift:133`);
  Android's "Load more defaulted assignments" is demo paging. iPhone big: the pinned buttons float over the card text
  with no bar ground (iOS-only).
- chmysignup: minor [Android] → G4 (prompt in sans; iPhone serif). Demo sign-up (1 request vs 3) and limits text.
  iPhone big: pinned buttons over text, as chassign.
- chprompts: match.
- Android · AO3 Account header inset (authorabout, authorbookmarks): `author/AuthorProfileScreen.kt:~722` the
  `usesAccountHeader` branch calls `SubjectHeaderBlock(... palette = palette)` without `gutter = 0.dp`, so the block's
  own gutter stacks on the list's padding (the error branch at ~703 passes `gutter = 0.dp`).
- Android · G3: `writing/WritingWorkFormScreen.kt:486` `WorkFormToggle` → use the exact fill (whatever
  `authorworksfilter`'s switch uses; it measures exact).
- Android · G4: serif for the sign-up prompt editor (`account/AO3ChallengeSignUpScreen.kt` ~171), challenge
  instructions, writing text editor, comment tray letters.
- chsettings: match (demo limits).
- chsettingsedit: minor → G4 (instructions in sans; iPhone serif). The olive hue is shot-route input: iOS's route
  passes the slug, Android's passes "Winter Exchange" (`DebugShots.kt:68`); both derive the hue from the title.
- chsignupdetail: match (demo sign-up; kicker is the route title).
- chsignups: minor [iPhone] (AX5: the pinned buttons float over the list text with no ground, as on chassign and
  chmysignup). Demo counts.
- colitems: match. The iPhone's Off/On text vs Android's switches follows each item's editability
  (`AO3CollectionItemsView.swift:662` `flagRow(isEditable:)`); the demo items differ (Awaiting you vs Awaiting collection).
- collection: match. Android's tab bar shows Home selected: the route navigates inside the Home tab (shot-route
  artefact, not product).
- collectiondetails: differs [Android] → G2 (green wash inside the details sheet; full height vs the iPhone's medium).
- collectionreorder: differs [Android] → G5 (Cancel red in Light, cream in Dark; iPhone green).
- collectionsgifts: minor [Android] (the search placeholder wraps to two lines at 1.0×). Demo counts.
- colmaint: differs [Android] → G6 ("Invite as" value red; iPhone teal).
- colmod: match (Android's pager is demo paging).
- colsettings: match (minor: the iPhone greys the locked "Collection name" label; Android only greys the value).
- colsfilter: minor [Android] ("AO3 order" has no ⌄; the iPhone has ⌃⌄; 3cr says a choice shows ⌄).
- comments: match (demo title).

### Batch 3 (Claude-CLI judged first; my independent read agrees, additions marked +)
- compose: differs [Android]: no wash (iOS: the comments palette's `subjectWash`, 320 pt). Minor: "10,000 left" is
  monospace on Android (`CommentComposerSheet.kt:314`); iOS uses the default font.
- creatorspicker: + differs [Android]: the pseud switches measure (219,114,114) in Dark and OLED and (133,37,37) in
  Light, the derived accent. They're `WorkFormToggle` (`WritingAssociationPickers.kt:188`), so 3he's fix covers them.
- customizetheme: differs [Android]: dark status-bar icons on the dark sheet (Dark: faint; OLED: invisible).
- downloaddate: differs [Android]: the bare `DatePickerDialog` (`WorkDetailMyCopySheet.kt:543`) takes the shell's
  Material colours (cream selected day in Dark and OLED, red in Light). The iPhone's Save is the work's purple.
- draftedit, editqueue, edittags (demo state), fandomfilter (segmented control vs pills, decided), fandomlist,
  fandomworks, hsec_reading, hsec_updated, inboxfilter (both washed), libpicker, libraryfilters, login (decided
  10-22), newcollection: match.
- formattingtray: differs [Android]: no wash (iOS: the app palette's `subjectWash`, 320 pt). Minor glyph differences:
  X² vs A², the "99" quote mark, and T vs H for Heading.
- languagepicker: differs [iPhone]: amber tick, the search page's hue leaking into `AO3FilterPanel`. Its hosts are
  `SearchView:689` and `NativeBrowseView:259` and `:614`, all under `.screenTint(resultsPalette)`. Android uses the
  app accent.
- mycopy: minor [Android]: the Downloaded row opens the editor but shows no chevron. The missing progress is demo:
  `publicationProgress` is null in Android's demo work.
- myseries: minor [Android]: the header inset (author-series route → `AuthorProfileScreen`'s account header). 3he
  fixes it. + The same double gutter is in `CollectionReorderSheet.kt:157`, inside a list padded 16 dp; ~60
  `SubjectHeaderBlock` call sites still need auditing.

### Batch 4 (Claude-Code, independent; merge with Claude-CLI's when it lands)
- newqueue, parentpicker (demo URLs and language state), privacydata (Android's "Imported fonts" row decided),
  queue, queuesettings, queuetag (the queue's wash; 3hf keeps it), queuetagedit (Android's dialog decided),
  queuetags, reader (demo text), readercontents (demo chapters), readerfind (Android's keyboard is up; the
  simulator hides it), readernote, pronunciations (sheet over Read Aloud vs a pushed page; voice-engine notes
  decided), pairing (no scanning on Android, decided): match.
- readerdisplay: match. Android's Keep screen awake and Audition Voice are also in iOS's `ReaderOptionsForm`
  (`SettingsView.swift:12`: Appearance, Text Size, Reading incl. Keep screen awake, Read Aloud incl. Audition, Font).
  The iPhone's medium detent just doesn't show them.
- pagejump: match (each a neutral pill over the search page; the iPhone's glass is translucent at its medium detent).
- prompttags: match. The olive vs teal is route input, as on chsettingsedit; the iPhone's sheet vs Android's page
  is platform.
- pronunciationedit: minor [Android]: Cancel and Save sit at the foot of the sheet, where the iPhone has them in the
  header. What's behind the sheet differs by route.
- queuestorage: minor [Android]: creator names in the accent, grey on the iPhone (A88a). Page vs sheet decided; demo counts.
- prefhelp: capture timing [Android Sepia, big]: the sheet hadn't finished rising (it sits lower than in the other
  columns). The content matches.
- **Merged with Claude-CLI's batch 4.** It caught two differs I missed, both confirmed in code:
  - **queue [Android]:** the Compact In Line grid draws only its left column. Cause: `QueueWorkItem` wraps a
    swipeable card in `SwipeActionRow`, which applies `fillMaxWidth()` (`ui/subject/WorkLibraryComponents.kt:271`).
    Inside the `chunked(2)` `Row` (`QueuePageScreen.kt:398`), the first card takes the whole row and the second gets
    no width. The obscured cards skip the swipe row, which is why only they and the second column vanish.
  - **queuetagedit [Android]:** the Edit tag dialog's Cancel and Save are the app accent. iOS `QueueTagEditSheet`
    (`QueueTagManagerView.swift:314`, wash `:411`, `.screenTint(palette)` `:451`) is the queue's colour. Dialog vs
    sheet is decided; the colour isn't. Check the manager's other dialogs too (`QueueTags.kt:390, 430, 573, 691`).
  - **readernote [Android, minor]:** Add Note's Done tick is primary ink (`ReaderNoteEditor.kt:100`). Its sibling
    sheets and the iPhone use the accent.
  - **prefhelp [Android, minor]:** Light measures (242,242,247) ground with white cards on the iPhone; Android is all
    white. 3ha's "white like iOS" no longer holds, so use the grouped ground. Check recovery in batch 5.
  - **pronunciations, pronunciationedit [Android, minor]:** the Listening page behind the sheet is scrolled under a
    transparent status bar. To check on readerspeech in batch 5.

### Batch 5, first 14 (readerspeech…seriespicker), Claude-Code independent
- readerspeech, revokedevice (Android's dialog decided), sec_downloaded, sec_finished, sec_later, sec_reading,
  seriesdetail (3ha's card holds): match.
- recovery: match (Android's HTML preview is demo text from the text editor; both are white in Light).
- savesearch: match after 3he (the sheet's Cancel takes the name's palette there). The routes differ (search start vs
  results).
- searchfilters: the iPhone's choice values look neutral over the search start page. That's the results palette
  leaking into `AO3FilterPanel`, which I22's `ScopeSurfaceAccent` fixes. Android's are the app accent.
- sec_favorites, sec_history: match. Demo progress and relative dates differ; at 2.0×, Android stacks the segmented
  control as a list.
- seriesedit: differs [Android] → the derived-accent switch: (219,114,114) in Dark/OLED, (133,37,37) in Light,
  (122,86,49) in Sepia, against the iPhone's exact colours. It's `WorkFormToggle` (`WritingSeriesScreen.kt:211`), so
  3he covers it.
- seriespicker: minor [Android]: the selected series shows a bare ✓. The iPhone shows a filled check circle, with an
  empty circle for the others. Android also adds "This work is in it" (extra, kept).
- Batch 5, last six:
  - seriespreserve: differs on both, already covered: G1 (the iPhone's purple controls; I21) and G2 (Android's red
    wash; 3he). The known-count text is demo data (A88 triage).
  - seriesremove: match. Android's words · date line is decided.
  - seriesreorder: match.
  - synconb: match. The checkbox is decided (10-22); the Material icons are platform (A76 matched it).
  - tagpicker: match. Android has the "Selected" group (`FilterTagPicker.kt:157`). Its route opens on the search
    start page, where no fandom is selected.
  - tagseditor: match (demo tags).
- pronunciations / pronunciationedit "text under the clock": a capture artefact. The status-bar ground comes from
  `ShellChromeState.isScrolled`, which only nested-scroll deltas feed (`ScrollAwayTopChrome.kt:44`). The shot route
  scrolls the Listening page programmatically, so the ground never shows. A user's own scroll does show it
  (decided 10-05, `MainScaffold.kt:436`). Not briefed.
- **Merged with Claude-CLI's batch 5:**
  - savesearch is a differ in these shots (pre-3he), and 3he covers it: `SubjectPaletteTheme(palette)` around
    `SaveSearchContent` turns its default `TextButton`s (Cancel `:98`, Save `:110`) to the sheet's ink.
  - sec_favorites and sec_reading pills: I21 covers them in all four themes. `LibraryCompletionPills.swift:22` goes
    through `SubjectChip.pill`, which now fills with `palette?.tint`.
  - **New, for 3hh: destructive red.** The iPhone uses system red (`role: .destructive`, `.red`: (255,56,60) in
    Light and Sepia, (255,66,69) in Dark and OLED, measured on seriesremove's ⊖ and recovery's Delete). Android uses
    the derived hue-0 accent, `SubjectPalette.fromHue(0.0, theme).accent` (33 sites): (219,114,114), (133,37,37) and
    (122,49,49). There's no decision on it. Plan: one Android token at iOS's system-red values, used wherever
    Android marks something destructive or an error.

### Batch 6 (tagset…writingpreview), Claude-Code independent
- tagseteditor, tagworks, texteditor (demo content), thread (demo kicker), welcome (icon decided), whatsnew
  (version text), workedit, works (Android's totals line decided; demo works): match.
- tagset: match. The differences are demo data: iOS loads `ao3_tag_set` for any tag set (`DemoLibrary.swift:780`),
  Android a dedicated `ao3_demo_tag_set_42` (`DemoNetwork.kt:251`), hence "0 tags" vs "7 tags" and the switch states.
- workdetail: match. The resume card's chapter and progress are demo state: "Chapter 2 · 75%" on the iPhone,
  "Content" with no progress on Android's demo EPUB.
- writingpreview: match by rule. The states differ: the iPhone's is a never-posted draft ("Post work"), Android's a
  posted work ("Update").
- **Merged with Claude-CLI's batch 6 (109 screens done; their tally: 64 match, 18 minor, 27 differ, one capture
  problem).** works [both]: the iPhone's selected chips are the lightened accent, and both rows go through
  `SubjectChip.pill(palette:)` (`WorksScopeAndSort.swift:31`, `AuthorProfileContentSections.swift:200`), so I21
  covers them. Android's header inset is 3he's fix.

### The 14 Settings pages (Claude-Code)
- s_appearance (Android's System theme decided; its dotted slider is the reader sheets' accepted control), s_font
  (demo font; footer decided), s_reader, s_listening (10-05 scope), s_downloads, s_preservation, s_queues,
  s_library, s_sync (demo pairing), s_import, s_privacy ("biometric" is platform), s_about (Android's Software
  Update decided): match.
- s_backup: match by rule. The technical notes and the Deletion signing section are owner question Q9, waiting.
- s_account: differs [Android]: the iPhone's "Log Out" row is system red (destructive). Android draws it in primary
  ink. 3hh's destructive audit covers it; check it in its report.

### The 20 main screens + the iPhone author re-shoot (Claude-Code)
- author: the re-shot iPhone Sepia and OLED columns are good, so the capture problem is closed. Its findings stand:
  the cream Subscribe (3he) and the lightened pills (I21).
- home, library, account (the "6+" badges and the blocked avatar are demo; decided 10-22), dashboard, prefs, more,
  settings, queues (the iPhone's lightened "All 4" pill → I21), collections, deleted, later, ao3colls: match.
- inbox, bookmarks: match, apart from the iPhone's lightened selected chip (I21 covers both sites). Bookmarks' extra
  local card is demo (Android's own account-bookmarks fixture).
- browse: match ("Jump back in" 3 vs 4 is demo history). search: match. The iPhone's demo has no saved search; iOS
  shows "Saved Searches" (`SearchView.swift:448`) when there are any.
- drafts: match by rule, demo data. Android loads `ao3_demo_drafts_1`, which has expiry dates; the iPhone's demo
  drafts have none. iOS draws the same "N days left" chip (`WritingDraftsView.swift:28/252`).
- subs: match by rule, demo data. Android's `ao3_subscriptions.html` adds a library work (999000002), and its demo
  seeds the "new since you last looked" snapshot. iOS has the same section (`AO3SubscriptionsWorksBrowser.swift:32`).
- history: match. Both keep AO3's order (decided 10-22), so "This month" can follow "Earlier".
- **insights: differs [Android] (A76 called it a match):**
  - (a) iOS draws all six Insights blocks as tinted subject cards, `.subjectCard(palette:)`: cardSurface + the
    palette's rowWash + rowBorder (`ReadingInsightsView.swift:186, 280, 341, 421, 448, 484`;
    `SubjectSurface.swift:411`). Measured in Dark: (60,27,31) on the iPhone against Android's neutral glass
    (33,33,35); in Light, (240,218,218) against (230,230,234). Android uses `subjectPanel()`.
  - (b) "words read" is 203K on the iPhone (Foundation's compactName) and 202.6K on Android: `formatCompactNumber`
    (`ReadingStatisticsScreen.kt:768`) keeps a decimal, where the shared `Int.compactCount()`
    (`SubjectComponents.kt`) already matches iOS.
  - Other iOS `.subjectCard` sites to check on Android: AO3CollectionDetail, AO3CollectionItems, AO3CollectionsList,
    AO3BookmarksWorksBrowser, AO3MarkedForLater, ChallengeAssignments, FavoriteAffinityRow, RecentlyDeleted. Most
    look tinted on Android already (deleted, ao3colls, later).

## Post-fix re-shoot: the iPhone half (claude/parity-i21 @ ad64c65d, the gated build; shot 08:19–09:01; tiles-post/)
Measured against `shots-final-2026-10-25/` (the before shots):
- **Scope sheets** (addtocollection, addtoqueue, bookmarkform, seriespreserve, addworks, bulktag): purple pixels in
  the sheets went from 94–393 to 0, except Add Works at 8–9, where the list's covers carry their own colour. The
  header accent is the app's in every column:
  - Dark (194,102,102) and OLED (189,89,89): the readable ink for #990000;
  - Light (153,0,0);
  - Sepia (154,103,50).

  bulktag's amber is gone. **Fixed.**
- **Selected pills in Dark:** on all 17 pill screens the lightened fill (216,112,112) fell (for example works
  6448→590, colitems 7000→1032), and exact (153,0,0) fills appeared (2271–8008 px). What's left is legitimate
  text ink. **Fixed.**
- **authorworksfilter's Sepia/big header band:** (255,255,255) → (236,222,193); Light is unchanged. **Fixed.**
- **colsfilter's wash:** now shows in Dark (63,7,8), Sepia (226,207,176) and OLED (67,0,0); Light is unchanged.
  The **formattingtray** wash shows below the header in the same three themes. **Fixed.**
- **languagepicker:** amber (218,167,113) → the red ink (193,101,102) in Dark, (153,0,0) in Light, brown in Sepia.
  **Fixed.**
- **bugreport:** the disabled Continue on GitHub is grey, text and icon, in every column. **Fixed.**
- **The AX5 bottom bars** (chassign, chmysignup, chsignups, chprompts, chsettingsedit): the clear buttons now sit
  on iOS 26's scroll-edge glass. The list behind is blurred and faded, and the labels read cleanly. **Fixed
  (native).**
- **New minor, iPhone-internal:** the search filter's menu values ("Any rating ⌃⌄") are primary ink with a red
  chevron, the system picker's look, while the author works filter's are red text. Android matches the latter.
  This isn't a parity regression; it's noted for a later decision. A98 chose the system picker's primary value
  for Sample Text.

## Post-fix re-shoot: the Android half (android/agent-codex-3he @ 6ca3f311; reshoot.sh then reshoot2.sh; tiles-post/)
The first run (09:04–12:36) lost a third of its shots to "isn't responding" and blank readers. `ab-anr.sh` showed
the old and new builds equal on a fresh emulator (main-thread CPU 2.6–3.5 s, 0 idle frames, 0 ANRs), so it was
host load. `reshoot2.sh` (android7.sh: retry on ANR or a sub-40 KB shot) re-took 251 pairs from 12:49.

Judged so far (Claude-Code), each against its A102 verdict:
- **Fixed:** addtoqueue, bookmarkform, bulktag (washes gone; controls in the app accent); collectiondetails (flat;
  its full height is decided); collectionreorder (Cancel/Done green); downloaddate (the work's purple); mycopy
  (Downloaded chevron); author (Subscribe red in Dark/OLED); authorabout, authorbookmarks, myseries, works (header
  at the cards' edge); addtocollection, seriespreserve (iPhone side); chapterform, creatorspicker, seriesedit
  (switches exact red, brown in Sepia); seriespicker (filled check circle); colmaint (Invite as teal);
  chsettingsedit, chmysignup (serif); chassign (tinted cards); compose, formattingtray, colsfilter (washes);
  customizetheme (light status icons on the dark sheet); queuetagedit (the queue's purple); queue (equal halves).
- **Unchanged and still match:** comments, parentpicker, workedit, chsettings, colmod, seriesremove, savesearch,
  chprompts, tagset, chsignups, colitems, thread, queuesettings, queuetag, queuetags, fandomfilter, fandomlist,
  readercontents, readerfind.
- **Older gaps both judges missed → 3hk** (`~/kudos-agent-codex/docs/android-port/briefs/3hk-post-fix-misses.md`):
  Add to Queue icon ink; bulk Tag's "+" and "YOUR TAGS"; the author hero's card; Dark/OLED Material `primary`
  cream (root cause of Add to Collection's cream checkbox/Done); the sign-up "PROMPT" label; challenge settings'
  one card per section; the series picker mark at 2.0×; My Series' header at the cards' edge; the collections
  filter at full height (iOS, and the 2026-10-15 account-lists rule).
- **Capture problems for a follow-up shot** (wrong screen or still loading; the scan's DIFF is a similarity, so
  low values are the suspects): customizetheme:sepia, fandomfilter:light, readercontents:big, seriesedit:light,
  seriesremove:dark, tagset:light.
- **Screens 51–61 (re-taken 13:31–13:54):** prefhelp fixed (Light: grey ground, white cards, as the iPhone);
  recovery, pronunciations, pronunciationedit, texteditor and the six sec_* screens re-shot pixel-identical to
  before (unchanged by the fixes; A102 matches).
- **Screens 62–68:** hsec_reading, hsec_updated, home, library, inbox re-shot pixel-identical (A102 matches);
  workdetail moved <0.2% (match); deleted's header now at the cards' edge (3he), tinted cards as the iPhone (match).
- **Screens 69–75:** queues, collections, bookmarks, history, subs, later, ao3colls re-shot (near-)identical; A102
  matches stand. Side by side, later/history/subs show the account lists' section headers 16 dp inside the cards'
  edge where the iPhone's sit at it → 3hk #10.

## 3hk Dark pass (cf110a23; shots vs shots-postfix-6ca3f311)
- First 64 of list-final-all: expected changes on author (hero card), bulktag, chmysignup, chsettingsedit, colsfilter,
  addtoqueue (icons), myseries (header), addtocollection (cream → red ink: 683 cream px → 762 red px). Capture
  noise (demo state or timing): bookmarkform, parentpicker, prefhelp, compose (its hue loads late; new purple
  matches the iPhone). aboutkudos and bugreport: the version hash only.
- F4's side effects, against the iPhone: backupimport's Replace Library… and pairing's Revoke now the system red
  (better); addworks' "Show mature" turned red, but iOS's MatureRevealToggle is primary ink when off
  (`.tint(gate.revealAll ? nil : Color.primary)`) → 3hk follow-up #12.
- Screens 65–109: seriesremove's Dark is the expected follow-up (now the Remove works page). F4 moved bare Material
  controls from cream to the accent ink in Dark, as they already were in Light: pronunciations' Done, the reader
  and speech sliders' ticks, pronunciationedit's controls, revokedevice's dialog buttons. queuesettings and
  workdetail: demo times only. No regressions.
- Main screens and Settings (35): 28 unchanged; history, subs, later (#10 headers), author (#3 card); s_appearance,
  s_listening (slider ticks in the accent ink, F4), s_sync (tiny). **Dark pass complete: no regressions.**
- **3hk's screens in the other columns (reshoot3, 16:09–17:10, host load ~9: 25 ANR retries):** author hero card in
  every theme; chsettingsedit one card per section; colsfilter full height, Reset at the foot; bulktagstate's
  cards white/cream/grey as the iPhone; seriespicker's mark grows at 2.0×; chmysignup's PROMPT label. Follow-ups:
  #13 the Scope row under the hero is a card on iOS (`pseudSelector(...).cardRow()`); #14 bulk option marks
  grow with the text. Recorded, not fixed (minor): chmysignup's Add request is plain accent text on Android, a
  grey capsule on the iPhone. Capture problems to re-take: authorbookmarks big, bulktag sepia, seriesedit light
  (ANR after 3 tries), colsfilter oled (came out in Sepia).
- **3hl (447ca8e8), reshoot4 17:25–17:32, no retries:** addworks' Show mature is primary ink while off (white in
  Dark/OLED, black in Light/Sepia), as iOS's MatureRevealToggle; the author's Scope row is a card as the hero's,
  its value still the accent; bulktagstate's marks grow at 2.0×. Follow-ups now good: seriesedit light (loaded),
  bulktag sepia (no "+", "Your tags"), authorbookmarks big, colsfilter oled (black ground).
  **Android post-fix verification complete: every A102, 3hk and 3hl fix seen in its columns; no regressions.**
