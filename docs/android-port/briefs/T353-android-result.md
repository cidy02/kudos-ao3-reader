# T-353 Android result

## Files changed

- Task/docs: `TASKS.md`, `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`,
  `docs/REGRESSION_TEST_MATRIX.md`.
- Room/domain: `KudosDatabase.kt`, `KudosDatabaseMigrations.kt`, `WorkEntity.kt`,
  `EntityMappers.kt`, `SavedWork.kt`, `KudosAppContainer.kt`, and exported schema
  `13.json`.
- Capture/import: `WorkImporter.kt`, `WorkRepository.kt`, `ExternalFileImport.kt`,
  `DownloadDateDetector.kt`, `DocumentImportPreparation.kt`,
  `DownloadDateImportConfirmation.kt`, and `KudosApp.kt`.
- Work detail/sort: `WorkDetailScreen.kt`, `WorkDetailMyCopySheet.kt`,
  `LibrarySort.kt`, and `LibraryQuery.kt`.
- Backup: `BackupManifest.kt`, `BackupMappers.kt`, and `BackupMergeService.kt`.
- Tests: `DownloadDateDetectorTest.kt`, `DownloadedAtBackupTest.kt`,
  `KudosDatabaseMigrationTest.kt`, `RoomDaoTest.kt`, `LibraryQueryTest.kt`, and
  `WorkLifecycleTest.kt`.

## Migration

Room **12 → 13**, adding nullable `works.downloadedAt INTEGER`. Existing rows are
left null. The production migration chain and current-schema assertions now include
13.

## Verification and uncertainties

- `android/Scripts/check-invariants.sh`: passed.
- `DownloadDateDetectorTest`: 6/6 passed through a direct Kotlin/JUnit run,
  including `2026-03-03T14:53:11.321543+00:00` read from an OPF.
- `DownloadDateDetector.kt`, `ExternalFileImport.kt`, and
  `DocumentImportPreparation.kt` compile through the standalone Kotlin compiler.
- Gradle could not start in the sandbox: its `FileLockContentionHandler` opens a
  local socket and failed with `java.net.SocketException: Operation not permitted`.
  Claude still needs to run the normal Gradle gate and let Room/KSP regenerate the
  schema-13 identity hash; `13.json` is structurally updated from schema 12 but its
  generated identity hash could not be refreshed here.
- The brief forbids touching `settings/`, while the Settings file-import launcher is
  implemented in `settings/SettingsPages2.kt`. I left that owned file untouched.
  Open/Share with Kudos now has the full single/batch confirmation flow, but the
  Settings launcher still needs the same shared `prepareDocumentImports` /
  `DownloadDateImportConfirmation` wiring by that area's owner.
- Android's existing local-file importer does not deduplicate user imports, so there
  is no existing local record for that path to preserve. AO3 re-downloads do preserve
  an already captured `downloadedAt`; local-import dedup remains a pre-existing gap.
- UI was not visually verified on a device or emulator.
