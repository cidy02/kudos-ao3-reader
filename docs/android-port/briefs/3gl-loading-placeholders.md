# Brief 3gl (owner-approved U3): placeholder rows while AO3 lists load, as iOS

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests, looks on the emulator and lands it. Do not edit
`TASKS.md`. Create `docs/android-port/briefs/3gl-result.md` FIRST; write each screen into it as you
finish it: **placeholder / kept / not applicable**, `path:line`, the iOS code followed, the test.

The owner approved this on 2026-10-21. iOS shows content-shaped placeholder rows while a list
loads (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/UIComponents/SkeletonLoading.swift`:
`SkeletonBlock`, `SkeletonTextLine`, the shimmer, `SkeletonListRow` and the rest; used by
`Features/Bookmarks/AO3AccountWorksList.swift`, `Features/Account/AccountInboxViews.swift`,
`AccountComponents.swift`, `Features/Authors/*`, `Features/Comments/CommentsView.swift`,
`Features/Search/*`, `Features/Browse/NativeBrowseView.swift`, `Features/Home/HomeView.swift`).
Android shows a `LoadingStateCard("Loading …")` spinner in 22 places (17 files: run
`grep -rn 'LoadingStateCard(' android/app/src/main`). Android already has some placeholders
(`ui/components/ReaderPageSkeleton.kt`, `ui/subject/SubjectWorkCoverCard.kt`, Home, Comments,
Search): reuse them and add only what iOS has that Android lacks, in `ui/subject/`.

1. For each of the 22, find the iOS screen's loading state. Where iOS shows placeholder rows,
   Android shows the same shape (the row or card that will arrive, the same count iOS draws,
   in each theme, and readable at 2x: placeholders scale like the text they stand for). Where iOS
   shows a spinner or nothing, keep Android's (say so).
2. Placeholders are not announced as content: one "Loading <list>" for the screen reader, the
   placeholders themselves hidden from it. Respect the system's reduced-motion setting for the
   shimmer (iOS: `accessibilityReduceMotion`).
3. Errors, empty lists and the first page arriving must replace the placeholders as the spinner
   was replaced; a pull-to-refresh over loaded content keeps the content (no placeholders then).
4. Tests: the shared placeholder hidden from the screen reader with one label; a list showing
   placeholders while loading and its rows after; reduced motion stopping the shimmer.
