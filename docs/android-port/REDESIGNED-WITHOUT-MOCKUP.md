# Screens redesigned without a mockup

Owner, 2026-10-20: *"if there are any screens that are not redesigned in the mockup, feel free to
do a best effort redesign and document it. the goal is visual and UX parity with no lost
features or information"*, and *"document in a separate .md any screens without a mockup that
you redesign"*.

The mockup is `docs/design/Final_Redesign_Spec.dc.html` (87 artboards, index
`.claude-overnight/polish/artboards.tsv` in the integrate tree). The screens below have no
artboard (`INVENTORY.md`, the rows marked "—").

## Rules for a best-effort redesign

- Use the shared redesign parts only: on Android `ui/subject/` (`SubjectHeaderBlock`,
  `SectionRuleHeader`, `subjectPanel`, `SubjectFormRow`, `SubjectToggle`,
  `SubjectSegmentedControl`, `subjectScreenWash`, the chips and cards); on iOS
  `UIComponents/SubjectSurface.swift`, `SubjectForm.swift`, `cardRow`.
- Keep every control, figure and line of text the screen had, in the same order unless the
  redesign's grammar elsewhere orders it differently (then say so below).
- Android's navigation and chrome stay Material 3 (owner, 2026-10-04).
- Where iOS already restyled the screen, Android follows iOS and the entry says so. Where
  neither had, both apps get the same redesign (or the entry names the side still to follow).
- Each entry: what it was, what it is now, the screen on the other app it matches, what was kept,
  the commit(s), and how it was seen (theme, text size, device).

## Screens with no artboard, and where each stands

| Screen | iOS file | Android file | Status |
|---|---|---|---|
| Add to queue / Add to collection | `AddToQueueView`, `AddToCollection…` | `library/WorkMembershipDialogs.kt` | to look at |
| Collections See All grid | `LibraryEntityGridView` | ? | to look at |
| Add works sheet | `AddLibraryWorksSheet` | `library/AddLibraryWorksSheet.kt` | to look at |
| Settings pages (reading, storage, backup, import, sync folder) | `Settings/*Page*.swift` | `settings/SettingsPages*.kt`, `backup/BackupScreen.kt` | compared 3dh–3dl (both on card rows, T-330) |
| Onboarding, Sync Folder onboarding | `WelcomeView`, `SyncFolderOnboardingView` | `onboarding/*.kt` | compared 3dh–3dl; to look at again for the redesign's grammar |
| About, legal, bug report, What's New, backup import, pairing | `AboutView`, `LegalNoticesView`, `BugReportView`, `WhatsNew`, `BackupImportSheet`, `PairingSheet` | `account/AboutScreen.kt`, `account/BugReportScreen.kt`, `support/WhatsNew.kt`, `backup/PairingSheet.kt` | compared 3dh–3dl in part; to look at |
| Availability sweep | `AvailabilitySweepView` | `settings/AvailabilitySweepScreen.kt` | compared (T-330 card rows) |
| Reader chrome, position card, scrub | `ReadiumReaderView`, `ReaderChromeTopBar`, `ReaderPositionCard`, `ReaderChapterScrub` | `reader/*` | compared 3dk–3dm; owner asked for the reader's controls to match the app (3dk, T-403) |
| Reader Contents, Find in Work, notes | `ReaderContentsSheet`, `ReaderSearchView`, `ReaderNoteEditor` | `reader/*` | compared 3dl, 3dz |
| Read Aloud settings, pronunciation, fan menu, Customize Theme | `ReaderSpeechSettingsSheet`, `ReaderPronunciationSettingsView`, `ReaderFanMenu`, `CustomizeThemeView` | `reader/*`, `settings/SettingsListeningPage.kt` | Customize Theme: iOS's sheet on Android since 3fs (`c6b0576a`), seen on the emulator; pronunciation: brief 3ft (missing on Android) |
| In-app web view | `WebBrowser` | `web/AO3WebViewFallbackScreen.kt` | to look at |

## Redesigned screens

(none yet)
