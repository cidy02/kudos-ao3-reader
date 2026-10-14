# 3do: a saved work's page and My copy beside the iPhone's (Android)

Done 2026-10-14 by Claude, alone. Gate 2,646 (+2). Pictures: `shots/3do/`. Follows 3dn.

Winter Garden (imported file, in a queue) on both apps. The page is the same top to foot
(Android's demo adds an Additional tags row the iPhone's demo has not).

## Fixed

1. **Any author name was a link.** iOS opens an author only when AO3 linked the name to an
   account ("fallback display text is never turned into a guessed profile URL", grey
   otherwise). Android linked every name of the byline, so a file from elsewhere opened the AO3
   page of whoever has that name. A name with no account is plain text now (`hasAccount`;
   tested). The demo's works carry an account, so they stay links there.
2. **My copy › Storage had no Preservation row.** iOS shows one for a work kept for later
   ("Preserved offline", "Needs restore", …). Android does now (`preservationStatusLabel`).
3. **My copy › Origin said "Imported EPUB file."** iOS: "This imported work doesn't include
   the website where it was first posted.", with a document glyph, and "… from its source"
   where Android said "from an imported file". iOS's words now.
4. **Demo:** queued copies were never recorded as preserved (the demo adds them to queues
   directly), so the new row said "Not preserved" under the sheet's own "Kept" figure while
   Queue Storage listed the same work. The demo records them now; a status already set is
   left alone.

## Closed, not a difference

- Home's hero says "Last opened" where the iPhone named the chapter: the same rule on both
  (the saved position's title, else "Last opened"); the iPhone had a position only because
  the work had been read in the simulator.
- The parity table's "no display mode on History, Bookmarks…" was stale: 3co landed it.

## Left

- My copy's rows are 48 dp tall on Android (touch targets) and about 22 pt on iOS.
- Dates read "Sep 17, 2026, 10:06 PM" (Android) and "Sep 8, 2026 at 7:46 PM" (iOS): each
  platform's own format.
- iOS's Downloaded row has a chevron; Android's has none.
- The progress bar is the theme's accent on Android and the work's colour on iOS.
