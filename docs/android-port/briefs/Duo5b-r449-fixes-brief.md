# Duo5b — fix R449's findings in T-449 (the reader through a change of size)

**Agent:** Codex. **Worktree:** `~/kudos-agent-ios2`, branch `claude/agent-ios-duo5b` (from the iOS lane's
T-449, `97187d9a`). iOS only.

## Why

T-449 (your Duo5) landed on the iOS working branches. Your own adversarial review R449
(`docs/android-port/briefs/R449-result.md` in this worktree) found three P1s and one P2, all of them ways
to lose or mis-save the reading position. Findings 1 and 2 are regressions T-449 introduced: before it
there was no hold. The reader must never lose the position.

## What to do

Fix all four as R449 proposes, or better if the code shows a better way:
1. Any explicit navigation (Contents, a bookmark, the seek slider's release and its position-list
   fallback, Read Aloud's follow and chapter moves, any other `go(to:)` the app issues) supersedes and
   cancels a pending resize restore **before** it is dispatched; an already-issued restore can't win
   afterwards; page measurement restarts.
2. A resize while an explicit navigation is still loading keeps that navigation's target (or defers the
   hold until it settles); it never snapshots the previous chapter.
3. Hold a content anchor (`navigator.firstVisibleElementLocator()`, which the pinned Readium has) taken
   before reflow and restore that; progression stays only as the fallback when no anchor is available.
   Say in the code which one was used.
4. The restore can't wait forever: a failed or stalled load, or the reader's teardown, ends it; the last
   good locator is kept; nothing is retained after close; check cancellation right after `go` returns,
   before `markFirstPagePresentedIfNeeded`.
5. A controllable navigation seam so tests drive the real restore loop, and regression tests for 1–4,
   each failing with its fix reverted. Keep the existing tests green.

Keep everything T-449 got right (side safe areas, host geometry, the remeasure, ordinary page turns
publishing at once, the guard's bounded last-attempt fallback).

## Rules

- iOS only, in this worktree. Do not commit, push, switch branches, build, sign in, contact
  archiveofourown.org, or edit `TASKS.md`. Nothing builds here; Claude builds, gates and checks on the
  simulator (`-KudosDebugRotate "12 landscape 26 portrait"` turns the window).
- No new UI elements.

## Output

`docs/android-port/briefs/Duo5b-result.md`, written first and kept current: each finding → the change
(file:line), the tests and how each fails when reverted, and simulator steps for Claude (including Read
Aloud playing through a rotation, and a Contents jump made just before one).
