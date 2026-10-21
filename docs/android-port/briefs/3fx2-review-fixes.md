# Brief 3fx-2: fix the review's findings on 3fx before it lands

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Append a section "Review fixes" to your result file and write each item there as you finish it: what changed (`path:line`) and the test that fails without the fix. Hard rules as in your first brief (data and networking invariants, iOS is the source of truth at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, nothing lost, ICU regex). The review findings, with quotes and each verifier's reasoning, are in `docs/android-port/audits/review-3fz-3ft-3fx-3ga.json` in the lane (`/Users/cidy02/kudos-android-lane`): read the entries for your patch. This worktree still holds your 3fx changes (not landed).

1. **Row #101 is not fixed where it happens.** A tapped tag reaches Android as a bare name and still
   goes through `buildFandomWorksUrl` without `view_adult=true`; the new URL branch only runs for
   strings starting with http(s). Build the tapped tag's address as iOS does on the path the taps
   actually take (`AO3BrowseRepository.worksForFandom`/`worksForTag`).
2. **Browse's badge now disagrees with Browse's hero.** `activeFilterCount` dropped the search
   subject, which Browse's filters do not carry. Count as iOS counts on each screen (Search and
   Browse), so badge and hero agree on both.
3. **The test oracle was changed to follow the app.** `AO3ChallengeSettingsEditTest.browserSubmission`
   is an independent stand-in for a browser; put it back. If the app's checkbox fields now differ
   from a browser's and from iOS's, fix the app (row #102), not the oracle.
