# Survey of the existing iPhone boards (shared parts, sizes, conventions)

SHARED TOKENS (apply to every Duo board)
- Large title: 34/41 700, letter-spacing 0.4. Duo-Open-Library column title: 28/34 700 (ls 0.35), subtitle 13/18 #6C6C70. Detail title: 20/25 700. Subtitle under a large title: 15/20 #6C6C70.
- Section header: 22/28 700 (ls 0.35), with "See All" as a 15px accent link on the same baseline. Account-Regrouped uses 20/25 700. Many iPhone boards (Search, Settings, Account, WorkDetail, Fandoms) still use 13px uppercase #6C6C70 headers. That breaks the rule sweep, so don't copy it. Uppercase 10–12px is fine for stat captions, kickers ("ORIGINAL WORK", "SERIES") and menu group labels.
- App glass: rgba(255,255,255,.74), or .78 for the sidebar; blur(24px) saturate(180%); shadow 0 6px 20px rgba(0,0,0,.10) on toolbars, 0 8px 28px .12 on bars, 0 10px 32px .10 on the sidebar; plus 0 0 0 .5px rgba(0,0,0,.06) and inset 0 1px 0 rgba(255,255,255,.9).
- Reader glass: rgba(255,253,248,.72), blur 24 saturate 160%, shadow rgba(60,40,10,.10) plus a .5px rgba(60,40,10,.08) ring and the inset highlight. Secondary ink is #6B645A.
- Toolbars: iPhone uses 44px circles and capsules of 46×44 buttons at top 54, inset 16. Duo-Open uses 40px-tall capsules of 42–44×40 buttons at top 14, right 16.
- Menus: 250–270 wide, radius 22–24, rgba(250,250,252,.86–.88), blur 30, shadow 0 18px 50px rgba(0,0,0,.22). Rows 42–44px, 16px text, 19px icons. Group separators .5px rgba(60,60,67,.18). Destructive colour #D70015.
- Cards: white. Radius 16 for lists and stats, 22 for the hero card, 14 for settings groups, 18 for queue cards, 20 for the profile card.
- Row heights: settings 46 with a 29px icon tile (radius 7); account 48; menu 44; sidebar 36 (radius 12), sidebar queues 34; fandom rows min 56; Insights author rows 56.
- Buttons: primary is an accent capsule 44 high (Home), 46 (Duo detail) or 50 (iPhone detail), with a 16px play icon. Secondary is an accentTint (10%) circle of the same height.
- Progress bars: 4px, radius 2, track #E5E5EA. WorkRow uses 3px.
- Segmented control: 34h, radius 17, rgba(118,118,128,.12), padding 2; selected segment white with shadow 0 2px 6px rgba(0,0,0,.12).
- Search field: 36–38h, radius 18–19, same fill as the segmented control. Switch 51×31 #34C759. Separators .5px #E5E5EA; #D1D1D6 inside WorkRow and stat grids.
- Sheets: top radius 38, grabber 36×5 #C7C7CC, 44px circles for Cancel (rgba(118,118,128,.14)) and Confirm (accent), title 17/600.

DUO-COVER-READER (466×678)
- Top controls: Close as a 44px circle on the left; on the right a capsule holding [Aa = Themes & Settings | ••• More].
- Bottom pill: left/right 16, bottom 28, radius 30, padding 10 8 6.
  - Line 1: title 14/600 plus "Ch 7 of 20" 13px #6B645A.
  - Line 2: Contents 44, Add bookmark 44, scrubber, Read aloud 44.
  - Scrubber: 4px track rgba(31,27,22,.14), 16px white thumb, caption 11px "Page 4 of 18 · 21 min left".
- More menu, 268 wide, paper glass rgba(252,250,245,.9), scrim rgba(40,30,10,.14), pressed state on ••• is rgba(0,0,0,.07):
  - Contents (22%)
  - Bookmarks & Highlights (5)
  - Find in Work
  - Comments (286)
  - separator, then Read Aloud ("hold for voices")
  - Themes & Settings
  - Rebuild from Original ("imported files")
  - separator, then Share
- Read Aloud state:
  - Current sentence highlighted in accent at 14%.
  - Player pill rgba(255,253,248,.82) showing title, "Ch 8 of 20", "Page 2 of 17" – bar – "18 min".
  - Chip "1.1× · Kokoro", 36h, rgba(60,40,10,.06).
  - Previous chapter 44, Pause 54 accent circle, Next chapter 44, Stop 36 circle. Bottom fade 220.
- Article: padding 124 30. Kicker "CHAPTER 7" 12/16 600 (ls 1.6). h1 28/34 600. Body serif 19 / 1.56, text-indent 1.3em. Paper fades: 120 at the top, 150 at the bottom.
- Open question: whether the tab rail hides in the reader. The iPhone reader hides its tab bar.

DUO-OPEN-HOME (951×669)
- Sidebar copied from Duo-Open-Library with Home selected:
  - Search field "Search AO3 and Library".
  - Library expands to: All Works 214, Reading 6, Up Next 12, Downloaded 98, Marked for Later 31, History.
  - Browse, Account.
  - Reading Queues: Summer Reading 8, Re-reads 5, For the Train 3.
- Toolbar: Select. Header "Home" with "3 new chapters · checked 2 min ago".
- IA order: Reading Now → New Chapters → stats strip → shelves. Main.dc puts the stats strip first; follow the IA.
- Stats strip (links to Insights): "4 h 10 m this week", "2 finished", "9 days reading streak", chevron.
- Reading Now hero:
  - Kicker "ORIGINAL WORK", title 18/22 600, author as an accent link.
  - "84,210 words · 3,104 kudos"; "Ch 7 · The Salt Road 58%" with bar.
  - Symbols labeled T/FM/none/wip with chapters 12/20, size 22.
  - Buttons: Resume, Read aloud (tint), Work details (#F2F2F7 circle).
- Reading Now CoverCard shelf (width 104): Salt & Starlight (+3, Ch 12 of 30, 40%), Letters Never Sent (50%), Moor and Mist (61%), Small Gods of the Kitchen (20%).
- New Chapters shelf: Salt & Starlight +3, The Hound, Revisited +1, Under the Same Stars +1, Northanger Nights +1.
- Reading Queues ("All Queues"): cards 214 wide with a 4-cover strip 62h and a colour dot. Summer Reading "8 works · 6 offline" (#C25E00); Re-reads "5 works · all offline" (#1E63C8).
- "Austen Variations" collection shelf: A Map of Small Hours, Northanger Nights, Five Times Elizabeth Laughed, Letters Never Sent.
- Subscriptions: WorkRow for Keeper of the Northern Light, badge "New", "New work · 3h ago".
- Insights, if shown as a detail:
  - Period: Week / Month / Year / All.
  - Stats: Time reading 11 h 40 m; Words read 312k; Works finished 6; Days with reading 22 of 25.
  - Minutes-per-day chart (avg 28; axis Oct 1 / 15 / 25).
  - Favourite authors: quietharbor, wrenfield, fogandlamplight.
- Queue, if shown as a detail:
  - Toolbar: Back, Add works, More (Edit Queue / Queue Details / Delete Queue).
  - Header: dot, title, description, chips "8 works · about 9 h 40 min", "6 offline", "fluff", "under 20k".
  - Up next card with a Start button; numbered WorkRows marked Offline / Not downloaded.
  - Row menu: Move to Top / Up / Down / Bottom, Work Details, Read, Remove from Queue (red).
- CoverCard rules:
  - Cover 1.42× width; progress bar directly under the cover so bars line up.
  - Symbols strip, title 2 lines at a fixed 32px, then meta.
  - Text variant for works with no cover; hidden-mature variant.

DUO-OPEN-SEARCH
- Query "lighthouse" with Clear and "Back to Browse".
- "In your library · 2": The Lighthouse Keepers ("Downloaded"), Salt & Starlight ("Tag: lighthouses").
- "Your tags, collections, fandoms" chips with an 11px uppercase kind label: Tag lighthouses 4, Collection Comfort Reads 1, Fandom Original Work 3.
- "Fandoms on AO3" (48px rows): To the Lighthouse - Virginia Woolf 312; The Lamp at Skerry Head (Novel) 48.
- "On AO3 · 1,284 works":
  - "Best match ▾" sort chip and an accent Filters chip showing "2".
  - WorkRows with summaries: Keeper of the Northern Light, What the Lamp Saw.
  - Pages: ‹ 1 2 3 … 65 ›.
- Filters (an .inspector column fits here):
  - Cancel / Apply.
  - Sort by "Date updated", with Newest first / Oldest first.
  - Symbols labeled chips, using `only=`:
    - Rating G T M E (G and T on).
    - Warnings none / undisclosed / present (none on).
    - Categories FF FM MM Gen Multi Other (FF and Gen on).
    - Completion complete / wip (complete on).
  - Include Not Rated (switch) and Crossovers (Include).
  - Ranges: Word count "10k or more", Hits, Kudos "100 or more", Comments, Bookmarks, Chapters, Updated "Past month", Language "English", Title & creator.
  - Tags: Include "Found Family", Exclude "Major Character Death", "Add a tag", and "Popular in Original Work" (Slow Burn, Fluff, Hurt/Comfort).
  - Reset filters (red) and Save Search….
- WorkRow anatomy:
  - Symbols grid size 24 (51px); title 16/21 600 on 2 lines; badge.
  - "author · fandom" 13px; summary 14/19 #3A3A3C on 2 lines.
  - Stats 12px: words · ch · kudos · hits · updated; progress bar plus label.
  - Padding 12 16, divider inset 79; selecting and hidden variants.

DUO-OPEN-WORKDETAIL
- Toolbar: Back, Kudos given (pressed, accent), Bookmark on AO3, More actions.
- Header: cover, title 24/29, author link 17 accent, fandom link 15. Symbols labeled with chapters 12/20.
- Buttons: Resume Chapter 7, Read aloud, and Update download with a "2" badge.
- Stats: 9 cells — Words, Chapters, Kudos, Hits, Comments, Bookmarks, Published Mar 3, Updated Oct 21, Language. Duo-Open-Library drops Published; keep all 9.
- Summary with a Notes link.
- Tag groups stay separate: Relationships (tinted), Characters (3), Additional tags (4).
- Series card: "Part 2 of The Coast Road · 3 works", with ‹ Part 1 / Preserve Series… / Part 3 ›.
- "My copy · private to this device":
  - Progress: Ch 7 · 58%
  - Downloaded: Oct 21 · Edit
  - Your tags: coast, reread · Add
  - Collections: Comfort Reads · Add
  - Queues: Summer Reading · Add
- File: "EPUB from AO3 · 1.2 MB", with the Rebuild note. Comments row showing 286.
- Read Aloud accessory: Salt & Starlight, "Read Aloud · Ch 15 · 12 min left", Pause.
- More menu:
  - On AO3: Give Kudos, Edit Bookmark… (saved), Subscribe, Mark for Later, Comments 286.
  - Library: Favourite, Save for Later (rename to **Want to Read**), Mark as Finished, Add to Queue…, Add to Collection…, Rebuild from Original.
  - Share: Share…, Open on AO3, Delete from Library (red).
- Series screen:
  - Kicker, title, "inkwell_moth · 3 works · 141k words · in progress", description.
  - Subscribe (primary) and "Preserve all 3", which should be an accentTint capsule.
  - Toolbar: Share series; More (Open on AO3; for your own series Edit / Reorder / Remove works).
  - Numbered rows: The Surveyor's Wife ("In your library"), The Cartographer's Daughter (58%), Blank Vellum.
- Comments: same as DUO-BOOK-COMMENTS below.

DUO-OPEN-ACCOUNT
- Base it on Account-Regrouped. Toolbar: Edit and a Settings gear.
- Profile card:
  - Avatar 60, "saltwindow" 24/29, "Posting as saltwindow ▾", a Profile button.
  - Counts: 6 Works, 142 Bookmarks, 27 Subscribed, 3 Unread.
- Groups:
  - Reading on AO3: Marked for Later 31, Bookmarks 142, Subscriptions 27 ("4 new"), AO3 History.
  - Writing: Works 6, Series 1, Drafts 2.
  - Community: Inbox (badge 3), AO3 Collections & Challenges 4.
  - Account: Preferences, Dashboard, More on AO3, Log Out (red, no chevron).
- Footnote about using Edit to pin, hide or reorder.
- From the old Account board, keep "View profile" and the shortcuts (Dashboard, Subscriptions, Works, Bookmarks, Collections, History); they become pinnable rows.
- Inbox:
  - Toolbar: Select. Title with "3 unread".
  - Rows: accent unread dot, sender (600 when unread), time, replied icon, context line, 2-line body.
  - Swipe actions: Unread (accent) and Delete (red), each 74 wide.
  - Bottom bar: Filter toggle (on), "Filtered by: Unread", Inbox settings on AO3.
  - Data: tidewright, marginalia, quietharbor, anne_at_lyme.

DUO-OPEN-SETTINGS
- "Back to Account", a Search settings field, then 46px rows with 29px colour tiles:
  - Reading: Appearance (Sepia), Font (New York), Reader (Pages), Listening (Kokoro · Bella).
  - Downloads & storage: Downloads (Keep what you read), Preservation (Auto up to 10 works), Reading Queues (412 MB).
  - Library & sync: Library, Backup (Oct 24), Sync Folder (On), Import.
  - Account & privacy: AO3 Account (saltwindow), Privacy (Blur mature works).
  - About: About Kudos (Version 1.6), Report a Bug.
- Appearance:
  - Themes Light / Sepia✓ / Dark / OLED: tiles 88h, radius 12, 2.5px accent ring.
  - "Match app and reader theme" switch.
  - 7 accent swatches at 32px: AO3 red, Blue, Teal, Green, Purple, Pink, Graphite; then "Reset to AO3 Red".
  - Fonts: New York✓, Georgia, San Francisco, Atkinson Hyperlegible, "Add Font…". Then Customize Theme ›.
- Backup & Sync:
  - "iCloud Drive › Kudos", "Up to date · synced 2 min ago". This uses #2F8F3A, which is about 4.1:1 — below 4.5, so darken it.
  - Auto Sync (on), Sync Now, Sync Details ("0 pending"), "Pause on this iPhone" (off), Change Folder, Disconnect (red).
  - Devices: This iPhone, Reading tablet, "Pair a Device…".
  - Last backup "Oct 24 · 2.1 GB", Export Backup…, Import Backup…, Import Files…, plus all 3 footnotes.

DUO-OPEN-READER (flat; content may cross the crease)
- Every iPhone-Reader control and the full More menu from DUO-COVER-READER.
- A two-page spread. Reader-Settings names the open Duo as the case for this.
- Themes & Settings:
  - Customize…, Done (accent check).
  - Light / Sepia / Dark / OLED "Aa" tiles, 64h, radius 14.
  - Text-size slider A–A, Font (New York) ›, Layout Pages / Scroll, "Spacing · Margins" (Normal · Wide) ›.
  - Justify text (on), Bold text (off), Keep screen awake (on), and the spread footnote.
  - Use a popover or inspector rather than a full sheet.

DUO-BOOK-COMMENTS
- Reader page on the left, comments on the right; nothing in x455–495.
- Comments pane:
  - "Newest First ▾" sort; "The Cartographer's Daughter · 286"; scope All Comments / "Chapter 7 ▾".
  - Comment cards: 32px initial avatar, author link, meta ("Creator" tag), body, more (copy link / edit / delete), Reply, "3 replies ›", replies indented 20.
  - "‹ Previous · Page 1 of 4 · Next ›"; composer "Comment on Chapter 7…" with a 38px accent send button.
- Thread:
  - Title "Thread", Back, "Parent Thread".
  - 2px #D1D1D6 reply rail; nested replies indented 12.
- Reply sheet:
  - Cancel, "Reply to saltwindow", "Expand to full screen", Post (accent, 40h).
  - Text area #F2F2F7, radius 14.
  - Formatting buttons (38h, radius 10): Bold, Italic, Underline, Strikethrough, Link, Quote, More formatting.

DUO-BOOK-HOME
- All DUO-OPEN-HOME content, split into panes 455 and 456; nothing in x455–495. The sidebar can't cross the fold.
- Don't carry over these Duo-Cover-Home gaps:
  - hand-drawn symbol squares;
  - the names "Continue Reading" / "Up Next";
  - the missing stats strip, kicker, kudos, Read aloud and Work-details buttons, Select, and the queues / collection / subscriptions shelves.

DUO-PORTRAIT-BROWSE (669×951)
- Browse:
  - AO3 website button (globe).
  - Jump Back In chips, 56h: Sherlock Holmes "Books · visited today"; Pride and Prejudice "Books · ★ favourite" (draw the star as SVG); Original Work.
  - 11 Categories, 64h cards with a 36px tint icon: Anime & Manga, Books & Literature, Cartoons & Comics, Celebrities & Real People, Movies, Music & Bands, Other Media, Theater, TV Shows, Video Games, Uncategorized Fandoms.
- Fandoms:
  - Back; accent Filter button (grouping / minimum works / tag kinds / yours).
  - Search fandoms; "Grouped by family · at least 50 works · Reset".
  - Favourites (2 "& related" rows with download counts), then J and N sections.
  - Star toggle (#E2A100 / #AEAEB2) and an A–Z index in 11px accent.
- Fandom-Works (selection):
  - Select All; Done (accent). Title 28/34.
  - "2 selected · sorted by kudos · filters: Complete".
  - 5 selecting WorkRows; Whatever Remains is E with 2 warnings.
  - Glass action bar 62h: Download, Add to Queue, Add to Collection.
- TabBar: 358 wide, fits at the bottom.
  - Full: 62h with 4 tabs of 54 each, plus a 62 Search circle.
  - Minimized: 54 tab circle, accessory, 54 Search.

DUO-COVER-HOME (466×678)
- Rail: right 10, top 182, width 64, radius 32, padding 4. Buttons 56 (radius 28), icon 22, label 10/600, selected = accent tint. Search is a 64 circle with a gap of 10 below the rail.
- Padding is 30 86 0 20. The 20px left edge breaks the one-16px-edge rule.
- Fix: replace the 16px hand-drawn symbol squares with the shared Symbols component. Use the IA names (Reading Now / New Chapters), add the stats strip, and add the Read aloud and Work details buttons. Make the shelf from CoverCards at about 96 wide; the current hand-built covers have no Symbols or progress bar.
- Keep the Up Next data: A Map of Small Hours (32k · Complete), Salt & Starlight (118k · 15/30), The Baker Street Irregular (9k · One-shot), Letters Never Sent (21k · Complete).
- Symbols palette:
  - Ratings: G #2F8F3A, T #F5C400 (text #3A2C00), M #E07000, E #C8102E, NR grey.
  - Categories: FF #D2264B ⚢, FM #B3127A ⚤, MM #1E63C8 ⚣, Gen ☉ green, Multi 4-quadrant, Other #1C1C1E ♅.
  - Warnings: none = dash, undisclosed = orange ?, present = red ! with count.
  - Status: complete = green check, wip = ring on #FFE6C2 / #B35A00.
  - Radius 0.24×size, gap 0.12×size.
  - Variants: grid / strip / labeled.

DUO-BOOK-READER
- The current board is missing these iPhone controls:
  - Add bookmark;
  - the ••• More menu (Bookmarks & Highlights, Find in Work, Comments, Rebuild, Share);
  - the scrubber with "Page x of y";
  - the "title · Ch 7 of 20" line.
  Add them without touching the fold.
- Layout tokens:
  - Panes: 455 | fold 40 (#EEE8DC with a centre line rgba(60,40,10,.14)) | 456.
  - Page padding 70 40/44. Running heads 11/14 600 uppercase at top 26. Folio 12px at bottom 22.
  - 36px inner-edge gutter shadow.
  - Close: 40px circle at 14,14. Right-page capsule (40h): Contents, Read aloud, Aa.
  - Progress: 3px bar with "Ch 7 · 9 min left" at bottom 48.
  - Body text 18 / 1.58.
