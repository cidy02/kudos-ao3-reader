# A31: Codex's assignments screen (brief 3cc), read against iOS before it lands

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A31-result.md`. No helper scripts left behind.

This worktree is at commit `cc8949af`: Codex's work on brief
`docs/android-port/briefs/3cc-challenge-assignments.md`, **not yet reviewed**. See it with
`git show cc8949af --stat` and `git show cc8949af -- android/app/src/main`. Its own account
is `docs/android-port/briefs/3cc-result.md`. iOS, the reference, is at
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only): start from
`Features/Challenges/` (the assignments view) and `Services/AO3ChallengeActions.swift`.

Claude will review the patch line by line; what helps is an **index of where to look**. So:
every row must quote the Kotlin (`path:line`) and the Swift (`path:line`) it compares. A row
without both quotes is worth nothing: leave it out. Never write "absent" or "missing" without
naming the files you searched and the words you searched for.

Check, in this order, and stop where you run out of time (say where):

1. **Requests.** For one opening by a moderator, by a participant and by anyone else: each
   request Android makes, in order, beside each request iOS makes. Then each write (claim a
   pinch hit, report a default, anything else in the patch): the address, every field name and
   value, beside iOS's. Any request Android makes that iOS does not, and the reverse.
2. **Verdicts.** For each write: what Android takes as AO3's confirmation, refusal and "not
   confirmed", beside iOS's code; each message, word for word, beside iOS's.
3. **Words on screen.** Every string in `account/AO3ChallengeAssignmentsScreen.kt` beside
   iOS's string for the same place; list only the ones that differ, with both quotes.
4. **Second taps.** For each write, what stops a second tap sending a second request while
   the first is out; quote the guard on both platforms.
5. **The demo.** Which demo addresses the patch answers locally
   (`network/ao3/DemoNetwork.kt`) and whether any of them was already answered for another
   screen with a different page.

End with a table: number, severity as you see it (P1 a wrong or doubled write; P2 a wrong
read, verdict or word; P3 the rest), the two `path:line`, one line.
