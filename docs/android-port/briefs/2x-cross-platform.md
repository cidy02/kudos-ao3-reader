# Brief 2x: prove iOS and Android backups are the same language

Owner rule (2026-10-02): *"a backup file from iOS must be loadable in android with all info imported
intact and vice versa. behaviour must be the same cross platform."* Prove it with golden fixtures,
using each app's real exporter and real restore, in both directions. Everything so far has been
tested only against hand-written JSON shaped like iOS. This brief replaces that guesswork with
real archives.

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network.
Leave changes uncommitted. Claude runs both test suites and sends failures back. If your sandbox
can run them, do: iOS through `xcodebuild test` on the `AO3_App_OpenSource` scheme with a simulator,
and Android through `cd android && ./gradlew :app:testDebugUnitTest --offline`.

## The format
- iOS: `kudos-ao3-reader/Services/KudosBackup.swift` (the manifest records, `restore(...)` ~line 2083) and
  `Services/KudosBackupExport.swift` (`writeArchive` ~line 192). Read
  `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` first.
- Android: `android/app/src/main/java/io/github/cidy02/kudos/backup/`: `BackupRepository.exportV2ZipBytes()`
  and `importV2ZipBytes(...)` / `importPackage(...)`, plus `BackupManifest.kt`, `BackupMappers.kt` and
  `BackupMergeService.kt`.

## Build
1. **The iOS golden export.** Add a test in `KudosTests/` (copy the in-memory `ModelContainer` setup
   in `KudosTests/KudosBackupTests.swift`). It seeds one library that sets **every** backed-up field
   to a distinctive non-default value:
   - every `SavedWork` field (`hasGivenKudos`, `keepInProgressOverride`, `hiddenFromHistoryAt`,
     `legacyReaderProgress`, preservation, dates, series, `ao3SeriesID`, Readium locator, user tags);
   - two works with small EPUB files;
   - a collection with `hue`, `colorHex`, `keepsWorksOffline`, `showsOnHome`, `workOrderRaw` and a
     description;
   - two queues with `hue`, `colorHex`, `isPinned`, `keepsWorksOffline`, `notes` and tags, plus
     memberships with order and notes, and the system Saved for Later queue;
   - annotations (bookmark, highlight with a colour, note);
   - reading sessions, reading favourites of each kind, and fandom watermarks;
   - a saved search with filters, a bookmark, and settings;
   - signed tombstones;
   - and, as a separate case, a work whose `hiddenFromHistoryAt` is explicitly nil.
   Export it with the real exporter, and write the archive bytes to
   `android/app/src/test/resources/cross-platform/ios-export.kudosbackup`, using the extension the
   real exporter produces. Make the test write this fixture only when an environment flag such as
   `KUDOS_WRITE_GOLDEN=1` is set, and otherwise assert that the committed file still decodes, so
   ordinary test runs don't rewrite it.
2. **The Android restore test** (`android/app/src/test/.../backup/CrossPlatformRestoreTest.kt`). It
   restores `ios-export…` into an empty Android library through the real import path, then asserts
   each field of each record against the values the iOS test set. Keep those values in one shared
   JSON file, `cross-platform/expected-values.json`, written by the iOS test beside the archive, so
   the two sides can't drift. Also check that both EPUB files land on disk byte-identical.
3. **The mirror.** An Android test seeds the same library through repositories, exports with
   `exportV2ZipBytes()`, and writes `KudosTests/Fixtures/cross-platform/android-export.…` behind a
   golden flag (for example the system property `kudos.writeGolden=true`). An iOS test restores it
   with `KudosBackup.restore` into an empty container and asserts every field.
4. **Round trips.** On iOS, restore the Android archive, re-export, and compare the manifest with the
   Android one field by field. Do the same on the Android side.
5. Where a field doesn't survive, **fix the code**, not the test. Each fix cites the iOS rule it
   matches. If a field is device-local by design on iOS (`freedAt`, `authorIdentitiesJSON`), assert
   that it's absent from the archive on both sides.
6. Write `docs/android-port/briefs/2x-result.md`: a table of every field and whether it survives
   iOS→Android, Android→iOS and each round trip, plus the fixes made.

## Don't
Change the archive format or bump the manifest version (it stays v8, additive keys only). Don't touch
UI code. Don't write fixtures outside the two directories above.
