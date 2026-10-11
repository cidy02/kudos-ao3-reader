# 3cn: the AO3 result card is not drawn as iOS draws it (Android)

Found 2026-10-11 by putting pages side by side (3cm's method). **P1 for looks:** this card is
every AO3 list in the app. Search results, a fandom's or a tag's works, an author's works,
bookmarks, history, Marked for Later, a series, a collection's works, Home's section lists.
Pictures: `shots/3cn/`.

## What is different

Android's `ui/components/SensitiveWorkRow.kt` says of itself that it expresses "Apple
`AO3WorkRow` hierarchy: title → author → fandom → summary → status chips → list stats".
That was iOS before its redesign. Briefs 3u, 3n, 3g and 3ab then took the two for the same
card by name. Nobody put them side by side.

| | iOS now (`Features/Search/AO3WorkRow.swift`) | Android |
|---|---|---|
| Fandom | a kicker over the title ("STAR WARS", with a quiet "+2") | a line with a book glyph under the author |
| Rating, category, warnings, status | the 2×2 grid of symbols at the top right, as on a Library card | a row of four chips with words |
| Figures | one line of words: "English · 12,345 words · 3/3 · 80 kudos · 900 hits" | a row of glyphs and numbers |
| Date | at the end of the figures line | not drawn |
| Order | kicker, title, by, summary, figures and date | title, by, fandom, summary, chips, figures |

Android's Library and Home cards already have the kicker and the grid
(`LibrarySubjectWorkCard`), so the pieces exist.

## To build

1. Read `AO3WorkRow.swift` whole first: what it draws for a sparse row (unknown figures are
   left out, L3-B5-20), a bookmark (T-313's note and pills), an own work (the kudos and hits
   strip inside the card), a series, the large-text layout (T-365, T-386), the expanded
   tags, the privacy blur.
2. Redraw `SensitiveWorkRow` to that order with the kicker and the symbols grid Android
   already has. One card, all three overloads; no second card beside it.
3. Keep what is Android's: the ripple, the overflow menu, Material's selection.
4. Every screen that draws it gets a look, in Sepia and Dark and at 2.0×, beside the
   iPhone's. `SensitiveWorkRowPrivacyTest` and `LargeTextScreensTest` name parts of the
   card and will need their words brought along, not loosened.

## Risks

- It is the most-drawn card in the app; a mistake is everywhere at once. Build it, look at
  five screens, then land.
- An author's works on Android draw a figures strip *under* each card and a "⋮" above it;
  iOS puts kudos and hits inside the card. Decide once the card is read.
- The owner's line is that Android keeps Material's chrome and takes iOS's layout, content
  and order. A work's card is content, and the Library's cards already followed. Recorded
  as a decision when it lands; the owner is told in the report.

## Smaller things seen in the same pass (not this brief)

- **Library:** the fandom chips are not the same names or order (iOS "Avatar: The Last
  Airbender · Doctor Who · Frozen", Android "Doctor Who · Doctor Who (2005) · Frozen
  (Disney Movies)"), and the chosen chip is the page's hue on Android, the theme's brown on
  iOS.
- **Home:** the Continue Reading card says "Last opened" where iOS names the chapter
  ("Chapter 2: Nine Minutes"). May be the two demos' reading positions; to check.
- **Account:** Collections and Series have a picture glyph where iOS has a box and a stack;
  Subscriptions carries "6+" on Android only.
- **Search (iOS):** the empty Search page came out white in Sepia, with no tab bar. To shoot
  again before calling it a fault. Its words differ from Android's hint; compare with the
  same saved searches on both.
- A fandom's works and an author's works have still not been paired like for like (the iOS
  routes used were search results and My Works).
- Chevrons at 12dp are half the size of the iPhone's across the app.
