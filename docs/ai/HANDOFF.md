# AI Handoff

## Handoff - T-58 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `02ad56a`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/build.gradle.kts`
- `android/gradle/libs.versions.toml`
- `android/app/build.gradle.kts`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupErrors.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupExporter.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupImporter.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupJson.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupManifest.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMappers.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupPaths.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupValidator.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupVersion.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/KudosBackup.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt`

Dependencies added:

- Kotlin serialization compiler Gradle plugin
  `org.jetbrains.kotlin.plugin.serialization` using the existing Kotlin/Compose
  compiler version `2.3.21`.
- No new runtime JSON dependency; Phase 3 uses the existing
  `kotlinx-serialization-json` runtime added in Phase 2.

Backup format implemented:

- Current Apple v1 directory-backed `.kudosbackup` manifest decoding and
  best-effort directory import where Android can access the package path.
- Android v2 ZIP `.kudosbackup` export/import with internal paths:
  `manifest.json`, `Works/<UUID>.epub`, and `Fonts/<fileName>`.
- v2 manifest includes `exportedBy`, optional collections, saved searches,
  v2 work stats/update fields, and Readium locator metadata. v2-only fields stay
  optional and are not treated as Apple v1 parity.

Import/export behavior:

- JSON is UTF-8 and decoded with unknown-field tolerance.
- UUIDs normalize to canonical lowercase for work, collection, and saved-search
  identity.
- Dates validate as ISO-8601 instants.
- ZIP import rejects missing manifests, unsupported versions, invalid JSON,
  invalid dates, invalid UUIDs, unsafe paths, absolute paths, traversal, malformed
  `Works/` or `Fonts/` entries, duplicate entries, truncated archives, and entries
  over the configured size limits.
- v2 ZIP output is deterministic where practical: manifest first, then sorted
  work/font entries with stable ZIP timestamps.

Merge behavior:

- Works merge by UUID without deleting local-only works.
- Local EPUB state is preserved when the backup lacks the EPUB file; a new work
  whose manifest claims `hasEPUB = true` is restored with `hasEpub = false` when
  the file is missing.
- Backup EPUB bytes are returned as files-to-write by work UUID for later
  app-private atomic persistence.
- User tags are trimmed, deduplicated, and unioned with local assignments.
- Bookmarks merge by URL and update title/date to match Apple restore behavior.
- Collections merge by UUID; name collisions with different UUIDs create a
  separate suffixed restored collection.
- Fonts merge by safe filename. Colliding different/unknown bytes are suffixed,
  and a restored `readerFontID` is retargeted to the suffixed file when needed.
- Settings are applied after data merge with enum/range validation. Missing or
  unsafe custom font references fall back to `system`.
- `readiumLocator` is preserved for same-platform precision; portable resume
  fields `lastSpineIndex` and `lastScrollFraction` are preserved as the
  cross-platform fallback.

Tests added:

- `BackupV1ManifestDecodeTest`
- `BackupV2ZipDecodeTest`
- `BackupV2ZipExportTest`
- `BackupRoundTripBasicTest`
- `BackupMergeDoesNotDeleteExistingWorkTest`
- `BackupMergeDoesNotDeleteExistingEpubTest`
- `BackupMissingEpubMarksHasEpubFalseTest`
- `BackupUserTagMergeTest`
- `BackupCollectionMergeTest`
- `BackupBookmarkMergeByUrlTest`
- `BackupFontMissingReaderFontFallbackTest`
- `BackupRejectsUnsupportedVersionTest`
- `BackupRejectsMissingManifestTest`
- `BackupRejectsPathTraversalTest`
- `BackupRejectsAbsolutePathTest`
- `BackupRejectsInvalidJsonTest`
- `BackupRejectsTruncatedZipTest`
- `BackupRejectsDuplicateEntryTest`
- `BackupPreservesLegacyProgressFieldsTest`
- `BackupPreservesReadiumLocatorAsPlatformSpecificDataTest`

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:compileDebugKotlin`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug`

Results:

- `:app:compileDebugKotlin` passed.
- First focused `:app:testDebugUnitTest` run found a test-fixture issue: Java
  `ZipOutputStream` refuses duplicate entries before the importer can inspect
  them. Fixed by hand-writing the duplicate-entry ZIP fixture.
- Final `:app:testDebugUnitTest` passed: 35 tests, 0 failures.
- Final `:app:assembleDebug` passed.
- Final `:app:lintDebug` passed and wrote
  `android/app/build/reports/lint-results-debug.html`.

Known gaps:

- Storage Access Framework picker/share-sheet wiring remains placeholder-only.
- Backup services return file bytes/maps for later app-private staging and atomic
  writes; production Room/DataStore persistence and file commit orchestration are
  not wired yet.
- Apple v2 ZIP import/export support is not implemented in this branch.
- No AO3 networking, parsing, search requests, auth, Readium, EPUB download/import
  from AO3, account lists, comments, or production Library browsing/filtering.

Next recommended agent: Claude or Codex

Recommended next phase:

Phase 4 AO3 networking core from an approved prompt. Keep it limited to request
policy/client foundations and tests; do not start search parsing, auth, reader,
or production Library UI unless the phase prompt explicitly allows it.

## Handoff - T-57 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `c1a7475`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/build.gradle.kts`
- `android/gradle/libs.versions.toml`
- `android/app/build.gradle.kts`
- `android/app/schemas/io.github.cidy02.kudos.data.local.KudosDatabase/1.json`
- `android/app/src/main/java/io/github/cidy02/kudos/core/model/**`
- `android/app/src/main/java/io/github/cidy02/kudos/data/local/**`
- `android/app/src/main/java/io/github/cidy02/kudos/data/preferences/**`
- `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsScreen.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/**`

Dependencies added:

- KSP Gradle plugin `2.3.9`
- Room runtime/ktx/compiler/testing `2.8.4`
- DataStore Preferences `1.2.1`
- Kotlinx serialization JSON `1.11.0`
- AndroidX Test core `1.7.0`
- JUnit `4.13.2`
- Robolectric `4.16.1`

Database schema summary:

- Room database: `KudosDatabase`, name `kudos.db`, schema version `1`, schema
  export enabled and committed.
- Tables: `works`, `user_tags`, `work_tag_cross_refs`, `collections`,
  `collection_work_cross_refs`, `bookmarks`, `custom_fonts`, `saved_searches`.
- User tags and collections are normalized with cross-reference tables.
- AO3 tag groups are stored as JSON-encoded string-list columns for Phase 2.
- Date/time values use `java.time.Instant` converted to epoch milliseconds.
- `comments`, `hits`, `knownChapterCount`, and `lastUpdateCheck` are nullable
  Android/local/future-compatible fields, not current Apple v1 backup parity
  fields.
- Production destructive migrations were not enabled.

Settings defaults implemented:

- `readerFontID = "system"`
- `readerMode = "scroll"`
- `readerTwoPage = false`
- `readerCustomize = false`
- `readerBoldText = false`
- `readerFontPt = 18`
- `readerLineHeight = 1.65`
- `readerLetterSpacing = 0`
- `readerWordSpacing = 0`
- `readerMargin = 28`
- `readerJustify = false`
- `confirmBeforeDelete = true`
- `hideMatureContent = true`
- `matureContentMode = "obscure"`
- `requireBiometricToReveal = false`
- `appTheme = "light"`
- `readerTheme = "light"`
- `matchAppReaderTheme = true`
- `accentColorHex = "#990000"`

Commands run:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:lintDebug`

Results:

- `:app:assembleDebug` passed.
- `:app:testDebugUnitTest` passed: 11 tests, 0 failures, 0 errors.
- `:app:lintDebug` passed with `0 errors, 6 warnings`; the warnings are the same
  version-availability notices carried from Phase 1.

Known gaps:

- No AO3 networking, parsing, search requests, auth, backups, Readium, EPUB
  import/download, account lists, comments, or production Library queries.
- DataStore repository exists and is tested, but app-wide runtime settings wiring
  remains minimal; Settings screen only displays default values.
- Backup import/export is not implemented; `BackupSettings` only preserves the
  contract field names for future Phase 3 work.
- Robolectric is included because Room DAO tests run under local JVM unit tests,
  not instrumentation.

Next recommended agent: Claude or Codex

Recommended next phase:

Phase 3 backup v1/v2 compatibility from an approved prompt. Keep it limited to
manifest decoding/encoding, ZIP safety, merge semantics, fixtures, and tests.

## Handoff - T-56 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `00a25b6`

Files changed:

- `TASKS.md`
- `docs/ai/HANDOFF.md`
- `android/settings.gradle.kts`
- `android/build.gradle.kts`
- `android/gradle.properties`
- `android/.gitignore`
- `android/gradle/libs.versions.toml`
- `android/gradlew`
- `android/gradlew.bat`
- `android/gradle/wrapper/gradle-wrapper.jar`
- `android/gradle/wrapper/gradle-wrapper.properties`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/res/drawable/ic_kudos_mark.xml`
- `android/app/src/main/res/values/styles.xml`
- `android/app/src/main/res/xml/backup_rules.xml`
- `android/app/src/main/res/xml/data_extraction_rules.xml`
- `android/app/src/main/java/io/github/cidy02/kudos/**`

Summary:

Phase 1 scaffold only. Added a native Android project under `android/` with
Gradle Kotlin DSL, a Gradle 9.4.1 wrapper, AGP 9.2.0, Kotlin/Compose compiler
2.3.21, Compose BOM 2026.06.00, Material 3, and placeholder Compose navigation.
The app shell has Home, Library, Browse, Account, global Search, Work Detail,
Reader placeholder, Settings, and Backup placeholder routes. It intentionally
does not implement AO3 networking, parsing, auth, backup import/export, Readium,
Room, DataStore, EPUB handling, account data, comments, or production Library
behavior.

Verification:

- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:testDebugUnitTest`
- `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:lintDebug`

Results:

- `:app:assembleDebug` passed.
- `:app:testDebugUnitTest` passed with no unit tests defined yet.
- `:app:lintDebug` passed and wrote `android/app/build/reports/lint-results-debug.html`.
- Lint report has `0 errors, 6 warnings`, all version-availability notices for
  Gradle, AGP, Activity Compose, Lifecycle, Navigation Compose, and the Compose
  compiler plugin.
- First assemble without `ANDROID_HOME` failed because Gradle could not locate
  the Android SDK. Re-running with `ANDROID_HOME=$HOME/Library/Android/sdk`
  succeeded; Gradle installed the licensed Android SDK Platform 37.0 package
  into the local SDK.

Version decisions:

- `minSdk = 26`
- `compileSdk = 37`
- `targetSdk = 37`
- Gradle wrapper `9.4.1`
- Android Gradle Plugin `9.2.0`
- Compose BOM `2026.06.00`
- Compose compiler plugin `2.3.21`

Known risks:

- UI has not been emulator/screenshot verified; verification was build/lint only.
- Placeholder copy and layout are intentionally temporary and should be replaced
  as each contract-backed implementation phase lands.
- Version catalog choices are pinned to the official AGP/Compose baseline used
  for this scaffold; review whether to bump the six lint-reported newer
  versions before Phase 2.
- `ANDROID_HOME` must be set to `$HOME/Library/Android/sdk` in this local
  environment unless Android Studio or shell configuration exports it.

Next recommended agent: Claude or Codex

Next steps:

1. Review the Phase 1 scaffold against the Phase 0 contracts and prompt scope.
2. If accepted, start Phase 2 only from the approved next-phase prompt.
3. Keep AO3 networking/parsing/auth, backups, Room/DataStore, Readium, EPUB import,
   and account/comment behavior out of the scaffold until their phases are approved.

## Handoff - T-55 - Codex - 2026-06-26

Branch: `kudos-ao3-reader-android`

Base commit: `69e92a6`

Files changed:

- `TASKS.md`
- `AGENTS.md`
- `docs/android/ANDROID_PORT_PLAN.md`
- `docs/contracts/CORE_BEHAVIOR_CONTRACT.md`
- `docs/contracts/BACKUP_FORMAT.md`
- `docs/contracts/AO3_BEHAVIOR_CONTRACT.md`
- `docs/contracts/READER_STATE_CONTRACT.md`
- `docs/contracts/SETTINGS_CONTRACT.md`
- `docs/contracts/UI_PARITY_CHECKLIST.md`
- `docs/ai/HANDOFF.md`

Summary:

Phase 0 docs only. Added the approved Android port plan from
`Kudos_Android_Port_Comprehensive_Plan_CODEX_READY.md`, contract skeletons,
Android branch policy notes, current Apple v1 backup facts, explicit v2 backup
additions, AO3 sort/concurrency notes, and this handoff. No Android Gradle,
Compose, Room, DataStore, networking, backup, reader, auth, or parser
implementation was added.

Commands run:

- `git branch --show-current`
- `git status --short`
- `git branch -a --list '*kudos-ao3-reader-android*'`
- `git switch -c kudos-ao3-reader-android`
- `mkdir -p docs/android docs/contracts docs/ai`
- `cp /Users/cidy02/Downloads/Kudos_Android_Port_Comprehensive_Plan_CODEX_READY.md docs/android/ANDROID_PORT_PLAN.md`
- `git rev-parse --short HEAD`

Tests passing:

- Not run; documentation-only Phase 0 change.

Tests failing/not run:

- Swift tests not run.
- Android tests unavailable because no Android scaffold exists yet.

Known risks:

- `docs/android/ANDROID_PORT_PLAN.md` is copied from the external plan and should
  be reviewed for any remaining wording drift before Phase 1.
- Contract docs are skeletons, not complete executable specs.
- Phase 1 remains blocked until Codex/Claude review accepts these docs.

Needs human decision:

- Confirm Android `minSdk`, `targetSdk`, desugaring policy, and first release
  channel during Phase 0/Phase 1 planning.

Next recommended agent: Codex

Next steps:

1. Review the Phase 0 docs for consistency with the current repo.
2. If accepted, hand to Claude for Phase 1 scaffold on `kudos-ao3-reader-android`.
3. Keep Phase 1 limited to Gradle/app shell/navigation/theme placeholders only.
