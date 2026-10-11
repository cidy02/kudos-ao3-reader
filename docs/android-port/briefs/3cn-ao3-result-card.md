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

## Step 1, landed 2026-10-11 (Claude alone; gate 2,608)

**A correction to the above, from reading `AO3WorkRow.swift` whole.** iOS has two forms of
the card, not one. `.standard` is the older order Android's card follows (with the symbols
grid at its top right, which Android's lacks). `.searchLedger` is the redesign's. Which
screen draws which:

| iOS screen | Form |
|---|---|
| Search results; Browse (a fandom's and a tag's works); Marked for Later; Subscriptions; an AO3 collection's works | always the ledger |
| History; Bookmarks; the account's works lists; the author's dashboard | the ledger or the standard card, by the screen's display mode |
| An author's profile works; a series; the Account hub's rows | the standard card |

So the job is not to redraw `SensitiveWorkRow` but to give it the ledger form and use it
where iOS does.

**Built:** `SensitiveWorkRow(ledger = true, dateText = …)` draws `LedgerBody`: the fandom
as a kicker (it searches the fandom AO3 names, and counts the others until the card is
open), the title and byline beside the tray of four symbols Home's cards already use, the
summary, the tags when unfolded (Fandoms, Archive Warnings, Relationships, Characters,
Additional Tags), then `ledgerMetadata`'s line of figures in words with AO3's date at its
end. At the large text sizes the tray goes under the names and the date under the figures.
Under the blur, or while selecting, the kicker and the unfold glyph are part of the row.
**Used by** Search results, a fandom's works and a tag's works.

**Tests:** `LedgerMetadataTest` (iOS's rule for a sparse row: with no word count nothing is
known to be zero), `SensitiveWorkRowLedgerTest` (the kicker, the figures, the tags
unfolding, the fandom search, and a blurred row that only reveals).

**Looked at:** a fandom's works in Sepia and Dark and at twice the text size, beside the
iPhone's; Search results in Sepia. **Not seen on the emulator:** a card unfolded (the
demo's results carry no tags; the test covers it), a tag's works, a blurred or selected
ledger row.

**Left for step 2:** Marked for Later, Subscriptions and an AO3 collection's works (always
the ledger); then History, Bookmarks and the account lists by their display mode; the
bookmark's form (its note and pills) and an own work's kudos and hits inside the card.

**Seen and left, in the shared tray** (Home's cards have the same): no category draws "–"
where iOS draws two figures; an unknown completion draws the dashed ring of a work in
progress where iOS draws "?"; an unknown rating draws a grey shield where iOS leaves the
tile out; in Sepia the rating's yellow is paler than iOS's. The date is AO3's own
("09 Jul 2026") where iOS prints the device's short form.

**A flaky test met on the way:** `WritingWorkActionsScreenTest
.newPreviewIsPushedWithItsOwnChromeAndEditThenSaveUpdatesTheCreatedDraft` timed out once
in the full run (a 15-second wait) and passed twice alone in half a second and in the two
full runs after. It does not draw this card. Nothing was committed on the red run. Its
wait is on real time and wants the same cure `AO3CollectionsViewModelTest` had.

