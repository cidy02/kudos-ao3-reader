# Brief 3i-fix2: make the Settings hub match iOS exactly

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`
Use **emulator-5554 only**. Open Settings directly with
`adb -s emulator-5554 shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --es kudosTheme dark --es kudosDebugRoute nav:settings`.

Your 3i landed (`5d58945c`). Compare `docs/android-port/shots/3i/hub-ios-vs-android.png` (iOS left,
Android right). Fix:

1. **Header.** The "Settings" title collides with the floating back circle. iOS draws the screen's
   `SubjectHeaderBlock` below the chrome row: kicker "AO3 ACCOUNT" (the hub's scope kicker; read
   `kudos-ao3-reader/Settings/SettingsHubView.swift` and `SettingsHeaderBlock.swift`), the large
   title, and the subtitle "Changes here affect Kudos, not your AO3 account". Use the same top
   spacing the other pushed screens use (see `works/WorkDetailScreen.kt`: a status-bar inset plus
   56.dp before the header) and the lane's `SubjectHeaderBlock`.
2. **Rows, order, labels and values exactly as `SettingsRoute.swift` (`hubGroups`, titles and
   value summaries):**
   - Reading: Appearance, Font, Reader, Listening.
   - Downloads & Storage: Downloads, Preservation, Reading Queues.
   - Library & Sync: Library, Backup, Sync Folder, Import.
   - Then Account & Privacy and About, as iOS orders them.
   - Value text as iOS prints it (e.g. Reader "Scrolled", not "Scroll").
   - Where a page doesn't exist on Android yet (Listening: text-to-speech voice and speed;
     Preservation; Import), build it from the iOS page, reusing the controls the old Settings
     screen had (`docs/android-port/briefs/3i-old-SettingsScreen.kt.txt`) and Android's existing
     repositories. Don't invent settings Android can't honour. If one needs new data, list it in
     your result instead.
3. Don't drop anything: rerun your `check_strings.sh` check before you finish. Then delete
   `check_strings.sh` (it shouldn't be committed); put the check in a unit test instead.
4. Append a "3i-fix2" section to `docs/android-port/briefs/3i-result.md`.

Don't touch `backup/`, `data/local`, migrations, `app/MainScaffold.kt`, `app/Routes.kt`, `reader/`
or `search/`.
