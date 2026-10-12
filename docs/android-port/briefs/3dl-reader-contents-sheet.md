# 3dl: the reader's sheets beside the iPhone's; the Contents sheet (Android)

Done 2026-10-12 by Claude, alone. Gate 2,641 (+2). Pictures: `shots/3dl/`. Follows 3dk and
the owner's note of the same day on the reader's controls being out of step with the rest
of the app.

## Compared

The reader's bottom card, and the four sheets behind the fan menu: Contents, Bookmarks &
Highlights, Find in Work, Display & Themes. Find in Work and Display & Themes have the
same content and order on both. The bottom card too (Android's scrubber is its own).

## Fixed: the Contents sheet was the odd one out

1. **No title and no Done.** Find in Work and Display & Themes have both, and so does
   iOS's Contents. It has them now.
2. **Material's row of tabs**, on a strip of another colour, where iOS has a segmented
   control and so has every other choice of this kind in the Android app (the Display sheet
   beside it included). It is `SubjectSegmentedControl` now.
3. **No percentages.** iOS prints where in the work each chapter starts, from the chapter's
   first position. Android does now (`ReadiumTocAdapter.startPercents`).
4. **The three sheets' Done ticks were three colours**: none on Contents, the ink's on
   Display & Themes, the raw accent on Find in Work. All three are the palette's accent,
   which reads on every theme.

## Fixed in the shared segmented control

At the large text sizes a label got a second line, and a label of one word was broken
across the two ("Bookmar / ks") where it could have been set smaller. A second line is
now only for a label of several words. Every page that uses the control gains.

Seen in the reader's Sepia and Dark, and at 2.0× with Appearance, Series and the Inbox.
Done closed the sheet; the three tabs were tapped.

## Also checked (from 3dk's "not checked")

The reader's bar in the reader's own Dark, OLED and Sepia, the open menu, and 2.0×.

## Left

- The demo book's contents is one row ("Content") on Android and two chapters on iOS: the
  two demo books differ.
- Android's sheets wrap their content; iOS's stop at a half-height.
- The empty state's bookmark is filled on Android and outlined on iOS.

## Lead, iOS

- The position card said "Page 1 of 1", "of 2" and "of 980" on successive openings of the
  same demo work. Not looked into.
