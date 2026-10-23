# Audit A81 (read only): which screens have never been put beside the other app's

**Write nothing but `docs/android-port/audits/A81-result.md` in `/Users/cidy02/kudos-agent-grok`.
Do not edit code, commit, push, switch branches, sign in, run Gradle or xcodebuild, or contact
archiveofourown.org.** Create the result file FIRST and add to it as you go.

Read the code here (not in your worktree, which is older):
- iOS: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (SwiftUI; debug routes in
  `App/DemoLibrary.swift` and `App/ContentView.swift`, `-KudosDebugRoute <route>`).
- Android: `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`
  (Compose; routes in `app/Routes.kt` and `app/AppNavHost.kt`; the debug extra is
  `--es kudosDebugRoute nav:<route>`, read in `MainActivity`).
- The pairs already shot on both apps, in four themes and the largest text, are the lines of
  `/Users/cidy02/kudos-tools/pairs/list.txt`, `list2.txt` and `settings-list.txt` (fields:
  `iosRoute|iosArgs|androidRoute|tap|name`; `tap` is text tapped after the route opens).

1. List every iOS **screen**: a View shown as a whole page or sheet (a tab's root, pushed with
   `NavigationLink`/`navigationDestination`, or presented with `.sheet`/`.fullScreenCover`/
   `.popover`). Skip rows, cards, menus, alerts and confirmation dialogs inside a page.
2. For each, the pair whose screen it is (the `name` column), or **unpaired**.
3. For each unpaired screen: its Android counterpart (`file:line` of the composable, or **none**),
   and the shortest way the **demo** reaches it on each app: a debug route, or a route plus the
   visible text to tap. Say **needs AO3** when only a signed-in session or a real AO3 answer can
   show it (we never sign in), and **no demo data** when the demo lacks what it lists.
4. Group by these areas (the rows of the parity table): Shell/tabs; Home; Library dashboard and
   sections; Reading queues; Local collections; Recently Deleted; Reading Insights; Browse;
   Search, filters and saved searches; Work detail and My copy; Reader (settings, annotations,
   read aloud); Comments; Account hub and signed out; Marked for Later, Bookmarks, History,
   Subscriptions; Inbox; Author pages, Works, Series, Dashboard; AO3 collections; Challenges;
   Writing; AO3 Preferences; Settings hub and pages; More on AO3; Onboarding, Support, About.

Report a table first (area | iOS screen `file:line` | pair or unpaired | Android `file:line` |
demo route on iOS | on Android), then the counts per area, then anything you could not place.
