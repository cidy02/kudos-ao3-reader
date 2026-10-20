# Brief 3ga: A66's verified fixes, batch 1 (Android)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Create
`docs/android-port/briefs/3ga-result.md` first; write each item into it as you finish it: what
changed (`path:line`), the iOS code followed (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`,
read-only), the test added.

Hard rules: `docs/AO3_NETWORKING_POLICY.md` and `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` are
binding; Room migrations additive only (none expected); backup manifest v8, additive keys; iOS is
the source of truth; nothing Android has may be lost; Android's ICU regex rejects some
JVM-accepted flags (`RegexPortabilityTest`). Sign-in code: never run it against AO3, never log or
store a password.

Each item below was checked by a verifier against today's code; its full finding, quotes on both
sides and suggested fix are in `docs/android-port/audits/A66-verified.json` (by `id`) and the
original audit in `docs/android-port/audits/A66-result.md`. Follow the verified fix unless the code
shows it wrong (then say why).

1. **#4 (data):** `files/CustomFontRepository.importFont` accepts fonts that later make every
   library backup export fail (over 4 MB, not a real TrueType/OpenType, or a total over 32 MB).
   Refuse them on import with iOS's words (`Settings/SettingsView.swift` importFont,
   `Services/KudosBackup.swift` `fontRejectionReason`, `fontTotalRejectionReason`), reusing
   `BackupFontValidator` and `BackupLimits`.
2. **#11:** the native login never ticks AO3's "remember me", so AO3 issues no `user_credentials`
   cookie (`auth/AO3NativeLoginScreen.kt` fill script; iOS `Services/AO3WebLoginCoordinator.swift:324`).
3. **#12:** a failed login keeps the password field as iOS does, shows AO3's own flash error when
   there is one, falls back as iOS does when the login form is missing, and the keyboard's Go
   submits (`Features/Auth/AO3LoginView.swift`, `AO3WebLoginCoordinator.swift`).
4. **#1 (decision changed today):** Privacy & Local Data's four Clears (Free up space, Clear reading
   positions, Clear reading history, Clear browse cache) always ask first, as iOS
   (`Features/Account/PrivacyDataView.swift:120`–`:177`), whatever "Confirm before deleting" says;
   that switch keeps governing swipes only, as its footnote says. Reverses DECISIONS 2026-10-09
   (3bz) by the owner's parity goal of 2026-10-20: add a DECISIONS entry saying so.
5. **#23:** Privacy & Local Data can be pulled to refresh its storage figures (iOS `.refreshable`).
6. **#19:** Settings › Downloads' "Storage used" is the same total Privacy & Local Data shows
   (`LocalDataFootprintScanner`), not a walk of `filesDir` (iOS `Settings/StorageUsedRow.swift`).
7. **#6:** Settings › Appearance holds what iOS's does (Theme, Match App & Reader Theme, Reader
   Theme, Accent Color, Reset to AO3 Red, Customize Theme…, Text Size): the second section of
   sliders (line height, letter and word spacing, margins) that also forced Customize on is
   removed, because the Customize Theme sheet (3fs) holds those sliders, as on iOS. Check nothing
   else in that section is lost; anything not in the sheet stays.
8. **#20:** Queue Storage's author line uses the verified byline that opens the author
   (`works/detail/VerifiedAuthorByline`), as iOS.
9. **#5:** Settings › Import's file picker lets every file through (`*/*`), as iOS's `.data`
   catch-all, so a format the importer cannot read gets a message naming it; check how a
   `.kudosbackup` picked there is handled and route it to the backup import if iOS does.

Tests for each where the rule is testable.
