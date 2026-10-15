# 3eh: Codex's A49 review, F9 to F11 (Android), and the review's tally

Done 2026-10-14 by Claude. Gate 2,662.

- **F9 (P2, real but rare):** two accounts printed alike on one work (both "Alex") always
  opened the first. Such a name is not a link now (`AO3AuthorIdentities.byline`), rather
  than possibly the wrong account. `AuthorIdentityRecordingTest`.
- **F10 (not changed):** a Home section's minimum word count reads compact ("1M+ words" for
  999,950). iOS's `LibraryFilters` writes it the same way on purpose (spec 1ay, "50k+
  words"), so Android matches; the edge case is iOS's too.
- **F11 (P2, real):** each file's start percentage for Contents was worked out on the main
  thread from every position of the work. It runs off the main thread now and keeps only
  each file's first position. Seen on the emulator: Contents still shows its percentages.

## A49's tally

Thirteen findings: twelve real and fixed (3ef: F5 to F8, F12, F13; 3eg: F1 to F4; 3eh: F9,
F11), one matching iOS by design (F10). Left from them: a way to replace a voice pack that
will not open (F4), and no test forces the speech or teardown timings (F2, F6, F8).
