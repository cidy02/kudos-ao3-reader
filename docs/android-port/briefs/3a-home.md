# Brief 3a: Home, redesigned as the iOS app draws it (artboard 1b)

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`

## Read first
- `docs/android-port/specs/home.md`: the porting spec, with iOS file:line for every claim. It's
  your main guide. Where it says UNSURE, read the iOS code.
- `docs/android-port/LIVING-PROMPT.md` §1 and §6. **iOS code wins over the artboard.**
- `docs/android-port/briefs/1a-result.md` and `1c-result.md`: the design system in `ui/subject` and the
  shell (floating bar, scroll-away title) you build on.
- iOS: `kudos-ao3-reader/Features/Home/HomeView.swift`, `HomeResumeHero.swift`, `HomeCards.swift`,
  `HomeSections.swift`, `HomeCollectionShelves.swift`, `kudos-ao3-reader/UIComponents/WorkCarouselSection.swift`,
  `CarouselCardStyle.swift`, the queue deck card (`Features/Library/ReadingQueues.swift`, search
  "1b" / deck), and `SubjectSurface.swift` (`WorkReadingOrDownloadRing`, `.downloadDimmed`).

## Build
Rebuild `home/HomeScreen.kt` (and new files under `home/` or `ui/subject/` as needed) to match the
iOS Home section by section:
1. **The resume hero** (`HomeResumeHero`): the top in-progress work with its kicker, big title,
   metadata line, status tray, ring and Resume button. Below it, the strip of up to four more.
2. **Reading Queues**: a carousel of 1b's stacked-deck queue cards (the hue or picked `colorHex`
   wash, queue name, work count, "next up"). It needs `hue` and `colorHex` from
   `ReadingQueueEntity`, which schema 11 has.
3. **Collection shelves** for collections with `showsOnHome`, in reading order.
4. **Recently Updated** and **Subscriptions** carousels, using iOS's cover card style
   (`CarouselCardStyle`, 164×232 cover cards with the subject wash), the progress ring, and the
   download ring with dimming while a work downloads (T-345).
5. `SectionRuleHeader` for every section, with collapse and See all exactly where iOS shows them
   (Reading Now's See all only when there are more than five).
6. Empty states, interactions (tap opens the reader for a local work, long-press menus with iOS's
   items and labels), select mode with the bulk bar, and pull to refresh, per the spec.
   **Keep every action that Android's Home has today working.** Restyle; don't drop features.

Data: use the existing Home ViewModel and repositories. "Downloaded" and keep semantics are
already ported (`core/model/WorkDownloadSemantics.kt`, commit 2d8d6290). Don't change data rules.

## Verify
If an emulator is attached (`adb devices`), launch with
`adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --es kudosTheme dark`
and save Home screenshots, unscrolled and scrolled, in Dark and Sepia, to `docs/android-port/shots/3a/`.
Reference iOS screenshots of the same demo data are in `docs/android-port/shots/ios/` if present.

## Don't
Touch `backup/`, `data/local`, migrations or `works/WorkRepository.kt`; another agent is changing
backup code. No new dependencies.

When done, write `docs/android-port/briefs/3a-result.md` (under 500 words): what you built, iOS →
Kotlin for each new component, and any difference from iOS and why.
