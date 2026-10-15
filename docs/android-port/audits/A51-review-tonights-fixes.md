# A51: review the fixes Claude landed on 2026-10-15 between 01:00 and 03:10 (Android; one iOS)

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A51-result.md`. **Leave no other file behind.** Do not edit `TASKS.md`.

Read the Android code as it stands on `android/redesign-parity` at `8723abbe` (in
`~/kudos-android-lane`, read-only). Each change has a note in `docs/android-port/briefs/`
(3ei to 3eu). Most fix your own A49, A50 and A37 findings; check that each fix does what its
note says, does not break what was right before, and has no new fault. iOS is
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only). The networking policy is
binding: `docs/AO3_NETWORKING_POLICY.md`.

Every finding quotes the Kotlin (or Swift) with `path:line`, says what happens to a reader, and
how sure you are; without a quote, leave it out. Say plainly when a change looked right.

In this order; stop where you run out of time (say where):

1. **3ei F1**: `AO3Client.defaultOkHttpClient` sets `retryOnConnectionFailure(false)`. What
   else did OkHttp's recovery quietly cover for GETs (a stale pooled connection after the
   phone sleeps, an HTTP/2 refused stream), and does `AO3RetryPolicy` cover each for a GET
   now, within the pacing? Any other client in the app that sends a write?
2. **3eo F4**: `AO3PageCache`'s per-removal records (`removed`, `removedSince`, `evict`). Can a
   read now install a page a write removed while it was in flight (the case the old global
   revision guarded)? Is the 64-entry window and `forgottenThrough` right? Thread safety?
3. **3ei F8**: `AO3WriteRepository.saveChallengeSettings` with `collectionSwitches` now posts
   the four switch changes onto the freshly read collection form. Can that send a field the
   reader never saw or changed, or drop one AO3 needs?
4. **3em / T-408**: Edit multiple works merges its tag changes into the single form read per
   work (`editWorkTags(id, …) { changes.applying(fresh) }`), Android and iOS
   (`AO3WorkActions.bulkEditWorks`). Anything the second read used to supply that is now
   missing (a token, an action URL, a check)?
5. **3ei F10**: comment writes post through `postInSession` with the session captured before
   the form read. And 3ei F11: an edit posts to `/comments/<id>`. Right for every caller
   (reply, edit, delete, chapter comments)?
6. **3ej**: the Authors round under `repeatOnLifecycle(STARTED)`; the narrowed byline account
   rule (only "pseud (account)"); a stale page ending the round. Can the round now never
   finish, or loop, when the reader goes back and forth?
7. **3ek, 3ep, 3eq, 3eu**: the subscribe button held while the page reloads; Clear History's
   `historyCleared`; Assignments' `usable` lists and the due-date retry; a series keeping its
   page on a failed next page; the fandom filter on an author's Works (`selectedFandom`, its
   fence in `loadTab`, the totals line); the queue row chevron.

End with a short list: the findings worth fixing first, one line each.
