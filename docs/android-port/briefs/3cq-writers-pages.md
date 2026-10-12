# 3cq: the writer's own pages beside the iPhone's (Android)

Done 2026-10-12 by Claude, alone. Gate 2,618. Pictures: `shots/3cq/`. The first of the
Writing screens to be put beside the iPhone's (§7 says none had been).

## Fixed

1. **A writer's figures were printed twice on each of their works.** The card's line said
   "8 comments · 80 kudos · 30 bookmarks · 900 hits" and a strip under the card said them
   again. iOS (`showsPerformance`) puts one strip **inside** the ledger card and leaves
   them off the line. Android does now (`figuresIncludePerformance`, the strip as the
   card's foot). The detailed card has its own row of figures and no strip, as on iOS.
2. **The dashboard did not know it was the reader's own page.** `AO3DashboardScreen` did
   not pass the session on, so its recent works had no strip and it offered nothing a
   writer's page offers. It passes it now.
3. **No way to start a work from the writer's own Works or Dashboard.** iOS has "+" in the
   chrome of both. Android had it only on Drafts. Both pages have it now and it opens the
   new-work form.
4. **The dashboard's fandoms did not say how many works each has.** iOS: "Star Wars (12)".
   Android parsed the count and did not print it.
5. **The dashboard's sections had no way on to their whole lists.** iOS ends each with "See
   all works / series / bookmarks". Android has the three links now (works and bookmarks
   open the account's lists, series the reader's series page).
6. **At twice the text size the strip's four cells cut their labels** ("COMMEN…",
   "BOOKMA…"), seen once the strip was inside the card. Two to a row at the large sizes.

## Compared and left

- **Drafts.** iOS's note has a second sentence, "Recovery copies stay on this device and
  aren't deleted with it." Android's leaves it out on purpose (a comment in
  `WritingDraftsScreen.kt` says to add it only once Android keeps recovery copies there).
  The two demos list different drafts; the page's parts are the same.
- **The writer's Works page has the profile's tabs (Works, Series, Bookmarks, About) and
  the reader's totals under its title on Android; iOS has the reader's name and a
  "Fandom" rail of chips to filter by.** Android's fandom filter is in its Sort and filter
  sheet. Not changed: a design difference to raise with the owner if it matters.
- iOS prints a count in "See all 12 works" when it has one cached; Android's links say
  "See all works".
- Android draws a "⋮" above each of the writer's works for its actions; iOS has them on a
  swipe and a long press.

## Not checked

- No new tests: drawing and wiring. The gate passes; each change was looked at on the
  emulator (Sepia; the dashboard in Dark too; the strip at twice the text size).
- "See all series" and "See all bookmarks" were not tapped ("See all works" was).
- The Series list (`acct:series`) pair was taken and not compared: Android's side opened
  the Works tab instead.
