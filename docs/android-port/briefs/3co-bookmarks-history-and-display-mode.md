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

