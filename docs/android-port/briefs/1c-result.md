# Brief 1c result

`:app:assembleDebug :app:testDebugUnitTest --offline` passed. Uncommitted. Dark demo-library shots from emulator-5554 are in `docs/android-port/shots/1c/`.

## Files

Edited: `app/MainScaffold.kt` (floating bar, scroll-away titles, pushed back bar), `app/Routes.kt` (`isShellRoot`, `shellTitle`).

Added: `app/ScrollAwayTopChrome.kt`, `test/.../ScrollAwayTopChromeTest.kt` (the iOS cases, plus the shared flag and the nested-scroll sign). `NavigationRoutesTest` checks that Search is a shell root and not one of the four tabs.

## Shared scroll state

`ShellChromeState` stores one hidden flag per shell route. The bar reads it as minimized, and the large title — or Account's gear and theme button — reads that same value. `ScrollAwayTopChrome.hides` is the iOS rule: show at `fromTop <= 44`, hide when the offset grows by more than 1, show when it shrinks by more than 6, otherwise keep the flag. Callers pass dp, so 44, 1, and 6 match points. Nested scroll feeds it. Compose's negative y is a downward scroll and grows the offset. Leftover motion toward the start means the list is at the top. `SideEffect` events are ignored, so the title inset collapsing is not treated as another scroll.

## Differences

Glass is `glassFill` and `glassStroke` only. The design system has no backdrop blur. The wide NavigationRail is gone; every width gets the capsule and the search circle. Home's title is "Home", as on iOS, rather than the old "Kudos" bar. Screen bodies are unchanged, so Home still shows its saved-count line. Search stays out of `topLevelDestinations` and is a fifth shell root. Minimized, the capsule becomes the selected tab's icon and the search circle stays full size. On Search that icon would be a second magnifying glass, so only the accented search circle remains. Account has no title. Its gear and the existing theme-cycle button float and fade together. The signed-out Account overview and the idle Search page fit the screen, so a swipe never passes 44dp and those scrolled shots match the unscrolled ones. Home, Library, and Browse hide the title and shrink the bar. Pushed screens, including the reader and a fandom list, hide the bar. They get a glass back button and a title, because that bar was their only back control. Settings keeps theme cycling on that row. Tab roots paint `KudosTokens.background` under the status bar and behind the bar. Pushed screens keep the Material page color.
