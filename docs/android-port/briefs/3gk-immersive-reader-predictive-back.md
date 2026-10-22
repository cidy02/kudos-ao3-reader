# Brief 3gk (owner-approved U1): immersive reader and predictive back on Android

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests, looks on the emulator and lands it. Do not edit
`TASKS.md`. Create `docs/android-port/briefs/3gk-result.md` FIRST; write each item into it as you
finish it: what changed (`path:line`), the iOS code followed, the test added and how it fails with
the change undone.

The owner approved these on 2026-10-21 (DECISIONS). Android's chrome and platform behaviour are
Android's own; nothing a reader can see or do may be lost.

1. **Immersive reading.** iOS hides the status bar and the home indicator whenever the reader's
   controls are hidden and shows them with the controls
   (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift:363`–`:364`:
   `.statusBarHidden(!chromeVisible)`, `.persistentSystemOverlays(chromeVisible ? .automatic : .hidden)`).
   Android's reader (`reader/ReaderScreen.kt` and what it hosts) keeps the system bars on screen.
   Hide the status and navigation bars while the reader's chrome is hidden
   (`WindowInsetsControllerCompat`, `BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE`), show them with the
   chrome, and always restore them when the reader leaves the screen (back, a sheet that takes
   over, configuration change, process death and return). Sheets opened from the reader (Contents,
   Display & Themes, notes, Read Aloud) must not be covered or shifted by the bars changing, and
   the page must not jump when the bars come and go (keep the content laid out under them, as now).
   Read Aloud's mini player and any reader banner stay reachable.
2. **Predictive back.** Opt in (`android:enableOnBackInvokedCallback="true"` on `<application>` in
   `app/src/main/AndroidManifest.xml`). Navigation Compose 2.9.5 and Activity Compose 1.12.0 are in
   use. Find every custom back path (`BackHandler`, `PredictiveBackHandler`,
   `onBackPressedDispatcher`, `LocalOnBackPressedDispatcherOwner`, the shell's `onBack` in
   `app/MainScaffold.kt`) and confirm each still runs, in order, with the callback API: unsaved
   form guards (writing forms, the note editor, comment composer drafts), selection modes that
   exit on back, sheets that close on back, the reader's own back, the web view's history. Say for
   each where it is and whether it needed a change.
3. Tests: the manifest flag (read the manifest); the reader's system-bar state following the
   chrome and restored on leaving (Robolectric); at least one guarded back (an unsaved form) still
   asking first with the callback API.
