# 3ev: Codex's A51 review of tonight's fixes (Android)

Done 2026-10-15 by Claude. Gate 2,675. Each finding read against the code (and iOS) first.
Codex's text: `audits/A51-result.md`.

- **F1 (P1, real; 3ei was incomplete):** OkHttp also sends a request again when a 503 says
  "Retry-After: 0" (and on a 421 over a shared HTTP/2 connection), whatever
  `retryOnConnectionFailure` says. A write's body is now one-shot, which OkHttp never repeats
  for any follow-up; and a 503 "retry now" becomes 1 second, so OkHttp leaves a GET to
  `AO3RetryPolicy`, which paces it. `AO3ClientRetryTest.aPostAnswered503RetryAfterZeroIsNotSentAgain`
  fails with both taken out (the server saw two POSTs).
- **F2 (P2, real, older):** Delete posted to AO3's Delete link, which is a confirmation page
  (`/comments/delete_comment?id=`), and deleted nothing. It posts to `/comments/<id>` with
  `_method=delete`, as iOS; the link still decides whether Delete is offered.
  `AO3CommentRepositoryTest.aDeleteGoesToTheCommentItselfNotItsConfirmationLink`.
- **F3 (not a fault):** a new comment while browsing a chapter goes to the whole work, as on
  iOS, and Android's composer already says so ("New comments post to the whole work").
- **F5 (P2, real, 3ej):** after a return, refreshed newest-work answers were not shown (the
  remembered snapshot kept its keys). Each resumed round sets its state to "running" first.
- **F7 (P2, real, 3ek):** a cleared History came back if the screen was rebuilt (only the
  screen knew). The list's view model empties it too (`historyCleared`). Seen on the emulator.
- **F8 (P2, real, 3ep):** when Complete failed on Refresh, Open was not read again but its old
  rows could still be reported. Open is not usable while Complete has failed.
- **F9 (P2, real, 3ep):** two page requests, the second failing, left "Loading page N…" on
  screen. A failed page clears its loading note.

**Left:** F4 (a cancelled Authors read can still start inside the shared request coalescer;
bounded, needs the coalescer to know its last waiter left); F6 ("No new work" when some
authors could not be checked; iOS says the same, so a change belongs to both apps).
