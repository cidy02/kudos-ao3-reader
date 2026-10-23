# Brief D5 (docs, read only): statements today's commits made wrong

**Write exactly one file: `docs/android-port/briefs/D5-result.md` in this worktree
(`/Users/cidy02/kudos-agent-gemini2`). Change nothing else anywhere; do not commit, push, switch
branches, run builds, sign in, or contact archiveofourown.org.** Use absolute paths.

The project rule (AGENTS.md, "Future Agent Checklist" item 7): any `docs/*.md` statement a change
falsified is updated in the same commit. Today's commits did not check. Two repos each keep their
own copy of these docs:
- iOS: `/Users/cidy02/kudos-ios-polish/docs/` — use
  `git -C /Users/cidy02/kudos-ios-polish log --since="2026-10-22 00:00" --stat`.
- Android: `/Users/cidy02/kudos-android-lane/docs/` (not `docs/android-port/`, which is current) —
  `git -C /Users/cidy02/kudos-android-lane log --since="2026-10-22 00:00" --stat`.

Check these docs in both repos: `ARCHITECTURE_MAP.md`, `AGENT_ONBOARDING.md`,
`DATA_AND_PERSISTENCE_INVARIANTS.md`, `AO3_NETWORKING_POLICY.md`, `REGRESSION_TEST_MATRIX.md`,
`KUDOSBACKUP_FORMAT.md`. For each statement that a 2026-10-22 commit made false, incomplete or
out of date (a file that moved, a rule that changed, a screen or route that now exists, a test that
now covers something the doc says is untested, a request pattern that changed), write:
- repo, file, and the exact current sentence;
- the commit that changed it and what it changed (one line);
- the exact replacement text, in the doc's own style (plain, short).

Only real contradictions: do not suggest new sections or rewrite style. If a doc has nothing stale,
say "nothing stale" for it. Start the file with the count of proposed edits per repo.
