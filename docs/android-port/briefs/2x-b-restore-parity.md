# Brief 2x-b: make iOS and Android restore and export the same library identically

Continues brief 2x (`docs/android-port/briefs/2x-cross-platform.md`). The golden fixtures now exist and
come from the **real** exporters:
- iOS: `KudosTests/CrossPlatformBackupTests.swift`, kept as WIP at
  `/private/tmp/claude-501/-Users-cidy02/ccc01029-a9b5-4ce6-9117-4dd231af6998/scratchpad/CrossPlatformBackupTests.swift.wip`.
  It writes `android/app/src/test/resources/cross-platform/{ios-export.kudosbackup,expected-values.json}`
  when run with `TEST_RUNNER_KUDOS_WRITE_GOLDEN=1`.
- Android: `android/app/src/test/java/io/github/cidy02/kudos/backup/CrossPlatformRestoreTest.kt` writes
  `KudosTests/Fixtures/cross-platform/android-export.kudosbackup` with `-Dkudos.writeGolden=true`.

Both round trips fail. No field is lost; each app **recomputes** values on restore that the other
doesn't, and the seeds hold states one app considers inconsistent. Diff of iOS restore + re-export
of the Android golden against the Android golden:

| Field | iOS re-export | Android archive | Cause (verify) |
|---|---|---|---|
| work 2 `isQueuedForLater` | true | false | iOS `ReadingQueueService.normalize` re-derives it from memberships. The Android seed put the work in a queue without setting the flag, and Android's restore doesn't normalise. |
| work 2 `epubPreservationStatusRaw`, `preservedAt` | `preserved`, now | `notPreserved`, none | iOS marks a queued work with a file as preserved on restore. |
| work 2 `metadataSyncStatusRaw` | pending | unknown | iOS restore resets it. |
| work 2 `lastModifiedAt`, collection `lastModifiedAt`, Saved for Later `dateUpdated` / `lastMembershipChangedAt` | now | archived | iOS stamps records the restore touched. |
| queue 2 `lastMembershipChangedAt` | 22:28 | 22:27 | iOS derives it from memberships. |
| Saved for Later `sortOrder` | -1000 | 0 | iOS pins the system queue at -1000; Android uses 0. |
| works `assetIdentifier` | `<uuid>.epub` | `cross-platform-one.epub` | iOS derives the archive name from the id. |

The Android restore of the iOS golden fails in the mirror-image way (run it and diff, as above).

## Do
For each difference, find the iOS rule (file:line) and decide:
1. **iOS normalises on restore** (`isQueuedForLater`, preservation status, derived
   `lastMembershipChangedAt`): port the same normalisation to Android's restore, so both apps leave
   the same state after a restore.
2. **iOS stamps "now"** on records the restore touched: decide which behaviour is correct. Preserving
   the archived timestamps avoids a restored copy "winning" every later sync on recency; stamping makes
   a restore count as an edit. Read `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` and the iOS comments, pick
   the rule the iOS code intends, make both apps do it, and log the decision in
   `docs/android-port/DECISIONS.md`.
3. **Conventions** (Saved for Later `sortOrder = -1000`, `assetIdentifier = "<uuid>.epub"`): make
   Android match iOS, with a migration-free fix, plus a one-time normalise for the existing system
   queue if needed.
4. **Seeds**: make both seeds internally consistent (a queued work has `isQueuedForLater = true`, and
   so on) so the fixtures describe a state either app could produce.
5. Only after 1–4, if a field is genuinely recomputed by design on both sides, may the canonicaliser
   ignore it, with a comment citing the rule.

Then regenerate both goldens with the real exporters (iOS flag first, then Android), and run both
suites without flags until **all four** checks pass: iOS→Android, Android→iOS, and both round trips.
Write `docs/android-port/briefs/2x-b-result.md`.

The iOS side runs in the iOS lane:
`/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish`
(scheme `AO3_App_OpenSource`). The Android side lives in its own worktree, where Codex's 2x Android changes
are still uncommitted: schema 12 pass-through columns, `.000Z` dates, and golden-flag plumbing.
Do not commit, push, switch branches, stash or reset; leave changes uncommitted for Claude.
