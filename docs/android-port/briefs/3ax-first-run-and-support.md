# Brief 3ax: first run, What's New, and the login screen, against iOS

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result, and if a question remains, ask it at once and stop rather than guess. Write
`docs/android-port/briefs/3ax-result.md` as you go.

Nobody has compared these screens with iOS yet. They are the first things a new reader sees.

## The screens

| iOS (`kudos-ao3-reader/Features/`) | Android (`android/app/src/main/java/io/github/cidy02/kudos/`) |
|---|---|
| `Onboarding/WelcomeView.swift`, `OnboardingComponents.swift` | `onboarding/WelcomeScreen.kt` |
| `Onboarding/SyncFolderOnboardingView.swift` | `onboarding/SyncFolderOnboardingScreen.kt` |
| `Support/WhatsNew.swift` | none |
| `Auth/AO3LoginView.swift` | `auth/AO3NativeLoginScreen.kt`, `auth/AO3WebLoginScreen.kt` |

Find where iOS decides to show each (first launch, after an update, from which buttons) and
where Android does (`app/KudosApp.kt`, `app/AppNavHost.kt`).

## Part 1: say what differs

Start the result with a table per screen: every element in iOS's order (title, each line of
text word for word, each button with its words, each link and where it goes, each footnote),
and beside it what Android shows. Then when each screen appears and what leaves it, on both.
Mark every difference. Where Android has something iOS does not, say whether it is an Android
need (a system permission, a folder picker that works differently) or just drift.

## Part 2: make Android's match

- **Welcome and sync-folder onboarding:** iOS's content, order and words; iOS's rule for when
  they appear and what "skip" does. The folder picker itself is Android's own (the system's
  document picker); what the screen says about it should be true of Android, so where iOS's
  words name an iOS-only thing (Files, iCloud Drive), use the Android thing and list each such
  change in the result.
- **What's New:** build it as iOS has it (what it lists, when it shows, how it is dismissed and
  remembered), with Android's own entries only where iOS's are about iOS-only features; say
  where the entries live so the next release can add one.
- **Login:** the screen's content, words, footnotes and error messages as iOS's
  `AO3LoginView`. **Do not change how signing in works** (the requests, cookies, validation,
  the web fallback's mechanics): this brief is what the reader sees and reads, nothing else. If
  a difference in the mechanics looks wrong, write it at the top of the result and leave it.
- Delete `support/BugReport.kt` (it holds only a comment saying it can be deleted) if nothing
  references it.

## How it must be drawn

The app's tokens and shared components (`ui/subject/SubjectComponents.kt`,
`settings/SettingsChrome.kt`): no stock Material cards, chips or default Material colours.
Buttons are Material's own button shapes in the app's colours, as the rest of the Android app
now does for controls (iOS's layout and words, Android's controls). Light, Dark, Sepia and
OLED; every text with a line height; nothing clipped at `isAccessibilityFontScale()`.

## So the screens can be looked at

The demo (`kudosDemoLibrary` launch extra, `app/DemoLibrary.kt`, the `nav:` demo routes in
`app/KudosApp.kt`) skips first run. Add debug-only demo routes that open each of these screens
for looking (`nav:welcome`, `nav:sync-onboarding`, `nav:whats-new`, `nav:login`), changing
nothing about what a real first run or a real sign-in does, and never sending anything from
the login screen in the demo. Say the exact route for each.

## Tests

No network. When each screen shows and stops showing (first launch, after an update, after
skip), with the stores faked; What's New's remembered version; the demo routes opening each
screen; the login screen sending nothing in the demo.
