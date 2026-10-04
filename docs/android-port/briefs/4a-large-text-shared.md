# Brief 4a: large text, in the shell and the shared components

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or backup formats; don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.

At Android's largest font size (Settings > Display > Font size, scale 2.0) the app breaks. Seen on
the emulator on 2026-10-03:

- the tab bar's labels grow and are cut off by the bar: they can't be read;
- on work cover cards (Home's row, Library's shelves) the title, the progress ring and the author
  overlap each other, because the card keeps its size while the text doubles;
- section headers are cut to "CONTINUE …", "SAVED FO…";
- a segmented control's label is cut to "Bookma…".

Android has no large-text handling at all (nothing reads `fontScale`). iOS has a rule for each of
these. Port iOS's rules; don't invent new ones. The iOS lane is `/Users/cidy02/kudos-ios-polish`.

## How iOS's sizes map to Android's

iOS's `dynamicTypeSize.isAccessibilitySize` is true from AX1 up (text about 1.65× and larger); its
largest ordinary size, xxxLarge, is about 1.35×. Android's steps are 0.85, 1.0, 1.15, 1.3, 1.5, 1.8
and 2.0. So: **Android's `fontScale` above 1.3 is an accessibility size.** Put that in one place: a
small helper in `ui/subject` (for example `@Composable fun isAccessibilityFontScale(): Boolean`,
reading `LocalDensity.current.fontScale`), and use it everywhere below. A value iOS marks
`@ScaledMetric` (a card's width and height, a ring's diameter) grows with the text: on Android,
its dp times `fontScale`, with whatever clamp iOS gives it. A cap such as
`.dynamicTypeSize(.xSmall ... .accessibility2)` is about 1.95×, which is Android's maximum, so it
needs no code.

## Do this, and only this

1. **The tab bar** (`app/MainScaffold.kt`). iOS's is the system `TabView`
   (`kudos-ao3-reader/App/ContentView.swift`), whose labels stay one size at every text size. Make
   Android's labels the same: a fixed size that ignores `fontScale` (convert dp to sp through
   `LocalDensity`). Nothing else about the bar changes.
2. **The shared components**, each from its iOS counterpart. Read every use of
   `dynamicTypeSize`, `isAccessibilitySize`, `@ScaledMetric` and `minimumScaleFactor` in the iOS
   file and give the Android component the same behaviour:

   | iOS (`kudos-ao3-reader/UIComponents/`) | Android (`ui/subject/` unless said) |
   |---|---|
   | `SubjectSurface.swift` (kicker, `SubjectHeaderBlock`, `SectionRuleHeader`, chips, `SubjectStatStrip`) | `SubjectComponents.kt` |
   | `SubjectScreen.swift` (the rows and headers it defines) | `SubjectComponents.kt`, `WorkLibraryComponents.kt` |
   | `SubjectForm.swift` (`SubjectFormRow` and its value rows) | `SubjectForm.kt` |
   | `CarouselCardStyle.swift` (the cover card's scaled width and height; read its long comment) | `SubjectWorkCoverCard.kt`, `WorkReadingRing.kt` |
   | `WorkStatLabel.swift` | the stat rows in `ui/components/` that `SensitiveWorkRow` uses |
   | the segmented control in `SubjectSurface.swift` | `SubjectSegmentedControl.kt` |

   Typical rules you will find: a title limited to two lines at ordinary sizes and unlimited at
   accessibility sizes; a section header that may wrap instead of being cut; a form row that
   stacks its label above its value at accessibility sizes; a card that grows with the text.
3. **At scale 1.0 nothing may change.** Every rule must reduce to today's exact layout when
   `fontScale` is 1.0 (and at 0.85 to 1.3 unless iOS's rule says otherwise). Claude will compare
   screenshots pixel by pixel.
4. Don't touch individual screens (`home/`, `library/`, `account/`, `reader/`, …) in this brief,
   even where one misbehaves at large text; list what you notice in the result. Home's hero
   (`HomeResumeHero.swift`), the Inbox rows and the AO3 collection cards are the next briefs.

## Result

Write `docs/android-port/briefs/4a-result.md`: for each component, the iOS rule (file and line) and
what the Android component now does; anything you could not port and why; and the screens you
noticed that still need their own large-text work.
