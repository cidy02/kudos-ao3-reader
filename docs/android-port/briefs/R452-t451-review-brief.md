# R452 — adversarial review of the T-451 fix before it lands (Readium's fixed-layout spread off for reflowable books)

**Agent:** Codex (fresh job). **Worktree:** `~/kudos-agent-ios2` (write only the result file). Read-only.

The fix: `~/kudos-tools/out/backups/T451.patch` (live here on `claude/agent-ios-t451`, base iOS `b4752bd5`), notes
`docs/android-port/briefs/T451-result.md`. It sets `config.defaults.spread = .never` when the publication's layout
isn't fixed, so a rotation no longer makes Readium 3.9.0 (pinned) reload the chapter's spreads and restore a
rounded-down progression.

Break it: could `.never` change anything else for reflowable books (the two-page spread the app offers through
`columnCount` on wide screens since T-448, page turns, RTL, scroll mode, preferences submitted later, the
navigator's own `submitPreferences` merging defaults)? Is the layout test right for EPUBs with missing or odd
layout metadata, and for fixed-layout books (unchanged)? Is there any other path that still reloads spreads on a
rotation or an unfold? Does the new test really fail without the fix?

Output `docs/android-port/briefs/R452-result.md`: findings (file:line, sequence, result, severity P1/P2/P3, fix) and a
verdict. Rules: read-only; no edits, commits, pushes, branch switches, builds, sign-in, AO3 traffic, TASKS.md edits.
