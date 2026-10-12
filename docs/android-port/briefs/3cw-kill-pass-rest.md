# 3cw: the rest of the kill pass, and a work reached by its id (Android)

Done 2026-10-12 by Claude, alone. Gate 2,631 (one new test). Pictures: `shots/3cw/`.
Follows 3cv, with the same harness (`~/kudos-tools/emu/kill-lib.sh`).

## Came back right (no change needed)

A fandom's works. A work's comments. **A comment being written**: typed, Home, `am kill`,
back to the comments, and "Write a comment" opens with the text there (the draft store,
which both apps have). A series. A Library section. Favorites on its Authors scope.
Settings › Appearance. The in-app browser page. With a menu or a sheet open (the account's
actions, "More on AO3", Search's filters) the page comes back with it closed. No crash in
any.

## Changed

**A work reached by its id alone** (a page further down the stack than the eight works
kept through a kill, 3cv) read AO3's page for tags and figures only. Its title was "AO3
Work 11", it had no author or summary, its rating was dropped though the page had been
read for it, and the reader was told "Loaded tags and stats from AO3. Title and summary
need a full work page parse." The parser reads the work's own heading, byline and summary
now (not a chapter's summary), the rating is passed on, and the sentence is gone.

## Not checked

- The heading, byline and summary on a real AO3 page (never contacted): the markup is
  AO3's work page as the rest of this parser already reads it (`h3.byline`), and the
  demo's work page has no heading, so on the emulator the title is still "AO3 Work N".
- An author's page other than the reader's own (the tap missed; it is the same screen as
  own Works, which came back right). Read Aloud playing and a download running through a
  kill. A note or highlight being made in the reader (the reader's page cannot be read by
  the UI dump).
