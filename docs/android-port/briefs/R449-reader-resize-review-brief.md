# R449 — adversarial review of T-449 (the reader through a change of size)

**Agent:** Codex. **Worktree:** `~/kudos-agent-ios` (write only the result file). Read-only review of the
iOS commit `97187d9a` in `/Users/cidy02/kudos-ios-polish` (`git show 97187d9a`). You wrote this code
(Duo5); review it as if someone else had, looking for what's wrong rather than defending it.

## The one thing that matters most

A reader must **never lose the reading position** or save a wrong one. Try to break that.

## Look for (file:line, a concrete sequence of events, the result)

1. Any path where a held or restored locator is written to persistence wrongly, or the real position is
   overwritten: rapid size changes (fold/unfold/fold within the 220 ms quiet period), a size change while
   a chapter is loading, during a chapter change, during the seek slider's scrub, while the Contents sheet
   or a bookmark jump navigates, while Read Aloud is playing or moving by chapter, on close/reopen, on
   background/foreground.
2. A hold that never releases (the page bar stuck on "Page …", or same-href callbacks swallowed forever),
   or a remeasure task that leaks or outlives the reader.
3. Places where `pageBoxGeometry`'s side insets and the existing vertical "no-jump" freeze disagree, so
   the text jumps when the chrome toggles.
4. Anything that changed behaviour on an ordinary iPhone in portrait that never changes size.
5. The DEBUG `-KudosDebugRotate` hook: anything that could reach a release build.

## Output

`docs/android-port/briefs/R449-result.md`, written first and kept current: each finding with file:line,
the sequence, the result, a severity (P1 loses or corrupts position; P2 wrong but recoverable; P3 polish)
and the smallest fix. Say plainly if you find nothing at P1/P2.

## Rules

Read-only. Do not edit any source, commit, push, switch branches, build, sign in, contact
archiveofourown.org, or edit `TASKS.md`.
