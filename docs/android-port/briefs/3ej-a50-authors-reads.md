# 3ej: Codex's A50 review, the Authors row's reads (Android)

Done 2026-10-15 by Claude. Gate 2,667. Each finding read against the code first.

The policy allows Favorites › Authors one foreground, cancellable round of newest-work reads
(one page per author). Codex found it right in kind and wrong in three ways:

- **F4 (P1):** the round went on reading author pages after the reader pressed Home or locked
  the phone: its `LaunchedEffect` is not cancelled by the app going to the background. It
  runs under `repeatOnLifecycle(STARTED)` now: it stops in the background and resumes on
  return, skipping answers already kept. Not seen on the emulator.
- **F5 (P1):** an AO3 work saved before accounts were kept had its account guessed from the
  byline's words (3b, `2ddab9c7`). A bare name can be a pseud of somebody else's account,
  so that person's page was read and shown. Only "pseud (account)", where AO3 printed the
  account, is read now; a bare name is not, as iOS never reads an account from words. Such
  an author is simply not asked about (no "No new work" claim). `ReadingAffinitiesTests`.
  This narrows 3b, which DECISIONS had flagged for the owner.
- **F6 (P2):** in an outage the page cache's old copy (up to a day old) was stamped as a fresh
  answer and the round went on. A stale copy now ends the round like the outage it stands
  in for. `AuthorNewestWorkStoreTest.anOldCopyKeptForAnOutageIsNotAnAnswer`.
