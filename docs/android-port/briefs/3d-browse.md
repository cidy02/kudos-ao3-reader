# Brief 3d: Browse, redesigned as the iOS app draws it (artboards 1g, 1al, 1am, 1an)

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`

## Read first
- `docs/android-port/specs/browse.md`: the porting spec, with iOS file:line for every claim. It's
  your main guide. Where it says UNSURE, read the iOS code.
- `docs/android-port/LIVING-PROMPT.md` §1 and §6. **iOS code wins over the artboard.**
- `docs/android-port/briefs/1a-result.md` and `1c-result.md`: the design system in `ui/subject` and the
  shell (floating bar, scroll-away title) you build on.
- iOS: `kudos-ao3-reader/Features/Browse/NativeBrowseView.swift`, `Features/Search/MediaBrowserView.swift`,
  `MediaBrowserJumpBackIn.swift`, `FandomListView.swift`, `FandomListFilterSheet.swift`,
  `FandomFamilyRows.swift`, `FandomCatalog.swift`, `FandomWorksView` and `TagWorksView`.
- The iOS reference shot is `docs/android-port/shots/ios/browse-dark.png`.

## Build
1. **The Browse root (1g)**: the Jump Back In carousel, then one full-width panel per category, with
   its icon square, name, counts line, "N downloaded", the "recently read" chips and the
   twelve-chip fandom cluster with "+N more". Use iOS's exact rules for the counts and chips, per
   `MediaBrowserView.swift`'s `computeStats`.
2. **Jump Back In (T-351, owner 2026-10-01)**: a horizontal carousel of up to **10** fixed-width
   cards, ranked by each fandom's latest **visit or read**. Port `MediaBrowserJumpBackIn.swift`
   (`jumpBackInFandoms`) with its tests from `KudosTests/BrowseAndWorkDetailRulesTests.swift`. Record
   a visit whenever a fandom is opened from Browse into `fandom_read_watermarks`
   (`ReadingLogDao.upsertWatermark`, schema 11), the way iOS `ReadingLogService.markVisited` does:
   update the existing row by raw name, else insert. A sibling family records its first tag.
3. **A fandom list (1al, 1am)** with its sort and filter via the top-right FilterButton (T-337: no
   filter button in the body), and **a fandom's works** with the subject header block and AO3
   result cards.
4. **Keep every Browse action** Android has today working.

## Verify
If an emulator is attached (`adb devices`), launch with
`adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --es kudosTheme dark`
and save Browse screenshots (the category list, a fandom list, a fandom's works), unscrolled and scrolled, in Dark and Sepia, to `docs/android-port/shots/3d/`.
Reference iOS screenshots of the same demo data are in `docs/android-port/shots/ios/` if present.

## Don't
Touch `app/MainScaffold.kt`, `app/Routes.kt`, the `library/` screens, `backup/` or migrations; another
agent is changing the shell. Use emulator-5554 only. No new dependencies.

When done, write `docs/android-port/briefs/3a-result.md` (under 500 words): what you built, iOS →
Kotlin for each new component, and any difference from iOS and why.
