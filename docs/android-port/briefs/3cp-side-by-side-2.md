# 3cp: more pages beside the iPhone's (Android)

Done 2026-10-11 by Claude, alone. Gate 2,618. Three commits. Pictures: `shots/3cp/`. The method is 3cm's.

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

5. **A saved work's detailed card lists every fandom and unfolds only for a long summary
   or for tags** (iOS `WorkRow`; third commit). Android used the AO3 card's rules for both:
   it named one fandom and "+1 other", and offered the unfold glyph to a work with nothing
   under it but "No Archive Warnings Apply". The unfolded card no longer repeats the
   warnings as a group, as on iOS. An AO3 work's card keeps its own rules (`savedWork`).

**Compared and the same:** what a tap on a saved work's card opens (the reader, on both:
iOS `WorkCardTap.destination`); the rest of a saved work's page (kicker, title, the four
figures, the Read card, the tag groups, the language line, kudos and hits, My copy).

## Seen, and left

- iOS's detailed card prints comments and bookmarks when they are zero ("0"); Android
  leaves them out for these demo works. May be the two demos' data.
- Where a card does unfold, Android's glyph is before the title and iOS's control is at
  the card's foot. Android's demo gives its works a tag ("Slow Burn") that iOS's demo does
  not, so the glyph shows on Android's demo cards and on none of iOS's.
- **The Finished section, compared on a fresh demo:** the same but for the demo's own
  data (iOS's "Tea in the Jasmine Dragon" is a work in progress and sorts first; Android's
  is complete and sorts second) and the zeros above.
- **The tab bar marks Home on a Library page opened by a debug route.** Through the
  Library tab it marks Library; nothing to fix.
- The reader's own menu still answers "Mark as Finished" with "Finished"
  (`ReaderFanMenuUiTest` pins the page's button, now brought along; the reader's menu was
  not looked at).

## A note on the emulator's demo

It had drifted through the day's testing (Sodium Lights finished, "Tea in the Jasmine
Dragon" queued, an extra queue and collection). **It was seeded afresh at 22:06**
(`adb -s emulator-5556 shell pm clear io.github.cidy02.kudos`, then any `open_route`): the
layout choices, the privacy setting and the reveal state are back to their defaults.
