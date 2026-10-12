# 3cv: each kind of page, back from a kill (Android)

Done 2026-10-12 by Claude, alone. Gate 2,630 (six new tests). Pictures: `shots/3cv/`.
A bug hunt, the second on restarts (3ct was the first). Method: the demo started as the
launcher starts it (no debug route, which a restart applies again), a page reached by
taps, Home, `am kill`, the same start again; then the page before and after, and the log
for a crash. The harness is `~/kudos-tools/emu/kill-lib.sh` (`fresh`, `killret <name>`).

## Found and fixed

1. **The Inbox said "AO3 requires login" to a signed-in reader.** A page that returns with
   the app is composed at once. The Inbox asked AO3 before the saved session had been read
   back; then it reloaded when the restore *started*, because the session's generation is
   advanced at the start, before the session is there; and nothing told it when the
   session arrived. "Try Again" worked. The order was read from temporary log lines on
   the emulator (not committed): `inbox vm init gen=0`, `load failed`, `restoreSession
   called`, `collector got gen=1`, `load failed`, `demo session set`.
   Fix (`869eb8c0`): the restore says when the saved session is back
   (`AO3AuthRepository.awaitSavedSession`: the file's read, not its check against AO3) and
   `KudosApp` draws no page until then, for at most two seconds. The generation and its
   fences are untouched. **On a real session the gap is wider** (a file read, where the
   demo's is instant), so pages that passed in the demo may have failed on a phone; none
   can now be composed inside the gap. Not seen with a real session: never signed in.
2. **A work's page came back as "AO3 Work 11".** A page is opened with the work it was
   given, kept in memory beside a route that carries only the id. After a kill the page
   read AO3 by id: no title, no summary, "Unknown" for the chapters, and the notice
   "Title and summary need a full work page parse." The works the open pages were given
   are saved state now (`RemoteSummaryCacheSaver`, the newest eight).
3. **Search came back empty.** The tab returned with its field and results gone. The page
   of the search on screen is saved state (`KeptSearch`: the page number and the filters
   as saved searches store them) and is read once more on return, as every other page
   reads its own address again. A search never run is never read; leaving the tab and
   coming back reads nothing.

## Came back right

Library, Browse, a queue's page, History, the Dashboard, Subscriptions, Marked for Later,
Bookmarks, AO3 Preferences, own Works, Drafts, AO3 Collections. No crash in any.

## Not checked

- Comments (a comment being written), a fandom's works, a collection's page, a series,
  an author's page, the browser page, Read Aloud playing, a download running, a sheet or a
  dialog open, Settings' pages, the reader with a note or a highlight being made.
- The work's page reached by id alone still says "Title and summary need a full work page
  parse." to the reader when it happens (a page further down the stack than the eight
  kept). It is a builder's sentence.
- A cold start's time with the wait for the session: 1.7 s on the emulator's debug build,
  with no figure from before to set it against.
