# Brief 3c: Reading queues, redesigned as the iOS app draws them (artboards 1h, 1i, 1j, 1bg, 1bh)

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`

## Read first
- `docs/android-port/specs/queues.md (it cites few lines: read the iOS files it names)`: the porting spec, with iOS file:line for every claim. It's
  your main guide. Where it says UNSURE, read the iOS code.
- `docs/android-port/LIVING-PROMPT.md` §1 and §6. **iOS code wins over the artboard.**
- `docs/android-port/briefs/1a-result.md` and `1c-result.md`: the design system in `ui/subject` and the
  shell (floating bar, scroll-away title) you build on.
- iOS: `kudos-ao3-reader/Features/Library/ReadingQueues.swift`, `ReadingQueueBrowser.swift`,
  `ReadingQueuePageParts.swift`, `ReadingQueueOrganizer.swift`, `ReadingQueueSwitcher.swift`,
  `ReadingQueueSettingsView.swift`, `NewReadingQueueSheet.swift` (New Queue and Edit Queue),
  `QueueCardMenu.swift`, `QueueTagManagerView.swift`, `QueueTagSheet.swift`,
  `kudos-ao3-reader/UIComponents/SubjectHueSwatches.swift`, and `Services/ReadingQueueService.swift`
  (`updateQueue`).
- Your Home work (commit b476ca47, `home/HomeQueueCard.kt` etc.) is in the lane. Reuse it.

## Build
1. **The queues organizer** (iOS `AllReadingQueuesGridView`, reached from Home's queue See all):
   the header block, search field, stat strip, tag rail, Pinned and All Queues sections, and empty
   states.
2. **A queue page** (iOS `ReadingQueueBrowser`): the subject header with that queue's
   wash, Up Next and In Line, the list and compact grid display modes, a top-right toolbar (Add Works,
   FilterButton, "…" with Select / Reorder / Display mode / Queue details), select mode, and drag
   to reorder. **No bottom switcher bar** (owner decision T-343): remove Android's `QueueSwitcherBar`.
3. **New Queue and Edit Queue** share one sheet (T-335), with name, colour, tags, keep works
   offline and description. Colour is iOS `SubjectHueSwatchRow`: five presets plus a dashed "+"
   that opens a colour picker. Android has no system picker, so build a simple HSV picker (a
   saturation/value square plus a hue slider, with a preview and Done/Cancel). The picked colour
   is stored exactly as `colorHex` (T-336), and `hue` is set from it. The sheet's wash follows the
   picked colour live (T-350).
4. **A press-and-hold menu on queue cards** (T-338, `QueueCardMenu`): Edit Queue, Pin/Unpin,
   Delete (with confirmation), on Home's deck cards and in the organizer.
5. **Queue details** (iOS `ReadingQueueSettingsView`) and the **tag manager**: queue tags are
   stored in `queue_tag_cross_refs` (`ReadingLogDao.upsertQueueTag`, etc.).
Add the repository functions you need (`updateQueue`, pin, tags) to
`library/ReadingQueueRepository.kt`, and set `dateUpdated` and `lastModifiedAt` as the existing
functions do. Tests for each new repository function.

## Also: Home follow-ups (from your 3a result)
- The top-right toolbar circles on Home must be the iOS size: 44pt-tall glass circles with
  17pt glyphs, the "+" in the accent. Fix `GlassCircleButton` usage or its size where the shell
  draws them, so every tab root gets the iOS size.
- The status tray: use icons, as iOS `WorkStatusIconGrid` does (rating, warnings, category,
  completion), instead of the text marks ("Gen", "F/F"). Use Material icons that match iOS's SF
  Symbols as closely as possible, and keep AO3's colours.

## Verify
If an emulator is attached (`adb devices`), launch with
`adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --es kudosTheme dark`
and save queue screenshots (the organizer, a queue page, the New Queue sheet), unscrolled and scrolled, in Dark and Sepia, to `docs/android-port/shots/3c/`.
Reference iOS screenshots of the same demo data are in `docs/android-port/shots/ios/` if present.

## Don't
Touch `backup/`, `data/local`, migrations, `works/WorkRepository.kt`, or the `library/Library*` screens
(another agent is rebuilding Library right now). No new dependencies.

When done, write `docs/android-port/briefs/3a-result.md` (under 500 words): what you built, iOS →
Kotlin for each new component, and any difference from iOS and why.
