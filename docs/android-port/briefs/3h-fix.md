# Brief 3h-fix: the signed-in Account hub's header as iOS draws it

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`
Use **emulator-5554 only** (airplane mode; keep it). The demo can now start signed in:
`adb -s emulator-5554 shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --ez kudosDemoSignedIn true --es kudosTheme dark --es kudosDebugRoute nav:account`

Compare `docs/android-port/shots/ios/account/hub-signed-in-ios-vs-android.png` (iOS left). iOS code:
`kudos-ao3-reader/Features/Account/AccountView.swift` and `AccountComponents.swift` in the iOS lane
`/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish`.

## Fix in `account/AccountScreen.kt` (and the components it uses)
1. **The wash:** iOS draws the scope wash (the app accent) at the top, via `.subjectScreenWash`
   with `themeManager.scopePalette`. Android has none. Use `Modifier.subjectScreenWash(palette, …)`
   with the app-accent palette other scope screens use.
2. **The identity header**, as iOS draws it, not a card:
   - the kicker "AO3 ACCOUNT" in the accent, with its short rule;
   - a large round avatar beside the username as a large bold title;
   - a green dot with "Signed in" in secondary ink;
   - the "Posting as …" capsule and a ⋯ glass circle on one row.

   Signed out keeps iOS's signed-out layout (read `AccountView.swift` for it).
3. **The top-right chrome:** iOS has only the gear (Settings) as an accent-tinted glass circle.
   Android also shows a theme-palette button. Read why with `git log -S "Theme cycling" --
   android/app/src/main/java/io/github/cidy02/kudos/app/MainScaffold.kt`. If it was an Android-only
   addition that iOS dropped, remove it, so theme changes go through Settings > Appearance as on
   iOS. Say what you did in the result.
4. **Counts:** iOS shows a "4+" badge on Subscriptions (the shortcut and the Reading row). Find
   where iOS gets the count, and show the same on Android from the same data source. In the demo,
   that's the fixture.

Keep every action the hub has. Diff the strings and `on…` callbacks of the files you rewrite
against `git show HEAD:<file>`; nothing may disappear unless iOS dropped it. Save Dark shots,
signed in and signed out, to `docs/android-port/shots/3h-fix/`. Write
`docs/android-port/briefs/3h-fix-result.md`.

Don't touch `backup/`, `data/local`, migrations, `settings/`, `reader/`, `comments/`, `library/`
or `app/MainScaffold.kt` (except removing the palette button, if item 3 says so).
