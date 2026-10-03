# Brief 3h-fix Result: Signed-in Account Hub Parity with iOS

## Summary of Changes

1. **Top Screen Wash (`AccountScreen.kt`)**:
   - Added `LocalSubjectPalette.current` and applied `Modifier.subjectScreenWash(palette)` to the `LazyColumn` when `signedIn` is true.
   - When signed out, no wash is drawn ("no session, so no accent and no wash", matching iOS Artboard 1n).

2. **Identity Header as iOS Draws It (`AccountScreen.kt`)**:
   - Replaced card-wrapped profile header with a cardless identity layout matching `AccountComponents.swift` (Artboard 1m):
     - Kicker: "AO3 ACCOUNT" rendered in the accent color with `SubjectKicker` including its short accent rule (`ruleWidth = SubjectMetrics.pageRuleWidth`, `ruleSpacing = 7.dp`).
     - Avatar: 56dp circular avatar (`AccountAvatar`) beside the username.
     - Title: 27sp bold username title (`letterSpacing = -0.5.sp`, 1 line with ellipsis).
     - Session indicator: 7dp green circular dot beside secondary ink text ("Signed in", "Checking session…", "Session expired", etc.).
     - Actions row: "Posting as Account Default" (or selected pseud) glass capsule button (`tokens.glassFill(0.12)`) and a ⋯ glass circle button (`tokens.glassFill(0.12)`) side-by-side on the same row.
   - Preserved all callbacks and options in the ⋯ dropdown menu: Verify Session, Open on AO3, Settings, Privacy & Local Data, Backup, Local Reading History, Favorites, Local Collections, About Kudos, and Log Out.
   - Signed-out state retains iOS Artboard 1n layout: 56dp circular avatar, 27sp bold "Not signed in" title, secondary explanatory text, prominent capsule "Log In to AO3" button, and ⋯ menu.

3. **Top-Right Chrome Parity (`MainScaffold.kt`)**:
   - Researched history of the theme palette button using `git log -S "Theme cycling"`. It was added during earlier Android development for quick testing, whereas iOS dropped it from the Account tab in favor of configuring themes via Settings > Appearance.
   - Removed the `Icons.Outlined.Palette` circle button from the Account route in `MainScaffold.kt`.
   - Updated the Settings gear `ToolbarCircleButton` to use `isAccented = true`, rendering it as an accent-tinted glass circle matching iOS.

4. **Counts Data Source & "4+" Badge (`AccountListRepository.kt`, `AccountViewModel.kt`, `AO3AuthRepository.kt`)**:
   - On iOS, `AO3AccountListCountsCache` stores counts derived from fetched account list pages (exact count if `totalPages <= 1`, lower bound `itemsOnPage * (totalPages - 1)` with `+` if `totalPages > 1`). In the demo, the bundled `ao3_subscriptions.html` fixture has 2 items on page 1 across 3 pages, yielding a lower bound of `2 * (3 - 1) = 4` displayed as `"4+"`.
   - `AccountListRepository.kt` now records parsed list counts into `countsCache` on successful response.
   - `AO3AuthRepository.kt` was updated so that `--ez kudosDemoSignedIn true` supplies the demo `_otwarchive_session` cookie (matching iOS `DemoNetworkBlock.demoSignedIn`), allowing authenticated client requests in demo mode to route through `DemoNetworkInterceptor` to the fixture.
   - `AccountViewModel.kt` pre-loads the Subscriptions count on session restore when not already cached and emits updated counts via `countsFlow`.
   - Both the Subscriptions shortcut tile and the Subscriptions row in the Reading section display the `"4+"` count badge.

## Verification Evidence

- **Compilation & Unit Tests**:
  `cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`
  Passed cleanly (exit code 0).
- **Screenshots Captured on emulator-5554 (Airplane mode enabled)**:
  - `docs/android-port/shots/3h-fix/hub-signed-in-dark.png`: Signed-in Account hub showing the red top wash, "AO3 ACCOUNT" kicker with accent rule, 56dp avatar, "AO3_Reader" title, green dot + "Signed in", "Posting as Account Default" capsule + ⋯ circle, accent-tinted Settings gear (palette button removed), and "4+" badges on Subscriptions shortcut and Reading row.
  - `docs/android-port/shots/3h-fix/hub-signed-out-dark.png`: Signed-out Account hub showing clean neutral backdrop (no wash), "Not signed in" header, login button, "WHAT IS WAITING" preview section, and accent-tinted Settings gear.
- **Callback & String Audit**:
  Verified all `on...` callbacks and menu destinations against `git show HEAD:android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt`. No actions, callbacks, or strings were lost.
