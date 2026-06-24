import OSLog
import SwiftUI
import LocalAuthentication

/// How Mature/Explicit works are presented when content privacy is on.
enum MaturePrivacyMode: String, CaseIterable, Identifiable {
    case obscure, hide
    var id: String { rawValue }
    var title: String {
        switch self {
        case .obscure: "Blur"
        case .hide: "Hide"
        }
    }
}

extension SavedWork {
    /// AO3-rated Mature or Explicit — the works the privacy feature shields.
    var isAdult: Bool { rating == "Mature" || rating == "Explicit" }
}

/// Tracks which sensitive works the user has temporarily revealed this session,
/// and gates reveals behind device biometrics when the user has enabled that.
@MainActor
@Observable
final class PrivacyGate {
    private(set) var revealedIDs: Set<UUID> = []
    /// When true, every sensitive work is shown until toggled back off.
    private(set) var revealAll = false

    func isRevealed(_ work: SavedWork) -> Bool { revealAll || revealedIDs.contains(work.id) }

    /// Reveals a single work (a Blur-mode tap), authenticating first if required.
    func reveal(_ work: SavedWork) {
        authenticate {
            self.revealedIDs.insert(work.id)
            Log.privacy.info("Revealed a mature work for this session")
        }
    }

    /// Shows or re-hides every sensitive work for the session.
    func toggleRevealAll() {
        if revealAll {
            revealAll = false
            revealedIDs.removeAll()
            Log.privacy.info("Re-hid all mature works")
        } else {
            authenticate {
                self.revealAll = true
                Log.privacy.info("Revealed all mature works for this session")
            }
        }
    }

    /// Whether this work should be omitted from a list right now (Hide mode only).
    func isHidden(_ work: SavedWork, enabled: Bool, mode: MaturePrivacyMode) -> Bool {
        enabled && work.isAdult && mode == .hide && !isRevealed(work)
    }

    private func authenticate(_ onSuccess: @escaping () -> Void) {
        guard UserDefaults.standard.bool(forKey: "requireBiometricToReveal") else {
            onSuccess(); return
        }
        let context = LAContext()
        var error: NSError?
        // If no passcode/biometrics are enrolled, don't lock the user out of their library.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            onSuccess(); return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "View mature content") { success, _ in
            if success {
                Task { @MainActor in onSuccess() }
            } else {
                Log.privacy.notice("Biometric auth failed or was cancelled; mature content stays hidden")
            }
        }
    }
}

/// A work row that respects content privacy. When the work is Mature/Explicit and
/// Blur mode is on, it blurs the row and reveals on tap; in Hide mode the list
/// filters the work out before it reaches this view. Otherwise it's a normal
/// navigation row. The caller still attaches its own `.swipeActions`.
struct SensitiveWorkRow: View {
    let work: SavedWork
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var mode: MaturePrivacyMode = .obscure

    private var blurred: Bool {
        hideMature && work.isAdult && mode == .obscure && !gate.isRevealed(work)
    }

    var body: some View {
        if blurred {
            WorkRow(work: work)
                .blur(radius: 6)
                .overlay {
                    Label("Tap to reveal", systemImage: "eye.slash.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
                .contentShape(Rectangle())
                .onTapGesture { gate.reveal(work) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hidden mature work. Activate to reveal.")
        } else {
            NavigationLink(value: work) { WorkRow(work: work) }
        }
    }
}

/// The eye toolbar button that reveals / re-hides Mature works for the session
/// (gated by Face ID when enabled). Shared by Library, History, and Favorites.
struct MatureRevealToggle: View {
    @Environment(PrivacyGate.self) private var gate

    var body: some View {
        Button {
            gate.toggleRevealAll()
        } label: {
            Label(gate.revealAll ? "Hide mature" : "Show mature",
                  systemImage: gate.revealAll ? "eye.slash" : "eye")
        }
    }
}

/// Placeholder shown when a list's only items are Mature works hidden by privacy.
struct MatureContentHiddenView: View {
    @Environment(PrivacyGate.self) private var gate

    var body: some View {
        ContentUnavailableView {
            Label("Mature works hidden", systemImage: "eye.slash")
        } description: {
            Text("Mature and Explicit works are hidden. Reveal them to read.")
        } actions: {
            Button("Show mature") { gate.toggleRevealAll() }
        }
    }
}
