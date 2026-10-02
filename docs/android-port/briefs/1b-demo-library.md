# Brief 1b: an Android demo library for screenshots

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network.
Leave changes uncommitted.

## Why
Claude verifies every redesigned Android screen by putting it next to the iOS app showing the
same data. iOS seeds that data from `kudos-ao3-reader/App/DemoLibrary.swift` when launched with
`-KudosDemoLibrary YES`. Android needs the same library, triggered by a launch extra on debug
builds.

## Do
1. Read `kudos-ao3-reader/App/DemoLibrary.swift` in full: `seedIfRequested`, `samples`,
   `seedRecentlyDeleted`, `seedHeldCopy`, `writePlaceholder`.
2. Create `android/app/src/main/java/io/github/cidy02/kudos/app/DemoLibrary.kt`. It seeds the
   same works (every sample: title, author, summary, fandoms, rating, warnings, categories, words,
   chapters, completion, kudos and hits as iOS derives them, language, dateAdded spacing,
   favourite, saved/kept, progress and lastReadDate, finished, knownChapterCount), the same three
   reading queues with the same works in the same order, Saved for Later with works 7 and 13, the
   two collections with their works, and the Recently Deleted rows.
   - Go through the existing repositories (`WorkRepository`, `ReadingQueueRepository`,
     collection functions on `WorkRepository`, etc.) so invariants hold. Don't write raw DAO rows
     unless no repository function exists, and say so in the result if you had to.
   - **On-device works** (`sample.onDevice`): write a real EPUB file for each, as iOS writes a
     placeholder. Use `works/converters/EpubBuilder.buildEpub(title, bodyHtml)` with a few
     paragraphs of placeholder prose so the reader can open it. Store it the way imports do (find
     how `WorkImporter` / `WorkFileStore` save an EPUB and set `hasEpub`).
   - Fields Android does not have yet (queue `hue`, queue tags, `keepsWorksOffline`, collection
     `hue` and `showsOnHome`, `legacyReaderProgress`, `freedAt` for the held copy): skip them, and
     leave a `// TODO(phase 2): <field>` comment at each spot so they are easy to fill in later.
   - Idempotent, as on iOS: if a work with the first sample's title exists, don't seed again.
3. Wire it so a **debug build** launched with
   `adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true`
   seeds before the first screen shows (or immediately after, followed by a refresh), and also:
   - skips the welcome/onboarding gate and the sync-folder onboarding, like iOS's
     `-hasCompletedOnboarding YES -hasPermanentlyDismissedSyncFolderOnboarding YES`;
   - accepts `--es kudosTheme dark|light|sepia|oled` and applies that theme
     (`KudosThemeMode`) for the session.
   Guard all of it with `BuildConfig.DEBUG`. Release builds must ignore the extras.
4. Add one JVM unit test under `app/src/test` that runs the seed against the in-memory Room
   database (see how `RoomDaoTest` builds one), and checks the work count, the queue names and
   their work counts, and that running it twice adds nothing.
5. Build and test: `cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`.
   Iterate until it passes. Do not change other tests to make it pass.
6. Write `docs/android-port/briefs/1b-result.md` (under 400 words): the files changed, how the
   extras are read, which iOS fields were skipped, and anything you were unsure of.

## Don't
- Touch persistence schemas, migrations, backup or sync code.
- Touch `ui/theme` or anything under `ui/subject`; another agent is building those.
- Add dependencies.
