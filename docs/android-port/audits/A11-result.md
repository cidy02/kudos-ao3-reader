# A11 Audit Result: Strings

## Counts
- iOS files read: 17
- Strings checked: 89
- Found: 66
- Not found: 23

## Not found on Android

| String | iOS Path:Line | Kind | Search | Nearest Android File |
|---|---|---|---|---|
| **kudos-ao3-reader/Features/Onboarding/WelcomeView.swift** | | | | |
| `An unofficial reader for Archive of Our Own. Kudos is free and open source, has no ads, and isn't affiliated with AO3 or the OTW.` | `kudos-ao3-reader/Features/Onboarding/WelcomeView.swift:46` | OnboardingPointRow message | Exact | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/WelcomeScreen.kt` |
| `Kudos has no ads, analytics, tracking, or hidden data collection. Your AO3 sign-in and the information Kudos needs stay on your device.` | `kudos-ao3-reader/Features/Onboarding/WelcomeView.swift:51` | OnboardingPointRow message | Exact | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/WelcomeScreen.kt` |
| `Kudos is made by fans. It doesn't accept donations, but you can contribute to the project.` | `kudos-ao3-reader/Features/Onboarding/WelcomeView.swift:56` | OnboardingPointRow message | Exact | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/WelcomeScreen.kt` |
| `Found a bug? Shake your device to send a report, or open an issue on GitHub. The AO3 team can't help with Kudos, so please don't contact them about it.` | `kudos-ao3-reader/Features/Onboarding/WelcomeView.swift:61` | OnboardingPointRow message | Exact | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/WelcomeScreen.kt` |
| **kudos-ao3-reader/Features/Onboarding/SyncFolderOnboardingView.swift** | | | | |
| `Choose where Kudos keeps another copy of your library. If the folder is in iCloud Drive, Apple can keep it up to date on your devices.` | `kudos-ao3-reader/Features/Onboarding/SyncFolderOnboardingView.swift:61` | OnboardingPointRow message | Exact | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/SyncFolderOnboardingScreen.kt` |
| `You can use Kudos without an internet connection. If you skip this, you can choose a folder later in Settings.` | `kudos-ao3-reader/Features/Onboarding/SyncFolderOnboardingView.swift:66` | OnboardingPointRow message | Exact | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/SyncFolderOnboardingScreen.kt` |
| `Kudos saves the same kind of file as a backup in your folder. Updates aren't instant.` | `kudos-ao3-reader/Features/Onboarding/SyncFolderOnboardingView.swift:71` | OnboardingPointRow message | Exact | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/SyncFolderOnboardingScreen.kt` |
| `To let another device remove items from your library, pair it in Settings → Sync Folder → Deletion signing. Pairing takes a few seconds.` | `kudos-ao3-reader/Features/Onboarding/SyncFolderOnboardingView.swift:76` | OnboardingPointRow message | Exact | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/SyncFolderOnboardingScreen.kt` |
| **kudos-ao3-reader/Features/Auth/AO3LoginView.swift** | | | | |
| `Kudos submits these credentials only to AO3's official login page. Your password is never saved.` | `kudos-ao3-reader/Features/Auth/AO3LoginView.swift:129` | Text | Exact | `android/app/src/main/java/io/github/cidy02/kudos/auth/AO3NativeLoginScreen.kt` |
| `Complete login on AO3 below.` | `kudos-ao3-reader/Features/Auth/AO3LoginView.swift:187` | Text | Exact | `android/app/src/main/java/io/github/cidy02/kudos/auth/AO3NativeLoginScreen.kt` |
| **kudos-ao3-reader/Features/Privacy/MatureContent.swift** | | | | |
| `Double-tap to select this work.` | `kudos-ao3-reader/Features/Privacy/MatureContent.swift:189` | accessibilityHint | Exact | `android/app/src/main/java/io/github/cidy02/kudos/ui/subject/SubjectWorkCoverCard.kt` |
| `Double-tap to deselect this work.` | `kudos-ao3-reader/Features/Privacy/MatureContent.swift:189` | accessibilityHint | Exact | `android/app/src/main/java/io/github/cidy02/kudos/ui/subject/SubjectWorkCoverCard.kt` |
| **kudos-ao3-reader/Features/Support/WhatsNew.swift** | | | | |
| `Welcome to Kudos — a native SwiftUI reader for Archive of Our Own.` | `kudos-ao3-reader/Features/Support/WhatsNew.swift:21` | ChangelogEntry notes | Exact | `android/app/src/main/java/io/github/cidy02/kudos/support/WhatsNew.kt` |
| **kudos-ao3-reader/Features/Support/BugReportView.swift** | | | | |
| `Include a screenshot` | `kudos-ao3-reader/Features/Support/BugReportView.swift:104` | Toggle | Exact | `android/app/src/main/java/io/github/cidy02/kudos/account/BugReportScreen.kt` |
| `Found a bug? Describe what happened and Kudos will open a prefilled GitHub issue you can review and post. Nothing is sent automatically.` | `kudos-ao3-reader/Features/Support/BugReportView.swift:27` | Text | Exact | `android/app/src/main/java/io/github/cidy02/kudos/account/BugReportScreen.kt` |
| `Only these app and system details are sent with your report. Nothing personal is included, and never your AO3 account.` | `kudos-ao3-reader/Features/Support/BugReportView.swift:48` | Text | Exact | `android/app/src/main/java/io/github/cidy02/kudos/account/BugReportScreen.kt` |
| `Attached screenshot preview` | `kudos-ao3-reader/Features/Support/BugReportView.swift:117` | accessibilityLabel | Exact | `android/app/src/main/java/io/github/cidy02/kudos/account/BugReportScreen.kt` |
| `Kudos screenshot` | `kudos-ao3-reader/Features/Support/BugReportView.swift:120` | SharePreview | Exact | `android/app/src/main/java/io/github/cidy02/kudos/account/BugReportScreen.kt` |
| `Save or Share Screenshot` | `kudos-ao3-reader/Features/Support/BugReportView.swift:122` | Label | Exact | `android/app/src/main/java/io/github/cidy02/kudos/account/BugReportScreen.kt` |
| `Screenshot` | `kudos-ao3-reader/Features/Support/BugReportView.swift:126` | Section header | Exact | `android/app/src/main/java/io/github/cidy02/kudos/account/BugReportScreen.kt` |
| `GitHub can't add the screenshot for you. Save it, then drag or paste it into the issue.` | `kudos-ao3-reader/Features/Support/BugReportView.swift:128` | Text | Exact | `android/app/src/main/java/io/github/cidy02/kudos/account/BugReportScreen.kt` |
| `\n- Screenshot: attached below (added separately)` | `kudos-ao3-reader/Features/Support/BugReportView.swift:161` | String interpolation | Exact | `android/app/src/main/java/io/github/cidy02/kudos/account/BugReportScreen.kt` |
| **kudos-ao3-reader/App/ContentView.swift** | | | | |
| `Show in Library` | `kudos-ao3-reader/App/ContentView.swift:127` | Button | Exact | none |

## Found, but worded differently on Android
None observed during manual review.

## What I did not read
I did not read files outside the specified iOS folders or strings contained in comments, debug-only code blocks, and `#Preview` blocks.
