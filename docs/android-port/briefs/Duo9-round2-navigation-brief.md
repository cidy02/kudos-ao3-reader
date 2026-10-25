# Duo9 — iPhone Duo round 2: local navigation that feels like Settings and Files

**Agent:** Codex. **Worktree:** `~/kudos-agent-ios`, branch `claude/agent-ios-duo9` (from the iOS lane's
`663eaa90`: T-452, round 1 landed). iOS only. T-451 (a six-line Readium configuration fix in
`ReadiumBook.swift`) is landing at the same time: don't touch `Features/ReaderReadium/`.

## Decided (Claude-CLI, owner-delegated; `docs/android-port/DECISIONS.md` 2026-10-24)

Your Duo7 plan (`docs/android-port/briefs/Duo7-plan.md`) is the direction; this brief is its **Round 2**,
exactly as you wrote it there (outcome, files, brief, risks, Claude checks): read that section first. Models:
iPad Settings (categories | page) and Files (locations | contents). Decisions that bind it:
- **One visible split at a time** (Library locations | section; queues | queue contents; Account destinations |
  page; Settings categories | settings page). Entering Settings or a queue replaces the parent's leading list;
  never three panes. Let `NavigationSplitView` own the split's geometry (it pads around the fold in Book pose).
- The split appears by **measured usable space** (round 1's `AdaptiveContentRegions` / `WideLayout`), never "is a
  Duo"; the cover and the iPhone keep their stacks; the iPad gets the same where it fits (full and narrow).
- No information or density lost; forms and rich rows at a readable width instead of 951 pt; no new
  destinations, no model or schema change; no page is loaded just because its label is visible.
- Keep Back, deep links, `NavigationPath`s, selections and filters working through collapse/expand and
  through a fold or unfold with a selected row and a dirty AO3 Preferences form.

Round 1 (T-452) is live: reuse its region helper; don't change Home or the dashboard shelves.

## Tests

Keep the existing route, queue-selection and filter tests green; add collapse-selection and deep-link coverage
where state changes; each new test fails with its logic reverted.

## Rules

- iOS only, in this worktree. Do not commit, push, switch branches, build, sign in, contact
  archiveofourown.org, or edit `TASKS.md`. Nothing builds here; Claude builds, gates and shoots every pose
  (`~/kudos-tools/duo-pose`).

## Output

`docs/android-port/briefs/Duo9-result.md`, written first and kept current: each change (file:line) and why,
tests and how they fail when reverted, the exact screens and poses for Claude, anything you'd decide
differently from Duo7, and any whole-app feature idea (for `FEATURE-IDEAS.md`), listed apart.
