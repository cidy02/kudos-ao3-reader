# Brief 1b Result: Android Demo Library for Screenshots

## Files Changed and Created
- **Created** `android/app/src/main/java/io/github/cidy02/kudos/app/DemoLibrary.kt`: Seeder providing identical sample works, queues, Saved for Later, collections, and Recently Deleted rows as iOS `DemoLibrary.swift`. Uses `EpubBuilder.buildEpub` and `WorkFileStore.writeWorkEpub` for on-device works.
- **Modified** `android/app/src/main/java/io/github/cidy02/kudos/MainActivity.kt`: Checks debug launch extras guarded by `BuildConfig.DEBUG`. Seeds demo library synchronously before `setContent`, dismisses onboarding, and parses session theme. Handles `onNewIntent` when re-launched.
- **Modified** `android/app/src/main/java/io/github/cidy02/kudos/app/KudosApp.kt`: Added `sessionTheme: KudosThemeMode?` and `skipOnboarding: Boolean` parameters to immediately bypass onboarding screens and apply session theme without mutating persistent DataStore preferences.
- **Created** `android/app/src/test/java/io/github/cidy02/kudos/app/DemoLibraryTest.kt`: Robolectric/JVM unit test running against in-memory Room database, verifying work counts (16 total, 15 active, 1 soft-deleted, 1 held copy), queue ordering/counts, collection memberships, and idempotency.

## How Extras Are Read
Guarded entirely inside `if (BuildConfig.DEBUG)` in `MainActivity.kt` (no-op in release):
- `--ez kudosDemoLibrary true`: Detected via `getBooleanExtra("kudosDemoLibrary", false)` (or string `"true"`). Executes `DemoLibrary.seed(container)` on `Dispatchers.IO` before `setContent`, and marks onboarding flags in `SettingsRepository` and `KudosApp`.
- `--es kudosTheme dark|light|sepia|oled`: Read via `getStringExtra("kudosTheme")` and mapped to `KudosThemeMode`. Passed into `KudosApp` as `sessionTheme`, overriding the active theme for the session while allowing in-session cycling.
- Onboarding flags (`hasCompletedOnboarding`, `hasPermanentlyDismissedSyncFolderOnboarding`): Bypassed automatically when demo library is active or when passed as intent extras.

## Skipped iOS Fields
Skipped as Android models do not have them yet; annotated with `// TODO(phase 2): <field>`:
- Queue: `hue`, tags, `keepsWorksOffline`
- Collection: `hue`, `showsOnHome`
- Work: `legacyReaderProgress` (mapped to `lastScrollFraction`), `freedAt` (for held copy)

## DAOs vs Repositories
All mutations strictly use repository methods: `WorkRepository.upsert`, `softDelete`, `createCollection`, `addWorkToCollection`, `softDeleteCollection`, and `ReadingQueueRepository.createQueue`, `addWork`, `ensureSavedForLaterQueue`. A single read on `workDao.getAllIncludingDeleted()` was used for the title-based idempotency check to inspect active, un-kept, and soft-deleted records.

## Unsure Of
None; all repository methods, file store paths, and types match existing codebase signatures.
