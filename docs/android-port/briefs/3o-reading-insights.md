# Brief 3o: Reading Insights, redesigned as iOS draws it

Rules (binding): work only in this worktree (`~/kudos-agent-codex`); don't commit, push, or switch
branches; never sign in and never contact archiveofourown.org (the demo library and fixtures
only); no stub files; no helper scripts or `.orig` files left behind; don't change Room schemas,
backup formats or any file outside the ones named here without saying so in your result. Your
sandbox can't run Gradle; Claude builds and tests afterwards, so make it compile by reading the
real symbols you use.

**Goal.** Android's `library/ReadingStatisticsScreen.kt` (route `Routes.ReadingStatistics`) should
match iOS's `kudos-ao3-reader/Features/Library/ReadingInsightsView.swift` in content, order,
wording and look. The iOS lane is `/Users/cidy02/kudos-ios-polish` (local disk).

1. Read the iOS view end to end, and `KudosTests/ReadingInsightsTests.swift` and
   `ReadingStatisticsTests.swift` for the numbers' definitions. In your result, list every section,
   stat, label and control iOS shows, in order.
2. Read Android's `library/ReadingStatistics.kt` (the numbers) and `ReadingStatisticsScreen.kt` (the
   screen), and list what differs: missing stats, different definitions, different wording, a
   different order.
3. Make the Android numbers match iOS's definitions in `ReadingStatistics.kt`, with unit tests in
   `app/src/test/java/io/github/cidy02/kudos/library/ReadingStatisticsTest.kt` that mirror the iOS
   tests' cases. If a stat needs data Android doesn't store, don't invent it: leave it out and say
   so in your result.
4. Redraw the screen with the redesign's parts, as the other pushed screens do. Read
   `account/AccountInboxPane.kt` and `ui/subject/` first and reuse what they use: floating chrome
   (`ProvidePushedShellChrome`), the status-bar inset plus 56dp, `SubjectHeaderBlock`, subject
   panels and rows, the theme's tokens (no literal colours). No Material `Scaffold` or `TopAppBar`.
   The tab bar is already hidden on this route.
5. Keep every existing callback and navigation working. Before you finish, diff every user-visible
   string and every callback against the old screen and list any you removed, with the reason.

Write `docs/android-port/briefs/3o-result.md` with the lists from steps 1, 2 and 5, and what you
couldn't do.
