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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var dontRemindAgain = false
    @State private var choosingFolder = false
    @State private var isConnecting = false
    @State private var connectionError: String?

    var body: some View {
        OnboardingScaffold {
            header
            introPoints
        } footer: {
            footer
        }
        .fileImporter(
            isPresented: $choosingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            connect(result)
        }
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
                Text("Optional. You can set this up anytime in Settings")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var introPoints: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingPointRow(
                symbol: "folder", title: "Choose a Folder",
                message: "Choose where Kudos keeps another copy of your library. If the folder "
                    + "is in iCloud Drive, Apple can keep it up to date on your devices."
            )
            OnboardingPointRow(
                symbol: "wifi.slash", title: "Works Fully Offline",
                message: "You can use Kudos without an internet connection. If you skip this, "
                    + "you can choose a folder later in Settings."
            )
            OnboardingPointRow(
                symbol: "doc.text.magnifyingglass", title: "Changes May Take Time",
                message: "Kudos saves the same kind of file as a backup in your folder. Updates "
                    + "aren't instant."
            )
            OnboardingPointRow(
                symbol: "signature", title: "Using More Than One Device?",
                message: "To let another device remove items from your library, pair it in Settings "
                    + "→ Sync Folder → Deletion signing. Pairing takes a few seconds."
            )
            if let connectionError {
                OnboardingPointRow(
                    symbol: "exclamationmark.triangle", title: "Couldn't Connect", message: connectionError
                )
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            dontRemindToggle
                .font(.subheadline)
                .accentFill()

            Button {
                choosingFolder = true
            } label: {
                if isConnecting {
                    ProgressView().frame(maxWidth: .infinity).accentFill()
                } else {
                    chooseFolderTitle
                }
            }
            .buttonStyle(.borderedProminent)
            .accentFill()
            .prominentLabel()
            .controlSize(.large)
            .onboardingWrapsButton(at: dynamicTypeSize.isAccessibilitySize)
            .disabled(isConnecting)

            notNowButton
                .font(.subheadline.weight(.medium))
                .disabled(isConnecting)
        }
    }

    @ViewBuilder
    private var notNowButton: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Button(action: dismissWithoutConnecting) {
                Text("Not Now")
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Button("Not Now", action: dismissWithoutConnecting)
        }
    }

    /// One line cut this to "Don't remin…" at AX5. The switch stays; the words wrap.
    @ViewBuilder
    private var dontRemindToggle: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Toggle(isOn: $dontRemindAgain) {
                Text("Don't remind me again")
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        } else {
            Toggle("Don't remind me again", isOn: $dontRemindAgain)
        }
    }

    @ViewBuilder
    private var chooseFolderTitle: some View {
        let title = Text("Choose Sync Folder").font(.headline)
        if dynamicTypeSize.isAccessibilitySize {
            title
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        } else {
            title.frame(maxWidth: .infinity)
        }
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
                connectionError = UserFacingError.message(for: error)
            }
        }
    }
}

/// Onboarding-state flags, kept separate from `hasCompletedOnboarding` (the existing
/// welcome-screen gate) so completing one never implies the other.
enum FolderSyncOnboardingState {
    static let configuredKey = "hasConfiguredSyncFolder"
    static let permanentlyDismissedKey = "hasPermanentlyDismissedSyncFolderOnboarding"

    static func recordConfigured(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: configuredKey)
    }

    static func recordDismissal(permanently: Bool, defaults: UserDefaults = .standard) {
        if permanently {
            defaults.set(true, forKey: permanentlyDismissedKey)
        }
        // Otherwise: no flag changes at all, so the onboarding predicate naturally stays
        // true and the screen reappears next launch — no separate "show next launch" flag needed.
    }
}
