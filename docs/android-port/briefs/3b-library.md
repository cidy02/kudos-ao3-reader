# Brief 3b: Library, redesigned as the iOS app draws it (artboards 1c, 1d, 1ah–1ak)

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`

## Read first
- `docs/android-port/specs/library.md (and specs/collections.md for its Collections section)`: the porting spec, with iOS file:line for every claim. It's
  your main guide. Where it says UNSURE, read the iOS code.
- `docs/android-port/LIVING-PROMPT.md` §1 and §6. **iOS code wins over the artboard.**
- `docs/android-port/briefs/1a-result.md` and `1c-result.md`: the design system in `ui/subject` and the
  shell (floating bar, scroll-away title) you build on.
- iOS: `kudos-ao3-reader/Features/Library/LibraryView.swift`, `LibrarySectionKind.swift`,
  `LibrarySectionListView.swift`, `LibraryFilterPanel.swift`, `LibraryFilters.swift`, `WorkRow.swift`,
  `WorkCardActions.swift`, `LibraryWorkSwipeActions.swift`, the Reading History and Favorites views,
  and `kudos-ao3-reader/UIComponents/` (`WorkCarouselSection`, `CarouselCardStyle`,
  `LibraryEntityGridView`, `SubjectSurface`).
- Home was done by another agent in parallel (brief 3a). If both of you need the same new
  shared component (cover card, carousel section, ledger row), put it in `ui/subject/` under the
  iOS name, and note in the result that Claude must reconcile it with 3a's version.

## Build
Rebuild `library/LibraryScreen.kt` (and its section list screens) to match the iOS Library: the
dashboard's shelves in iOS's order (Reading Now, Saved for Later, Finished, Collections,
Downloaded, Reading History, Favorites), the shelves/ledger display toggle, the fandom chip rail,
the filter panel (top-right FilterButton with a badge), long-press menus and swipe actions with
iOS's items and labels, select mode with the bulk bar, and the See all list screens with their
headers. Reading History and Favorites become shelves as on iOS. **Keep every Library action
Android has today working.** Restyle; don't drop features. Use the existing Library ViewModel,
repositories and `WorkDownloadSemantics`; don't change data rules.

## Verify
If an emulator is attached (`adb devices`), launch with
`adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --es kudosTheme dark`
and save Library screenshots, unscrolled and scrolled, in Dark and Sepia, to `docs/android-port/shots/3b/`.
Reference iOS screenshots of the same demo data are in `docs/android-port/shots/ios/` if present.

## Don't
Touch `backup/`, `data/local`, migrations or `works/WorkRepository.kt`; another agent is changing
backup code. No new dependencies.

When done, write `docs/android-port/briefs/3a-result.md` (under 500 words): what you built, iOS →
Kotlin for each new component, and any difference from iOS and why.
