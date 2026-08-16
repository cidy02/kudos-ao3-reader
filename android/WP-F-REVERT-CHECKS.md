# WP-F revert checks (M1a timestamp clamp, M3 privacy stricter-of, M2b)

Local-only verification on `security-fixes/wp-f-android`. No push. No merge. Tests were not weakened.

Environment:

- `JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home`
- `ANDROID_HOME=$HOME/Library/Android/sdk`
- `./gradlew :app:testDebugUnitTest`

## Production still present

**M1a — archive timestamp clamp.** `BackupValidator.parseInstant` still rejects far-future clocks by clamping to `now + 24h`:

```144:156:android/app/src/main/java/io/github/cidy02/kudos/backup/BackupValidator.kt
    fun parseInstant(value: String, field: String): Instant {
        val parsed = try {
            Instant.parse(value)
        } catch (_: DateTimeParseException) {
            try {
                OffsetDateTime.parse(value).toInstant()
            } catch (_: DateTimeParseException) {
                throw BackupError.InvalidDate(field, value)
            }
        }
        val maxAllowed = Instant.now().plus(24, java.time.temporal.ChronoUnit.HOURS)
        return if (parsed.isAfter(maxAllowed)) maxAllowed else parsed
    }
```

Ingest (`BackupWork.toSavedWork`, `BackupCollection.toWorkCollection`, `BackupReadingQueue.toReadingQueue`) and merge (`BackupMergeService.merge` via those mappers plus `parseOptionalInstant`) all go through this helper.

**M3 — privacy stricter-of.** `SettingsRepository.replaceAll` is the persist path used by `BackupRepository.applyMergeResult`. It ORs `hideMatureContent` and `requireBiometricToReveal`, and keeps local `Hide` over incoming `Obscure`:

```205:215:android/app/src/main/java/io/github/cidy02/kudos/data/preferences/SettingsRepository.kt
            prefs[Keys.HideMatureContent] = current.privacy.hideMatureContent || settings.privacy.hideMatureContent
            
            val newMatureMode = if (current.privacy.matureContentMode == MatureContentMode.Hide) {
                MatureContentMode.Hide
            } else {
                settings.privacy.matureContentMode
            }
            prefs[Keys.MatureContentMode] = newMatureMode.storageValue
            
            val newBiometric = current.privacy.requireBiometricToReveal || settings.privacy.requireBiometricToReveal
            prefs[Keys.RequireBiometricToReveal] = newBiometric
```

**M2b — blank/unknown `recordTypeRaw`.** `BackupTombstone.toSyncTombstone()` throws `IllegalArgumentException` when the trimmed type is empty or not in the known allow-list. It does **not** default to `savedWork`. `BackupMergeService.merge` calls that mapper, so a hostile tombstone cannot be indexed as `SAVED_WORK`.

Hole closed in this pass:

- Existing ingest tests never set work `lastModifiedAt`, so a clamp-`dateAdded`-only substitute stayed GREEN on works.
- No production-entry merge test existed for the clamp or for M2b tombstone rejection.
- Privacy assertions had no messages (harder to quote on RED).

## M1a Mutation A — drop the clamp (far-future dates win)

Change: `parseInstant` returned `parsed` with no `now + 24h` cap.

Command: `./gradlew :app:testDebugUnitTest --tests io.github.cidy02.kudos.backup.BackupTimestampClampTest`

Result: **RED**. `4 tests completed, 3 failed`. Wall clock **real 4.31s** (`/usr/bin/time -p`; suite XML time `0.041s`).

Quoted assertions:

- `java.lang.AssertionError: expected:<2026-08-16T21:04:04Z> but was:<2026-08-25T21:04:04Z>` — `testParseInstant_ClampsFutureDate`
- `java.lang.AssertionError: Work dateAdded should be clamped` — `testIngestPaths_ClampFutureTimestamps`
- `java.lang.AssertionError: Merged work dateAdded should be clamped` — `testMerge_ClampFutureTimestampsOnWorksAndCollections`

Code restored immediately after.

## M1a Mutation B — weaker substitute (clamp `dateAdded` only)

Change: `parseInstant` clamped only when `field` contained `dateAdded`. `lastModifiedAt` / queue clocks passed through unclamped.

Same test command.

Result: **RED**. `4 tests completed, 2 failed`. Wall clock **real 4.06s** (suite XML time `0.037s`).

Quoted assertions:

- `java.lang.AssertionError: Work lastModifiedAt should be clamped` — `testIngestPaths_ClampFutureTimestamps`
- `java.lang.AssertionError: Merged work lastModifiedAt should be clamped` — `testMerge_ClampFutureTimestampsOnWorksAndCollections`

`testParseInstant_ClampsFutureDate` stayed GREEN (field name is `dateAdded`), which is why the lastModified / merge assertions are load-bearing.

Code restored immediately after.

## M3 Mutation A — incoming backup overwrites privacy

Change: `replaceAll` wrote incoming `hideMatureContent`, `matureContentMode`, and `requireBiometricToReveal` with no stricter-of.

Command: `./gradlew :app:testDebugUnitTest --tests io.github.cidy02.kudos.data.preferences.SettingsRepositoryPrivacyTest`

Result: **RED**. `1 test completed, 1 failed`. Wall clock **real 2.39s** (suite XML time `0.11s`).

Quoted assertion:

- `java.lang.AssertionError: hideMatureContent must stay true under stricter-of restore` — `testPrivacyStricterOf` (`SettingsRepositoryPrivacyTest.kt`)

Code restored immediately after (then re-applied as Mutation B).

## M3 Mutation B — weaker substitute (OR hide flag only)

Change: kept `hideMatureContent` OR, but applied incoming `matureContentMode` and `requireBiometricToReveal` unchanged.

Same test command.

Result: **RED**. `1 test completed, 1 failed`. Wall clock **real 6.14s** (suite XML time `0.243s`).

Quoted assertion:

- `java.lang.AssertionError: matureContentMode must stay Hide under stricter-of restore expected:<Hide> but was:<Obscure>` — `testPrivacyStricterOf`

Code restored immediately after.

## M2b

Mapper already throws on blank (`"   "`) and unknown (`"maliciousType"`) `recordTypeRaw`. Existing `testM2b_BlankOrUnknownTombstoneRejected` hits `toSyncTombstone()` directly.

Added production-entry `testM2b_MergeRejectsBlankOrUnknownTombstone`: `BackupMergeService.merge` of a package whose only payload is a blank or unknown tombstone throws `IllegalArgumentException`. The hostile type never becomes `savedWork`.

## GREEN last

After all restores (production diffs empty vs pre-mutation):

Targeted classes (clamp + restore-security + privacy):

| Suite | tests | failures |
|---|---:|---:|
| `BackupTimestampClampTest` | 4 | 0 |
| `BackupRestoreSecurityTest` | 4 | 0 |
| `SettingsRepositoryPrivacyTest` | 1 | 0 |
| **targeted total** | **9** | **0** |

Full `:app:testDebugUnitTest`: **798 tests, 0 failures, 0 errors, 0 skipped** (224 suites). Wall clock **real 16.40s**.
