# R451 — adversarial review of Duo5c before it lands (removing the reader's resize hold)

**Agent:** Codex (fresh job). **Worktree:** `~/kudos-agent-ios2` (write only the result file). Read-only.

Duo5c (`~/kudos-tools/out/backups/Duo5c.patch`, live in this worktree on `claude/agent-ios-duo5c`, base iOS
`64979c71`) removes T-449's locator hold and restore and keeps the side safe areas, the host page box and the
page-count remeasure (brief `docs/android-port/briefs/Duo5c-remove-hold-brief.md`, result
`docs/android-port/briefs/Duo5c-result.md`; why: R449 and R450 in the same folder).

Break it: is the reading position path now exactly what it was before T-449 (`git show 97187d9a^:...`), with no
remnant of the hold (a gate, a flag, a task) that can still swallow a location update, delay persistence, or
issue a `go(to:)`? Does anything kept (the remeasure task, the unready-bar rearm, the geometry debounce) interact
with navigation, Read Aloud, the seek slider, close/reopen or background in a way the pre-T-449 code didn't? Do
ordinary page turns publish the bar at once? Do the tests cover what was removed?

Output `docs/android-port/briefs/R451-result.md`: findings with file:line, sequence, result, severity (P1 loses or
corrupts position; P2 wrong but recoverable; P3), smallest fix; a verdict (land / land after fixes / don't).
Rules: read-only; no edits, commits, pushes, branch switches, builds, sign-in, AO3 traffic, or TASKS.md edits.
