# 3dy: a queue's details page and the New Queue sheet beside the iPhone's (Android)

Done 2026-10-14 by Claude, alone. Gate 2,649 (one new test). Pictures: `shots/3dy/`. Follows 3dx.

## Fixed: a description typed and then left was lost (a real fault)

On a queue's details page the description was written only when the field lost focus.
Leaving the page is not that, so typing a description and going back (keyboard down, then
back) kept nothing: seen on the emulator. It is written as it is typed now, as iOS does.
The writes take turns (a lock) and each takes the latest text when it runs, so the last one
wins whatever order they finish in. `QueueDescriptionTest` types into the field without
leaving it and waits for the saved queue to hold the text; it fails with the write taken out.

## Made like iOS

- **Details page.** The description is the note itself in serif with "Add a description"
  as its placeholder, not a boxed field. Tags show the × that says a tap removes them
  ("Remove Long fic" to TalkBack); "+ Tag" is "Add tag" with a plus. The footnote under
  Details had no side margin.
- **New Queue sheet.** Tags are picked from one row: every tag, any typed here, and a
  dashed "+ New tag" chip that asks for a name (a name matching one already there, ignoring
  case, picks that one, iOS's rule). It was a text field and button, then a second row
  repeating the chosen tags. "Copy 1 works" says "Copy 1 work".
- **The sheet's Description field is gone**: iOS's sheet has none, and the details page
  edits it. Edit Queue keeps the queue's description as it was.

## Same

The details page's order and facts; the sheet's Name, Colour, Tags, Offline, Start from.

## Left

Android's sheet keeps text Cancel/Create (its own chrome); iOS's colour swatches are paler
when none is picked.
