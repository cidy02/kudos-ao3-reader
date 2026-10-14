# 3dq: Browse and Search beside the iPhone's (Android); iOS T-405

Done 2026-10-14 by Claude, alone. Gate 2,647 (+1). Pictures: `shots/3dq/`. Follows 3dp.

## Fixed: Browse never saw the Library (a real fault)

Browse computes each category's figures in a flow started once. The Library was captured as
a plain value on the first frame, when it was still empty, and the flow never saw it change.
So no category ever said how many of its works were downloaded, no fandom chip was marked as
read before, and Jump Back In knew only visits, not reading. It is read as state now
(`rememberUpdatedState`). On the demo: "2 downloaded" on each card, Doctor Who, Sherlock and
Supernatural marked, Jump Back In from 1 to 4.

## Fixed: Browse beside the iPhone's

- The cards' figures carry iOS's glyphs (books, a page, a download arrow) in the card's
  accent, the words in the secondary ink; the glyphs grow with the text.
- A "Recently read" block of chips sat above each card's fandom chips, saying "Doctor Who"
  twice for Doctor Who and Doctor Who (2005). It is iOS's Mac card; the iPhone's panel marks a
  fandom read before with a bar on its chip, and Android's does too. Removed.
- **Counts read "48.3K", "312.4K", "635.8K"** where the iPhone says "48K", "312K", "636K".
  `compactCount` (used across the app) writes Foundation's compact form now: two significant
  digits, never fewer than the whole number ("4.5K", "48K", "1M" for 999,950). Tested.

## Search

The same words and layout. The Android demo has a saved search and the iPhone's has none.
Looking at it found an **iOS** fault, fixed as **T-405**: with no saved searches Search's
"Search Kudos" prompt had no backdrop, so the page was plain white under Sepia. It takes the
theme's backdrop now (seen in four themes).

Seen on the emulator in Sepia, Dark and at 2.0×.
