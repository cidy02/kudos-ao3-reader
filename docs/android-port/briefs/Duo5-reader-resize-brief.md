# Duo5 — the reader survives a change of size (unfolding, turning the phone)

**Agent:** Codex. **Worktree:** `~/kudos-agent-ios2`, branch `claude/agent-ios-duo5` (from the iOS lane's
T-446, `d9e0d44f`). iOS only. Duo4 runs at the same time in `~/kudos-agent-ios` (horizontal shelves and the
card clamp): don't touch those files.

## Why

The owner's focus is now optimizing Kudos for iPhone Duo. Opening or closing the Duo changes the reader's
window from 466×678 pt (cover) to 951×669 pt (inner, landscape) or 669×951 pt (inner, portrait) **mid-chapter**,
and the inner landscape window has side exclusions. Your Duo3 audit
(`~/kudos-agent-gemini2/docs/android-port/briefs/Duo3-result.md`) found three reader faults that a change of
size exposes. The same faults show when an ordinary iPhone turns to landscape (the app allows landscape on
iPhone; the Dynamic Island then makes a side safe area), so Claude can check this round on the iPhone 17
simulator without the Duo's fold control:
- **Finding 7:** the reader drops horizontal safe areas (`ReaderDismissDrag.swift:176–183`,
  `ReadiumReaderView.swift:990,1003,1021–1022,1074–1075`, `ReadiumBook.swift:1234`).
- **Finding 9:** the page box is seeded from `UIScreen.main.bounds.height` and refreshes on height alone
  (`ReadiumBook.swift:201–206, 1243–1255`).
- **Finding 16:** a same-chapter reflow doesn't remeasure the visual page count (`ReadiumBook.swift:692–704,
  874–877`; the injected script has no resize listener, `:1111–1168`).

## What to do

1. The reader's text and its controls (top bar, the fan, the bottom controls, the position card, the
   Read Aloud mini-player) keep clear of the window's side safe areas; the page background stays full-bleed.
   Keep the existing protection against the chrome jumping when the status bar toggles.
2. The page box is seeded from the hosting view, not the screen, and refreshes when the host's size (width or
   height) or its safe insets change meaningfully.
3. After a settled change of viewport size in the same chapter, the reader keeps its locator (the reading
   position) and runs the existing clear + scheduled remeasure of the page count, so the page bar's "page X of
   N" and the seek scale are right for the new size, whether N grows or shrinks. Reuse the existing
   agreement guard; don't publish a guessed count.
4. Out of scope: the fold itself, a two-page spread, Book pose, hinge APIs (Duo3's findings 3, 8, 10, 11):
   those wait for the inner display. No idiom checks.
5. Tests where the code allows (the freeze key's arithmetic; the remeasure being scheduled on a same-href size
   change); the rest as precise simulator steps for Claude.

## Rules

- iOS only, in this worktree. Do not commit, push, switch branches, build, sign in, contact
  archiveofourown.org, or edit `TASKS.md`. Nothing builds here; Claude builds, gates and shoots in
  `~/kudos-ios-polish`.
- Don't lose density or information (AGENTS.md); no new UI elements; reading position must never be lost.

## Output

`docs/android-port/briefs/Duo5-result.md`, written first and kept current: each change (file:line) and why,
the tests and how they fail when reverted, and the exact simulator steps (open Night Market, scroll and paged
modes, turn to landscape and back mid-chapter with chrome up and down, Read Aloud playing): what Claude should
see at each step.
