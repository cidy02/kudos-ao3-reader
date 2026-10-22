# A75: re-check A29's rules against today's Android code

**Read only: change no code, commit nothing, sign in nowhere, contact no website.** Write
`docs/android-port/audits/A75-result.md` FIRST and fill it in as you go.

`docs/android-port/audits/A29-result.md` (written 2026-10-09 by another model) lists iOS test rules
that A25 found no Android test for, and says for each whether Android's *code* implements the
rule: 9 implemented, 2 differ, 113 absent, 71 not read. Spot checks show it is unreliable: for
example it calls the account stats parsing absent, but Android has read `/users/<name>/stats`
since 2026-10-11 (`docs/android-port/DECISIONS.md`, "The writer's own Works page shows …"), and
a great deal has landed since 10-09.

For **every** rule in A29's tables (including the 71 "not read"), decide against this worktree's
code (HEAD `cd04b55a`) and the iOS test that states the rule
(`/Users/cidy02/kudos-ios-polish/KudosTests/`, the suite and test name in A29's first column) plus
the iOS code it tests (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`):

- **implemented**: Android's code does what the iOS test requires. Give the Android `path:line`.
  Say also whether an Android test covers it (test file and name) or not.
- **differs**: Android does something else. Quote both behaviours with `path:line` on each side
  and say what a user or a backup would see differently.
- **absent**: Android has no code for it. Say what the feature is and whether Android has the
  feature at all (an absent rule in a missing feature is one finding, not one per rule).
- **not applicable**: an iOS-only platform matter, or a decision in `DECISIONS.md` (quote it).

Open the code; do not decide from names. A verdict without a `path:line` on both sides does not
count. Group by iOS suite. End with: the list of **differs** and **absent** items ranked by what a
reader would notice (data loss or wrong data first, then wrong text, then missing tests only),
and the counts.
