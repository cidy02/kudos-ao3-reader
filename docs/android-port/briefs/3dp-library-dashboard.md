# 3dp: the Library dashboard beside the iPhone's (Android)

Done 2026-10-14 by Claude, alone. Gate 2,646. Pictures: `shots/3dp/`. Follows 3do.

## Compared and the same

The fandom chips (names, order, the chosen chip's fill), the seven sections in iOS's order
(Reading Now, Saved for Later, Finished, Collections, Downloaded, Reading History,
Favorites), the cards, Recently Deleted's row, and a fandom chosen. The 10-11 note ("the
fandom chips differ in names and order and the chosen chip's colour") no longer holds.

## Fixed

An empty section's line had no glyph; iOS's `SectionEmptyState` puts the section's glyph
before it (a book for Reading Now, a clock for Saved for Later). The dashboard uses the
glyphs Android's section pages already had.

Seen in Sepia and Dark.

## Not differences

- Reading Now's order: Android had Winter Garden first because it had been opened on the
  emulator that day; the order is by last reading on both.
- The filter button: a badge with the count on Android, a filled circle on iOS (each
  platform's chrome).
