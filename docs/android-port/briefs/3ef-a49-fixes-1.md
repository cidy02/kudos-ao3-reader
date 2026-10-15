# 3ef: Codex's A49 review, first fixes (Android)

Done 2026-10-14 by Claude. Gate 2,661. Each finding below was read against the code before it
was fixed; Codex's text is `audits/A49-result.md` (copied from `~/kudos-agent-codex`).

- **F7 (P1, real, Claude's 3dy):** after a description was typed and saved, picking a
  colour, Keep or a tag wrote the page's old, empty description back over it (the page's
  copy of the queue was never refreshed). The page's queue now takes the typed text.
  `QueueDescriptionTest` types, picks Mint, and checks the description; it fails without
  the fix. Seen on the emulator.
- **F6 (P1, real, 3dy):** a description write still waiting when the page left was
  cancelled with the page. It starts at once and cannot be cancelled now.
- **F8 (P1, real, 3dz):** a note kept as the reader closed was written in the reader's view
  model, whose jobs are cancelled when it is cleared. `updateNote` starts at once and cannot
  be cancelled now. (No test forces the window; the pattern is the standard one.)
- **F12 (P1, real, 3ec):** a tag's works asked AO3 for a fandom of the tag's name too
  (`fandom_names=Fluff`), so an ordinary tag found nothing. Tags use `worksForTag`, which
  sends only the reader's filters, as iOS's `TagWorksView`. `Brief3caScreenTest` row 6
  checks the request now. Seen on the emulator: a tag's page still loads.
- **F5 (P2, real, 3eb):** a link's page was read from the whole address, so
  `/tags/Fluff?next=/works/123` opened work 123 and `/tags/Fluff#top` searched "Fluff#top".
  Only the path is read now. `ReaderLinkHandlerTest.onlyThePathNamesThePage`.
- **F13 (P2, real, 3dv and older):** the sort menus in the works page's and Search's heads
  kept the last sort's direction (Title from Date Updated came Z to A). They take the sort's
  natural direction, as the filter sheet and iOS do, through one helper
  (`AO3SearchFilters.withSort`). `SearchURLTests`.

Still to check: F1 to F4 (Read Aloud), F9 to F11.
