# 3dz: a typed note is kept when its sheet goes away; only Cancel throws it away (both apps)

Done 2026-10-14 by Claude, alone. Gate 2,653 (four new tests). Pictures: `shots/3dz/`.
Follows 3dy, the same kind of fault (typed words lost on leaving).

## The fault

The note editor (a highlight's note, from Contents › Highlights or a highlight on the page)
held the note in a draft written only by Done. On Android, Back is how a sheet is left: the
first Back drops the keyboard, the second closed the sheet and the note was gone. A swipe
down did the same, on the iPhone too. Dismissing also put the old colour back on Android,
which iOS's swipe never did.

## Now

- **Android** (`reader/ReaderNoteEditor.kt`, `ReaderScreen.kt`). The editor writes a changed
  note when it leaves by any way but Cancel, Done or Delete Highlight (`onKeep`). Dismissing
  the sheet keeps the colour too, as iOS's swipe; Cancel still takes both back (audit A12-6).
  `ReaderNoteEditorKeepTest`: closing keeps the note (fails with the keep taken out), Cancel
  throws it away, Done writes it once, an unchanged note is not written. Seen on the
  emulator: a note typed, Back twice, the highlights list shows it.
- **Android's Add note pop-up** (the selection menu's): a tap beside it no longer closes it
  while a note is typed. Cancel and Back still do.
- **iOS** (`ReaderNoteEditor.swift`, T-407): the same; a swipe down keeps a changed note.

## Not changed: owner question 30

On the iPhone, the selection menu's Highlight marks the text at once in the last colour,
and Add Note marks it and opens this editor. Android asks first in a pop-up (colour, and a
note field for Add note). That is the reader's controls (question 12), so it is asked.
