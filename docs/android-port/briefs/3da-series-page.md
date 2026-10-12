# 3da: a series's page beside the iPhone's (Android)

Done 2026-10-12 by Claude, alone. Gate 2,632 (one new test). Pictures: `shots/3da/`.
Compared once iOS's demo could open a series (T-400).

## Fixed

1. **The page said nothing of the series but its title.** iOS opens a series with the
   series's own card over its works: who made it, its fandom, what it is, "3 works ·
   45,678 words · 62 bookmarks", Complete and Restricted, the date. Android drew the title
   and "Works · Page 1 of 1", though the page it reads has the creator, the description
   and the figures in its header (`dl.series.meta`). The parser keeps them now (the
   creators' names, the description, whether it is complete, the bookmarks, "Series
   Updated"), by a figure's class or by the label before it, and the page draws the series
   card under its title (`AO3SeriesRow`, without the title the page already has, and
   opening nothing).
2. **A work's card there had no date.** iOS's standard card closes with the day AO3 gives
   the work; Android's ledger card had it and its standard card did not. It does now,
   wherever the standard AO3 card is drawn.

Seen in Sepia beside the iPhone's, in Dark, and at 2.0×.

## The same, or left

- iOS titles the page "Series" in its bar and puts the name in the card. Android keeps the
  name as the page's title, as its other pages do, and leaves it out of the card.
- iOS's card there comes from the list the series was opened from, so in the demo it also
  has the bookmarks, "Restricted" and the date. Android's comes from the series's own
  page, which the demo's page gives no bookmarks or date; AO3's own page has both
  ("Bookmarks:", "Series Updated:"), read by their labels. **Not checked against AO3**
  (never contacted). Whether a series is restricted is not on its own page as read here.
- Android prints only the figures AO3 gave ("— · 21,678 · 1/1"); iOS prints zeros for
  comments, kudos, bookmarks and hits. Known, recorded in 3cp.

## Not checked

- A series's edit form on iOS (its "…" on the series page has no "Edit series" for the
  demo's series).
- The standard card's date on the other pages that draw it (an author's works and a
  collection in Detailed).
