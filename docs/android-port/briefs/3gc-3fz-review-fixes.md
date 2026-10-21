# Brief 3gc: fix the review's findings on 3fz (landed as `609e4c1b`)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Append a section "Review fixes" to your result file and write each item there as you finish it: what changed (`path:line`) and the test that fails without the fix. Hard rules as in your first brief (data and networking invariants, iOS is the source of truth at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, nothing lost, ICU regex). The review findings, with quotes and each verifier's reasoning, are in `docs/android-port/audits/review-3fz-3ft-3fx-3ga.json` in the lane (`/Users/cidy02/kudos-android-lane`): read the entries for your patch. This worktree is at the lane HEAD, which includes 3fz.

1. **Read Aloud on the main thread.** `ReaderSpeechController`'s speak loop moved from
   `Dispatchers.Default` to the Main scope, so `AutomaticTTSService.speak` (pack checks,
   `kokoro.ensureReady()`, which can load the model after a fresh download) runs on the UI
   thread. Put that work off Main again.
2. **A paragraph lost on Next/Previous during a pull.** `skipForward`/`skipBackward` cancel the
   job while `ReaderContentText`'s source has already taken the text inside `withContext(IO)`;
   the text is dropped and the queue goes out of step. Never lose pulled text: let a pull finish
   (as `beginSeeking` does) or keep what it took.
3. **Converter records across the apps.** Rule (decided 2026-10-20): each app judges only its
   own records. Android: stale iff `converterPlatform == "android"` and version < Android's
   current; a record with no platform (iOS's, or older) or another platform is **not** stale on
   Android (My copy then asks before rebuilding; no reader pill). Keep writing
   `converterPlatform = "android"` (an additive key iOS ignores; Claude changes iOS to apply the
   same rule, T-421). Tests both ways.
4. **Hold-seek as iOS.** iOS steps through the book's positions, moves the page there and
   re-anchors speech at the new locator on release (`Features/ReaderReadium/ReaderSpeechSkip.swift`,
   its caller in `ReadiumReaderView.swift`). Android only moves an index in its queue. Make the
   page follow and speech restart from the new locator on release.
