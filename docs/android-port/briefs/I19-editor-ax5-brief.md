# I19 — the iPhone's text editor at the largest text size

**Agent:** Codex. **Worktree:** `~/kudos-agent-ios`, branch `claude/agent-ios-i19` (from the iOS lane's
`7f479443`). iOS only.

## The fault

A97 (`~/kudos-tools/out/a97/A97-claude-notes.md`, `texteditor`; tile
`~/kudos-tools/pairs/tiles-a97/texteditor.png`, the iPhone's "big" column at AX5): in the work's text
editor (`kudos-ao3-reader/Features/Writing/WritingTextEditor.swift`), the footer takes most of the screen
at the largest accessibility size:
- the recovery line "Recovery copy on this device · Save from the work form" (`:100`),
- the formatting tray's chips,
- and the footnote "AO3 supports only certain formatting. The toolbar adds formatting that AO3 can keep
  when you post." (`:110`; a second copy at `:267`).

Only one line of the text being edited stays visible ("A long walk home"). At normal sizes it is fine.
Android at 2.0× keeps the text area and puts a compact tray at the foot.

## What to do

Keep the text being edited usable at AX5: aim for at least five lines of it visible on an iPhone 17
(402×874 pt) with the keyboard down. Don't drop information (AGENTS.md: density is not to be lost
without approval): what doesn't fit should stay reachable, for example the footnote shortened to a line
with the rest behind a disclosure or an info button, the recovery line truncated to one line with the
full text in its accessibility label, and the tray kept to one scrolling row. Prefer what iOS's own
patterns and the app's existing components already do (look for how other screens in the app handle
AX5 footers before inventing one). Normal sizes must look exactly as they do now.

## Test

Add a Swift Testing test in `KudosTests/` that would fail with your change reverted: for example, the
footer's height at AX5 in a rendered `WritingTextEditor` (or the extracted footer view) stays under a
bound that leaves five lines of body text, or the footnote's line limit applies only at accessibility
sizes.

## Rules

- Change only what the fix needs in `Features/Writing/` (and a shared component if one already fits).
- Do not commit, push, switch branches, build, run tests or the simulator (Claude does), sign in, contact
  archiveofourown.org, or edit `TASKS.md`. SwiftLint stays at its current level.

## Output

Write `docs/android-port/briefs/I19-result.md` **first**, then keep it current: what changed
(`path:line`), what is visible at AX5 and at normal sizes, where the shortened information is reachable,
and what the test checks and how it fails with the change reverted.
