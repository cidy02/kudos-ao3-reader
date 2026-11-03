import SwiftData
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

    // Board 51's "Data on this iPhone": the same figures, selections and
    // confirmations as Privacy and local data (`LocalDataClearDialogs`).
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion })
    private var works: [SavedWork]
    @State private var footprint = LocalStorageFootprint()
    @State private var hasMeasured = false
    @State private var confirmClearHistory = false
    @State private var confirmClearDownloads = false
    @State private var confirmClearPositions = false
    @State private var confirmClearBrowseCache = false
    @State private var browseCacheCleared = false

    private var freedHistory: [SavedWork] { LocalDataClearDialogs.freedHistory(from: works) }
    private var freeableDownloads: [SavedWork] { LocalDataClearing.selectFreeableDownloads(from: works) }
    private var positionedWorks: [SavedWork] { LocalDataClearing.selectReadingPositions(from: works) }

    private var cacheLabel: String {
        hasMeasured ? LocalStorageFootprint.formatted(bytes: footprint.cacheBytes) : "—"
    }

    var body: some View {
        SettingsPageForm(route: .privacySettings) {
            Section {
                Toggle("Hide mature content", isOn: $hideMatureContent).accentFill()
                if hideMatureContent {
                    Picker("When locked", selection: $matureMode) {
                        ForEach(MaturePrivacyMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accentFill()

                    Toggle("Require Face ID to reveal", isOn: $requireBiometric).accentFill()
                }
                NavigationLink(value: SettingsRoute.privacy) {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#3A3A3C") ?? .gray, systemImage: "hand.raised")
                        Text("Privacy & Local Data")
                    }
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

            Section {
                dataRow(
                    title: "Browse cache",  // what it clears: saved fandom lists
                    detail: cacheLabel,
                    button: browseCacheCleared ? "Cleared" : "Clear",
                    disabled: browseCacheCleared
                ) { confirmClearBrowseCache = true }
                dataRow(
                    title: "Reading history",
                    detail: Self.workCount(freedHistory.count),
                    button: "Clear…",
                    disabled: freedHistory.isEmpty
                ) { confirmClearHistory = true }
                dataRow(
                    title: "Reading positions",
                    detail: Self.workCount(positionedWorks.count),
                    button: "Clear…",
                    disabled: positionedWorks.isEmpty
                ) { confirmClearPositions = true }
                dataRow(
                    title: "Downloads of finished works",
                    detail: Self.workCount(freeableDownloads.count),
                    button: "Free…",
                    disabled: freeableDownloads.isEmpty
                ) { confirmClearDownloads = true }
            } header: {
                Text("Data on this \(ThisDevice.name)")
            } footer: {
                Text("Kudos keeps your reading on this device. Your AO3 sign-in stays in the "
                    + "Keychain and is never in a backup. Privacy and Local Data lists everything "
                    + "stored here.")
            }
        }
        .task {
            guard !hasMeasured else { return }
            await measure()
        }
        .modifier(LocalDataClearDialogs(
            works: works,
            confirmHistory: $confirmClearHistory,
            confirmDownloads: $confirmClearDownloads,
            confirmPositions: $confirmClearPositions,
            confirmBrowseCache: $confirmClearBrowseCache,
            browseCacheCleared: $browseCacheCleared,
            cacheLabel: cacheLabel,
            onMeasure: { Task { await measure() } }
        ))
    }

    nonisolated static func workCount(_ count: Int) -> String { "\(count) work\(count == 1 ? "" : "s")" }

    private func measure() async {
        let readingCopies = works.filter { $0.hasEPUB && !$0.isDownloaded }.map(\.fileURL)
        footprint = await LocalDataFootprintScanner.measure(readingCopies: readingCopies)
        hasMeasured = true
    }

    /// Title and measured detail on the left, the inline destructive button on the
    /// right. The button is the only control: the row itself does nothing, so a
    /// stray tap on the text cannot start a clear.
    private func dataRow(
        title: String, detail: String, button: String, disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            Button(button, role: .destructive, action: action)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(disabled)
                .accessibilityLabel("\(button.replacingOccurrences(of: "…", with: "")) \(title)")
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
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
        #if DEBUG
        .task { if DebugLaunchRoute.takeSheet("aboutkudos") { showAbout = true } }
        #endif
        .sheet(isPresented: $showAbout) {
            NavigationStack { AboutView() }
                .environment(themeManager)
                .accentTint(themeManager.effectiveTint, on: themeManager.appTheme)
        }
        .sheet(isPresented: $showingBugReport) {
            BugReportView()
                .environment(themeManager)
                .accentTint(themeManager.effectiveTint, on: themeManager.appTheme)
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
                HStack(spacing: 12) {
                    SettingsIconTile(color: Color(hex: "#3A3A3C") ?? .gray, systemImage: "hand.raised")
                    Text("Privacy and local data")
                }
            }

            Button(action: onShowAbout) {
                HStack(spacing: 12) {
                    SettingsIconTile(color: Color(hex: "#8E8E93") ?? .gray, systemImage: "info.circle")
                    Text("About Kudos")
                }
            }

            Button(action: onReportBug) {
                HStack(spacing: 12) {
                    SettingsIconTile(color: Color(hex: "#FF3B30") ?? .red, systemImage: "ladybug")
                    Text("Report a Bug")
                }
            }

            if let url = URL(string: AppLinks.repository) {
                Link(destination: url) {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#6C6C70") ?? .gray, systemImage: "chevron.left.forwardslash.chevron.right")
                        Text("Source on GitHub")
                    }
                }
            }
        } footer: {
            // 1ab's closing line: these rows change Kudos, and AO3's own
            // account settings stay on AO3.
            Text("These settings only change Kudos. Change anything AO3 stores about your "
                + "account in AO3 Preferences.")
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
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#821019") ?? .red, systemImage: "person.crop.circle")
                        Text("Signed In")
                    }
                }

                Button(role: .destructive) {
                    confirmingLogOut = true
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#D70015") ?? .red, systemImage: "rectangle.portrait.and.arrow.right")
                        Text("Log Out")
                    }
                }
                .logOutConfirmation(isPresented: $confirmingLogOut) { Task { await auth.logout() } }

            case .signedOut, .signingIn, .usingFallback:
                Button(action: onLogIn) {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#821019") ?? .red, systemImage: "person.badge.key")
                        Text("Log In to AO3…")
                    }
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
