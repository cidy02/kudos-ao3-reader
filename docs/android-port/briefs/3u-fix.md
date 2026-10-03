# Brief 3u-fix: finish Library lists and the work card as iOS draws them

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`
Use **emulator-5554 only**:
`adb -s emulator-5554 shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --es kudosTheme dark --es kudosDebugRoute nav:library-section/readingNow`
Don't leave helper scripts in the worktree; delete any you create before finishing.

Your 3u landed (`409c4d2f`). Compare `docs/android-port/shots/3u/reading-now-ios-vs-android.png` (iOS
left). iOS: `Features/Library/LibrarySectionListView.swift`, `UIComponents/WorkStatLabel.swift`, and
the iOS work row (`SensitiveWorkRow` and the row it wraps), in the iOS lane
`/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish`.

1. **Filter chips** under the subtitle: "All 3", "WIP 2" for Reading Now. Read which chips each
   section offers and what they filter (`LibrarySectionListView.swift`: chip strip, counts,
   `applyFavoriteChips` and the like). Match per section, with the selected chip in the accent.
2. **Section headers** as iOS: "IN PROGRESS 3" (iOS grouping and wording per section, with the
   count), not "READING NOW".
3. **Card**, as iOS's work row:
   - the background tinted in the work's colour (`HomeFacts.workHue` →
     `SubjectPalette.cardWash`, as `ui/subject/SubjectWorkCoverCard.kt` does). Sodium Lights is
     purple, Winter Garden green;
   - a **yellow** favourite star (`Color(0xFFFFCC00)`, iOS `.yellow`), not white;
   - no expand chevron unless iOS shows one in this context;
   - iOS's stats row: language, words, chapters, comments, kudos, bookmarks, hits, with iOS's
     symbols and order (`WorkStatLabel.swift` `secondaryItems`).
4. **Show zero counts** (Settings > Library; iOS `@AppStorage("showsZeroStats")`, default **on**,
   WorkStatLabel.swift ~691): a stored setting (DataStore key `showsZeroStats`), the toggle on the
   Settings Library page under "Confirm before deleting", with iOS's footnote, and the stats row
   honouring it: an unknown count is never shown; a zero is shown only when the setting is on. Add
   a unit test for that rule.
5. The "Tap to reveal" capsule uses secondary ink, as iOS does, not the accent.

Keep every action. Diff strings and `on…` callbacks against `git show HEAD:<file>` before you finish.
Save Dark shots of Reading Now, Favorites, Saved for Later and Finished to
`docs/android-port/shots/3u-fix/`. Write `docs/android-port/briefs/3u-fix-result.md`.
Don't touch `backup/`, `data/local`, migrations, `reader/`, `comments/`, `account/` (another agent
is there) or `app/MainScaffold.kt`.
