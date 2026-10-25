# R450 — adversarial review of Duo5b before it lands (the reader's resize restore)

**Agent:** Codex (a fresh job: you did not write this diff in this session). **Worktree:** `~/kudos-agent-ios`
(write only the result file). Read-only.

**What to review:** the uncommitted diff at `~/kudos-tools/out/backups/Duo5b.patch` (also live in
`~/kudos-agent-ios2` on `claude/agent-ios-duo5b`), on top of iOS `97187d9a` (T-449) in
`/Users/cidy02/kudos-ios-polish`. It claims to fix R449's four findings
(`~/kudos-android-lane/docs/android-port/briefs/R449-result.md`); its own notes are
`~/kudos-agent-ios2/docs/android-port/briefs/Duo5b-result.md`.

## Your job: break it

The reader must never lose the reading position or save a wrong one. For each of R449's four findings,
say whether the fix really closes it (trace the code, including the pinned Readium source in the
SwiftPM checkouts), and look for anything the fix newly breaks: an explicit navigation that is now
blocked or delayed, a hold that never releases, the content anchor restoring the wrong element (or none)
in paged vs scrolled mode, Read Aloud's follow, the seek slider, close/reopen, background, a retained
reader, ordinary page turns on a phone that never changes size. Check that the new tests drive the real
restore loop and would fail on the bugs they name.

## One observation from Claude-CLI's simulator run (iPhone 17, paged mode)

Once, 13 s after the window turned back to portrait (DEBUG `-KudosDebugRotate`), the page was blank with a
loading spinner until a tap; a second run without taps showed the text 8 s after the turn. Shots:
`~/kudos-tools/out/duo/r5b-paged.png` (`paged-3-back-plain`), `~/kudos-tools/out/duo/r5b-notap.png`. Say whether
the code can leave the page skeleton or the spinner up after a restore (e.g. a restore that waits for a
location callback only a touch produces).

## Output

`docs/android-port/briefs/R450-result.md`: each finding with file:line (in the patched files), the sequence,
the result, severity (P1 loses or corrupts position; P2 wrong but recoverable; P3 polish), the smallest fix.
End with a verdict: land, land after named fixes, or don't land.

## Rules

Read-only. Do not edit any source, commit, push, switch branches, build, sign in, contact
archiveofourown.org, or edit `TASKS.md`.
