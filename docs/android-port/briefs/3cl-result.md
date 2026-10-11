# 3cl result: a category's fandom list is drawn as iOS draws it (Android)

Landed 2026-10-11 by Claude, alone (Codex and Gemini were out). Gate 2,601.
Pictures: `shots/3cl/` (before, beside iOS; after, in Sepia, ungrouped and Dark beside iOS;
after, at the ordinary size and at twice the text size).

## What changed

1. **A fandom's qualifier and other names are drawn.** A single fandom's row now has iOS's
   three tiers: the title (with its download badge beside it), the qualifier under it
   ("(TV)", "(2005)"), then the other names it is tagged under. Only the title was drawn, so
   "Sherlock (TV)" was "Sherlock".
2. **No titled bar.** The page uses the shell's floating chrome (`ProvidePushedShellChrome`,
   `hasSubjectHeader`): a back button and the filter button over the wash. The header block
   is the title, as on iOS and on Android's other redesigned pages.
3. **Rows are cards**: one for a single fandom, one for a family with its tags inside.
4. **"Group variants" is a chip** in the rail after "A–Z" and "Most works", on or off (a
   switch to TalkBack), not a switch on a row of its own.
5. **The search field is the app's glass field** with a magnifier, under the rail. It stays
   at the top (Material's place for it; iOS floats it at the bottom). "Open on AO3" is gone
   from the list: iOS has it only on the page shown when the list cannot be read, and
   Android's error page keeps it.
6. A works count is followed by iOS's document glyph, and is set in the app's own face with
   figures of one width (`tnum`), not a typewriter face. "All n tags" and the download count
   keep the monospaced face, as on iOS. A single fandom's row has no chevron (its card is
   the affordance; iOS has none there).

## Not done, and not checked

- No test: this is drawing. The gate passes; the screen was looked at on the emulator.
- The A–Z order with its letter headings and index strip was not looked at after the change
  (the rows are the same composables).
- At twice the text size the names here are short and fit beside their figures; a very long
  fandom name wraps in its column. iOS stacks the figures under the name at its
  accessibility sizes (T-398); Android does not, and with its 2.0× ceiling did not need to
  for anything the demo shows.
- **A slip:** the last two touches were built with the emulator still running, against the
  rule of one build or emulator at a time. The gate was run again afterwards with the
  emulator off.
