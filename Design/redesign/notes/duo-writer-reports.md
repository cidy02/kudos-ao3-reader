# Duo board writer reports (2026-10-26). None of these boards were reviewed: every reviewer hit the usage limit.

## Duo-Cover-Reader

I've written the Cover · Reader board at Design/redesign/project/Duo-Cover-Reader.dc.html (466×678) and created no other file. The self-check passed: the support.js line is present, data-props parses, sc-for is 1/1, sc-if 4/4, dc-import 0/0, and every element is closed.

**What it shows:** Chapter 7, "The Salt Road", in New York 18px (adjustable from 15 to 26) on #FAF7F0 paper, with the reader controls visible and no tab rail. The controls match the iPhone reader:
- **Top:** a glass Close button (44px) on the left, and a capsule with Aa and ••• on the right.
- **Bottom pill:** "The Cartographer's Daughter · Ch 7 of 20" on top, then Contents, Add bookmark, a slider reading "Page 4 of 18 · 21 min left", and Read aloud.

A `view` setting (an enum) switches the board between three states:
- **controls:** the default, described above.
- **more:** adds a scrim, shows ••• as pressed, and opens the full 8-item menu from Reader-Menu.
- **readAloud:** the highlighted sentence and the full player.

**Imports:** none. No shared component fits a reader page.

**Not placed:** nothing.

**Decisions for the owner:**
- I used one board with a `view` setting instead of three boards, to keep this to one file.
- Controls sit at top 28 and the pill at bottom 20, because I don't know the cover screen's safe areas.
- The h1 is 26/32 (iPhone uses 28/34).
- The 1.1× · Kokoro chip and the Stop button still look 36px, but each now has a 44px touch target.
- Read Aloud hides the top controls, as the iPhone board does.

## Duo-Open-Home

The board is written at Design/redesign/project/Duo-Open-Home.dc.html. The self-check passed: the support.js line is exact, data-props parses with accent and $preview 951×669, and the sc-for (7/7), sc-if (1/1) and dc-import (5/5) tags all close. I have not rendered it.

**What it shows:** The floating glass sidebar is copied from Duo-Open-Library: same search field, items and queues, with Home selected. To its right is a glass Select capsule and the large title "Home" with "3 new chapters · checked 2 min ago". Under that, Reading Now uses the wide layout: the hero (336px, about 48% of the content width) sits on the left and the next works sit on the right as CoverCards. The 3rd card peeks at the edge to show the row scrolls. New Chapters (+3/+1 badges) is cut by the board edge just below its Symbols strip. Then follow, in IA order: the stats strip linking to Insights.dc.html, Reading Queues, Austen Variations and Subscriptions. All of these are in the markup below the fold.

**Imports:** Symbols (labeled, in the hero), CoverCard (three shelves), WorkRow (Subscriptions).

**Could not place:** nothing. Every section from Main.dc.html is kept.

**Decisions for the owner:**
- The Reading Now cards are 134px wide, not 104, so they match the hero's height. The other shelves stay at 104.
- The stats strip, Queues, the collection and Subscriptions are only visible by scrolling, not on the board.
- The sidebar still says "Marked for Later 31" under Library, copied from Duo-Open-Library. Per the IA the local list should be "Want to Read", and Account already has AO3's "Marked for Later 31".

## Duo-Open-Account

The board is written at `Design/redesign/project/Duo-Open-Account.dc.html`. The self-check passed: the support.js line is exact, data-props parses with accent and the 951×669 preview, and the sc-for (6/6), sc-if (5/5) and dc-import (0/0) tags balance. I didn't render it.

**What the board shows:** three panes, like Mail on iPad.
- **Sidebar:** the glass sidebar from Duo-Open-Library, with Library expanded and Account selected.
- **Account column (368 wide):** "Account" title with an Edit + Settings gear capsule. Then a profile card (S avatar, saltwindow, "Posting as" pseud menu, Profile button, counts 6 / 142 / 27 / 3). Then all four Account-Regrouped groups, with Inbox selected in a 10% accent tint, and the Edit footnote.
- **Inbox column (331 wide):** "Inbox · 3 unread" with Select, the four inbox messages (unread dots, replied icon, Unread/Delete swipe actions), and the glass filter bar.

**Imports:** none, because no works appear.

**Not visible on the static board:** a 669px-tall column can't fit 13 rows of 44px plus the profile card. The column scrolls (open the board in Play to scroll it). Below the visible area are AO3 Collections & Challenges (8px peeks), Preferences, Dashboard, More on AO3, Log Out and the footnote.

**Decisions for the owner:**
- Account rows are 44 tall, not 48. Section headers line up with the 16px edge.
- Swipe actions are now on anne_at_lyme's row, so "Unread" acts on a read message. A read row still shows while the Unread filter is on, which the iPhone board already does.
- The tab sidebar plus a separate Account list column settles gap 6.

## Duo-Open-Settings

I wrote `Design/redesign/project/Duo-Open-Settings.dc.html` (951×669). The self-check passed: the support.js line is there, the data-props JSON parses with the accent tweak and `$preview`, every tag opens and closes, and the JS parses. I did not render the board.

**What the board shows:**
- **Left column (330 wide, no glass):** a glass "‹ Account" back capsule, the title "Settings" at 28/34, a search field, then all 15 categories from Settings.dc.html in their 5 groups. Each row has its coloured 29px tile and its value. "Backup" is selected (accent fill).
- **Right column:** "Backup & Sync" as a small centred title, as iPad Settings detail pages do, then every row and footnote from Settings-Backup-Sync as an inset grouped list. The two switches work.

**Components imported:** none; this board needs no work components.

**Below the fold (in the list, but you have to scroll to see them):** 44–46px rows can't fit in 669px.
- In the left column: Sync Folder (half visible), Import, AO3 Account, Privacy, About Kudos and Report a Bug.
- In the right column: Pair a Device (half visible), Backup file, Import Files and their footnotes.

**Decisions for the owner:**
- The app tab sidebar is hidden while Settings is open, so the back capsule is labelled "Account".
- Action rows (Sync Now, Disconnect) have no chevron.
- The status green is darkened to #1E7B34 (5.3:1 contrast).
- Section headers are sentence case, not uppercase.
- Backup, Sync Folder and Import all lead to this one page. Should they merge into one category?

## Duo-Open-Reader

The board is written to `Design/redesign/project/Duo-Open-Reader.dc.html`, and the self-check passed. It has the support.js line, the data-props JSON parses (accent, view, $preview 951×669), and sc-for 3/3, sc-if 3/3, dc-import 0/0 match. No tags are left unclosed.

**What it shows:** a two-page Sepia spread (pages 475 | 476) with a soft gutter shadow at the centre and justified 18/28 serif text. Each page has a running head (work title on the left, "Chapter 7 · The Salt Road" on the right) and a folio. Chrome:
- top-left glass Close (44px);
- top-right glass capsule with Aa and the ••• More button;
- one 520px glass pill centred across the gutter: title and "Ch 7 of 20", then Contents, Add bookmark, a slider with "Pages 4–5 of 18 · 21 min left", and Read aloud.

A `view` tweak (controls / more / settings) and clicks open the 8-item More menu or a Themes & Settings popover. The popover has every Reader-Settings item.

**Imports:** none. The board needs no Symbols, CoverCard or WorkRow.

**Not placed:** the Read Aloud player state. It has its own boards (Reader-ReadAloud, Duo-Cover-Reader).

**Decisions for the owner:**
- The tab sidebar is hidden in the reader, matching the iPhone, which hides its tab bar.
- Folios sit at the outer bottom corners so the centred pill can't cover them.
- Folios use chapter page numbers (4 and 5) to match the scrubber. Duo-Book-Reader uses 112/113.
- The popover gains a "Two-page spread" switch (on) and the footnote "needs the Pages layout". This replaces the iPhone footnote, because the open Duo is wide enough for the toggle to show.
- I dropped the textSize tweak so pages clip on whole lines.

## Duo-Book-Comments

I wrote the board at Design/redesign/project/Duo-Book-Comments.dc.html. The self-check passes: support.js line, data-props JSON, matched tags, no expression holes, and renderVals runs in node.

**What it shows**
- **Left pane (0–455):** page 113 of Chapter 7 with a running head, folio and gutter shadow. The reader controls are hidden, so the page is immersive.
- **Fold (455–495):** paper shadow and centre line only.
- **Right pane (495–951):**
  - Header: "Comments" title, "The Cartographer's Daughter · 286", and a glass capsule with Newest First ▾ and Close.
  - The segmented control (All Comments / Chapter 7 ▾) switches when tapped.
  - Three comment cards with avatar initials, a Creator badge, the ••• menu (Copy Link, plus Edit and Delete on your own comment), Reply and "3 replies ›".
  - Paging row and the composer sit at the bottom of the pane.
- **Interactive states:** the Thread view (Back, Thread, Parent Thread, reply rail, nesting at 12) and the reply sheet (Cancel, title, Expand to full screen, Post, text area, 7 formatting buttons). Both open inside the right pane only.

**Imports:** none. No Symbols, WorkRow or CoverCard element is needed on this screen.

**Could not place:** nothing.

**Decisions for the owner**
- Paging is pinned above the composer instead of sitting at the end of the list. At 669px tall it would otherwise be off-screen.
- Formatting buttons and Post are 44px tall, not the 38/40 in the checklist, to meet the 44px touch-target rule.
- I added a fourth thread reply (quietharbor) so the thread matches "3 replies".
- Tapping the page to bring back the reader controls is assumed and not drawn.

## Duo-Book-Home

The Book-pose Home board is written to Design/redesign/project/Duo-Book-Home.dc.html. The self-check passed: the support.js line is present, data-props parses (accent, $preview), sc-for is 6/6, sc-if 0/0 and dc-import 5/5. I have not rendered it.

**What it shows:** one shared scroll in rows that span both panes, following DashboardRegionRow. Nothing sits in the fold band (x 455–495).
- **Header:** "Home" with its subtitle in the left pane. A glass Select capsule sits top-right.
- **Reading Now:** the full hero in the left pane (Symbols labeled, Resume, Read aloud, Work details). Three complete CoverCards, 110 wide, in the right pane; Small Gods of the Kitchen is one swipe away. See All is on the same baseline.
- **Next row:** New Chapters (4 CoverCards, 96 wide) on the left. On the right, the stats strip linking to Insights, then Reading Queues.
- **Below the board edge:** Austen Variations (left) and Subscriptions (right).

**Imports:** Symbols, CoverCard, WorkRow.

**Not placed as specified:**
- Queue cards are 2 × 171 wide with a 46px cover strip instead of 214 / 62h, because the right pane's content area is only 354px.
- The New Chapters titles and everything after them are cut off at the bottom edge.

**Decisions for the owner:**
1. Tabs: the sidebar collapses to the cover display's vertical glass rail with a Search circle, on the outer edge of the right pane. That pane (456×669) is nearly the size of the cover display. This is unverified on a device, since TASKS records nothing for the inner screen.
2. The two panes share one scroll, as the code does today, rather than scrolling separately.

## Duo-Portrait-Browse

The board is written at `Design/redesign/project/Duo-Portrait-Browse.dc.html`. The self-check passed: the support.js line is exact, data-props parses, and the sc-for (3/3), sc-if (4/4) and dc-import (1/1) counts match. I did not render it.

**What it shows:** Compact width, because 669 is below the regular threshold and T-452/T-455 say portrait stays compact. The large title "Browse" sits in the toolbar row (the code uses `.inlineLarge`) with the glass globe button. Below it:
- **Jump Back In:** a carousel of 56px cards: Sherlock Holmes, Pride and Prejudice (★ favourite as SVG), Original Work, and Jane Eyre peeking at the edge.
- **Categories:** all 11 in a 2-column grid, each fully visible above the tab bar. Each card has the 36px tinted icon, a stats line ("18k fandoms · ~2.1M works"), a download count, and one row of popular-fandom chips from the app's `FandomChipCluster`. Chips have an accent bar for fandoms you've read from, plus a dashed "+N more".

**Imports:** TabBar only (Browse selected, full variant), centred.

**Not placed:**
- Fandoms and Fandom-Works: they are pushed screens, and one board shows one screen.
- The app's dashed "Open AO3 Website" row and its instruction caption: the globe button covers that action, and a second copy would duplicate it.
- "AO3 site sections": the app has none.

**Decisions:**
- Category cards are 100px tall, not 64px, to carry the stats and chips.
- Chips are capped at one row; the app allows two.
- TabBar stays 358 wide and centred instead of stretched.
- The fandom names are real AO3 fandoms, and their counts are placeholders.

## Duo-Cover-Home

I rewrote `Design/redesign/project/Duo-Cover-Home.dc.html` at 466×678. The self-check passed: the support.js line is there, data-props parses and includes accent and $preview, and the open/close counts match. I have not looked at it rendered.

**What the board shows, top to bottom:**
- "Home" large title with "3 new chapters · checked 2 min ago", and a 44px glass Select capsule at top-right.
- **Reading Now** card: cover, "ORIGINAL WORK" kicker, title, author link, Symbols grid at size 24, "84,210 words · 12/20 ch · 3,104 kudos", "Ch 7 · The Salt Road 58%" with bar, then Resume, Read aloud and Work details.
- **New Chapters**: one real WorkRow for Salt & Starlight (+3).
- The stats strip, linking to Insights.
- **Up Next**: four CoverCards at 96 wide, using the original data, clipped at the rail.

The right-edge rail and Search circle are unchanged. The left edge is now 16px and all section headers are sentence case.

**Imports:** Symbols, WorkRow, CoverCard.

**Not placed:** Reading Queues, the Austen Variations shelf and Subscriptions. They would sit below Up Next, past the bottom of the board.

**Decisions for the owner:**
1. I kept the IA order, so the stats strip comes before Up Next. That pushes Up Next down: only its header and the tops of the covers show, so the lined-up progress bars can't be seen on this board. Swapping the two would show most of the covers, but the bars still wouldn't fit, and the stats strip would drop below the board.
2. Up Next works not yet started get an empty progress track (progress 0), so all four bars sit at the same height.
3. I shortened the bottom fade to 34px, because the cover screen has no bottom bar.

## Duo-Book-Reader

I rewrote `Design/redesign/project/Duo-Book-Reader.dc.html` and it passes the self-check: the support.js line is there, data-props parses, and the sc-for and sc-if tags match up.

**What the board shows:** the book-pose reader with its controls showing. Pages 5 and 6 sit either side of the 40px fold (455 | 40 | 456). Nothing is placed in x455–495.
- **Left pane:** a glass Close button (44px) at 16,14, the running head, the page text, and folio "5".
- **Right pane:** a glass capsule at top right with Aa and More, and the bottom pill at left 511 / right 16 / bottom 20. The pill has the title with "Ch 7 of 20", then Contents, Add bookmark, the slider ("Pages 5–6 of 18 · 18 min left") and Read aloud.
- **More menu:** all 8 items from Reader-Menu, 268 wide, opening inside the right pane. It opens from the More button or the new `moreMenu` tweak.
- I removed the old loose progress line.

**Components imported:** none. The board doesn't need Symbols, WorkRow, CoverCard or TabBar.

**Not placed here:** the Read Aloud player state and the Themes & Settings popover. They are separate states, covered by Reader-ReadAloud and Duo-Open-Reader.

**Decisions for the owner:**
- Running heads are now sentence case at 12px weight 500, like Apple Books, instead of letter-spaced capitals.
- Body text is justified, to match Duo-Open-Reader.
- The right folio is left out because the pill covers it.
- Close is 44px rather than 40, to meet the touch-target minimum.
- The menu's dimming layer covers the whole screen, fold included. It's a tap-to-dismiss layer, not content, so I treated it as allowed under the fold rule.
