import Foundation
import SwiftData
import SwiftUI

// Settings › Account & Privacy (AO3 Account, Privacy) and Settings › About.
// Sections moved as-is from the old single Settings page.

/// Copy helpers for Settings › AO3 Account (`Settings-Account`).
enum SettingsAccountCopy {
    static func loggedInTitle(username: String) -> String {
        "Logged in as \(username)"
    }

    static func sessionSubtitle(deviceName: String) -> String {
        "Session stored on this \(deviceName) only"
    }
}

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hideMatureContent") private var hideMatureContent = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @AppStorage("requireBiometricToReveal") private var requireBiometric = false

    // Board 51's "Data on this iPhone": the same figures, selections and
    // confirmations as Privacy and local data (`LocalDataClearDialogs`).
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion })
    private var works: [SavedWork]
    @State private var cacheBytes: Int64?
    @State private var downloadMeasurement: (urls: [URL], bytes: Int64?)?
    @State private var confirmClearHistory = false
    @State private var confirmClearDownloads = false
    @State private var confirmClearPositions = false
    @State private var confirmClearBrowseCache = false
    @State private var browseCacheCleared = false

    private var freedHistory: [SavedWork] { LocalDataClearDialogs.freedHistory(from: works) }
    private var freeableDownloads: [SavedWork] { LocalDataClearing.selectFreeableDownloads(from: works) }
    private var positionedWorks: [SavedWork] { LocalDataClearing.selectReadingPositions(from: works) }

    private var cacheLabel: String {
        cacheBytes.map { LocalStorageFootprint.formatted(bytes: $0) } ?? "—"
    }

    var body: some View {
        let downloadURLs = freeableDownloads.map(\.fileURL)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                privacyPanel
                localDataPanel(downloadURLs: downloadURLs)
                NavigationLink(value: SettingsRoute.privacy) {
                    HStack(spacing: 10) {
                        Image(systemName: "shield")
                            .foregroundStyle(.accentInk)
                            .accessibilityHidden(true)
                        Text("Privacy and Local Data").foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondaryInk)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minHeight: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(themeManager.appTheme.cardSurface, in: cardShape)
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.vertical, 8)
        }
        .appScreenSurface(.grouped)
        .navigationTitle(SettingsRoute.privacySettings.pageTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await measureCache() }
        .task(id: downloadURLs) {
            let bytes = await Task.detached(priority: .utility) {
                Self.allocatedBytes(for: downloadURLs)
            }.value
            guard !Task.isCancelled else { return }
            downloadMeasurement = (downloadURLs, bytes)
        }
        .modifier(LocalDataClearDialogs(
            works: works,
            confirmHistory: $confirmClearHistory,
            confirmDownloads: $confirmClearDownloads,
            confirmPositions: $confirmClearPositions,
            confirmBrowseCache: $confirmClearBrowseCache,
            browseCacheCleared: $browseCacheCleared,
            cacheLabel: cacheLabel,
            onMeasure: { Task { await measureCache() } }
        ))
    }

    nonisolated static func workCount(_ count: Int) -> String { "\(count) work\(count == 1 ? "" : "s")" }

    private var hideModePicker: some View {
        Picker("How to hide", selection: $matureMode) {
            ForEach(MaturePrivacyMode.allCases) { mode in
                Text(SystemPrivacyBoardCopy.modeTitle(mode)).tag(mode)
            }
        }
        .accessibilityLabel("How to hide")
        .accentFill()
    }

    private var privacyPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            panelHeader("Mature and Explicit works")
            VStack(spacing: 0) {
                Toggle(isOn: $hideMatureContent) {
                    HStack(spacing: 10) {
                        WorkSymbolTileView(symbol: .rating("Explicit", dark: colorScheme == .dark))
                            .accessibilityHidden(true)
                        Text("Hide mature content")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .accentFill()
                .padding(.horizontal, 16)
                .frame(minHeight: 46)

                if hideMatureContent {
                    SubjectRowSeparator(inset: 0)
                    if dynamicTypeSize.isAccessibilitySize {
                        hideModePicker.pickerStyle(.menu)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    } else {
                        hideModePicker.pickerStyle(.segmented)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    SubjectRowSeparator(inset: 0)
                    Toggle(isOn: $requireBiometric) {
                        Text(SystemPrivacyBoardCopy.authenticationTitle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.switch)
                    .accentFill()
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                }
            }
            .background(themeManager.appTheme.cardSurface, in: cardShape)
            panelFooter(hideMatureContent
                ? "Applies to your Library, Home and history."
                : "You see Mature and Explicit works normally.")
        }
    }

    private func localDataPanel(downloadURLs: [URL]) -> some View {
        let downloadBytes = downloadMeasurement?.urls == downloadURLs ? downloadMeasurement?.bytes : nil
        return VStack(alignment: .leading, spacing: 6) {
            panelHeader("Data on this \(ThisDevice.name)")
            VStack(spacing: 0) {
                dataRow(
                    title: "Browse cache",
                    detail: cacheLabel,
                    button: browseCacheCleared ? "Cleared" : "Clear",
                    disabled: browseCacheCleared
                ) { confirmClearBrowseCache = true }
                SubjectRowSeparator(inset: 0)
                dataRow(
                    title: "Reading history",
                    detail: Self.workCount(freedHistory.count),
                    button: "Clear…",
                    disabled: freedHistory.isEmpty
                ) { confirmClearHistory = true }
                SubjectRowSeparator(inset: 0)
                dataRow(
                    title: "Reading positions",
                    detail: Self.workCount(positionedWorks.count),
                    button: "Clear…",
                    disabled: positionedWorks.isEmpty
                ) { confirmClearPositions = true }
                SubjectRowSeparator(inset: 0)
                dataRow(
                    title: "Downloads of finished works",
                    detail: SystemPrivacyBoardCopy.downloadDetail(count: downloadURLs.count, bytes: downloadBytes),
                    button: "Free…",
                    disabled: downloadURLs.isEmpty
                ) { confirmClearDownloads = true }
            }
            .background(themeManager.appTheme.cardSurface, in: cardShape)
            panelFooter("Kudos keeps your reading on this device. Your AO3 sign-in stays in the "
                + "Keychain and is never in a backup.")
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
    }

    private func panelHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .padding(.horizontal, 16)
            .accessibilityAddTraits(.isHeader)
    }

    private func panelFooter(_ detail: String) -> some View {
        Text(detail)
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
    }

    private func measureCache() async {
        cacheBytes = await Task.detached(priority: .utility) {
            Self.allocatedBytes(for: [FandomCatalogCache.defaultFileURL]) ?? 0
        }.value
    }

    private nonisolated static func allocatedBytes(for urls: [URL]) -> Int64? {
        var bytes: Int64 = 0
        for url in urls {
            guard let info = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]),
                  let size = info.totalFileAllocatedSize ?? info.fileSize
            else { return nil }
            bytes += Int64(size)
        }
        return bytes
    }

    /// Title and measured detail on the left, the inline destructive button on the
    /// right. The button is the only control: the row itself does nothing, so a
    /// stray tap on the text cannot start a clear.
    private func dataRow(
        title: String, detail: String, button: String, disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(button, role: .destructive, action: action)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(disabled)
                .accessibilityLabel("\(button) \(title)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
    }
}

enum SystemPrivacyBoardCopy {
    static var authenticationTitle: String {
        #if os(iOS)
        "Require Face ID to reveal"
        #else
        "Require authentication to reveal"
        #endif
    }

    static func downloadDetail(count: Int, bytes: Int64?) -> String {
        let works = SettingsPrivacyPage.workCount(count)
        guard let bytes, count > 0 else { return works }
        return "\(works) · \(LocalStorageFootprint.formatted(bytes: bytes))"
    }

    static func modeTitle(_ mode: MaturePrivacyMode) -> String {
        switch mode {
        case .obscure: "Blur"
        case .hide: "Hide Completely"
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
                    SettingsIconTile(color: Color(hex: "#1E63C8") ?? .blue, systemImage: "shield")
                    Text("Privacy and Local Data")
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
    @Environment(ThemeManager.self) private var themeManager
    @State private var confirmingLogOut = false

    var body: some View {
        Section {
            switch auth.status {
            case .restoring:
                // Restoring the AO3 session — show the shape of the signed-in row.
                SkeletonListRow(width: 96, trailingWidth: 120)

            case let .signedIn(username):
                let identity = themeManager.appTheme.subjectPalette(hue: CoverArt.hue(for: username))
                let initial = username.first.map { String($0).uppercased() } ?? "?"
                let title = SettingsAccountCopy.loggedInTitle(username: username)
                let subtitle = SettingsAccountCopy.sessionSubtitle(deviceName: ThisDevice.name)

                HStack(spacing: 12) {
                    Text(initial)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(identity.labelOnAccent)
                        .frame(width: 36, height: 36)
                        .background(identity.accent, in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(title)
                .accessibilityValue(subtitle)

                NavigationLink {
                    AO3PreferencesView()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#8E8E93") ?? .gray, systemImage: "slider.horizontal.3")
                        Text("AO3 Preferences")
                    }
                }

                Button("Log Out", role: .destructive) {
                    confirmingLogOut = true
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
        } header: {
            Text("AO3")
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
