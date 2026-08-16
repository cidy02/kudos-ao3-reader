# Grok tombstone review fixes (`security-fixes/rc`)

Local only. No push, no PR, no remote branch. Tree: `/Users/cidy02/kudos-fix-rc`. Base still `c241d2f`; these commits sit on `cc83994`.

Implementer: Grok 4.6. Reviewer of the original tombstone work was Claude (see `/Users/cidy02/kudos-fix-tombstone/REVIEW-CLAUDE-TOMBSTONE.md`).

## Commits

| SHA | What |
|---|---|
| `02fa547` | **TOMB-5** — signature-flip no longer reproduces a valid sig |
| `791bba0` | **TOMB-1 + TOMB-2** Android (`BackupMergeService.merge`) + `importPackage` tests |
| `36b9344` | **TOMB-1 + TOMB-3** iOS production (`makeTombstone`, Merge undelete) |
| `9a3d61b` | **TOMB-4** — `sign` / `resignLocalUnsignedIfNeeded` take `defaults` |
| `0b89f6f` | iOS production-entry tests + 130-char assertion wrap |
| `7433016` | **TOMB-9** — wrap Replace Library footer |

## What changed

### TOMB-1 (both platforms) — unsigned `lastModifiedAt` is the suppression key

`PHASE2-CONTRACT.md` signs six fields. `lastModifiedAt` is not one of them, but it is the only field `suppressesResurrection` / `suppressesWorkResurrection` consults.

- **iOS** `KudosBackupService.makeTombstone`: `lastModifiedAt = archived.createdAt`. The RC `min(..., contents.manifest.exportedAt)` clamp is still applied immediately after adopt.
- **Android** `BackupMergeService.merge`: `archived.toSyncTombstone().copy(lastModifiedAt = createdAt)` before verify/trust/adopt.

Lossless: every minting site already sets `lastModifiedAt == createdAt` (`SyncTombstone.init`, `WorkRepository.recordWorkTombstone`).

Tests at the real entry:

- iOS `trustedSignedTombstoneForgedLastModifiedAtCannotPermanentlySuppressWork` → `KudosBackupService.restore`
- Android `importPackagePinsAdoptedTombstoneLastModifiedAtToSignedCreatedAt` → `BackupRepository.importPackage`

### TOMB-2 (Android only) — unsigned `id` must not overwrite a local row

The adopt map is keyed by `id` (`@PrimaryKey`) and written back through `syncTombstoneDao().upsert()`. A trusted signature whose six signed fields were copied onto a *local* tombstone's `id` destroyed that row and resurrected the work it was suppressing.

Fix: `if (tombstonesById.containsKey(incomingKey)) return@forEach`.

iOS is not vulnerable (dedupes on `recordTypeRaw|recordID`, insert-if-absent) and was not changed.

Test: `importPackageDoesNotOverwriteLocalTombstoneRowByUnsignedId` → `importPackage`.

### TOMB-5 (Android) — 1-in-16 flake

`TombstoneSigningTest.signThenVerifyRoundTrip` now flips the last hex char the same way `BackupTrustPhase2Test` already does.

### TOMB-4 (iOS) — injectable trust-store write

`TombstoneSigning.sign(..., defaults:)` / `resignLocalUnsignedIfNeeded` now pass `defaults` into `TombstoneTrustStore.add`. `restoreDoesNotAddIncomingSignerPublicKeyToTrustStore` also asserts `UserDefaults.standard` does not contain the peer pub.

### TOMB-3 (iOS) — Merge undeletes collections and queues

On `.merge`, if an existing collection or queue is `isPendingDeletion`, clear `isPendingDeletion` / `deletedAt` / `permanentDeletionScheduledAt` before applying (same as works). Replace → Merge of the user's real backup now brings them back.

Test: `fileMergeUndeletesPendingDeletionCollectionsAndQueues` → `restore(..., .replaceLibrary)` then `restore(..., .merge)`.

### TOMB-9 (iOS lint)

Wrapped the 155-char Replace Library footer in `SettingsView.swift`. Also wrapped the 130-char standing-tombstone `#expect` in `KudosBackupTests.swift` (same CI `--strict` ceiling; the review listed it under FIX-9).

## Mutation evidence

A 0.000s failure would be a setup throw and does not count. These are assertion failures.

### TOMB-1 Android — revert pin (`copy(lastModifiedAt = createdAt)` removed)

`importPackagePinsAdoptedTombstoneLastModifiedAtToSignedCreatedAt` **RED 3.196s**:

> `Adopted lastModifiedAt must be pinned to the signed createdAt expected:<2026-01-01T00:00:00Z> but was:<2026-08-17T07:19:27.181Z>`

`2026-08-17` is `BackupValidator.parseInstant`'s now+24h clamp of the forged `2099-01-01` — still not the signed `createdAt`. Restored pin → GREEN.

### TOMB-2 Android — revert skip (overwrite by `id` restored)

`importPackageDoesNotOverwriteLocalTombstoneRowByUnsignedId` **RED 3.405s**:

> `incoming signed tombstone must not overwrite a local row by unsigned id expected:<[cccccccc-cccc-4ccc-8ccc-cccccccccccc]> but was:<[dddddddd-dddd-4ddd-8ddd-dddddddddddd]>`

Restored skip → GREEN.

### TOMB-1 iOS — revert pin (`lastModifiedAt = archived.lastModifiedAt`)

`trustedSignedTombstoneForgedLastModifiedAtCannotPermanentlySuppressWork` **RED 0.024s** (`/tmp/grok-tomb-tomb1-red.xcresult`, 44/43/1):

> `Expectation failed: (storedTomb.lastModifiedAt → 2026-08-16 07:24:23 +0000) == (storedTomb.createdAt → 2024-01-01 00:00:00 +0000): Adopted lastModifiedAt must be pinned to the signed createdAt`

That timestamp is the snapshot `exportedAt` after the G5 clamp — proving the clamp alone does not close TOMB-1. Restored pin → GREEN.

## Gates (GREEN last)

**Android** `cd android && ./gradlew :app:testDebugUnitTest`

```
tests=848 failures=0 errors=0 skipped=0
```

(846 at RC tip + the two new `BackupTrustPhase2Test` cases.)

**iOS** filter `KudosTests/PersistenceGateSuites/KudosBackupTests`, destination UDID `C71780B1-35DE-4E5E-ABCD-2AB66BCB28B0`, `-derivedDataPath /tmp/grok-tomb-dd`, no `-sdk iphonesimulator`. Result bundle `/tmp/grok-tomb-green.xcresult`:

```
result: Passed
passedTests: 44
failedTests: 0
totalTestCount: 44
```

A single-test filter of the new TOMB-1 name matched **0** cases (`totalTestCount: 0`); only the suite path is valid. Do not trust `xcodebuild` exit 0 without reading the bundle.

No existing assertion was weakened. `project.pbxproj` was not touched.

## Not closed (out of this brief)

Claude's review also filed these; they were **not** in the assigned list:

| Review | Why still open |
|---|---|
| FIX-6 / G3 | No iCloud KVS entitlement; Settings copy still promises same-Apple-ID auto-pickup |
| FIX-7 | Android Replace still builds the suppressor index from `adoptedIncoming`; iOS Replace ignores suppressors |
| FIX-8 / G2 | Android `AnnotationRepository.deleteAnnotation` still mints no tombstone; next folder sync can resurrect a highlight on the same device |
| STACK note | Confirm RC kept WP-F's reject of blank `recordTypeRaw` (do not restore tombstone's `ifBlank { "savedWork" }`) |

## Working tree

`git status` clean of these fixes after the six commits above. No push.
