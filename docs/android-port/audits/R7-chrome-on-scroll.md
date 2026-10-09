# R7: how the chrome hides on scroll on Android, and where iOS would do it (a reading)

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/R7-result.md`. No helper scripts or scratch files left behind.

Android is in this worktree under `android/app/src/main/java/io/github/cidy02/kudos/`. iOS is
at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only).

The owner asked (task T-349, 2026-10-01) that on iOS **the tab bar minimise and the top
chrome hide when a list is scrolled down, and come back when it is scrolled up**. Android
already does this. This reading is what someone needs to build it on iOS.

## Part 1: Android, as built

Read `app/ScrollAwayTopChrome.kt`, `app/PushedShellChrome.kt`, `app/MainScaffold.kt`, and
every screen that reports its scrolling to them. Write, with `path:line` for each claim and
the code quoted:

1. What exactly hides and what stays (the tab bar, the top row, its Back button, a screen's
   own buttons, the status bar's ground), on a tab's root screen and on a pushed screen.
2. What drives it: which scroll signal, the threshold or the distance, the animation and its
   duration, and what happens at the top of a list, at its end, on a short list that does
   not scroll, and on a fling.
3. What brings the chrome back without scrolling: a screen taking over the row (`holder`,
   `reveal`), a tab change, a dialog or a sheet, the keyboard, selection mode, a search
   field gaining focus, a refresh. List each, with the line that does it.
4. Which screens opt out, and how.
5. Accessibility: what a screen reader user and a keyboard user get (is hidden chrome still
   reachable?), and what Reduce Motion changes.
6. Every comment or entry in `docs/android-port/DECISIONS.md` that records a fault this
   behaviour had and how it was fixed (quote the entry's heading and its gist). These are
   the traps iOS will meet too.

## Part 2: iOS, where it would go

Read `App/ContentView.swift`, `App/AppRouter.swift`, the tab bar and the shell
(`UIComponents/` and anything named for the tab bar, the top bar, the floating toolbar or
"glass"), and the Browse web view's existing `tabBarHidden` in
`Features/Browse/WebBrowser.swift`. Write, with `path:line`:

1. How the tab bar is drawn today (a system `TabView`, a custom bar, both by platform), and
   what already hides it anywhere (the reader, the browser's `tabBarHidden`, sheets).
2. How a screen's top row is drawn (system navigation bar, a custom floating row, both), per
   platform (iPhone, iPad, Mac), and what already hides or shrinks it.
3. Every list screen that would need to report its scroll position, grouped by how it
   scrolls (`List`, `ScrollView`, `LazyVStack`, a `UIViewRepresentable`), with a count.
4. What iOS 18 and later offer for this directly (`tabBarMinimizeBehavior`,
   `toolbarVisibility`, `scrollPosition`, `onScrollGeometryChange`), which of them the
   project's deployment target allows (find the target in the project file or
   `Package.swift` and quote it), and which the code already uses.
5. The smallest plan: where one piece of shared state would live, which modifier each list
   would take, and which of Part 1's traps (item 6) apply.

Exact files and lines only. Quote code as it is written.
