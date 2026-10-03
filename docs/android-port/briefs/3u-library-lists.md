# Brief 3u: Library section lists (and Search's "In Your Library") as iOS draws them

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`
Use **emulator-5554 only** (airplane mode; keep it). Open a list directly:
`adb -s emulator-5554 shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --es kudosTheme dark --es kudosDebugRoute nav:library-section/readingNow`
(Other ids are in `library/LibrarySectionKind.kt`.)

## The difference
See `docs/android-port/shots/ios/library-lists/reading-now-ios-vs-android.png` (iOS left).
iOS `Features/Library/LibrarySectionListView.swift` (iOS lane
`/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish`)
draws:
1. A subtitle: "3 works · most recently read first" (each section's count and sort wording).
2. Filter chips under the header ("All 3", "WIP 2"; read which chips each section offers, with counts).
3. Section headers inside the list ("IN PROGRESS 3"; read the grouping rule per section).
4. **Rows are `SensitiveWorkRow`**: the full work card, the same one iOS uses for AO3 results.
   - Fandom-tinted card; title, "by" byline, fandom line, summary.
   - Rating, category, warning and status chips; stats (language, words, chapters, comments,
     kudos, bookmarks, hits).
   - The favourite star; privacy blur with "Tap to reveal".

   Android uses the compact `WorkLedgerRow` instead. Android already has a full work card for AO3
   search results (`ui/components/WorkCoverCard.kt` or the card `search/SearchScreen.kt` uses).
   Reuse or extend it. Don't build a third card.
5. Toolbar: iOS has filter and ⋯ (read its menu: select, privacy, sort…). Android shows filter, an
   eye toggle and a select icon. Move them into ⋯ as iOS does, keeping every action.

Apply the same row to Search's "In Your Library" (`search/SearchScreen.kt`, iOS
`SearchLocalResultsList.swift` uses `SensitiveWorkRow` too). Also use it for Collection detail if iOS's
`CollectionDetailView` does (check).

**Keep** swipe actions, the long-press menu, selection mode and bulk actions, and the privacy reveal
(rows must stay blurred until revealed). Before you finish, diff the strings and `on…` callbacks of
every file you rewrote against `git show HEAD:<file>`: nothing may disappear unless iOS dropped it.
Save Dark shots of Reading Now, Favorites, Saved for Later and Finished to
`docs/android-port/shots/3u/`. Write `docs/android-port/briefs/3u-result.md`.

Don't touch `backup/`, `data/local`, migrations, `settings/`, `reader/`, `comments/` or
`app/MainScaffold.kt`.
