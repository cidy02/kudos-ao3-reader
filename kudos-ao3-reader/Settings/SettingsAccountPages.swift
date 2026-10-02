import SwiftUI

// Settings › Account & Privacy (AO3 Account, Privacy) and Settings › About.
// Sections moved as-is from the old single Settings page.

struct SettingsAccountPage: View {
    @State private var showAO3Login = false

    var body: some View {
        SettingsPageForm(route: .account) {
            AO3AccountSettingsSection(onLogIn: { showAO3Login = true })
        }
        .sheet(isPresented: $showAO3Login) {
            AO3LoginView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Mature-content privacy, and the way on to Privacy and local data (1ac).
struct SettingsPrivacyPage: View {
    @AppStorage("hideMatureContent") private var hideMatureContent = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @AppStorage("requireBiometricToReveal") private var requireBiometric = false

    var body: some View {
        SettingsPageForm(route: .privacySettings) {
            Section {
                Toggle("Hide mature content", isOn: $hideMatureContent)
                if hideMatureContent {
                    Picker("When locked", selection: $matureMode) {
                        ForEach(MaturePrivacyMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Require Face ID to reveal", isOn: $requireBiometric)
                }
                NavigationLink(value: SettingsRoute.privacy) {
                    Label("Privacy & Local Data", systemImage: "hand.raised")
                }
            } footer: {
                Text(hideMatureContent
                    ? (matureMode == .hide
                        ? "Kudos hides Mature and Explicit works from your Library, History, and "
                        + "Favorites until you reveal them."
                        : "Kudos blurs Mature and Explicit works in your Library, History, and "
                        + "Favorites until you tap to reveal them.")
                    : "You see Mature and Explicit works normally.")
            }
        }
    }
}

struct SettingsAboutPage: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var showAbout = false
    @State private var showingBugReport = false

    var body: some View {
        SettingsPageForm(route: .about) {
            AboutSettingsSection(
                onShowAbout: { showAbout = true },
                onReportBug: { showingBugReport = true }
            )
        }
        .sheet(isPresented: $showAbout) {
            NavigationStack { AboutView() }
                .environment(themeManager)
                .tint(themeManager.effectiveTint)
        }
        .sheet(isPresented: $showingBugReport) {
            BugReportView()
                .environment(themeManager)
                .tint(themeManager.effectiveTint)
        }
    }
}

/// Artboard 1ab's About group.
private struct AboutSettingsSection: View {
    var onShowAbout: () -> Void
    var onReportBug: () -> Void

    var body: some View {
        Section {
            // 1ab states the running version on the page. It was reachable only
            // by opening the About sheet — the one place you cannot read it from
            // while writing a bug report about it.
            LabeledContent("Version", value: Changelog.currentVersion)

            NavigationLink(value: SettingsRoute.privacy) {
                Label("Privacy and local data", systemImage: "hand.raised")
            }

            Button(action: onShowAbout) {
                Label("About Kudos", systemImage: "info.circle")
            }

            Button(action: onReportBug) {
                Label("Report a Bug", systemImage: "ladybug")
            }

            if let url = URL(string: AppLinks.repository) {
                Link(destination: url) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        } footer: {
            // 1ab's closing line. The last sentence is the one worth stating:
            // the accent chosen on the Appearance page is what tints the Account
            // tab's wash, which neither screen says on its own.
            Text("These settings only change Kudos. Change anything AO3 stores about your "
                + "account in AO3 Preferences. Your accent colour from Appearance also colours "
                + "this tab.")
        }
    }
}

/// The AO3 session rows. The only section in Settings that touches AO3, and it
/// says so in its footer.
private struct AO3AccountSettingsSection: View {
    var onLogIn: () -> Void

    @Environment(AO3AuthService.self) private var auth
    @State private var confirmingLogOut = false

    var body: some View {
        Section {
            switch auth.status {
            case .restoring:
                // Restoring the AO3 session — show the shape of the signed-in row.
                SkeletonListRow(width: 96, trailingWidth: 120)

            case let .signedIn(username):
                LabeledContent {
                    Text(username)
                } label: {
                    Label("Signed In", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button(role: .destructive) {
                    confirmingLogOut = true
                } label: {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .logOutConfirmation(isPresented: $confirmingLogOut) { Task { await auth.logout() } }

            case .signedOut, .signingIn, .usingFallback:
                Button(action: onLogIn) {
                    Label("Log In to AO3…", systemImage: "person.badge.key")
                }
            }
        } footer: {
            if let notice = auth.noticeMessage {
                Text(notice)
            } else {
                Text("Sign in to use your AO3 bookmarks, history, subscriptions, kudos, "
                    + "comments, and restricted works in Kudos.")
            }
        }
    }
}
