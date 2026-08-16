# WP-F revert checks (M1a timestamp reject + exportedAt clamp, M3 privacy stricter-of, M2b)

Local-only verification on `rc-fix/android` (stacked RC). No push. No merge.
Tests were not weakened.

Environment:

- `JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home`
- `ANDROID_HOME=$HOME/Library/Android/sdk`
- `./gradlew :app:testDebugUnitTest`

The previous M1a mutations in this file certified the *broken* clamp-to-`now+24h`
implementation. They have been replaced. M3 / M2b evidence below is unchanged
from the WP-F tree (those production checks were not touched here).

## Production still present

**M1a — reject `> now+24h`, clamp `min(value, exportedAt)`.**
`BackupValidator.parseInstant` throws `BackupError.InvalidDate` when the parsed
instant is more than 24h in the future. It does **not** rewrite the value to
`now + 24h`. When `exportedAt` is supplied, the result is also
`min(parsed, exportedAt)`.

`BackupValidator.validateManifest` parses `exportedAt` first and threads it into
every other archive clock it checks, including `works[].lastModifiedAt`.
`BackupMergeService.parseOptionalInstant` and the inbound mappers take the same
`exportedAt`. Tombstone adopt still pins `lastModifiedAt` to the signed
`createdAt` (TOMB-1) and then applies `min(..., exportedAt)`.

**M3 — privacy stricter-of.** Unchanged. `SettingsRepository.replaceAll` is the
persist path used by `BackupRepository.applyMergeResult`.

**M2b — blank/unknown `recordTypeRaw`.** Unchanged. `toSyncTombstone()` throws
on blank or unknown types.

## M1a Mutation A — drop reject and exportedAt clamp

Change: `parseInstant` returned `parsed` with no `now+24h` reject and no
`exportedAt` clamp.

Command: `./gradlew :app:testDebugUnitTest --tests io.github.cidy02.kudos.backup.BackupTimestampClampTest`

Result: **RED**. JUnit XML `tests=8 failures=6 errors=0 time=0.171`.

Quoted assertions (durations from the testcase `time` attribute):

- `java.lang.AssertionError: expected io.github.cidy02.kudos.backup.BackupError.InvalidDate to be thrown, but nothing was thrown` — `testParseInstant_RejectsFutureDate` — **0.002s**
- `java.lang.AssertionError: expected io.github.cidy02.kudos.backup.BackupError.InvalidDate to be thrown, but nothing was thrown` — `testIngestPaths_RejectFutureTimestamps` — **0.002s**
- `java.lang.AssertionError: expected io.github.cidy02.kudos.backup.BackupError.InvalidDate to be thrown, but nothing was thrown` — `testMerge_RejectsFutureTimestampsOnWorksAndCollections` — **0.032s**
- `java.lang.AssertionError: expected io.github.cidy02.kudos.backup.BackupError.InvalidDate to be thrown, but nothing was thrown` — `testMerge_RejectsFutureExportedAt` — **0.067s**
- `java.lang.AssertionError: forged just-now timestamp must clamp to the snapshot exportedAt expected:<2026-08-09T16:39:35.472645Z> but was:<2026-08-16T16:39:35.472Z>` — `testParseInstant_ClampsToExportedAt` — **0.060s**
- `java.lang.AssertionError: Merged work dateAdded must clamp to exportedAt expected:<2026-08-09T16:39:35.631Z> but was:<2026-08-16T16:39:35.631Z>` — `testMerge_ClampsLastModifiedAtToExportedAt` — **0.003s**

Code restored immediately after.

## M1a Mutation B — reject future, skip exportedAt clamp

Change: `parseInstant` still threw on `> now+24h` but returned `parsed` without
`min(parsed, exportedAt)`.

Same test command.

Result: **RED**. JUnit XML `tests=8 failures=2 errors=0 time=0.14`.

Reject tests stayed GREEN (so Mutation B is not just Mutation A again):

- `testParseInstant_RejectsFutureDate` — **0.005s**
- `testMerge_RejectsFutureExportedAt` — **0.035s**
- `testMerge_RejectsFutureTimestampsOnWorksAndCollections` — **0.010s**
- `testIngestPaths_RejectFutureTimestamps` — **0.003s**

Quoted RED assertions:

- `java.lang.AssertionError: forged just-now timestamp must clamp to the snapshot exportedAt expected:<2026-08-09T16:40:17.873055Z> but was:<2026-08-16T16:40:17.873Z>` — `testParseInstant_ClampsToExportedAt` — **0.056s**
- `java.lang.AssertionError: Merged work dateAdded must clamp to exportedAt expected:<2026-08-09T16:40:17.980Z> but was:<2026-08-16T16:40:17.980Z>` — `testMerge_ClampsLastModifiedAtToExportedAt` — **0.018s**

The merge-entry dateAdded assertion is load-bearing: `sanitizeArchivedLastModifiedAt`
still clamps `lastModifiedAt` even without the parseInstant clamp, so a lastModified-only
check would have stayed GREEN. The dateAdded check fails because ingest now goes
through `parseInstant(..., exportedAt)`.

Code restored immediately after.

## M3 Mutation A — incoming backup overwrites privacy

(Unchanged from the WP-F tree. Production was not edited in this pass.)

Change: `replaceAll` wrote incoming `hideMatureContent`, `matureContentMode`, and `requireBiometricToReveal` with no stricter-of.

Command: `./gradlew :app:testDebugUnitTest --tests io.github.cidy02.kudos.data.preferences.SettingsRepositoryPrivacyTest`

Result: **RED**. `1 test completed, 1 failed`. Wall clock **real 2.39s** (suite XML time `0.11s`).

Quoted assertion:

- `java.lang.AssertionError: hideMatureContent must stay true under stricter-of restore` — `testPrivacyStricterOf` (`SettingsRepositoryPrivacyTest.kt`)

## M3 Mutation B — weaker substitute (OR hide flag only)

Change: kept `hideMatureContent` OR, but applied incoming `matureContentMode` and `requireBiometricToReveal` unchanged.

Result: **RED**. `1 test completed, 1 failed`. Wall clock **real 6.14s** (suite XML time `0.243s`).

Quoted assertion:

- `java.lang.AssertionError: matureContentMode must stay Hide under stricter-of restore expected:<Hide> but was:<Obscure>` — `testPrivacyStricterOf`

## M2b

Mapper already throws on blank (`"   "`) and unknown (`"maliciousType"`) `recordTypeRaw`.
`testM2b_MergeRejectsBlankOrUnknownTombstone` hits `BackupMergeService.merge`.

## GREEN last

After all restores (production reject + exportedAt clamp present):

Full `:app:testDebugUnitTest` tallied from `android/app/build/test-results/testDebugUnitTest/*.xml`:
**854 tests, 0 failures, 0 errors, 0 skipped** (230 suites).
