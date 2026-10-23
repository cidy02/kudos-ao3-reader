# Brief I17 (iOS): Comments' kept page after any failed read (§5c item 6c, from A74)

**Write code in `/Users/cidy02/kudos-agent-ios` only, on the new branch `claude/agent-ios-i17` from `bd533264`
(I15 and I16 are recorded on their own branches and land as T-440/T-441).** Rules:
- Do not commit, push, sign in, contact archiveofourown.org, boot a simulator, or run xcodebuild (Claude
  builds and tests).
- Write `docs/android-port/briefs/I17-result.md` first: per item `path:line` and what changed; per test,
  what it does with its change reverted.

The problem: when a comments read fails and an earlier copy of the page is shown instead, iOS's Comments
says so ("You're offline… from {time}") only when the failure is `.notConnectedToInternet`
(`Features/Comments/CommentsView.swift:718`, `isFromCache && isOffline`). After a timeout or a lost host, the
old page shows with no notice at all. Android says the copy's age after any network failure.

1. Tell a failure fallback (a read failed and the kept copy is shown) from a fresh in-session cache hit.
   Today both set `isFromCache`.
2. Show a notice for every failure fallback.
   - Keep the offline words for `.notConnectedToInternet`.
   - Give the other failures their own words, with the copy's time. Read Android's strings for the same
     case and match them where they fit.
3. A fresh in-session cache hit shows no notice, as now.

Tests (Swift Testing, as the suite's other files) for each case: offline, timeout, lost host, a fresh hit.
Each should fail with its change reverted. Say which suites to run.
