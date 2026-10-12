# 3co: Bookmarks and History are not drawn as iOS draws them, and the account lists have no display mode (Android)

Found 2026-10-11 while building 3cn. **P2.** Pictures: `shots/3co/` (Android beside iOS;
iOS's Bookmarks and History in each of its three display modes).

## What iOS has

`WorkListDisplayMode` (`UIComponents/WorkCardListControls.swift:18`): **Detailed** (the full
card), **Ledger** (the dense row) and **Compact** (covers, two up). A screen draws one of
them, chosen in its More menu under "Layout" (`DisplayModeMenuPicker`), and remembers it:

| Stored as | Default | Screens | Modes offered |
|---|---|---|---|
| `account.displayMode` | Compact | History, Bookmarks, the account's works lists (`AO3AccountWorksList`) | all three; History's Compact is a column of covers |
| `authorProfile.displayMode` | Ledger | an author's profile | Ledger, Detailed |
| `collection.displayMode` | Detailed | a local collection | Ledger, Detailed |

Android has the author's (`AuthorDisplayMode`) and the collection's
(`CollectionDisplayMode`) and Home's section lists. **It has none for the account lists**
(`account/AccountWorksListScreen.kt:248` says so) and always draws the detailed card.

## What is different on the screen

**Bookmarks** (iOS 1q, T-313: "one fixed card shape in every Bookmarks layout"). iOS draws
one card: the fandom kicker with **REC** or **Private** beside it, title, byline, the
symbols tray; the bookmark's **note on a rail inside the card**; its **tags as pills**;
the **date bookmarked** at the foot. Android draws the detailed work card and puts a "Rec"
chip, the note and the tags *under* it, and no date. iOS does not show the work's summary
or its tags on this card: the bookmark's own note and tags take that place.

**History.** iOS groups the list by time (**This week, Earlier, This month…**, each with a
count) and puts the visit line ("Visited 7 times · Update available · Last visited 2 days
ago") **inside** the card, with "Marked for later" under it where it applies. Android has
no groups, puts the visit line under the card and a Delete button beside it. (iOS deletes
by a swipe or the card's menu: check which before moving Android's button.)

## To build, in this order

1. **The bookmark's card.** `SensitiveWorkRow` in its ledger form with: badges beside the
   kicker (`Rec`, `Private`), the note and the pills in place of the summary and the work's
   tags, the bookmark's date as `dateText` (iOS's label is "Bookmarked <date>"), and no
   engagement figures (`includesPerformance: false` in iOS's `bookmarkMetadataRow`). Read
   `AO3BookmarkFootnote` and `AO3WorkRow.bookmarkCard` first.
2. **History's groups and its visit line inside the card**, in the ledger form. Read
   `AO3HistoryWorksBrowser.swift` whole first (the grouping rule, what "Earlier" means,
   where Delete lives). The Library's own Reading History already groups on Android (3bp):
   see whether its rule is the same one.
3. **The Layout choice** in the More menu of History, Bookmarks and the works lists,
   remembered as iOS does. Ledger and Detailed exist once 1 and 2 are done; Compact needs
   the cover grid (`account/AccountScreen.kt:1097` has one). Until it exists, Android's one
   form is the ledger.

## Not to do

- No new card beside `SensitiveWorkRow`: the ledger body takes what a bookmark adds.
- Delete in History writes to AO3. It is single-shot and against fixtures only; moving the
  button must not change when it fires.

## Step 1, landed 2026-10-11 (Claude alone; gate 2,610): the bookmark's card

- **A bookmark of a work not in the Library is one card** (`SensitiveWorkRow(ledger = true,
  bookmark = LedgerBookmark(…))`): "Rec" and "Private" beside the kicker, the note on its
  rail and the tags as pills where the work's summary and tags would be, then language,
  words and chapters with the day it was bookmarked ("Bookmarked 07 Jul 2026" to a screen
  reader). No kudos or hits: they are the work's, not the bookmark's
  (`ledgerMetadata(includesPerformance = false)`).
- **A bookmark of a saved work** draws the work's own row and the same pieces under it,
  now with the date, as iOS does (`showsStatus`).
- **A fault closed on the way (privacy, A38's kind):** the note and tags of a bookmarked
  work were drawn under its row *while the row was blurred*. A note written about a hidden
  mature work was in plain sight. They are not drawn until the row is revealed, as on iOS
  (`AO3BookmarksWorksBrowser.rowStack`: `!isBlurred(entry)`).
- The note's rail is as tall as the note. At a fixed 34dp it stopped beside the second
  line.

**Tests:** `SensitiveWorkRowLedgerTest.aBookmarkIsOneCardWithItsNoteWhereTheSummaryWouldBe`,
`LedgerMetadataTest.aBookmarksCardLeavesTheEngagementFiguresOut`. **No test for the blurred
row's note** (the row that pairs a bookmark with a saved work is private to the screen); it
was seen on the emulator: the demo's first bookmark is a hidden mature work with a note.

**Looked at:** Bookmarks in Sepia and Dark and at twice the text size, beside the iPhone's;
the hidden work before and after revealing.

**Not the same as iOS, and left:** a bookmark's card does not unfold on Android (on iOS
unfolding only drops the "+1" from the kicker); the author's profile draws its bookmarks
with the detailed card and the footnote under it, now with the date.

**Next: step 2, History.**

## Step 2, landed 2026-10-11 (Claude alone; gate 2,614): History

- **Rows are in groups by time** ("This week", "Earlier", "This month", with a count), in
  the page's own order: a heading goes in where AO3's order changes from one time to
  another, and no row is moved (`AO3HistoryVisitBucket`, `historyVisitGroups`, ported
  from iOS with its test cases, `AO3HistoryVisitTest`).
- **The visit line is inside the card**, in the ledger form, with "Marked for later" and
  "Flagged to skip" under it. A saved work's line also says where the reader is in their
  own copy ("Ch. 14 of 24", "Finished", "42%"; `historyLocalProgress`).
- **Delete is inside the card, and only where AO3 gave a delete link** (iOS `canDelete`).
  It used to be offered on every row, and on a row with no link it ended in "AO3 didn't
  show a delete link". When and what it writes is unchanged: the same confirmation, one
  request. **Not on a blurred row**: its confirmation names the work. iOS deletes by a
  swipe; Android keeps a button, which a screen reader can reach.
- **Two small faults found by reading the screen and fixed:** the empty state said "No
  works on this page are inProgress."; and a "Clear your entire history?" dialog that
  nothing could open, whose confirm would only have hidden the rows on this device under
  words that said AO3's history would be cleared, is removed.

**Looked at:** History in Sepia and Dark and at twice the text size beside the iPhone's;
the delete confirmation opened and cancelled; the "In progress" empty message.
**Not done on the emulator:** a delete confirmed (it writes; the fixture path is covered by
the existing tests), a saved work's own-progress words (the demo's history rows are not in
the Library), a blurred history row.

**Next: step 3, the Layout choice** (Detailed, Ledger, Compact) in the More menu of
History, Bookmarks and the works lists. Until then Android's one form there is the ledger
(Bookmarks, History) or the detailed card (the works lists).

## Step 3, landed 2026-10-11 (Claude alone; gate 2,614): the Layout choice, in part

- **History, Bookmarks and the account's works lists have "Layout" in their More menu**,
  with **Detailed** and **Ledger**, drawn the way Home's section pages already draw theirs
  (a second menu with a tick). The choice is kept between launches under iOS's own name
  (`account.displayMode`, in the `account-lists` preferences; not in a backup, as iOS's is
  not). Marked for Later and Subscriptions have one layout, as on iOS.
- A bookmark of a work not in the Library is the one bookmark card in either layout (iOS
  1q). History's visit line and Delete are inside the card in either layout.
- **Android opens on Ledger; iOS opens on Compact.** Compact (covers, two up; in History a
  column of covers under each heading) **is not built**, so it is not offered. The works
  lists therefore changed their opening look from the detailed card to the ledger.

**Looked at:** History's menu, the Layout menu, Detailed beside the iPhone's Detailed, the
choice kept across a restart of the app, and back to Ledger. **Not looked at:** the choice
on Bookmarks and on a works list (the same state and the same rows).

## Left from this brief

1. **Compact** on the three lists, then offer it. Whether Android then opens on it, as iOS
   does, is the owner's to say (told in the 20:28 report; the ledger stands until then).
2. **iOS's detailed card has the tray of four symbols at its top right; Android's has
   not.** Seen in step 3's picture. Small: `HomeStatusTray` in the standard body.
3. **Clear History.** iOS's History menu has it and it writes to AO3
   (`confirmClearReadingsURL`, `clearReadingsURL`). Android has no such write and no menu
   row; the dialog removed in step 2 was a shell of it. A missing feature, with a write: a
   brief of its own, fixtures only.
4. **The other two display modes are not kept between launches, and one opens differently.**
   An author's profile opens on Detailed and forgets (iOS: Ledger, kept as
   `authorProfile.displayMode`); a local collection's is kept only while the app lives (iOS
   keeps `collection.displayMode`).

## Step 4, landed 2026-10-11 (Claude alone; gate 2,614): what was left, items 2 and 4, and a swap

- **The detailed card has the tray of four symbols at its top right**, as iOS's has
  (`HomeStatusTray` in `SensitiveWorkRow`'s standard body). Not spoken (the chips under
  it say the same in words) and not drawn at the large text sizes, where it would take
  the title's room (iOS draws it there too; its tray does not grow with the text).
- **An author's profile opens on the ledger and keeps the choice** (iOS
  `authorProfile.displayMode`). It opened on the detailed card and forgot. Its ledger is
  now the ledger card every AO3 list draws; its own thinner row (no tray, no figures) is
  deleted.
- **A local collection keeps its choice** between launches (iOS `collection.displayMode`,
  one for every collection).
- One helper, `rememberStoredChoice`, keeps all three (and the account lists') in a small
  file, `layout-choices`, under iOS's names. No setting and no backup changes.
- **Found by looking, and fixed: a collection's two layouts were the wrong way round.**
  "Detailed" drew the dense row and "Display · Ledger" the full card, so a collection
  opened on the dense row where iOS opens on the full card. Picture:
  `shots/3co/collection-modes-were-swapped-…png`.

**Looked at:** the author's profile opening on the ledger, Detailed chosen and kept across
a restart, and back; the tray on the detailed card on the author's works, a collection and
Home's Reading Now; a collection opening on the full card, Ledger, and back, with the
choice kept across a restart.

**Not the same as iOS, and left:** a collection's dense row has no reading ring and no tray
(iOS's has both; Home's section pages have a row that does, `LibrarySubjectLedgerRow`).
The three overflow buttons are named three ways ("More actions", "More", "Menu").

**Still left from this brief:** Compact on the account lists; Clear History.

## Step 5, landed 2026-10-11 (Claude alone; gate 2,614): the ledger row

- **A collection's Ledger is the row iOS draws** (`WorkRow.ledger`): the reading ring, the
  fandom kicker, the title, the author and figures, the tray. It is the shared
  `WorkLedgerRow`, which Home's section pages already drew; the collection page's own
  thinner copy (100 lines, no ring, no tray, its own hue rule) is deleted.
- **That shared row's tray is the tray of four symbols** every other card has
  (`HomeStatusTray`). It drew four letters ("T", "F", "!", "✓") in its own little grid;
  that grid and what fed it are deleted (`WorkCardSignal`, `defaultWorkSignals`).
- Net: 30 lines added, 164 removed.

**Looked at:** a collection's Ledger beside the iPhone's, in Dark and at twice the text
size; Home's Reading Now in Ledger. Both layouts were put back as they were found.

**Seen and left:** a finished work whose stored place is 3% draws "3% FINISHED" in its
ring, here and on Home (the same row; iOS not checked).

**Still left from this brief:** Compact on the account lists; Clear History; one name for
the overflow button ("More actions", "More", "Menu").

## Step 6, landed 2026-10-11 (Claude alone; gate 2,614): Compact

- **"Compact" is the third Layout** on History, Bookmarks and the account's works lists:
  covers, as many to a line as fit (iOS `AccountWorksCompactGrid`). History draws them
  under each time heading. A bookmark's card is the same in every layout, so Bookmarks in
  Compact draws its cards (iOS `compactRow` does the same).
- A cover is the redesign's cover card (`SubjectWorkCoverCard`): a saved copy's own, with
  its place in it and its blur; for a work not in the Library, one drawn from AO3's blurb
  (a display-only `SavedWork`, marked `ponytail:` where it is made). A tap opens the work,
  or reveals a blurred one.
- "Expand All" is not offered in Compact (iOS).
- **Android still opens on Ledger.** The owner has been told twice that iOS opens on
  Compact and that the choice is theirs.

**Looked at:** History in Compact beside the iPhone's, in Dark and at twice the text size;
Bookmarks in Compact; a cover tapped (it opened the work); the menu without Expand All; the
layout put back to Ledger.

**Not seen: two covers on one line.** The demo's History has one work under each heading,
and the demo's own-works route opens the author's page, which has no Compact (iOS has none
there either). The arithmetic says two fit (164 + 12 + 164 in 379dp).

**Not the same as iOS, and left:** Android's cover names the author and draws four tiles in
its tray; iOS's History cover has the title and three. In Compact History has no Delete
and no visit line, on both.

**Left from this brief: Clear History** (a write; a brief of its own).

## Step 7, landed 2026-10-11 (Claude alone; gate 2,616): Clear History

**A write to AO3. Never run against AO3; fixtures and the demo only. Owed a second review.**

- **History's More menu has "Clear History"**, as iOS's has, when the page has works. It
  opens iOS's confirmation ("Clear your entire history?" / "This clears your AO3 reading
  history. It doesn't delete the works and can't be undone." / Cancel, Clear History).
- **The write is iOS's `clearReadingHistory`, field for field**
  (`AO3WriteRepository.clearReadingHistory`): one GET of AO3's own confirm page
  (`/users/<name>/readings/confirm_clear`) for the page's token, then one POST to
  `/users/<name>/readings/clear` carrying only that token, with the confirm page as
  referer. It goes through `indexWrite`, as Delete from History does: the session is
  checked before the POST, the POST is never sent twice, and "cleared" is only AO3's own
  evidence (a success flash or a redirect; a page that confirms nothing is a failure).
- **After AO3 confirms, the list is emptied on the device without a second read**, as on
  iOS. A page loaded afterwards shows what AO3 has.
- One write at a time on the screen: the row is disabled while a delete or a clear is out.
- The demo answers both requests (`ao3_demo_readings_confirm_clear.html`, written by hand
  and marked so; the POST is accepted only with the demo page's token).
- `docs/AO3_NETWORKING_POLICY.md` has a "Reading history writes" row. It had none, though
  Delete from History landed on 10-08.

**Tests** (`AO3HistoryDeleteTest`): the confirm page is read once and the POST carries only
its token to the right address with the right referer; a redirect confirms; a maintenance
page, an error flash, a rate limit and a lost connection do not, and nothing is sent twice;
a confirm page with no token sends nothing.

**Looked at** in the demo, in airplane mode: the menu row, the confirmation, Cancel (the
list stays), confirm (the list empties to "No reading history"), the menu afterwards. The
log had no request outside the demo and no crash.

**Not tested:** the screen's own wiring (the dialog, the emptied page) has no unit test; it
was seen on the emulator. A failed clear's message was not seen.

**Brief 3co is closed.** What it leaves for the owner: whether Android opens these lists on
Compact, as iOS does.

