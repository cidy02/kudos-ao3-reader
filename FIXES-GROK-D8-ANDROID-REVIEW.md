# D8 Android — review of Gemini's commits + remaining work

Local only. No push, no PR. Worktree: `/Users/cidy02/kudos-d8-android`.
Branch: `d8-fix/android`.

Implementer / reviewer: Grok 4.6. Spec: `/Users/cidy02/kudos-fix-tombstone/D8-FIX-SPEC.md`.
iOS sibling (behavior reference only): `/Users/cidy02/kudos-d8-ios` on `d8-fix/ios`.

| SHA | What |
|---|---|
| `2cc8534` | Gemini: clock-gate helper + merge call sites |
| `0e989dc` | Gemini: one-time reconciliation (work path used recency; see review) |
| `6d901ec` | This pass: recon existence-only, hold/notify, tests, notes |

This report is the independent review of Gemini's two commits, plus what was
completed after that review. It does not rubber-stamp the earlier work.

## Premise check — is "gate the clock" sufficient on Android?

The spec says gating `permanentDeletionScheduledAt` is enough if Android
`hardDelete` is reachable only via the expired-soft-delete sweep or an
explicit user tap.

Verified against this tree:

| Caller | Kind | Path |
|---|---|---|
| `WorkRepository.sweepExpiredSoftDeletes` | production, automatic | `WorkRepository.kt` → `hardDelete` |
| `WorkRepository.sweepExpiredCollectionSoftDeletes` | production, automatic | → `hardDeleteCollection` |
| `ReadingQueueRepository.sweepExpiredQueueSoftDeletes` | production, automatic | → `hardDeleteQueue` |
| Recently Deleted "Delete forever" | production, first-party tap | `RecentlyDeletedScreen.kt` |
| `WorkRepository.removeFromLibrary` | legacy wrapper around `hardDelete` | everyday UI uses `softDelete`; grep of production Compose call sites shows `softDelete` on Library / Work Detail / bulk bar |

No unsigned-data path calls `hardDelete` except the scheduled sweep. The
claim holds. The clock gate is the right fix. `hardDelete` was not touched.

## Review of Gemini's two commits

### `2cc8534` — `restoredDeletionState` + call sites

**Verdict: the clock-gate helper and the three merge call sites are sound.**

`restoredDeletionState` matches the spec rule table and the iOS
`archivedDeletionState` behavior:

| Incoming | Trusted tombstone? | Result |
|---|---|---|
| `isDeleted != true` | n/a | `(false, null)` |
| `isDeleted == true` | no | `(true, null)` — hide, **clear** any running local schedule |
| `isDeleted == true` | yes, local already pending + scheduled | keep the local schedule |
| `isDeleted == true` | yes, otherwise | start `now + RECOVERY_WINDOW` |

Call-site wiring (committed code, not the later uncommitted hold attempt):

| Record | Call site | Trust signal | Match? |
|---|---|---|---|
| Work | `BackupMergeService.merge` work loop | `tombstoneIndex.suppressesWorkResurrection(archived)` | Yes — Android analog of iOS `suppressesResurrection` (AO3 ID → URL → record ID, tombstone at least as new as incoming) |
| Collection (existing LWW) | `mergeCollections` | `collectionResolution == SUPPRESS_STALE` | Yes — same encoding iOS used (`hasTrustedCollectionDeletion`) |
| Queue (existing LWW) | `mergeQueues` | `queueResolution == SUPPRESS_STALE` | Yes |
| Collection / queue (new-to-device) | after a `SUPPRESS_STALE` early-return | `== SUPPRESS_STALE` again | Dead code. New deleted collections are skipped entirely (`if (archived.isDeleted == true) return`). New queues that survive the tombstone check can never have `SUPPRESS_STALE`. Harmless: default `hasTrustedTombstone = false` is the conservative value. Not a D8 miss on the existing-record path the attack uses. |
| `replaceCollections` / default mapper args | no explicit trust flag | defaults to `false` | Conservative. File Replace is a first-party import, not the unsigned sync-folder attack. |

`mergeWork` preserves the restored deletion fields when incoming wins and
keeps local deletion state when it does not. Correct.

Mapper defaults `hasTrustedTombstone = false`. Any missed call site fails
closed (hide, no clock). Safe.

### `0e989dc` — `D8ReconciliationMigration`

**Verdict: the launch ordering and the collection/queue existence check are
sound. The work path had a real bug.**

What was right:

- Runs in `KudosApplication` **before** `sweepExpiredSoftDeletes` /
  collection / queue sweeps. That is the required "before the next sweep
  can fire" placement.
- One-time DataStore flag; completion is written only at the end, so a
  mid-pass crash retries.
- DAO queries select `isDeleted = 1 AND permanentDeletionScheduledAt IS NOT NULL`
  for all three types. Hide state is not cleared.
- Collections / queues used `collectionResolution(id, Instant.MIN) == SUPPRESS_STALE`.
  `Instant.MIN` is not after any real tombstone, so this is existence-only.
  Correct for those two types.

What was wrong:

1. **Works used `suppressesWorkResurrection(work.toBackupWork())`.** That
   helper requires `tombstone.lastModifiedAt >= work.lastModifiedAt`. The
   spec (and the independently verified iOS pass) require **existence
   only**: "any matching local `SyncTombstone` means a trusted delete was
   recorded here." A first-party soft-delete whose `lastModifiedAt` was
   later bumped (merge, metadata touch) would have been treated as
   unsigned and **disarmed**. That is a false clear of a legitimate clock.
2. **`toBackupWork()` does not populate `ao3WorkID`**, so the AO3-id tier
   of `suppressesWorkResurrection` was dead on this path. URL / record-id
   still worked, but the identity chain was not the one the spec asked
   for.
3. **`KudosApplication` referenced `D8ReconciliationMigration` without
   importing it.** Compile break in the committed file. Fixed.

### Uncommitted work left in the tree (Gemini, incomplete)

Not part of the two commits, but present when this review started. It was
**not sound** and did not compile:

- `mergeCollections` / `mergeQueues` assigned `summary = summary.copy(...)`.
  `summary` is a local in `merge()`, not in scope in those private
  functions.
- After merge, `BackupRepository.importPackage` threw
  `UnsignedHidesAnomaly` and refused the **entire** package. The spec and
  the iOS implementation hold only the unsigned *hides*; other merge work
  still proceeds.
- `testAnomalyHold_10UnsignedHides` only asserted a count. It used
  `"…1111$i"` IDs that are not valid UUIDs for `i` in 1..9
  (`canonicalUuid` would throw). It did not assert that hides were held.
- `BackupRestoreSecurityTest` still encoded the **old** bug ("unsigned
  `isDeleted` starts `now + RECOVERY_WINDOW`").

That incomplete hold was discarded and rewritten.

## What was completed after the review

### Reconciliation fix

`D8ReconciliationMigration` now uses existence-only helpers on
`TombstoneIndex`:

- works: AO3 id from `sourceUrl` → canonical URL → record id
- collections / queues: record id

Recency is not consulted. The `Instant.MIN` hack is gone.

### Notify-on-use + anomaly hold

Ported the iOS *behavior* into Android's merge shape:

- `BackupMergeService.merge` pre-scans unsigned **work** hides that this
  pass would actually apply (same LWW / MERGE-add-only / suppress rules
  as the restore loop).
- Floor `UNSIGNED_HIDE_HOLD_FLOOR = 10`.
- ≥ 10: apply **none** of those hides; other merge work still proceeds.
  Summary carries `unsignedHidesHeld`, titles, and work ids.
- < 10: apply hide-without-schedule; `unsignedHidesApplied` for a digest.
- `BackupRepository.importPackage` / `importV2ZipBytes` apply the merge
  (they do **not** throw the whole batch away) and record the result on
  `UnsignedDeletionReview`.
- `KudosApp` presents the review dialog ("N works from … want to be
  hidden") and the below-floor digest. Confirm calls
  `BackupRepository.applyHeldUnsignedHides` — hide, no clock, no
  tombstone.
- **First-sync-from-new-trust exemption: deferred.** Same reason as iOS:
  no cheap "just granted" signal; pairing / Settings UI are out of scope.
- Recently Deleted: `SavedWork` has no `deletedOnDeviceID`. Did not
  invent storage. Nil schedule now labels **"Kept until you delete"**
  instead of a deleted-date line that implied a countdown.

Collection / queue unsigned hides are still clock-gated (hide, no
schedule) but are **not** part of the hold floor. That matches the spec
copy ("N works …") and the iOS implementation.

### Docs

`android/PHASE1-NOTES.md` and `android/PHASE2-NOTES.md` document the
clock-gate rule, the one-time existence-only reconciliation pass, and
the hold (hold-the-hides, not reject-the-batch).

## Tests

Production entries: `restoredDeletionState`, `BackupMergeService.merge`,
`BackupRepository.importPackage`, `D8ReconciliationMigration.runIfNeeded`,
`BackupRepository.applyHeldUnsignedHides`.

`BackupRestoreSecurityTest` (14):

| Test | Asserts |
|---|---|
| `unsignedIncomingDeletionNeverSetsAScheduleEvenIfOneWasAlreadyRunning` | gate clears a running local schedule |
| `trustedTombstoneStartsAFreshLocalWindow` / `trustedTombstoneKeepsAnAlreadyRunningLocalCountdown` | trusted path |
| `incomingUndeleteClearsBothFields` | `isDeleted=false` still clears |
| `mergeHidesWithoutSchedulingWhenArchiveHasNoTrustedTombstone` | `merge()` hide, `scheduledAt == null` |
| `mergeSchedulesWhenLocalTrustedTombstoneMatches` | matching local tombstone does schedule |
| `mergeHoldsTenUnsignedHidesAndAppliesNone` | 10 → hold, none hidden |
| `mergeAppliesNineUnsignedHidesWithoutScheduling` | 9 → all hidden, none scheduled |
| `mergeHidesCollectionWithoutSchedulingWhenUnsigned` | collection sibling |
| old hostile-overlay / past-schedule cases | updated from "recompute a 90-day clock" to hide-without-schedule |

`D8ReconciliationMigrationTest` (7):

| Test | Asserts |
|---|---|
| `runIfNeededClearsUnsignedScheduleWithoutClearingHide` | pre-fix pending+expired, no tombstone → schedule cleared; hide left |
| `runIfNeededKeepsAScheduleBackedByALocalTombstone` | local tombstone keeps the clock |
| `runIfNeededKeepsScheduleWhenTombstoneIsOlderThanWorkClock` | existence-only: older tombstone still counts (the Gemini recency bug) |
| `runIfNeededClearsCollectionAndQueueSchedulesWithoutLocalTombstones` | all three record types |
| `runIfNeededIsANoOpOnceComplete` | flag prevents a second pass |
| `importPackageHoldsTenUnsignedHidesAndAppliesNone` | production `importPackage` hold |
| `applyHeldUnsignedHidesHidesWithoutSchedulingOrMintingATombstone` | confirm path |

## Mutation evidence

A 0.000s failure that is a setup throw does not count. These are assertion
failures. Logged from
`android/app/build/test-results/testDebugUnitTest/TEST-io.github.cidy02.kudos.backup.BackupRestoreSecurityTest.xml`.

### Mutation A — revert the D8 guard

Removed `if (!hasTrustedTombstone) return RestoredDeletionState(true, null)`.

`BackupRestoreSecurityTest` **RED, 14 tests, 6 failures, 0 errors, suite 0.046s**:

| Test | Duration | Failure |
|---|---|---|
| `unsignedIncomingDeletionNeverSetsAScheduleEvenIfOneWasAlreadyRunning` | 0.000s* | `expected null, but was:<1970-01-01T00:08:20Z>` (kept the running local countdown) |
| `mergeHidesWithoutSchedulingWhenArchiveHasNoTrustedTombstone` | **0.001s** | `expected null, but was:<2026-11-14T23:22:51.187333Z>` (fresh 90-day window) |
| `mergeAppliesNineUnsignedHidesWithoutScheduling` | **0.033s** | `works.all { scheduledAt == null }` |
| `mergeHidesCollectionWithoutSchedulingWhenUnsigned` | **0.001s** | collection also scheduled (`…23:22:51.178393Z`) |
| `testAttack_PastPermanentDeletionDate_UnsignedHidesWithoutScheduling` | **0.003s** | `Unsigned isDeleted must not arm a destruction clock` |
| `testAttack_HostileArchiveDeletionOverlay_HidesWithoutScheduling` | **0.001s** | `Unsigned collection hide must not start a schedule` |

\*JUnit XML rounded a sub-millisecond assertion to `0.0`. The message is
the running local countdown (`1970-01-01T00:08:20Z`), not a setup throw.
The 0.033s nine-hide case is an unambiguous non-zero-duration assertion
failure.

`mergeHoldsTenUnsignedHidesAndAppliesNone` stayed GREEN: the hold skips
applying those hides entirely, so it does not depend on the clock-gate
helper.

### Mutation B — weaker substitute (don't start a *new* clock, keep an existing one)

```
if (!hasTrustedTombstone) {
    if (localIsPendingDeletion && localScheduledAt != null) return (true, localScheduledAt)
    return (true, null)
}
```

`BackupRestoreSecurityTest` **RED, 14 tests, 1 failure, 0 errors, suite 0.047s**:

| Test | Duration | Failure |
|---|---|---|
| `unsignedIncomingDeletionNeverSetsAScheduleEvenIfOneWasAlreadyRunning` | **0.001s** | `expected null, but was:<1970-01-01T00:08:20Z>` |

The new-clock cases went green. The spec requires **clearing** an
already-running unsigned clock; this mutation proves that test is
load-bearing.

Fix restored. Working tree has the guard back.

## GREEN last

`./gradlew :app:testDebugUnitTest` from `android/`,
`JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home`,
`ANDROID_HOME=/Users/cidy02/Library/Android/sdk`.

Tallied from `android/app/build/test-results/testDebugUnitTest/TEST-*.xml`
(231 files), **not** Gradle's summary line:

| | |
|---|---|
| tests | **870** |
| failures | **0** |
| errors | **0** |
| skipped | **0** |

Key suites (same XML):

| Suite | Result |
|---|---|
| `BackupRestoreSecurityTest` | **14/14**, 0.046s |
| `D8ReconciliationMigrationTest` | **7/7**, 0.128s |
| `BackupTrustPhase1Test` | **16/16**, 0.423s |
| `BackupTrustPhase2Test` | **10/10**, 0.188s |

## Manual remaining

- Review-hold dialog + digest after a real folder-sync of ≥10 unsigned
  hides (unit tests drive `merge()` / `importPackage`, not the Compose
  presentation).
- Recently Deleted "Kept until you delete" on a device.
- First-sync-from-new-trust hold exemption (deferred; pairing / trust-store unit).

## Out of scope (honoured)

- Did not touch `TombstoneSigning.kt`, Settings UI, or pairing.
- Did not touch anything outside `android/` except this report.
- Did not push, did not open a PR.
