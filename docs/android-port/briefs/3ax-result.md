# Brief 3ax result

**Landing note (Claude, 2026-10-05).** Landed with one change. It compiled and passed first
time; gate green (1,610 tests).

**How signing in works was not changed.** Read line by line: the hidden page that submits the
form, the script, the cookie check, `acceptWebLogin`, the 25-second timeout and the fallback
are as they were. What changed is what the reader sees and reads. One real improvement rides
along: in the demo the login screens no longer create a web view at all, so a demo can never
load AO3's login page.

Changed on landing: where AO3's login form cannot be found, the patch showed iOS's "Let's
finish logging in on AO3's page below." iOS moves to AO3's page by itself at that point;
Android does not, so there is nothing below. That case keeps Android's own truthful sentence
("Couldn't find AO3's login form. Try the alternative method.").

Fixed by the patch, beyond the brief's wording work: the sync-folder setup used to record
itself as done even when the first sync returned an error; the error now shows under
"Couldn't Connect" and setup is not marked done. A folder already connected in Settings no
longer gets the setup offered again. Back on Welcome no longer skips it.

Seen on the emulator through the new demo routes (`nav:welcome`, `nav:sync-onboarding`,
`nav:whats-new`, `nav:login`) in Light, Dark, Sepia and OLED and at double text size; a normal
demo launch still opens Home with none of them. In Dark and OLED the links and some actions
are the default accent on a near-black ground and hard to read: owner question 2. **Not
checked:** a real first run and a real sign-in (the emulator runs the demo only, and never
signs in), and What's New after a real update.

Still different from iOS on the login screen, all kept so as not to change how signing in
works: "Use alternative method", the fallback's Reload and Back controls, and AO3's own error
text for a wrong password (Android shows its generic sentence).

## Login mechanics findings — deliberately unchanged

- Android mounts and loads its hidden WebView immediately; iOS mounts one WebView and starts an automatic attempt on submit. Android replaces it with a second visible WebView on fallback; iOS keeps one host. Android clears the password on failure and disposal; iOS retains it on failure and avoids cancelling an in-flight attempt on incidental teardown. Android rejects a whitespace-only password; iOS tests only empty. These are outside this UI brief.
- iOS displays AO3's parsed error text for invalid credentials. Android inspection does not parse that text, so its existing generic “Login failed. Check your username and password.” remains. Adding extraction would change validation/inspection mechanics. No network or auth parser changes are made.

## Welcome — comparison before edits

| In iOS order | iOS (verbatim) | Android before this brief | Difference |
|---|---|---|---|
| Artwork | AppIconArt, 108pt rounded square | ic_kudos_mark, 108dp rounded square | Platform artwork |
| Title | Welcome to Kudos | Welcome to Kudos | Same |
| Subtitle | Free to use • Ad-free • Built by fans | Open Source • Ad-Free • Community Built | Drift |
| Point title | Built for AO3 Readers | Built for AO3 Readers | Same |
| Point text | An unofficial reader for Archive of Our Own. Kudos is free and open source, has no ads, and isn't affiliated with AO3 or the OTW. | An unofficial, third-party reader for Archive of Our Own — free, open source, and always ad-free. Not affiliated with AO3 or the OTW. | Drift |
| Point title | Your Privacy Matters | Your Privacy Matters | Same |
| Point text | Kudos has no ads, analytics, tracking, or hidden data collection. Your AO3 sign-in and the information Kudos needs stay on your device. | No ads, analytics, tracking, or hidden data collection. Anything the app needs — like your AO3 login — stays on your device. | Drift |
| Point title | Community Built | Community Built | Same |
| Point text | Kudos is made by fans. It doesn't accept donations, but you can contribute to the project. | A labor of love. Donations aren't accepted, but contributions are always welcome. | Drift |
| Point title | Need Help? | Need Help? | Same |
| Point text | Found a bug? Shake your device to send a report, or open an issue on GitHub. The AO3 team can't help with Kudos, so please don't contact them about it. | Found a bug? Shake your device to send a report, or open a GitHub issue. Please don't contact the AO3 team — they can't support this app. | Drift |
| Link | View on GitHub → https://github.com/cidy02/kudos-ao3-reader; hint: Opens the project's source code in your browser | Same label and destination, external ACTION_VIEW; no hint | Missing hint |
| Button | Continue | Continue | Same |
| Footnotes | None | None | Same |

## Sync-folder onboarding — comparison before edits

| In iOS order | iOS (verbatim) | Android before this brief | Difference |
|---|---|---|---|
| Artwork | folder.badge.gearshape, 108pt | Folder, 108dp | Android glyph |
| Title | Protect Your Library | Protect Your Library | Same |
| Subtitle | Optional. You can set this up anytime in Settings | Optional — set this up anytime in Settings | Drift |
| Point title | Choose a Folder | Choose a Folder | Same |
| Point text | Choose where Kudos keeps another copy of your library. If the folder is in iCloud Drive, Apple can keep it up to date on your devices. | Choose a folder where Kudos can safely keep a copy of your library data. If you choose a synced folder (like Google Drive or Syncthing), it will sync across your devices. | Android folder-provider adaptation plus drift |
| Point title | Works Fully Offline | Works Fully Offline | Same |
| Point text | You can use Kudos without an internet connection. If you skip this, you can choose a folder later in Settings. | Kudos still works completely offline either way, and you can set this up later in Settings if you'd rather skip it for now. | Drift |
| Point title | Changes May Take Time | Not Real-Time Cloud Sync | Drift |
| Point text | Kudos saves the same kind of file as a backup in your folder. Updates aren't instant. | This uses the existing Kudos backup format written to a folder you choose — it's folder-based sync, not real-time cloud sync. | Drift |
| Point title | Using More Than One Device? | Using More Than One Device? | Same |
| Point text | To let another device remove items from your library, pair it in Settings → Sync Folder → Deletion signing. Pairing takes a few seconds. | Deletes are signed on each device so only devices you've paired can remove things from your library. Pair your devices anytime in Settings → Deletion signing — it takes a few seconds. | Drift |
| Error point (conditional) | Couldn't Connect; UserFacingError.message(for: error) | Couldn't Connect; exception localizedMessage or Unknown error | Native errors; Android also ignored runSync() Error result (fixed below) |
| Toggle | Don't remind me again | Same checkbox label | Android control |
| Button | Choose Sync Folder (spinner while connecting) | Same | Same |
| Button | Not Now | Not Now | Same |
| Links / footnotes | None | None | Same |

## What's New — comparison before edits

| In iOS order | iOS (verbatim) | Android before this brief | Difference |
|---|---|---|---|
| Title | What's New | Absent | Missing screen |
| Section | Version 1.0 | Absent | Missing entry |
| Notes | Welcome to Kudos — a native SwiftUI reader for Archive of Our Own. | Absent | SwiftUI is iOS-only; adapt for Android |
| Toolbar button | Checkmark, accessibility label Done | Absent | Missing |
| Presentation | Sheet, visible drag indicator; no links or footnotes | Absent | Missing |

## Login — comparison before edits

| In iOS order | iOS (verbatim) | Android before this brief | Difference |
|---|---|---|---|
| Navigation title / cancellation | Log In to AO3 / Cancel | AO3 Login (account route), Sign In (native route); Cancel below fields | Drift |
| Section heading | AO3 Account (person glyph) | No heading; Sign in with your AO3 account. Your password is sent only to AO3 over HTTPS. | Drift |
| Field | Username or email | Same | Same |
| Secure field | Password | Same | Same |
| Footnote | Kudos submits these credentials only to AO3's official login page. Your password is never saved. | No footnote | Drift |
| Conditional error | auth.errorMessage, warning glyph, red | message above fields, no warning glyph | Drift; error sources differ (see mechanics) |
| Submit button | Log In / spinner + Logging In… | Sign in / spinner; Signing in… above fields | Drift |
| Link button | Create an AO3 account → https://archiveofourown.org/users/new in Browse, closing login | Absent | Missing |
| Link button | Forgot your password? → https://archiveofourown.org/users/password/new in Browse, closing login | Absent | Missing |
| Footnote | These open AO3 in the Browse tab. Come back here to log in afterwards. | Absent | Missing |
| Extra Android button | Absent | Use alternative method | Drift, retained to preserve existing fallback entry mechanics |
| Fallback banner | Using alternative login method… | Using alternative method — log in on AO3's page. | Drift |
| Fallback instruction | auth.fallbackMessage, normally Let's finish logging in on AO3's page below.; default Complete login on AO3 below. | Log in on AO3's page below. Kudos never sees or stores your password. | Drift |
| Fallback conditional error | auth.errorMessage | AO3 login was detected, but the session could not be captured. | Drift |
| Fallback extra controls | Only toolbar Cancel | Cancel, Reload, spinner; Back to username/password | Drift, retained to preserve fallback mechanics |
| Fallback slow-load text | No separate slow-load text; coordinator reports fallback prompt | This is taking a while - try Reload, or check your connection. | Android reload affordance; retain mechanics |

## Appearance and exit rules (source comparison)

| Screen | iOS | Android before this brief | Difference |
|---|---|---|---|
| Welcome | ContentView.onboardingPresented: !hasCompletedOnboarding; Continue (or binding dismissal) persists completion, then sync setup | KudosApp: nullable stored completion; Continue persists, then sync setup; demo bypass | Same primary flow; Android Back had no explicit handling |
| Sync setup | Completed welcome, not configured, not connected in FolderSyncService.snapshot(), not permanently dismissed, not dismissed this session. Success records configured; Not Now only records permanent dismissal when checked and always ends this session. Picker cancel leaves screen. | Same flag gates and session skip, but did not check an already connected folder. Picker permission is Android SAF. | Missing connected-folder suppression; copy drift |
| What's New | ContentView.onAppear only if welcome was already completed. Changelog.unseenEntries seeds missing last-seen to current version without notes. Changed version: entries preceding known version, or all if unknown. Done marks current seen; swipe only clears session entries. | Absent | Missing |
| Login | Sheets from Account Log In, Settings AO3 Account, author follow, Comments, account work lists and collections signed-out actions. Success, Cancel or help link closes; fallback/signingIn blocks swipe. | Navigation routes account-login and native-login from Account, Settings AO3 Account, collections, comments, work detail and author actions. Success pops to Account; Cancel pops one route. | Native navigation vs sheet; preserve real auth mechanics |

## iOS code takes precedence

The brief says What's New is remembered when dismissed. Actual ContentView only calls Changelog.markSeen on Done; swiping the sheet away does not mark it. Android follows that code: Back/swipe closes for this launch, Done remembers the version. There is no manual What's New button in iOS.

## Implemented Android behavior

- WelcomeScreen.kt now has every iOS heading and paragraph verbatim, in the same order, plus View on GitHub and Continue. The GitHub link still uses Android ACTION_VIEW. Continue persists the existing welcome flag; real Welcome consumes Back rather than skipping mandatory onboarding.
- OnboardingComponents.kt shares the intro and raised footer across both screens. It uses LocalKudosTokens, explicit line heights, a 540dp content limit and safe drawing insets. Buttons retain Material shapes with token colors and minimum rather than fixed heights. At isAccessibilityFontScale(), the entire screen scrolls, including the actions; regular type keeps the pinned footer.
- SyncFolderOnboardingScreen.kt uses the system OpenDocumentTree picker and existing SyncRepository.connect()/runSync(). Cancellation leaves the screen; successful initial merge/write records configured. Returned sync errors now appear in Couldn't Connect rather than falsely completing. KudosApp waits for a single firstRunState preference emission before deciding; a folder connected through Settings suppresses setup even without the historic configured flag. Once offered, setup stays mounted while connection publishes its URI, until completion or a visible error.
- Not Now (and Android Back) closes setup for the current launch. Only a checked Don't remind me again persists dismissal. A successful setup's configured record still suppresses the offer if the reader later disconnects the folder.
- What's New uses support/WhatsNew.kt: Changelog.entries is the bundled, newest-first release list. For each release, add its Android marketing version and paragraph there. Changelog.currentVersion reads BuildConfig.VERSION_NAME. The current entry is Version 0.2.1 / “Welcome to Kudos — a native Android reader for Archive of Our Own.” The version matches android/app/build.gradle.kts; “SwiftUI” becomes “Android” because it describes a platform-only implementation.
- SettingsRepository.lastSeenChangelogVersion is device-local, separate from KudosSettings and backup/restore. A missing key is seeded to the running version and shows nothing. An update offers entries preceding the remembered entry, or all entries if its version is missing. Done stores the running version; Back/swipe closes for this launch without writing it. No manual entry button was added, because iOS has none. KudosApp checks once on the first loaded launch state only when welcome was already completed, and presents after any full-screen setup finishes.
- Native login uses the shared SettingsPanel/SettingsFootnote chrome and tokens, with AO3 Account, both field labels, credential footnote, conditional warning, Log In / Logging In…, the two help buttons and their footnote in iOS order. The page owns Log In to AO3 and Cancel so the shell's single-line title cannot truncate them; its Android Back affordance remains. The header stacks at accessibility font scales. Both account-login and native-login route help to Browse, then the existing in-app web fallback destination, after closing login.
- All login timeout, WebView submission JavaScript, cookie inspection, authRepository.acceptWebLogin validation, password clearing, disposal and fallback navigation callbacks retain their production behavior. The explicit Use alternative method, fallback Reload/Cancel and Back to username/password controls remain because removing them would change the existing web-fallback entry/interaction mechanics. These are residual Android drift, not an Android system requirement. Both login views exclude WebView construction and all submit/reload/help dispatch while DemoNetwork is active.
- Deleted the unreferenced comment-only support/BugReport.kt. The real account/BugReportScreen.kt remains.

## Android-specific copy adaptations

| iOS wording / element | Android wording / element | Reason |
|---|---|---|
| If the folder is in iCloud Drive, Apple can keep it up to date on your devices. | Use the system folder picker. If the folder belongs to a cloud storage app, that app can keep it up to date on your devices. | Android SAF only offers providers that support folder selection; do not promise Google Drive or any named provider supports OpenDocumentTree. It is the provider, not Kudos, that shares the folder. |
| Version 1.0; native SwiftUI reader | Version 0.2.1; native Android reader | Android's running marketing version and implementation. No invented feature announcements. |
| SF Symbols and AppIconArt | Corresponding Material glyphs and ic_kudos_mark | Android artwork and controls. |
| Full-screen cover / sheet swipe | Android full-screen onboarding / Back; Material bottom sheet for notes | Android navigation. Mandatory Welcome consumes Back; optional setup handles it as Not Now. |

There is no “Files” label in the current iOS content to replace. The deletion-signing path is now verbatim Settings → Sync Folder → Deletion signing; that section exists in Android PairingSheet.kt, mounted by SettingsPages2.kt's SyncFolderSettingsPage.

## Login error copy

| Condition | iOS source wording | Android result |
|---|---|---|
| Empty credentials | Enter your AO3 username or email and password. | Existing UI validation disables submission. No new validation path. |
| Failed credentials | AO3's own parsed flash error (no hard-coded sentence in AO3LoginView) | Existing Login failed. Check your username and password. retained; inspection does not supply AO3's text. |
| Network failure | AO3 could not load. Check your connection and try again. (manual coordinator); hidden flow offers fallback prompt | Native network error now uses the same connection wording; original triggering behavior remains. |
| Timeout / form unavailable | Let's finish logging in on AO3's page below. | Same text; original 25-second timeout and form-unavailable behavior remain. |
| Session save failed | AO3 logged in, but the session could not be saved securely. | Same native sentence. |
| Fallback capture failed | AO3 logged in, but its session cookie could not be captured. | Same fallback sentence. |
| Fallback slow page | No equivalent slow-page action in AO3LoginView | Existing This is taking a while - try Reload, or check your connection. retained with Reload mechanics. |
| Other iOS-only observations | The AO3 login page could not be checked. / Return to AO3 to complete login. / The saved AO3 session could not be restored. | No new triggers fabricated; Android's observation and restoration mechanisms are unchanged. |

## Exact demo routes

Use a **debug build**, with both the existing demo extra and the route extra:

| Screen | kudosDebugRoute |
|---|---|
| Welcome | nav:welcome |
| Sync setup | nav:sync-onboarding |
| What's New | nav:whats-new |
| Native login (including inert fallback preview) | nav:login |

Example:
~~~sh
adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --es kudosDebugRoute nav:welcome --es kudosTheme sepia
~~~

Use kudosTheme light, dark, sepia or oled. The route resolver requires BuildConfig.DEBUG and DemoNetwork.isActive (the existing kudosDemoLibrary activation). It cannot override a real first run in a release build. Preview callbacks perform no onboarding/changelog preference writes; sync's picker is inert. DemoLibrary's existing seeding/bypass remains unchanged. Native login accepts text but Log In, help links, and fallback Reload do nothing; neither hidden nor visible WebView is mounted. Closing a preview returns to the demo app.

## Source trace for appearance and entry buttons

iOS reference:
- App/ContentView.swift: onAppear changelog check, onboardingPresented, syncFolderOnboardingPresented, sheet binding and Done callback.
- Features/Support/WhatsNew.swift: Changelog.unseenEntries/markSeen, WhatsNewView.
- Features/Onboarding/SyncFolderOnboardingView.swift: connect, dismissWithoutConnecting, FolderSyncOnboardingState.
- Features/Account/AccountView.swift → Account components: Log In to AO3 (Logging In… during an attempt).
- Settings/SettingsAccountPages.swift: AO3AccountSettingsSection's Log In to AO3….
- Features/Authors/AuthorProfileView.swift: protected actions first show “Log in to AO3”; that alert's Log In button opens the sheet.
- Features/Comments/CommentsView.swift: Log in to comment and comment-row onRequestLogin.
- Features/Bookmarks/AO3AccountWorksList.swift: signed-out Log In to AO3.
- Features/Account/AO3CollectionsList.swift: signed-out Log In to AO3….
- Features/Auth/AO3LoginView.swift and Services/AO3WebLoginCoordinator.swift / AO3AuthService.swift: content, errors and exit rules.

Android:
- app/KudosApp.kt: launch gate, session skip, notes presentation and preview dispatch.
- data/preferences/SettingsRepository.kt: firstRunState and local flags/version.
- app/AppNavHost.kt: AccountLogin and NativeLogin destinations; onLogin callbacks from Account, Collections, SettingsAccount, WorkDetail, Comments and AuthorProfile.
- app/Routes.kt: account-login / native-login; titles now Log In to AO3.
- onboarding/FirstRunState.kt and FirstRunDemoDestination.kt: exact debug/demo route gate and screen destinations.
- MainActivity.kt: passes a debug-route request counter so a repeated request reopens a dismissed preview. Its existing demo activation/bypass logic, app/DemoLibrary.kt and network/ao3/DemoNetwork.kt are unchanged.

## Verification and remaining work for Claude

**No Gradle, Xcode, sign-in or network calls were run.** No runtime compile/pass or visual correctness is claimed. TASKS.md, the branch, iOS reference, backup format, Room schema and auth services were not edited; no commits or pushes were made.

Static checks completed:
- Read the actual referenced Kotlin repositories, routes, theme tokens, Settings chrome, SyncResult variants and iOS presentation/auth code.
- Confirmed the new login glyphs exist in the locally cached material-icons-extended classes.
- Compared login submission JavaScript and AO3WebLoginInspection against HEAD; unchanged.
- Compared welcome and sync paragraph order against the reference, with the folder-provider adaptation listed above.
- git diff --check passes; no helper scripts, .orig files or stub source files were added.

Added no-network tests (not run):
- onboarding/FirstRunStateTest: fake in-memory DataStore; welcome then setup; temporary skip across launches; permanent skip and successful configuration; Settings-connected folder; fresh/known/unknown changelog versions; Done vs session dismissal; local flags survive settings restore; all routes require debug + demo.
- onboarding/FirstRunDemoScreensTest: route destinations and preview dismissal; inert picker; native submit, help and fallback Reload send nothing, verified by zero callbacks and no WebView in the Android hierarchy; 2× type scrollability/text layout across Light, Dark, Sepia and OLED, including What's New.

Run from android/:
~~~sh
./gradlew :app:assembleDebug :app:assembleRelease :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.onboarding.*'
~~~
Also run the existing auth, preferences, navigation and demo-network regression suites (or the full :app:testDebugUnitTest suite).

Runtime/UI checks still owed:
- Real first launch, Continue, Not Now unchecked then relaunch, checked then relaunch, an already-connected Settings folder, and completed-then-disconnected setup.
- Offline update with known and unknown last-seen version; Done persists, Back/swipe reoffers next launch, first install shows no notes; notes wait behind setup.
- Offline SAF cancel, connection error and successful initial sync; ensure setup stays mounted until the sync result.
- Open all four exact demo routes using kudosDemoLibrary and verify no live AO3/WebView activity. Existing real-login routes must also stay inert inside the demo.
- Review narrow portrait and landscape layouts at default and accessibility font scales in all four themes, including login fallback chrome, keyboard, sheet drag handle and both help footnotes.
- Real sign-in remains out of scope for this handoff; do not claim its correctness from these UI edits or demo tests.

