# Brief 3gu (Android): Read Aloud settings in the reader, and the dashboard's bookmarks

**Write code in this worktree only (`/Users/cidy02/kudos-agent-codex`, branch
`android/agent-codex-3gu`). Do not commit, push, switch branches, sign in, contact
archiveofourown.org, or run Gradle (Claude builds and tests).** Do not edit `TASKS.md`. Create
`docs/android-port/briefs/3gu-result.md` FIRST and fill it in as you go: `path:line` for each
change and, for each test, what it does if the change is reverted (it must fail).

Grok's inventory (`docs/android-port/audits/A81-result.md`, rows 63 and 85) found two iOS screens
Android has no counterpart for. The owner's goal is parity with no lost features; both are small.

1. **Read Aloud settings from inside the reader** (iOS `Features/ReaderReadium/ReaderSpeechSettingsSheet.swift`
   in `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader`, opened by a long press on the fan's Read
   Aloud button, `ReadiumReaderView.swift:1288`, and by the mini player's waveform button,
   `ReaderSpeechController.swift:940-960`). On Android a long press on Read Aloud opens the
   Display sheet (`reader/ReaderScreen.kt:693`). Make it open a "Read Aloud" sheet that holds the
   same controls as Settings › Listening — reuse `settings/SettingsListeningPage.kt`'s content, do
   not copy it — titled "Read Aloud" with Done, and apply the chosen voice and speed to speech
   already playing when the sheet closes (iOS calls `speech.applyPreferences()` on dismiss). If the
   mini player (`reader/ReaderPositionCard.kt`, `PositionMiniPlayer`) draws iOS's equalizer bars,
   make them open the same sheet, spoken "Read Aloud settings"; if it draws no such control, add
   none and say so. The Display sheet keeps its own Read Aloud group (iOS's has one too).
2. **The dashboard's "See all bookmarks"** opens the author profile on its Bookmarks tab, as iOS
   (`Features/Authors/AuthorProfileView.swift:83` pushes `AuthorProfileView` on Bookmarks). On
   Android it opens the account Bookmarks list (`author/AuthorProfileScreen.kt:879`,
   `AccountListType.Bookmarks`). "See all works" and "See all series" stay as they are. Use the
   existing author-profile route with an initial tab (as `author-about/<name>` opens About); add a
   route only if none can take a tab.
3. Add two names to the DEBUG shot dispatcher (`app/DebugShots.kt`): `readerspeech` (the reader
   with the new Read Aloud sheet open) and `authorbookmarks` (the author profile on Bookmarks).
4. Tests (Robolectric/JVM, as the suite's others): the long press opens the Read Aloud sheet, not
   the Display sheet; the dashboard's bookmarks link goes to the author profile's Bookmarks tab.
   Each must fail with its change reverted.

Nothing else changes. Keep `BuildConfig.DEBUG` guards on anything debug-only.
