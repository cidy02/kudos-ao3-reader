# Brief 2b Result: Back up and restore schema-11 fields

Implemented schema-11 field backup, restore, and merge logic aligned with iOS `KudosBackup.swift` and `PersistenceSync.swift`.

## Files Changed

1. `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupManifest.kt`:
   - Added schema-11 fields with `= null` defaults:
     - `BackupWork`: `keepInProgressOverride`, `bookmarks`, `epubDigest`, `legacyReaderProgress` (`JsonElement?`), `hiddenFromHistoryAt` (`JsonElement?`).
     - `BackupCollection`: `hue`, `colorHex`, `keepsWorksOffline`, `showsOnHome`, `workOrderRaw`.
     - `BackupReadingQueue`: `hue`, `colorHex`, `isPinned`, `keepsWorksOffline`, `notes`.

2. `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMappers.kt`:
   - `toBackupWork`: writes tri-state fields (`legacyReaderProgress`, `hiddenFromHistoryAt`) as `JsonPrimitive` or `JsonNull` (preserved under `explicitNulls = false`); passes `keepInProgressOverride`, `bookmarks ?: 0`, `datePublished`, `dateUpdated`, `ao3SeriesID`, and `epubDigest`/`assetIdentifier` (`ifBlank { null }`). Keeps `freedAt` and `authorIdentitiesJSON` device-local.
   - `toSavedWork`: parses tri-state fields (`null`/`JsonNull` -> `null`), maps dates and strings with fallback defaults.
   - Mappers for collections and queues export and import the five respective fields.

3. `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`:
   - Added `SyncMerge.chosenColor` ported from iOS.
   - `mergeWork`: preserves `freedAt` and `authorIdentitiesJSON` across winning/losing archives; merges tri-state, override, and blank-fill string/integer fields per specification.
   - Added `fillCollectionFields` and `fillQueueFields` helpers, applied across `MERGE`, reconcile-loss, and reconcile-win branches.

4. `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupPhase2FieldsTest.kt`:
   - Added tests covering round-trips, tri-state omission/null/date resolution, local retention of `freedAt`/`authorIdentitiesJSON`, `SyncMerge.chosenColor` parity, collection/queue merge rules, and literal iOS export JSON parsing.

## Items Noted

No open ambiguities; all field mappings and merge branch behaviors matched the iOS reference implementations and brief instructions directly.
