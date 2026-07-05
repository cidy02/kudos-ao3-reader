import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// First-install Library Sync Folder onboarding, shown once after `WelcomeView` (never
/// in place of it). Optional and dismissible — Settings remains the fallback surface for
/// configuring this regardless of what the user chooses here.
struct SyncFolderOnboardingView: View {
    /// Called once the user has connected a folder, or dismissed for good (checkbox
    /// checked); the host persists completion. Dismissing without the checkbox leaves
    /// the host free to show this again next launch.
    var onFinished: () -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @State private var dontRemindAgain = false
    @State private var choosingFolder = false
    @State private var isConnecting = false
    @State private var connectionError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    introPoints
                }
                .padding(.horizontal, 28)
                .padding(.top, 44)
                .padding(.bottom, 24)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            footer
        }
        .background(backgroundColor.ignoresSafeArea())
        .fileImporter(
            isPresented: $choosingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            connect(result)
        }
    }

    private var backgroundColor: Color {
        if let themed = theme.appTheme.appBaseBackground { return themed }
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .frame(width: 108, height: 108)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Protect Your Library")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Optional — set this up anytime in Settings")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var introPoints: some View {
        VStack(alignment: .leading, spacing: 22) {
            point(
                "folder", "Choose a Folder",
                "Choose a folder where Kudos can safely keep a copy of your library data. "
                    + "If you choose a folder in iCloud Drive, Apple can sync it across your devices."
            )
            point(
                "wifi.slash", "Works Fully Offline",
                "Kudos still works completely offline either way, and you can set this up "
                    + "later in Settings if you'd rather skip it for now."
            )
            point(
                "doc.text.magnifyingglass", "Not Real-Time CloudKit Sync",
                "This uses the existing Kudos backup format written to a folder you choose — "
                    + "it's folder-based sync, not real-time CloudKit sync."
            )
            if let connectionError {
                point("exclamationmark.triangle", "Couldn't Connect", connectionError)
            }
        }
    }

    private func point(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Toggle("Don't remind me again", isOn: $dontRemindAgain)
                .font(.subheadline)

            Button {
                choosingFolder = true
            } label: {
                if isConnecting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Choose Sync Folder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isConnecting)

            Button("Not Now", action: dismissWithoutConnecting)
                .font(.subheadline.weight(.medium))
                .disabled(isConnecting)
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func dismissWithoutConnecting() {
        FolderSyncOnboardingState.recordDismissal(permanently: dontRemindAgain)
        onFinished()
    }

    private func connect(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }
        isConnecting = true
        connectionError = nil
        Task { @MainActor in
            defer { isConnecting = false }
            do {
                try FolderSyncService.connect(to: url)
                // Matches the required first-connection flow: if a sync file already
                // exists, this merges it in before writing back; if not, it seeds the
                // folder from local state. Never destructive either way.
                _ = try await FolderSyncService.syncNow(in: modelContext)
                FolderSyncOnboardingState.recordConfigured()
                onFinished()
            } catch {
                connectionError = error.localizedDescription
            }
        }
    }
}

/// Onboarding-state flags, kept separate from `hasCompletedOnboarding` (the existing
/// welcome-screen gate) so completing one never implies the other.
enum FolderSyncOnboardingState {
    static let configuredKey = "hasConfiguredSyncFolder"
    static let permanentlyDismissedKey = "hasPermanentlyDismissedSyncFolderOnboarding"

    static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: configuredKey) && !defaults.bool(forKey: permanentlyDismissedKey)
    }

    static func recordConfigured(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: configuredKey)
    }

    static func recordDismissal(permanently: Bool, defaults: UserDefaults = .standard) {
        if permanently {
            defaults.set(true, forKey: permanentlyDismissedKey)
        }
        // Otherwise: no flag changes at all, so shouldShow(...) naturally stays true and
        // the screen reappears next launch — no separate "show next launch" flag needed.
    }
}
