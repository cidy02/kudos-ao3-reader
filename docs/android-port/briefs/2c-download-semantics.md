# Brief 2c: what "Downloaded" means, and what finishing a work does, as iOS does it

You are porting behaviour (not UI styling) from the iOS app to the Android app (Kotlin, Room,
Jetpack Compose). Work only in this worktree. **Do not commit**, push, switch branches,
stash or reset. No network except Gradle's offline cache. Leave changes uncommitted; Claude
reviews and commits.

Build and test (iterate until green; do not weaken existing tests to pass):
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`
If Gradle can't run in your sandbox, say so in the result and compile by careful reading.

Read first: `docs/android-port/LIVING-PROMPT.md` §1 and §6, and `docs/android-port/GAP-INVENTORY.md`
("Data parity", "Library", "Recently Deleted"). iOS wins over everything else (owner decision).

## The iOS behaviour to reproduce (owner decisions T-341, T-344, T-346, T-347; TASKS.md rows)
Read these iOS files fully before writing code:
- `kudos-ao3-reader/Models/Models.swift`: `SavedWork.isDownloaded`, `isKeptOffline`,
  `isProtected`, `freedAt`.
- `kudos-ao3-reader/Services/WorkDownload.swift`: `action(for:)` and `perform`
  (Download / Remove Download / "kept by").
- `kudos-ao3-reader/Services/WorkLifecycle.swift`: `markFinished`, `freeEPUBIfFinished`,
  `holdFinishedCopy`, `restoreHeldCopy`, `freeHeldCopy`, `sweepHeldCopies`, `releaseHeldCopy`,
  `freedCopyWindow` (60 days), `freeEPUB`, `setSaved`, `keepsWorksYouReadKey`,
  `keepIfKeepingWorksYouRead`.
- `kudos-ao3-reader/Services/KeepOffline.swift`: queue and collection keeps, where `nil` means
  never asked (queues keep, collections don't).
- `kudos-ao3-reader/Features/Library/RecentlyDeletedView.swift`: the two sections, "Deleted"
  (90 days) and "Finished, not kept" (60 days), and what each row's actions do.
- `kudos-ao3-reader/Settings/SettingsStoragePages.swift`: the "Keep works you read" toggle and
  its copy.

In short, on iOS:
- **Downloaded** means the file is on the device *and* (`isSaved`, or kept by a queue or collection
  whose keep is on, or an import with no AO3 id).
- **Reading copies are not downloads.** Opening a work to read may fetch its file, but that
  doesn't make it "Downloaded".
- **Remove Download** only clears the keep (`isSaved = false`). Only Delete removes the file.
- **Finishing** an un-kept AO3 work no longer deletes the file at once. It stamps `freedAt`, and
  the copy shows in Recently Deleted › "Finished, not kept" for 60 days, where it can be restored
  (clear `freedAt`) or freed now. A sweep frees held copies past 60 days. "Free up space" in
  Settings frees immediately. Setting saved/kept again clears `freedAt`.
- **Keep works you read** is a setting, off by default. When it's on, opening a work in the reader
  marks it kept, so it is Downloaded.

## Android today (verify each claim yourself)
- `works/WorkRepository.kt`: `setSaved` only flips `isSaved`. `setFinished` deletes the EPUB
  immediately for unprotected works. `deleteLocalEpub` deletes directly.
- `library/LibraryQuery.kt`: the Downloaded filter tests `hasEpub`.
- `library/LibraryScreen.kt`: the long-press menu's Download / Remove Download.
- `library/RecentlyDeletedScreen.kt`: one list of soft-deleted works, collections and queues
  (90 days).
- `data/preferences/SettingsRepository.kt` and `settings/SettingsScreen.kt`: settings.
- Schema 11 already has `freedAt`, `keepsWorksOffline` on queues and collections, and
  `hiddenFromHistoryAt` / `keepInProgressOverride` on works. Don't add migrations.

## Do
1. An `isDownloaded` rule (a pure function plus a repository query) that matches iOS exactly,
   used by the Downloaded shelf and filter, and anywhere Android currently means "downloaded"
   by `hasEpub` or `isSaved`.
2. Download / Remove Download / "kept by" actions with iOS semantics: Remove Download un-keeps
   only. When a queue or collection keeps a work, the menu says so (iOS `.keptBy`) rather than
   offering Remove Download.
3. Finishing holds the copy (`freedAt`). Add restore, free-now, a sweep past 60 days that runs
   where the existing soft-delete sweep runs, and make setSaved/keep clear `freedAt`.
4. Recently Deleted gets the "Finished, not kept" section with restore and free-now actions.
   Reuse the iOS strings verbatim. Keep the current visual style; the redesign comes later.
5. Add the "Keep works you read" setting (DataStore, off by default) with the iOS copy, and
   wire it where the reader opens a work.
6. Unit tests for each rule, mirroring iOS's tests where they exist (`grep -rn` in
   `KudosTests/` for `isDownloaded`, `freedAt`, `holdFinishedCopy`, `keepsWorksYouRead`).
7. Write `docs/android-port/briefs/2c-result.md` (under 500 words): each iOS rule → Android
   location, anything left out, and anything unsure.

## Don't
- Touch `backup/` (another agent is changing it right now) or `ui/subject` / `ui/theme`.
- Change networking behaviour, or download anything automatically except where iOS does.
- Delete user files anywhere iOS wouldn't.
