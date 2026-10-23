# Brief D6 (docs, read only): the older stale facts D5 noticed

**Write exactly one file: `docs/android-port/briefs/D6-result.md` in this worktree
(`/Users/cidy02/kudos-agent-gemini2`). Change nothing else; do not commit, push, switch branches,
run builds, sign in, or contact archiveofourown.org.** Use absolute paths.

In D5 you noticed facts that were already wrong before today, in both repos
(`/Users/cidy02/kudos-ios-polish/docs/` and `/Users/cidy02/kudos-android-lane/docs/`):
`KUDOSBACKUP_FORMAT.md` (format version 7, "classic / non-ZIP64", "Android (future / sibling)") and
`AGENT_ONBOARDING.md` ("216 tests / 29 suites as of T-74").

For each such statement in those two docs (and any other plainly outdated fact you find in them),
check the truth in the code and history, not from memory:
- the backup manifest version (iOS `Services/KudosBackup.swift`; Android `backup/`), what the
  archive writer does today (ZIP64? streaming? see TASKS.md T-139/T-140 in the iOS repo), and what
  Android reads and writes (the cross-platform fixtures `KudosTests/Fixtures/cross-platform/`);
- the iOS test count (count `@Test` functions and XCTest `func test` methods under `KudosTests/`;
  say how you counted) and the Android unit-test count (`@Test` under
  `android/app/src/test/` in the Android repo).

Write, per repo and file: the exact current sentence, the evidence (file:line or commit), and the
exact replacement in the doc's own plain style. Only facts, no new sections. Start with the count of
edits per repo.
