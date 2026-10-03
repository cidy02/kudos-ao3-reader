# Brief 3l-fix: the author profile's chrome and header as iOS draws them

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`
Use **emulator-5554 only** (airplane mode). Open the profile directly:
`adb -s emulator-5554 shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --ez kudosDemoSignedIn true --es kudosTheme dark --es kudosDebugRoute nav:author-profile/nine_of_wands`
Delete any helper scripts you create before finishing.

Your 3l landed (`d11c4056`). Android shot: `docs/android-port/shots/3l/author-profile-android.png`.
iOS: `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift` and its parts (iOS lane
`/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish`;
reading files there can be slow because of iCloud).

1. **Chrome:** Android shows a "← Author" title bar, with the ⋮ menu on a separate row below.
   iOS uses `SubjectScreenScaffold`'s floating chrome: a glass back circle top-left, and the
   trailing toolbar circles (⋮ and any others) top-right on the same row, with no title bar. Use
   `ProvidePushedShellChrome(hasSubjectHeader = true, trailingContent = …)` as the other
   redesigned pushed screens do (see `works/WorkDetailScreen.kt`), and move the ⋮ menu into
   `trailingContent`.
2. **Header:** match iOS's author header: the kicker, the large name, the avatar, the pseud line,
   and the Subscribe / Mute / Block controls, with iOS's layout and strings. Drop the card panel
   if iOS doesn't draw one. Put the status-bar inset plus 56dp above it, as the other pushed
   screens do.
3. Check the AO3 dashboard screen (`account/AO3DashboardScreen.kt`) the same way against iOS.

Keep every action (diff strings and `on…` callbacks against `git show HEAD:<file>`). Save Dark shots
to `docs/android-port/shots/3l-fix/`. Write `docs/android-port/briefs/3l-fix-result.md`.
Don't touch `backup/`, `data/local`, migrations, `account/AccountScreen.kt` (Flash is there),
`library/`, `settings/` or `app/MainScaffold.kt`.
