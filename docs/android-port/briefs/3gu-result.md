# Brief 3gu result

Status: implementation, regression tests, and static review complete on
`android/agent-codex-3gu`. Builds and test execution remain with Claude.

Scope: reader Read Aloud settings, dashboard author Bookmarks navigation, DEBUG
shots, and regression tests. No TASKS.md edits, commits, pushes, branch switches,
sign-in, AO3 requests, or Gradle runs. Existing `3gu-two-gaps.md` is untouched.

## Changes

- `docs/android-port/briefs/3gu-result.md:1`: created this running result log before code edits.
- `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsListeningPage.kt:42`:
  extracted the existing Listening form into shared `SettingsListeningContent` with
  a frame slot. The Settings page retains its existing frame, controls, audition
  lifecycle, voice-pack management, pronunciation editor, and preference writes.
- `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderSpeechSettingsSheet.kt:37`:
  added the reader-themed Read Aloud modal with Done and the shared Listening
  content. Audition playback uses its own engine. Both Done and dismissal read the
  current saved speech preferences before invoking the reader callback.
- `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderFanMenu.kt:86`:
  extracted the production Read Aloud action; its long press selects Speech
  settings while its ordinary tap retains playback toggling.
- `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderScreen.kt:255`:
  selects Display or Speech as mutually exclusive settings sheets; either keeps
  system bars visible. `:383` handles the readerspeech shot; `:694` uses the shared
  fan action; `:1001` presents the speech sheet and calls
  `speechController.configure(speech.applyTo(state.preferences), state.work.title)`
  on close, applying voice/rate/pitch/engine to the existing speech session.
  Display retains its own Read Aloud group.
- `android/app/src/main/java/io/github/cidy02/kudos/app/Routes.kt:228`:
  extended the existing author-profile route with optional `tab`, preserving
  existing bare routes and pseud encoding. No new destination was added.
- `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:102`:
  added an author/tab callback; `:880` sends See all bookmarks to the current
  author on Bookmarks. See all works and series retain their existing actions.
- `android/app/src/main/java/io/github/cidy02/kudos/account/AO3DashboardScreen.kt:31`:
  carries the author/tab callback through the dashboard wrapper (`:51`).
- `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt:608`:
  wires the dashboard callback to the existing author-profile route; `:1308`
  registers its optional argument and `:1328` supplies the selected initial tab.
- `android/app/src/main/java/io/github/cidy02/kudos/app/DebugShots.kt:49`:
  added readerspeech (reader + speech modal) and `:57` authorbookmarks (profile
  initialized on Bookmarks). Existing BuildConfig.DEBUG / DemoNetwork guards in
  DebugShotRequests and the launch dispatcher are retained.

Mini player: `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderPositionCard.kt:404`
draws a decorative VolumeUp speaker icon, not iOS's equalizer bars. Per brief, no
new control was added and this file was not changed.

## Tests and verification

- Tests are written, not executed; no Gradle command has been run. Reversion
  outcomes below describe the assertions that must fail, not observed mutation runs.
- `android/app/src/test/java/io/github/cidy02/kudos/reader/ReaderSpeechSettingsSheetTest.kt:77`
  `longPressOpensReadAloudAndReusesListeningControlsInsteadOfDisplay`: physically
  long-presses the production fan action, verifies Speech selection, Read Aloud,
  Done, shared audition controls, and absence of Display & Themes; changes speed
  and voice through shared controls and checks the preferences delivered on Done.
  Revert the action's long-press target to Display: the Speech assertion fails
  (and the Read Aloud/Done/shared-content checks cannot pass). Revert close-time
  preference delivery: the close wait or voice/rate assertions fail.
- `android/app/src/test/java/io/github/cidy02/kudos/reader/ReaderSpeechSettingsSheetTest.kt:101`
  `dismissGestureAlsoDeliversTheLatestPreferences`: changes speed and invokes the
  modal's real Dismiss semantics. Revert Speech routing: no speech modal can
  deliver preferences; revert the dismissal preference callback: the close wait
  or 1.1x assertion fails.
- `android/app/src/test/java/io/github/cidy02/kudos/author/DashboardBookmarksNavigationTest.kt:104`
  `seeAllBookmarksPushesAuthorProfileOnBookmarksInsteadOfTheAccountList`: mounts
  the production dashboard, clicks See all bookmarks through Compose and routes
  into the production author screen using the shared route/initial-tab decoder.
  Checks the actual Bookmarks request (fixture-backed only), selected segment,
  author-profile destination, and absence of account-list navigation/Works fetch.
  Also checks the existing series and works actions. Revert the bookmarks link
  to AccountListType.Bookmarks: the Bookmarks request wait and profile/tab
  assertions fail. Revert tab encoding/decoding: it opens Works and fails those
  same assertions. Test client fails on unbundled URLs and strips image URLs.
- `android/app/src/test/java/io/github/cidy02/kudos/app/DebugShotsTest.kt:11`
  `speechAndAuthorBookmarksShotsOpenTheirProductionDestinations`: checks both
  names and their exact destination/page requests. Revert either dispatcher
  entry: debugShot returns null and its equality assertion fails.
- `git diff --check`: passed after implementation. New files were also checked
  for trailing whitespace and final newlines. Reviewed the shared form extraction,
  every dashboard callback hop, route argument registration/decoding, and DEBUG
  launch/consumption guards. No dependency changes.
- Claude handoff: compile, run these Robolectric/JVM tests plus existing Listening,
  reader fan, and navigation suites; visually inspect both shots and confirm
  changed voice/speed are audible during an active session after Done and swipe
  dismissal. No visual or listening verification is claimed here.
