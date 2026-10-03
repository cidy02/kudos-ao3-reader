# Brief 3i-fix3: every Settings page as iOS draws it

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`
Use **emulator-5554 only** (airplane mode; keep it). Open Settings directly:
`adb -s emulator-5554 shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --es kudosTheme dark --es kudosDebugRoute nav:settings`

The Settings hub now matches iOS (`3ebbfcd2`). **The pages behind it don't.** iOS references, Dark,
one per page: `docs/android-port/shots/ios/settings/*.png` (appearance, font, reader, listening,
downloads, preservation, reading-queues, library, backup, sync-folder, import, privacy, about).
iOS code: `kudos-ao3-reader/Settings/Settings*Page*.swift` and `SettingsHubView.swift`
(`SettingsPageForm`) in the iOS lane
`/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish`.

## Bugs seen on Appearance (`settings/SettingsPages.kt`), likely on every page
1. The header collides with the back circle, and the title is drawn twice (once by the chrome's
   `customTitle`, once by the page's `SubjectHeaderBlock`). Do what the hub does: a status-bar inset
   plus 56.dp, then a `SubjectHeaderBlock` (kicker "SETTINGS", page title). Set no `customTitle`
   when the page draws its own header.
2. "App Theme" is a `SubjectFormRow` with the chips as trailing content, so the label wraps one
   letter per line. iOS uses a "Theme" field label over a full-width segmented control (Light,
   Sepia, Dark, OLED). Add one `SubjectSegmentedControl` in `ui/subject/` (iOS `Picker`
   `.segmented`: a glass track with a filled selected segment) and use it wherever iOS uses a
   segmented picker (Theme, Reader Scrolled/Paged, Privacy Blur/Hide).
3. The accent colour is drawn as hex-text chips plus a text field. iOS has an "Accent Color" row
   with a colour well, "Reset to AO3 Red", and a "Customize Theme" row. Use colour swatches
   (circles) for the presets, keep custom hex entry behind a row, and keep Apply and Reset working.

## Do
For each page, match the iOS shot: field labels, row types (toggle, value, disclosure, destructive
action in accent), the footnote under each panel (iOS strings verbatim), and order. **Keep every
control that exists today.** Android-only controls (text spacing sliders, Software Update, the
Alpha note, the font importer) stay, placed where the nearest iOS equivalent lives:
- spacing sliders on Appearance or Font;
- Software Update and the Alpha note on About.

`SettingsStringsTest` must stay green; add any newly visible strings to it if you like.

Save Android Dark shots of every page to `docs/android-port/shots/3i-fix3/` with the same names as
the iOS ones. Append a "3i-fix3" section to `docs/android-port/briefs/3i-result.md`: one line per
page, saying what changed and what still differs from iOS, and why.

Don't touch `backup/`, `data/local`, migrations, `app/MainScaffold.kt`, `app/Routes.kt`, `reader/`,
`search/` or `works/`.
