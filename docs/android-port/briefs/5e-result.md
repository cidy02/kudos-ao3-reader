# Brief 5e result

Ready for Claude’s build/test/review handoff. Android only; iOS reference read-only. No Gradle/Xcode, network, sign-in, commit, push, or branch switch. No backup-format or Room-schema changes.

## Findings to carry forward

- **iOS concern, left untouched:** `FolderSyncService.readChangedRemoteAssets` independently fetches a missing conversion record without checking that the local original matches the folder original. This can pair a record with different source bytes. Android uses the requested size/digest guard (Part 3).
- **Remaining Android data-loss risk, left untouched:** Replace Library’s separate omission sweep can delete or soft-delete rows created after capture (Part 2).
- **Fixed here, needs tests:** Android suppressed incoming tombstoned queue memberships but did not sweep a membership already held here. Part 1 now removes unchanged captured memberships too, so normalization can observe the paired device’s removal.

## Part 1

Implemented, awaiting execution. iOS ORs the flag, then normalizes from membership (including deleted queues); it does not take the newer snapshot's flag. Android `ReadingQueueRepository.removeWork` clears the flag on last active membership removal and soft-deletes queue-only works, so a cleared local flag must not be migrated from a stale incoming flag.

Legacy migration runs inside `BackupMergeService.merge`, after work identity remapping and before queue reconciliation/normalization. It sees both input membership sets before a tombstone can remove one, so it cannot mistake a just-removed membership for legacy flag-only data. Existing locally cleared flags also block migration from stale archives. Shared `ReadingQueueRepository` queue/membership constructors now serve both live adds and migration, preserving system kind/name/pinning and order. Applied membership rows make subsequent restores idempotent; no Room migration or preference marker is needed.

Normalization handles only members or still-flagged works, resets abandoned preservation, checks actual EPUB availability, and includes omitted Replace queues' retained memberships. Held membership tombstones now sweep unchanged captured rows during apply. No EPUB deletion was added. Added six repository tests in `BackupTrustPhase2Test`; existing pure `restoreKeepsAQueueOnlyWorkOutOfTheLibrary` and `BackupEpubPreservationPassThroughTest` also need running.

## Part 2

Implemented, awaiting execution. `BackupMergeResult` records removed sessions/favorites/watermarks from the captured snapshot, just as it already records removed searches. Apply deletes only those captured rows, inside a Room transaction and only if their whole row is unchanged. Each new test also checks an unchanged swept row disappears and a changed captured row survives, alongside the row created after capture.

**Replace's own omission sweep has the same fault:** `removeRecordsAbsentFromReplaceSnapshot` reads current works/bookmarks/searches/collections/queues/annotations and compares them to the older merged snapshot without captured-row equality checks. A later-created row can be deleted or marked deleted. Its queue-membership omission sweep similarly reads live memberships. Left unchanged per brief. This is a remaining data-loss risk.

## Part 3

Implemented, awaiting execution. `SyncRepository.importOriginals` fetches groups when the original or record is absent, using the existing `MAX_ENTRY_BYTES` stream limit. `BackupRepository.restoreOriginals` (after `WorkIdentityIndex` remapping) accepts an absent record only alongside a newly installed original or an existing original with equal size and SHA-256 (`BackupPaths.sha256`). A local original is never rewritten. The shared guard also safely handles a later archive restore of identical source bytes.

Asset-only `BackupRepository.importOriginalFiles` avoids a full metadata restore. The own-manifest shortcut now runs this original/record pass too, so a late sidecar alone is sufficient; there is no need for another device to change the manifest. Unreadable/over-limit present originals withhold pruning and the skip digest, while the manifest is still written. Missing files do not stop sync. Three new tests cover late records, equal-size/different-digest originals, and identical locally imported originals (including unchanged file modification time); the existing different-extension original test remains.

## Part 4

The two requested tests were written before the batch fix; neither was executed here. The subsequent cross-batch membership-deletion test guards the interaction with Part 1.

- **Real font cap:** `aFontLibraryOverTheRealAggregateLimitConvergesInTwoSyncs` uses the bundled valid OpenDyslexic OTF, zero-padded after its tables to the real 4 MiB entry limit, as iOS's `syncDownConvergesWhenFontLibraryExceedsAggregateCap` does. Nine files total 36 MiB. The production default 32 MiB allowance must take eight first, keep all nine listed/in the folder, and take the ninth next. There is no injected cap. This requires 36 MiB of fixture I/O, ordinary font validation, and two syncs; actual loader validity and runtime need Claude's run.
- **Preservation between batches:** `queuePreservationFromAnEarlierBatchDoesNotRejectALaterEpub` first asserts that the ordinary first-batch merge promotes the second work's existing EPUB to preserved, and that one complete merge would accept that work's corrected bytes. It then exercises the real one-file-per-batch sync. Source tracing predicts failure before the fix: the second batch sees preserved old bytes and declines replacement. This prediction has not been run.
- **Small iOS-aligned fix:** `SyncRepository.importManifest` defers queue preservation promotion until its final batch, via a default-true `normalizeQueuePreservation` argument through repository/merge. iOS selects all assets then performs one restore whose end normalizes queues; Android's batches now preserve that ordering. Membership flags and abandoned preservation still normalize on every batch: otherwise batch one could delete a membership yet leave its flag set, and batch two could mistake it for legacy flag-only data and recreate membership. `aMembershipRemovedInTheFirstBatchIsNotMigratedBackInLaterBatches` covers that interaction. Normal archive restores still run full normalization on every restore. Existing preservation gates remain unchanged, including protection for works already preserved before the restore.

## Verification

- `git diff --check`: passed. Read real DAO, entity/model, identity matcher, file-store, merge mapper, and repository call-site signatures. Reviewed every changed source/test diff. This is static inspection, not compilation or passing-test evidence.
- Added **15 tests**: six queue cases and three snapshot-race cases in `BackupTrustPhase2Test`, three record cases and three limit/batch cases in `SyncRepositoryTest`.
- Claude needs to compile Android and run `BackupTrustPhase2Test`, `SyncRepositoryTest`, all classes in `BackupCompatibilityTest.kt` (including `BackupEpubPreservationPassThroughTest`), `BackupReadingLogTest`, `IncomingEpubGateTest`, `ReadingQueueRepositoryTest`/`ReadingQueueRepositorySeriesTest`, then the full Android suite. These runs establish every behavioral claim above. Measure the real-font-cap test’s runtime; none was measured here.
- No Gradle/Xcode execution, AO3 requests, sign-in, commits, pushes, or branch switches. No Room entity/DAO/schema edits, serialized manifest-key/version edits, or backup filename/folder changes. `KudosBackup.kt` additions are internal merge bookkeeping only. No helper scripts, stubs, `.orig` files, or generated fixtures were created.
- Remaining manual coverage: actual cloud-provider file arrival order and paired-device convergence. No screen work or visual claim.

## Next step

Claude builds, runs the focused and complete Android suites, performs the merge-bound adversarial review, and commits after verification. Branch remains `android/agent-codex-5e`; changes are intentionally uncommitted. No iOS port was made or requested.
