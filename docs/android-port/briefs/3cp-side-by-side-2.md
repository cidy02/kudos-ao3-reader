# 3cp: more pages beside the iPhone's (Android)

Done 2026-10-11 by Claude, alone. Gate 2,618. Two commits. Pictures: `shots/3cp/`. The method is 3cm's.

## Fixed

1. **A mistake of 3co's step 4, caught here: the tray of four symbols was drawn on a saved
   work's detailed card.** iOS draws it on an AO3 work's detailed card
   (`AO3WorkRow.standardCard`) and **not** on a saved work's (`WorkRow`): its Library, Home
   and collection cards have none. Step 4 read the AO3 card's code and gave the tray to
   every detailed card. It is drawn for AO3 works only now (`showsStatusTray`). The lesson
   is the one this pass keeps teaching: put the page beside the iPhone's before keeping a
   change, not only its code.
2. **The rating on a detailed card's chip is AO3's letter** ("G", "T", "M", "E", "NR"), as
   iOS's is (`WorkStat.ratingLetter`): spelled out ("General"), the four chips took two
   lines on every card. A screen reader is still given the full rating; cover cards keep
   the name. `WorkStatusChipsTest`.

3. **A work's page, the button for a finished work said "Finished".** It is a button that
   takes the work back out of Finished, so iOS names the action: "Mark as Still Reading"
   (`WorkActionLabels.finished`). Android's does now (second commit).
4. **A work's page, "My copy" left Saved for Later out of its count.** iOS says "Downloaded
   · 1 queue · 1 collection" for a work in Saved for Later and a collection; Android said
   "Downloaded · 1 collection". Saved for Later is a queue and counts as one now
   (`myCopySummary`, iOS's rule, `MyCopySummaryTest`).

**Compared and the same:** what a tap on a saved work's card opens (the reader, on both:
iOS `WorkCardTap.destination`); the rest of a saved work's page (kicker, title, the four
figures, the Read card, the tag groups, the language line, kudos and hits, My copy).

## Seen, and left

- iOS's detailed card prints comments and bookmarks when they are zero ("0"); Android
  leaves them out for these demo works. May be the two demos' data.
- Android's detailed card has an unfold glyph beside the title where iOS's has none for
  the same work (a work with only "No Archive Warnings Apply" counts as having more to
  show on Android).
- **Not compared yet from this batch:** the Finished section (the pictures are taken).
- The reader's own menu still answers "Mark as Finished" with "Finished"
  (`ReaderFanMenuUiTest` pins the page's button, now brought along; the reader's menu was
  not looked at).

## A note on the emulator's demo

Sodium Lights is now under Finished on the emulator: it was opened in the reader earlier
today and its short demo book ends on the first page. Home's "Continue reading" and
Reading Now therefore differ from the simulator's until the demo is seeded again.
