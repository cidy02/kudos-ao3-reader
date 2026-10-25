# T-451 — paged reading returns to the chapter's start after a rotation round trip

**Agent:** Codex. **Worktree:** `~/kudos-agent-ios2`, branch `claude/agent-ios-t451` (from iOS `b4752bd5`, T-450).
iOS only.

## The fault

On the iPhone 17 simulator (DEBUG `-KudosDebugRotate "60 landscape 90 portrait"`), paged mode, opened mid-chapter
(Night Market, chapter 2, page 2–3): after the window turns to landscape and back, the page shows the chapter's
first page. Scrolled mode keeps the exact passage. Shots: `~/kudos-tools/out/duo/r5c-paged2.png` (p0 before, p3/p4
after). T-450 removed the app's resize hold, so the position through a resize is Readium's (pinned 3.9.0) plus
whatever the app does on a size change: the page box refresh, `refreshContentInsets`/`navigatorContentInset`, the
remeasure (`ReadiumBook.swift`'s `updatePageBoxGeometry` and the measurement code).

## What to do

1. Find the cause in the code (yours and the pinned Readium source in the SwiftPM checkouts), with file:line:
   likely the content-inset refresh after a size change makes Readium reload its spreads, and the reload lands on
   the resource's start (e.g. a pending location without progression), but check.
2. Say whether the pre-T-449 app (`de1a36ae`) had the same behaviour.
3. Fix the cause with the smallest change and **no locator hold and no callback gating** (R449/R450 are in
   `docs/android-port/briefs/` for why). If the only fix is a one-shot `go(to:)`, it must be superseded by any
   user navigation, never swallow callbacks, and wait for Readium's own presentation (R450 finding 4).
4. A test that fails without the fix, if the code allows; otherwise exact simulator steps.

## Rules

iOS only, in this worktree. No commits, pushes, branch switches, builds, sign-in, AO3 traffic, or TASKS.md edits.
Output `docs/android-port/briefs/T451-result.md`, written first and kept current.
