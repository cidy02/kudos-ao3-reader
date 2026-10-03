# Brief 1d: pushed screens get iOS's floating chrome

Edit-only. **Do not commit**, push, switch branches, stash or reset. No network. You cannot run
Gradle: write code that compiles by careful reading. Claude builds and checks on the emulator.

## The difference
On Android, a pushed screen (a queue page, the queues organizer, lists) gets a title bar ("← Reading
Queues") with its toolbar circles on a **second row** below it. On iOS
(`docs/android-port/shots/ios/queue-neon-reread-dark.png`) there is **no title bar**. A glass back circle
floats top-left and the toolbar circles float top-right **on the same row**. The screen's own header
block (kicker, rule, big title) carries the title.

## iOS reference
- `kudos-ao3-reader/UIComponents/SubjectScreen.swift`: `SubjectScreenScaffold` (leading chrome is a
  `GlassCircleButton` with `chevron.left`, then trailing chrome, then the header block, then content),
  `hidesSystemNavigationBar()`, and `reinstatesBackSwipe`.
- `kudos-ao3-reader/UIComponents/FloatingChrome.swift`: `hidesFloatingTabBar()`.
- iOS hides the **tab bar** only on screens that call `hidesFloatingTabBar()`. Today those are
  `AO3CollectionsList`, `AO3SeriesDetailView`, `AuthorProfileView`, `CommentThreadScreen`,
  `FandomListView`, `SettingsHubView`, and whatever `SubjectScreen.swift` applies it to (read it to see
  exactly which). All other pushed screens keep the floating tab bar, including the queue page, as the
  iOS shot shows.

## Android
`app/MainScaffold.kt` decides each route's chrome. Brief 1c's result
(`docs/android-port/briefs/1c-result.md`) says pushed screens hide the bar and get a glass back
button plus a title. Home and Library hand their toolbar to the shell through
`home/HomeShellChrome.kt` and `library/LibraryShellChrome.kt`, drawn with the shared
`ToolbarCircleButton` (`ui/subject/SubjectComponents.kt`).

## Do
1. For pushed routes whose screen draws its own subject header block (the queue page, the queues
   organizer, Queue details, and any other screen already restyled with `SubjectHeaderBlock`), drop
   the title bar. Draw a glass back circle top-left and the screen's toolbar circles top-right on
   one row, floating over the content and scrolling away with the same scroll-away rule the tab
   roots use. Let each screen hand its trailing buttons to the shell the way Home and Library do;
   generalise that holder rather than adding a third copy.
2. Older, not-yet-restyled pushed screens (no header block) keep a title, but on the same single row
   as their actions.
3. Tab bar visibility follows iOS: hidden only on the Android equivalents of the iOS screens listed
   above (plus the reader), and visible on every other pushed screen.
4. The system back gesture and the back circle both pop.

Don't touch `backup/`, `data/local`, migrations, repositories, or the `home/Home*Card*` and
`ui/subject/SubjectWorkCoverCard.kt` content files. Write `docs/android-port/briefs/1d-result.md` (under
300 words) listing each pushed route and its chrome and tab-bar choice, with the iOS evidence.
