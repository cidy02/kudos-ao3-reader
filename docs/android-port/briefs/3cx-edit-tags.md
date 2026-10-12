# 3cx: Edit tags beside the iPhone's (Android)

Done 2026-10-12 by Claude, alone. Gate 2,631. Pictures: `shots/3cx/`.

## Compared

**Edit tags**, top to foot, for a posted work on both: the same page. The title and the
line under it ("changes here do not touch the text"), Rating and Archive warnings as lists
with a tick, Categories as switches, the four kinds of tag as chips with "Add", and the
note at the foot, in the same order with the same words.

## Fixed

**The tag chips were twice the iPhone's height and blank past their "×", and "Add" sat on
a row of its own.** The page laid its chips out at the width of the *tag editor's* chip,
which has a 48 dp button beside it (38 dp more than this page's chip needs), and drew each
chip as tall as its touch target. Now a chip is laid out at its own width and drawn at its
own height inside the 48 dp it is touched by, and "Add" follows the last chip when there
is room, as on iOS. The allowance for the chip's mark grows with the reader's text size:
the first try used a fixed one and wrapped words by a letter at 2.0× ("Ad / d"), seen on
the emulator before it was committed.

Seen at 1.0×, 1.3× and 2.0×, Sepia and Dark. A tag removed by its chip, and "Add" opening
the tag editor, both tapped.

## Could not be compared in the demos

- **The chapter form.** "Add chapter" ends at "Couldn't load from AO3. AO3's page format
  wasn't what the app expected." on both: neither demo has that page. To compare it both
  demos need the page for a new chapter.
- **The chapters list.** Android's demo has it (three chapters with their dates); iOS's
  ends at the same sentence.
- **A draft's form on iOS.** Its demo opens the same posted work's form for any work.

## Leads, not acted on

- iOS: the Chapters page draws its failure bare (the sentence at the left, "Try Again"
  centred under it), where "Edit chapter" draws the usual centred state with its mark.
- iOS: the page reached by "Add chapter" is titled "Edit chapter" while it has not loaded.
  Android says the same. Whether it says "Add chapter" once loaded was not seen.
