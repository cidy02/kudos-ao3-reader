# Duo11 — iPhone Duo round 4a: Work Detail composed like an album page

**Agent:** Codex. **Worktree:** named in the dispatch, branch `claude/agent-ios-duo11` (from the iOS lane's tip;
Claude names the SHA). iOS only. Other rounds may run at the same time: touch only Work Detail's files and the
shared region helper; don't touch `Features/ReaderReadium/`, Library, Account, Settings, Search or Browse.

## Decided (Claude-CLI, owner-delegated; `docs/android-port/DECISIONS.md` 2026-10-24)

Your Duo7 plan's **Round 4** is split: **4a is Work Detail only** (this brief); Search, Browse and results follow as
4b once round 2's navigation host has landed. Read Duo7's "Work Detail — Music album detail" section and Round 4.
Model: Music's album page on iPad. Decisions that bind it:
- **Two content regions when Work Detail's own container fits** (measured, never "is a Duo"; reuse round 1's
  `AdaptiveContentRegions`): leading = identity, figures, Read/Resume, archive stats and the existing actions;
  trailing = summary, tags, facts, comments links, series and My copy. Each region scrolls on its own so Read/Resume
  stays in reach while reading long tags. VoiceOver reads leading then trailing.
- **Book pose:** the two regions sit either side of the fold, each wholly inside its pane.
- **Narrow containers keep today's single column:** the cover, the iPhone, inner portrait (one centred readable
  column at 669 pt) and Work Detail pushed into a split's detail column that's too narrow.
- Same content, order within each group, privacy (hidden mature works), errors next to the action that caused them,
  Show More on the summary. Never lose warning tags, author links, dates, kudos/hits/bookmarks/comments, chapter
  completeness or My copy's local controls. No chapter index, no prefetch, no new control or screen, and don't
  restore the old segmented sections (the current `pageSections` has none).

## Tests

Extend `WorkDetailPresentationTests` / `BrowseAndWorkDetailRulesTests` where behaviour changed (region choice by
width, the narrow fallback, group membership and order); each new test fails with its logic reverted. Server
URL/filter tests stay unchanged.

## Rules

- iOS only, in this worktree. Do not commit, push, switch branches, build, sign in, contact
  archiveofourown.org, or edit `TASKS.md`. Nothing builds here; Claude builds, gates and shoots every pose
  (`~/kudos-tools/duo-pose`), the iPad and the iPhone, at default and AX5.

## Output

`docs/android-port/briefs/Duo11-result.md`, written first and kept current: each change (file:line) and why, tests
and how they fail when reverted, the exact screens and poses for Claude, anything you'd decide differently from
Duo7, and any whole-app feature idea (for `FEATURE-IDEAS.md`), listed apart.
