# A34: Codex's in-memory page cache and its "Showing cached AO3 data" line (brief 3ce), read against iOS before it lands

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A34-result.md`. No helper scripts left behind.

This worktree is at commit `40e8fdb4`: Codex's work on the brief in
`docs/android-port/briefs/` whose name starts with `3ce-`, **not yet reviewed**. See it with
`git show 40e8fdb4 --stat` and `git show 40e8fdb4 -- android/app/src/main`. Its own account is
`docs/android-port/briefs/3ce-result.md`. iOS, the reference, is at
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only): the brief's "Read first"
list names the Swift files.

Claude will review the patch line by line; what helps is an **index of where to look**. So:
every row must quote the Kotlin (`path:line`) and the Swift (`path:line`) it compares. A row
without both quotes is worth nothing: leave it out. Never write "absent" or "missing" without
naming the files you searched and the words you searched for.

Check, in this order, and stop where you run out of time (say where):

1. **Requests.** For one opening: each request Android makes, in order, beside each request
   iOS makes, for each kind of viewer the code distinguishes. Then each write in the patch: the
   address, every field name and value, beside iOS's. Any request Android makes that iOS does
   not, and the reverse.
2. **Verdicts and failures.** What Android takes as success, refusal and "not confirmed" for
   each write, and which failures of a read it treats how, beside iOS's code; each message,
   word for word, beside iOS's.
3. **Words on screen.** Every string in the new screen files beside iOS's string for the same
   place; list only the ones that differ, with both quotes.
4. **Second taps and stale answers.** What stops a second tap sending a second request, and
   what stops an answer that arrives after a sign-out or a session change being shown; quote
   the guard on both platforms.
5. **The cache.** Its key, its two lifetimes and its size beside iOS's `AO3AuthorPageCache`; every read that goes through it on each platform; every removal after a write; and exactly which failures show the old copy on each platform (quote both `catch`es).

End with a table: number, severity as you see it (P1 a wrong or doubled write, or one
reader shown another's data; P2 a wrong read, verdict or word; P3 the rest), the two
`path:line`, one line.
