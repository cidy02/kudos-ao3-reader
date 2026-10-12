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
