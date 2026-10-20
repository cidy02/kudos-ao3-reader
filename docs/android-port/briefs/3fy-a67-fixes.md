# Brief 3fy: fix A67's findings (Android)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Leave a result
file `docs/android-port/briefs/3fy-result.md`, written as you go: per finding, **fixed / not real
at this HEAD / left** with `path:line`, what changed, the iOS rule followed
(`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, read-only) and the test added.

Your own audit is `docs/android-port/audits/A67-result.md` (in this worktree). Fix F1 to F9 in its
priority order. Hard rules: read `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` first; Room migrations
additive only (a new DAO query is fine; a schema change is not expected); backup manifest v8,
additive keys only; `docs/AO3_NETWORKING_POLICY.md` binding; iOS is the source of truth. Android's
ICU regex rejects some JVM-accepted flags (`RegexPortabilityTest`).

How to fix the stale-copy writers (F1 to F6), the lesson of 2026-10-16 (`bab161fd`, `28bcd3c5`):
after any suspend that can take time (a query, a `delay`, a file or network call), a whole-row
`@Upsert` of a copy taken before it undoes what was written meanwhile. Prefer the root-cause fix
that removes the class: a column-only `@Query("UPDATE works SET … WHERE id = :id")` for writers
that change one or two columns (the search index's `searchText` and `searchIndexVersion`; a file
flag), or read the row again inside a transaction right before writing. Do not add a guard at
each caller where one shared function serves them all.

- F7 and F8 touch Replace: a sync that passed its check must not import after Replace paused
  sync; Replace's undo copy must be reachable by the Import picker (or written where iOS writes
  its own and opened the way iOS reopens it). Follow iOS
  (`Services/KudosBackupService.swift`, `Settings/SettingsBackupPage.swift`).
- F9: a multi-item Inbox delete sends exactly the items the reader confirmed.

Tests: each fix gets one that fails with the fix taken out (for F1, a reading place written while
the rebuild is between its batches survives).
