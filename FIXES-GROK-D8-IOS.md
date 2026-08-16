# D8 iOS — unsigned `isDeleted` must not mint a signed tombstone

Local only. No push, no PR. Worktree: `/Users/cidy02/kudos-d8-ios`. Branch: `d8-fix/ios`.

Implementer: Grok 4.6. Spec: `/Users/cidy02/kudos-fix-tombstone/D8-FIX-SPEC.md`.

## Premise check (required before implementing)

The spec claims gating the clock is **sufficient** because `WorkLifecycle.hardDelete` is only reachable via (a) `PreservedWorkService.sweepExpired` or (b) an explicit user "Delete Permanently" tap.

Verified against this tree:

| Caller | Kind | Path |
|---|---|---|
| `PreservedWorkService.sweepExpired` | production, automatic | `PreservedWorkService.swift:250` → `WorkLifecycle.hardDelete` |
| `RecentlyDeletedView` confirmation | production, first-party tap | `RecentlyDeletedView.swift` "Delete Permanently" → `WorkLifecycle.hardDelete` |
| Tests | not production | `PersistenceSyncTests`, `UserDocumentImportTests`, `WorkReconversionTests`, `ReadingAnnotationBackupTests` |

No third production caller. Collection/queue `PreservedWorkService.hardDelete` has the same two production callers (sweep + Recently Deleted). **The claim holds.** Implemented the clock gate; did not add a guard on `hardDelete`.

Related clock-rearm (not a `hardDelete` path): `PersistenceMigrationService.backfillPermanentDeletionScheduledAt` (`PersistenceSync.swift`) still sets a schedule on any `isPendingDeletion && scheduledAt == nil` record during an incomplete migration. That is neutralized because `sweepExpired` now runs `reconcileUnsignedDeletionSchedules` **before** deleting, and ContentView's launch order is `runIfNeeded` then `sweepExpired`. Left `PersistenceSync.swift` untouched (out of spec file list).

## Commits

| SHA | What |
|---|---|
| `b4a58bd` | Clock gate, collection/queue siblings, reconciliation, hold/notify, tests, docs |
| `5b1077a` | Test compile (`#expect` + SwiftData key path) + review UI on `ContentView` |

## What changed (file:line)

### Clock gate — `archivedDeletionState`

`kudos-ao3-reader/Services/KudosBackup.swift:2943-2958`

New `hasTrustedTombstone` parameter. Unsigned incoming `isDeleted` returns `(true, nil)` — hide, **clear** any already-running local schedule. Trusted tombstone keeps the existing local countdown or starts `now + recoveryWindow`.

### Work `apply()` call site

`KudosBackup.swift:3076-3091`

```
hasTrustedTombstone: tombstones.suppressesResurrection(of: archived)
```

Reuses the already-built `TombstoneIndex` (adopted-only). When the anomaly hold is active, unsigned hides are skipped entirely.

### WorkCollection / ReadingQueue

Same unsigned-clock pattern existed. Gated with the existing resolution enum:

- Collections `KudosBackup.swift:1874-1886` — `tombstones.hasTrustedCollectionDeletion` ≡ `collectionResolution == .suppressStaleData`
- Queues `KudosBackup.swift:2027-2038` — `tombstones.hasTrustedQueueDeletion` ≡ `queueResolution == .suppressStaleData`

`.suppressStaleData` is the analog of `suppressesResurrection`: a matching adopted tombstone at least as new as the incoming snapshot. `.reviveNewerData` / `.noTombstone` / `.preserveAmbiguous` do **not** arm the clock.

Helpers: `KudosBackup.swift:2771-2778`.

### Reconciliation (required)

`PreservedWorkService.swift:143-186` `reconcileUnsignedDeletionSchedules`

Called at the start of every `sweepExpired` (`PreservedWorkService.swift:237-242`), so it runs on launch (`ContentView`) and on the folder-sync background task **before** anything can be hard-deleted.

For every `isPendingDeletion && scheduledAt != nil` record: if no local persisted `SyncTombstone` matches (works: AO3 ID → canonical URL → record ID; collections/queues: record ID), clear `scheduledAt` only. Hide state is left alone.

### Notify-on-use + anomaly hold

- Pre-scan in `restoreIsolatedContents` (`KudosBackup.swift:1652-1672`) counts unsigned work hides that this pass would apply.
- Floor `unsignedHideHoldFloor = 10` (`KudosBackup.swift:2963`).
- ≥10: apply **none** of those unsigned hides; `KudosBackupRestoreSummary.unsignedHidesHeld` + `heldUnsignedHideWorkIDs`.
- <10: apply hide-without-schedule; digest via `unsignedHidesApplied`.
- `KudosBackupService.restore` (`KudosBackup.swift:1587-1589`) records the result on `UnsignedDeletionReview`.
- Review sheet + digest alert presented from `ContentView` (not Settings, not pairing). Confirm hides without minting a tombstone (`applyHeldUnsignedHides`, `KudosBackup.swift:3004-3016`).
- **First-sync-from-new-trust exemption: deferred.** `TombstoneTrustStore` has no cheap "just granted" timestamp, and pairing/Settings are out of scope.
- Recently Deleted provenance: `SavedWork` has no `deletedOnDeviceID`. Did not invent storage. Nil schedule now labels **"Kept until you delete"** instead of the misleading "0 days left".

### Docs

- `PHASE2-CONTRACT.md` — new "D8" section.
- `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` — unsigned `isDeleted` cannot arm the clock.
- `docs/REGRESSION_TEST_MATRIX.md` — Deletion/recovery row.

## Tests (production entry: `restore` / `sweepExpired` / `archivedDeletionState`)

`KudosTests/ArchiveDeletionScheduleTests.swift` (now **12/12**):

| Test | What it asserts |
|---|---|
| `unsignedIncomingDeletionNeverSetsAScheduleEvenIfOneWasAlreadyRunning` | `hasTrustedTombstone=false` clears a running local schedule |
| `trustedTombstoneStartsAFreshLocalWindow` / `trustedTombstoneKeepsAnAlreadyRunningLocalCountdown` | trusted path unchanged |
| `restoreHidesWithoutSchedulingWhenArchiveHasNoTrustedTombstone` | `restore()` hides, `scheduledAt == nil` |
| `restoreSchedulesWhenArchiveCarriesAMatchingAdoptedTombstone` | matching adopted tombstone does schedule |
| `sweepReconcilesPrefixedUnsignedScheduleWithoutClearingHide` | pre-fix pending+expired schedule, no tombstone → schedule cleared, **not** hard-deleted |
| `sweepKeepsAScheduleBackedByALocalTombstone` | real soft-delete keeps its clock |
| `restoreHoldsTenUnsignedHidesAndAppliesNone` | 10 → hold, none hidden |
| `restoreAppliesNineUnsignedHidesWithoutScheduling` | 9 → all hidden, none scheduled |
| `restoreHidesCollectionWithoutSchedulingWhenUnsigned` | collection sibling |
| `forgedDeletionScheduleCannotHardDeleteAWorkOnTheNextLaunch` | updated: unsigned hide, no schedule (was: start a fresh local window) |

`PreservedWorkTests.twoDeviceConvergenceThroughSoftDeleteAndRestore` still expects a schedule: same-process tests share the device signing key, so B adopts A's tombstone. That is the **trusted** path. Comment added; unsigned coverage lives in `ArchiveDeletionScheduleTests`.

## Mutation evidence

A 0.000s failure would be a setup throw and does not count. These are assertion failures.

### Mutation A — revert the D8 guard (unsigned `isDeleted` starts/keeps a schedule)

Removed `guard hasTrustedTombstone else { return (true, nil) }`.

`ArchiveDeletionScheduleTests` **RED 1.438s, 4 issues**:

| Test | Duration | Failure |
|---|---|---|
| `unsignedIncomingDeletionNeverSetsAScheduleEvenIfOneWasAlreadyRunning` | **0.018s** | `state.scheduledAt → 1970-01-01 00:08:20 +0000 == nil` (kept the running local countdown) |
| `restoreHidesWithoutSchedulingWhenArchiveHasNoTrustedTombstone` | **0.082s** | `scheduledAt → 2026-11-14 22:26:22 +0000 == nil` (fresh 90-day window) |
| `restoreAppliesNineUnsignedHidesWithoutScheduling` | **0.534s** | `stored.allSatisfy { $0.permanentDeletionScheduledAt == nil }` |
| `restoreHidesCollectionWithoutSchedulingWhenUnsigned` | **0.112s** | collection also scheduled |

Suite 8/12. Log: `/tmp/kudos-d8-mutA2.log`.

### Mutation B — weaker substitute (don't start a *new* clock, but keep an existing one)

```
if !hasTrustedTombstone {
    if localIsPendingDeletion, let localScheduledAt { return (true, localScheduledAt) }
    return (true, nil)
}
```

`ArchiveDeletionScheduleTests` **RED 1.508s, 1 issue**:

| Test | Duration | Failure |
|---|---|---|
| `unsignedIncomingDeletionNeverSetsAScheduleEvenIfOneWasAlreadyRunning` | **0.025s** | `state.scheduledAt → 1970-01-01 00:08:20 +0000 == nil` |

The new-clock cases went green (weaker substitute is almost the fix). The spec requires **clearing** an already-running unsigned clock; this mutation proves that test is load-bearing. Log: `/tmp/kudos-d8-mutB.log`.

Fix restored. `git diff` clean against `5b1077a`.

## GREEN last

`xcodebuild test` on iPhone 17 (`77492544-056E-4D4A-ABB6-7E38CC042A4D`, iOS 26.5), `CODE_SIGNING_ALLOWED=NO`, `-parallel-testing-enabled NO`.

**TEST SUCCEEDED — 1119 tests / 104 suites / 0 failures** (32.425s of test runtime after build). Log: `/tmp/kudos-d8-full.log`.

Key suites:

| Suite | Result |
|---|---|
| `ArchiveDeletionScheduleTests` | **12/12** |
| `PreservedWorkTests` | **17/17** |
| `KudosBackupTests` | **51/51** |
| `PersistenceSyncTests` | **17/17** |
| `FolderSyncTests` | **27/27** |
| `ArchiveTrustBoundaryTests` | **9/9** |
| Full iOS target | **1119/1119**, 104 suites |

Focused pre-mutation GREEN (same destination): `ArchiveDeletionScheduleTests` 12 + `PreservedWorkTests` 17 = **29/29** under `PersistenceGateSuites`.

## Manual remaining

- Review-hold sheet + digest alert after a real folder-sync of ≥10 unsigned hides (unit tests drive `restore()`, not the SwiftUI presentation).
- Recently Deleted "Kept until you delete" label on a device.
- First-sync-from-new-trust hold exemption (deferred; pairing/trust-store unit).

## Out of scope (honoured)

- Did not touch `TombstoneSigning.swift`, Settings UI, or pairing.
- Did not touch `android/`.
- Did not push, did not open a PR.
