# Brief 1c: the app shell, redesigned (tab bar, Search, chrome that scrolls away)

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`

Read first:
- `docs/android-port/LIVING-PROMPT.md` §1 and §4. iOS is the source of truth over the artboards.
- `docs/android-port/briefs/1a-result.md`: the design system you build with, in
  `ui/subject` (`KudosTokens`, `SubjectPalette`, `GlassCircleButton`, and so on).

## iOS reference
- `kudos-ao3-reader/App/ContentView.swift`, `tabs`: four main tabs (Home, Library, Browse,
  Account) plus **Search in its own circular button beside the bar** (iOS 26's search-role
  tab), `.tabBarMinimizeBehavior(.onScrollDown)`, and a floating glass bar.
- `kudos-ao3-reader/UIComponents/ScrollAwayChrome.swift` (T-349): scrolling down a tab root hides
  the top chrome; scrolling up, or reaching the top, brings it back. Direction comes from the
  raw scroll offset, not one adjusted for insets. An inset-based reading looped forever at the
  bottom of a list on iOS.
- `kudos-ao3-reader/UIComponents/FloatingChrome.swift`: pushed screens hide the floating bar.
- Each tab root: the title is large inline at the top (`toolbarTitleDisplayMode(.inlineLarge)`),
  over the theme's card backdrop. Account has no title bar; its gear floats top-right and fades
  on scroll.

## Android today
`app/MainScaffold.kt` and `app/Routes.kt`: a Material `NavigationBar` with four tabs, and Search
as an icon in Home's top bar. The demo library launches with
`adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --es kudosTheme dark`.

## Do
1. **The floating tab bar.** A rounded glass capsule (theme tokens: `glassFill`, `glassStroke`)
   floats above the content with side margins. It holds four tabs (icon over label; the selected
   tab gets the accent and a soft pill behind it), and **a separate circular Search button** to its
   right. Search becomes its own top-level destination, the existing `SearchScreen`, rather than
   an icon on Home. Remove Home's search icon.
2. **Minimize on scroll.** While the current tab's root list scrolls down, the bar shrinks to a
   compact form (the selected tab's icon alone in a small circle, with the Search circle kept);
   scrolling up or reaching the top restores it. Share one scroll-direction state with the top
   chrome below, and port iOS's pure `hides(hidden, from, to, fromTop)` rule with its unit test
   (`KudosTests/ScrollAwayTopChromeTests.swift`).
3. **Top chrome scrolls away** on the five tab roots, by the same rule: titles and top-right
   actions hide while you scroll down and return on the way up.
4. **Pushed screens** (work detail, lists, and so on) hide the floating bar, as on iOS.
5. **Backgrounds:** tab roots draw `KudosTokens.background` edge to edge, under the status bar and
   behind the bar.
6. **Leave each screen's content as it is.** Only the shell changes. If a screen breaks without
   its old top bar, give it a minimal title in the new style and note it in the result.
7. Screenshots: if an emulator is attached (`adb devices`), install and capture Home, Library,
   Browse, Account and Search in Dark, scrolled and unscrolled, into `docs/android-port/shots/1c/`.
   Skip this if no device is available.

## Don't
Touch `backup/`, `data/local`, migrations, `works/WorkRepository.kt`, `library/LibraryQuery.kt`, or the
`RecentlyDeleted` screen; other agents are changing those. No new dependencies.

When done, write `docs/android-port/briefs/1c-result.md` (under 500 words): the files changed, how
the scroll state is shared, and anything that differs from iOS and why.
