# Brief 3fg: A55's write and request faults

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3fg`, at the lane's HEAD named in the dispatch); don't commit, push, or
switch branches; never sign in and never contact archiveofourown.org; no stub files; no helper
scripts or `.orig` files left behind; **don't edit `TASKS.md`**. No Room schema or
backup-format change. Your sandbox can't run Gradle: Claude builds, tests and commits
afterwards. End with `docs/android-port/briefs/3fg-result.md`: what you changed, file by file,
what each test proves, what you could not check. Binding: `docs/AO3_NETWORKING_POLICY.md`
(a write only on the reader's tap, sent once, never retried; "done" only on AO3's evidence).

Your A55 (`docs/android-port/audits/A55-result.md`). Claude already fixed #1 (the bookmark's
private checkbox) and #3 (the hidden posting pseud) in 3ff; leave those. For each below, first
confirm it against the code at the dispatch commit (Claude confirmed #4); fix it as iOS does
(`/Users/cidy02/kudos-ios-polish/`, read-only), with a test that ports the iOS assertion; if
it turns out not to be real, say why and leave it.

1. **(#4, confirmed) Unmark in Marked for Later is local only**, while the page says it also
   removes the work on AO3 (`account/AccountWorksListScreen.kt`, `onUnmark` only adds to
   `unmarkedIds`). Port iOS's write (`unmarkForLaterPatchesMarkAsReadOnce`,
   `anUnmarkWithoutAO3sNoticeIsNotASuccess`): a fenced GET for the token, one `mark_as_read`
   POST with the method override, the row removed only on AO3's confirmation, a failure shown
   and the row kept. Through `AO3WriteRepository` like the other writes (session fence,
   one-shot, never retried).
2. **(#2) A comment can be posted twice**: single-flight admission (a second tap while the
   first is on its way does nothing) and the unresolved-submission record keyed by account,
   context and body, as iOS's `CommentSubmissionTests` require; reopening after a lost answer
   verifies before allowing another POST.
3. **(#8) Comment drafts**: an unnamed session's draft moved into the verified account; only
   the successful submission's chapter variants cleared.
4. **(#5) Challenge schedule without a timezone**: when AO3 gives no timezone, the schedule
   fields are left out of the save, not re-sent (`missingTimeZoneMakesScheduleReadOnlyAndOmitsItFromSave`).
5. **(#6) A saved search with a language Android doesn't know** keeps its `language_id` in the
   query it sends (`languageDecodesEveryShapeItHasEverBeenWrittenIn`).
6. **(#7) Closing the filter sheet during the first load** restores the requested filters too
   (`aClosedPanelPutsBackTheSearchOnScreenAndNothingInBrowse`).
7. **(#10) URL trust**: AO3 download subdomains accepted; a cleartext `http` AO3 address refused
   where iOS refuses it (`subdomainHostIsAllowedByDefault`, `cleartextHTTPAbsoluteAO3URLIsRejected`).
   Say every caller this changes, and make sure no in-app link that works today stops working.

Leave A55's #9 (web view frames and the demo) and the "lower priority" list for later; note
any of them you find cheap and safe.
