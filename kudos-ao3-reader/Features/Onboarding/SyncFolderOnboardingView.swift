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
        OnboardingScaffold(introSpacing: 30, topInset: 44, bottomInset: 8) {
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
        VStack(spacing: 18) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 36))
                .foregroundStyle(.accentInk)
                .frame(width: 64, height: 64)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius))
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Protect Your Library")
                    .font(.title.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
                    .multilineTextAlignment(.center)
                Text("Optional. You can set this up any time in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var introPoints: some View {
        VStack(alignment: .leading, spacing: 22) {
            point("folder", title: "Choose a folder",
                  message: "Kudos keeps a second copy of your library there. In iCloud Drive, "
                    + "Apple keeps it on your other devices too.")
            point("wifi.slash", title: "Works offline",
                  message: "You can use Kudos without an internet connection. If you skip this, "
                    + "you can choose a folder later in Settings.")
            point("doc.text.magnifyingglass", title: "Changes take a moment",
                  message: "Kudos saves the same kind of file as a backup. Updates are not instant.")
            point("ipad.and.iphone", title: "More than one device?",
                  message: "Point each one at the same folder. Pair devices in Settings to trust their deletions.")
            if let connectionError {
                OnboardingPointRow(
                    symbol: "exclamationmark.triangle", title: "Couldn't Connect", message: connectionError
                )
            }
        }
    }

    private func point(_ symbol: String, title: String, message: String) -> some View {
        OnboardingPointRow(symbol: symbol, title: title, message: message,
                           iconWidth: 30, horizontalSpacing: 14, messageFont: .footnote)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                choosingFolder = true
            } label: {
                if isConnecting {
                    ProgressView().frame(maxWidth: .infinity).accentFill()
                        .accessibilityLabel("Connecting sync folder")
                } else {
                    chooseFolderTitle
                }
            }
            .buttonStyle(.kudosPrimaryConfirm)
            .onboardingWrapsButton(at: dynamicTypeSize.isAccessibilitySize)
            .disabled(isConnecting)

            notNowButton
                .font(.body)
                .foregroundStyle(.accentInk)
                .disabled(isConnecting)

            dontRemindToggle
                .font(.footnote)
                .accentFill()
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
                Text("Don’t Remind Me Again")
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        } else {
            Toggle("Don’t Remind Me Again", isOn: $dontRemindAgain)
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
