# Brief 3ge result

- Step 1: Started in the dispatched Android worktree on `android/agent-codex-3ge`. Existing user edit in `docs/android-port/briefs/3ge-cross-platform-fixture-coverage.md` will be preserved. No builds, branch switches, commits, pushes, sign-ins, or AO3 traffic will be performed. Inspecting both fixture pipelines before changes.

- Step 2 (Round 1; corrected in Round 2): Inspected the archive and sync generators/readers on both dispatched branches. Incorrectly treated the collection membership clock's absence from backup DTOs/mappers as a production gap and added a conflicting T-421 claim. The clock is deliberately device-local; Round 2 removes those expectations and the task-board patch.
- Environment blocker: an ordinary `apply_patch` targeting `/Users/cidy02/kudos-agent-ios/KudosTests/CrossPlatformBackupTests.swift` was rejected: “writing outside of the project; rejected by user approval settings”. Approval is disabled. iOS changes are staged under `/tmp/kudos-3ge-ios` for a patch in this worktree; the actual iOS worktree remains untouched.

- Step 3: Added matching Swift/Kotlin fixture seed/check helpers for all three pronunciation scopes, font metadata and byte equality, a soft-deleted annotation/collection/custom queue, and a valid signed tombstone with AO3 work ID 829998. The original 804-byte two-glyph TrueType payload was validated with CoreText (`KudosFixture-Regular`, 2 glyphs) and CGFont. Signed payload was checked with CryptoKit using the actual whole-second tombstone wire format.
- Step 4: Wired archive and all three sync-folder paths to the helpers. iOS compares pronunciations, fetches/restores/re-exports fonts, and clears seeded font/pronunciation state before Android archive restore. Default pronunciation bytes and the font-directory override are restored after each iOS test. Android asserts actual restored rows/files before native reseeding for its outgoing golden. Existing assertions remain; only the newly added deleted custom queue's device-local recovery schedule is excluded from the Swift canonical comparison, as the existing canonical rules already do for deleted works/collections/system queues. Deletion dates and queue membership clocks remain explicit assertions; Round 2 removes the erroneous collection clock expectations.

- Step 5: Reviewed the new soft-deleted records against the restore paths. A second existing gap is explicit in Android `BackupMergeService.mergeCollections`: when no local row exists, `if (archived.isDeleted == true) return@forEach` drops the entire incoming deleted collection (currently line 1346). The default archive import is `RECONCILE`; sync uses this merge path too. iOS `KudosBackupService.restore` creates the collection and applies its deletion state. The new blank-device assertions deliberately fail on the Android loss; they do not preseed the destination or change restore mode to conceal it.

## Handoff status

**Not suite-verified or ready to land.** Android production/test edits are in this worktree. Direct iOS edits were rejected by the sandbox; the complete iOS test/helper change is in [3ge-ios.patch](3ge-ios.patch), based on the dispatched `/Users/cidy02/kudos-agent-ios` files. The patch contains no TASKS.md change. The actual iOS worktree was not changed. No commit, push, branch switch, sign-in, Gradle, xcodebuild, or AO3 request was performed. The pre-existing Android brief edit, Android TASKS.md edit, and iOS untracked docs were preserved; neither tree's TASKS.md was edited in Round 2.

Apply the iOS patch from Claude's writable session:

```sh
git -C /Users/cidy02/kudos-agent-ios apply /Users/cidy02/kudos-agent-codex/docs/android-port/briefs/3ge-ios.patch
```

Round 2 resolves the confirmed production gap: Android `BackupMergeService.mergeCollections` now restores a previously absent soft-deleted collection through its existing tombstone resolution and `toWorkCollection` path. The mapper retains `deletedAt` and creates a device-local recovery deadline; repeated Reconcile keeps the local deadline. Replace already imports deleted collections through `replaceCollections`. Works, queues, and annotations already retain absent soft-deleted records; no analogous skip needs changing there.

The collection membership clock is intentionally absent from both manifests. Its local use is documented in iOS `Services/KudosBackup.swift` beside the membership-deletion sweep (around line 2707). No DTO or production clock transport change is needed. This dispatch correction supersedes the collection-clock item in the original brief; queue membership clocks still travel and are checked.

No golden ZIP/JSON/folder was hand-edited. Existing committed goldens intentionally fail the new stale-fixture checks until the real generating tests are run. `expected-values.json` and `ios-export.kudosbackup` currently have no fonts and empty pronunciation maps (confirmed by offline JSON/ZIP inspection).

## Regeneration order — iOS first, Android second, then iOS readers

All paths below are relative to the worktree in which the test runs. Generators use the existing real exporters, not a JSON/ZIP construction script.

Before step 1, Claude applies the revised iOS patch and includes the Android production fix. No collection clock schema change is required. Codex has regenerated no fixture in either round.

| Order | Exact generating test | Flag | Fixture output |
|---|---|---|---|
| 1a | iOS `PersistenceGateSuites.CrossPlatformBackupTests.iosAndAndroidGoldenArchivesRestoreAndRoundTrip` | `TEST_RUNNER_KUDOS_WRITE_GOLDEN=1` (or `KUDOS_WRITE_GOLDEN=1` inside the runner) | `android/app/src/test/resources/cross-platform/ios-export.kudosbackup` and `expected-values.json` |
| 1b | iOS `PersistenceGateSuites.CrossPlatformFolderSyncTests.theFolderIOSWritesIsTheFixtureAndroidReads` | same | `android/app/src/test/resources/cross-platform/ios-sync-folder/KudosLibrary/` including `Fonts/kudos-cross-platform-fixture.ttf` |
| 2a | Android `io.github.cidy02.kudos.backup.CrossPlatformRestoreTest.iosGoldenRestoresThroughRepositoryAndAndroidRoundTripsEverySharedField` | `-Dkudos.writeGolden=true` | `KudosTests/Fixtures/cross-platform/android-export.kudosbackup` |
| 2b | Android `io.github.cidy02.kudos.backup.SyncRepositoryTest.theFolderAndroidWritesIsTheFixtureIosReads` | same | `KudosTests/Fixtures/cross-platform/android-sync-folder/KudosLibrary/` including font bytes |
| 2c | Android `io.github.cidy02.kudos.backup.SyncRepositoryTest.androidAddsItsWorkToTheIosFolderWithoutPruningEitherDevicesAssets` | same | `android/app/src/test/resources/cross-platform/android-after-ios-sync-folder/KudosLibrary/` including the iOS font bytes |

After 1a/1b, copy the two iOS archive/JSON files and the entire `ios-sync-folder/` directory from the iOS runner worktree into the Android runner worktree at those same relative paths. The archive test is an existing combined writer/reader: on the **first** regeneration run its Android-reading half can report a stale Android fixture after it has already written the iOS fixtures. That is resolved by step 2 and a final rerun; do not remove that assertion or accept that first run as validation.

After 2a/2b/2c, copy `android-export.kudosbackup`, the entire `android-sync-folder/`, and the entire `android-after-ios-sync-folder/` to the iOS runner worktree at their same relative paths. Keep all six output groups synchronized across the two trees: two archives, expected-values JSON, and three folder directories.

Finally, with both golden-write flags **unset**, Claude runs both cross-platform iOS suites and Android `CrossPlatformRestoreTest` plus the three cross-platform `SyncRepositoryTest` cases (including `aFolderIosWroteIsReadAndKept`), then Android `BackupMergeParityTest` (including the three Round 2 regressions) and the normal full suites/gates. Use the project's case-sensitive APFS harness for the complete iOS target. The final iOS folder readers are `aFolderAndroidWroteIsReadAndKept` and `aFolderBothAppsWroteIsReadAndKept`. Every path checks the new manifest values, restored rows, local font bytes, and remote/archive font bytes. Existing EPUB/original/file-set/canonical assertions remain.

## Verification actually performed

- `swiftc -frontend -parse` on all three staged Swift test/helper sources: exit 0. This parses syntax; it is **not** app/test typechecking.
- `swiftlint lint --quiet --no-cache` on the staged Swift sources: exit 0 with length/tuple warnings in the existing large suites; the new helper is clean. A first lint attempt used an unsupported `--path` flag; rerun with positional paths. Another first run could not write its cache; the successful rerun disabled that cache.
- CoreText and CGFont accept the original embedded font: `KudosFixture-Regular`, 2 glyphs, 804 bytes. Both language payloads decode to SHA-256 `1b9f2c091cce0d2499c8915fbfa9925802aff00f6fa928bc866fc35df1fc1b16`.
- CryptoKit verifies the pinned test tombstone signature, including AO3 ID 829998 and the actual whole-second signature timestamp. Both helpers contain that signature.
- `git diff --check`: clean for the Android edits. iOS patch applicability checked separately below.
- No Kotlin compilation, Gradle tests, Swift app/test typecheck, xcodebuild, suite execution, fixture regeneration, or visual verification was performed. Claude owns those remaining checks and landing; there is no commit SHA for this uncommitted handoff.

- Step 6 (Round 1): Wrote the durable iOS patch and exact regeneration/copy order above; `git -C /Users/cidy02/kudos-agent-ios apply --check .../3ge-ios.patch` passed without modifying that worktree. Final Swift syntax parse and Android `git diff --check` passed. The conflicting task claim is withdrawn in Round 2; Claude owns task-board bookkeeping and landing.

## Round 2 — 2026-10-21 dispatch corrections

- Removed the collection-only `membershipAt` seed constant, local seed assignment, raw manifest assertion, and restored-row assertion from the Android helper and the staged iOS helper/patch. Kept queue seeding and existing queue comparisons, and added explicit raw/restored queue `lastMembershipChangedAt` checks on both sides.
- Removed the entire TASKS.md hunk from `3ge-ios.patch`. Did not edit TASKS.md in either worktree; the already-present Android TASKS.md diff remains for Claude to reconcile.
- Fixed `BackupMergeService.mergeCollections` by removing only the unconditional `archived.isDeleted` skip for an absent local collection. Existing tombstone suppression/newer revival, mapper deletion-state handling, local recovery scheduling, and the separate Replace path remain in control. Inspected works (`merge`), queues (`mergeQueues`), and annotations (`mergeAnnotations`): none has the same unconditional skip; annotation restore still requires a parent work.
- Added `BackupMergeParityTest.absentSoftDeletedRecordsRestoreInEveryModeWithALocalRecoveryWindow` for blank-device restoration of deleted works, collections, custom queues, and annotations in every mode, including preserved deletion dates and fresh local recovery windows rather than the archived deadline. Added `absentSoftDeletedCollectionStillRespectsTombstonesExceptInReplace` for older/equal/newer clocks in every mode, and `reconcilingAnImportedDeletedCollectionKeepsItsRecoveryDeadline` for repeated Reconcile.
- Verification: revised iOS patch applicability, Swift syntax parsing of all three staged sources, SwiftLint on the revised helper, and `git diff --check` pass. These are static checks; no Kotlin compilation or test suite execution was performed. No fixtures were regenerated or hand-edited, and no Gradle, xcodebuild, commit, or push was run. The generators and suite execution remain Claude's next step in the order above.
