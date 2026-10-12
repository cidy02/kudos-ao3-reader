# 3cs: the series card (Android)

Done 2026-10-12 by Claude, alone. Gate 2,622 (three new tests). Pictures: `shots/3cs/`;
the card before is in `shots/3cr/after-series-page-…`.

## Fixed

1. **Every unfinished series was read as finished.** AO3 writes "Series Complete: Yes" or
   "Series Complete: No". Android's rule was "the words contain *complete*", and both do.
   Nothing drew the answer until this pass, so it was never seen; the first test written
   for the card's new badge failed on it. The rule is iOS's `seriesCompletion` now.
2. **A figure could be read as nothing where AO3 labels it.** `statInt` took the first
   element of the figure's class in the stats list. Where a "Words:" `<dt>` carries the
   class too, that is the label, and the count after it was dropped. It never takes a
   `<dt>` now. **Not checked against AO3** (never contacted): the demo page has no
   labels, and the test adds them.
3. **The card did not say a series is complete or restricted.** iOS draws "Complete"
   (green) and "Restricted" (amber) beside the fandom. Android does now; the parser keeps
   the blue members-only lock from the heading's image (a summary that says "restricted"
   is not one). At the large text sizes the pills take a line of their own.
4. **The figures.** iOS: "3 works · 45,678 words · 62 bookmarks" with the date at the far
   end. Android said "45.7K words", no bookmarks, and the date on the same run. Now the
   same as iOS (the date goes under the figures at the large sizes).

The pill is the drafts' "29 days left" pill, moved to `SubjectStateBadge` and shared.

## Not checked

- Against AO3's real pages (never contacted): the lock image's name and the labels'
  classes are as iOS reads them and as the demo page writes them.
- OLED and the other themes; Sepia, Dark and Light were looked at, and 2.0× in Sepia.
- The series card on another author's page (the same component).
