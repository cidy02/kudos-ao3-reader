# R453 — adversarial review of T-451's paged restore before it lands

**Agent:** Codex (fresh job). **Worktree:** `~/kudos-agent-ios2` (write only the result file). Read-only.

The change: `~/kudos-tools/out/backups/T451final.patch` (live here on `claude/agent-ios-t451`, base iOS `b4752bd5`). The
decision it implements is in `~/kudos-android-lane/docs/android-port/DECISIONS.md` (2026-10-24, "Paged reading: one
restore after a settled size change"): Readium's FXL `spread` `.never` for reflowable books, plus ONE `go(to:)` of
the burst's first accepted locator after the 220 ms settle, paged only, cancelled by any explicit navigation, a
chapter change, dismiss or close; no callback gating, no held persistence, no retries. R449/R450 (same folder)
show why the earlier hold failed.

Since round 3, Claude-CLI added: a touch observer on the reader's container (`TouchBeganObserver` in `ReadiumNavigatorContainer.swift`; any touch cancels a pending restore, so native swipes and link taps win) and the test `pagedResizeRestoresTheFirstLocatorOnceUnlessTheReaderNavigates` (fails with the restore call removed). On the iPhone simulator, two paged round trips went page 4/4 → mid-chapter → 3/4, no chapter-start reset.

Break it: can the one restore ever override a position the reader chose (native swipe or link during the
window, Read Aloud follow, the slider, Contents/bookmark, a chapter turn by edge tap) or save a wrong one? Does it
fire when it shouldn't (scroll mode, a status-bar toggle, chrome show/hide, an open sheet, a first layout) or fail
to cancel? Can the snapshot come from a stale resource? Any retained task after close? Do the tests drive the real
paths and fail on the bugs they name?

Output `docs/android-port/briefs/R453-result.md`: findings (file:line, sequence, result, P1/P2/P3, smallest fix) and a
verdict. Read-only; no edits, commits, pushes, branch switches, builds, sign-in, AO3 traffic, or TASKS.md edits.
