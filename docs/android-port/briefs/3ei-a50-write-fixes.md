# 3ei: Codex's A50 review, the write findings (Android)

Done 2026-10-15 by Claude. Gate 2,666. Each finding read against the code (and iOS) first;
each has a test that fails with its fix taken out (checked).

- **F1 (P1):** OkHttp's own recovery sent a request again by itself (a 408, a dropped pooled
  connection), a POST included, outside the pacing and the session check: one tap could
  write to AO3 twice, which the networking policy forbids. The AO3 client turns it off
  (`retryOnConnectionFailure(false)`); only `AO3RetryPolicy` retries, and only a GET.
  `AO3ClientRetryTest.theAppsClientNeverSendsAPostTwice`: with OkHttp's default the server
  saw two POSTs.
- **F11 (P1):** a comment edit was sent to the form's address (`/comments/9/edit`) and failed.
  It goes to `/comments/9`, as iOS's `commentThreadURL`. `AO3CommentRepositoryTest`.
- **F10 (P1):** a comment, reply, edit or delete prepared in one session could be sent in the
  next (a sign-out or another account between reading its form and sending). Each now posts
  only in the session its form was read in (`postInSession`), as iOS's
  `requireSessionGeneration`. `AO3CommentRepositoryTest`.
- **F8 (P1):** saving Challenge Settings' collection switches resent the collection form as
  the screen first read it, undoing a name, tagline or introduction saved meanwhile on the
  collection's own form. The switches now go onto the form as AO3 serves it at the save.
  `AO3ChallengeSettingsEditTest.aSwitchSavedAfterABasicsSaveKeepsTheNewBasics`.
- **F9 (P1):** words typed while a comment sent were erased when the earlier text was
  accepted. The field is read-only while it sends, as iOS disables its editor.

Not seen on the emulator: these are network and timing faults; the tests drive them.
Still to check from A50: F2 to F7.
