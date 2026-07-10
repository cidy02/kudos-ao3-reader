import LocalAuthentication
import OSLog
import SwiftUI

/// How Mature/Explicit works are presented when content privacy is on.
enum MaturePrivacyMode: String, CaseIterable, Identifiable {
    case obscure, hide
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .obscure: "Blur"
        case .hide: "Hide"
        }
    }
}

extension SavedWork {
    /// AO3-rated Mature or Explicit — the works the privacy feature shields.
    var isAdult: Bool {
        rating == "Mature" || rating == "Explicit"
    }
}

/// Tracks which sensitive works the user has temporarily revealed this session,
/// and gates reveals behind device biometrics when the user has enabled that.
@MainActor
@Observable
final class PrivacyGate {
    private(set) var revealedIDs: Set<UUID> = []
    /// When true, every sensitive work is shown until toggled back off.
    private(set) var revealAll = false

    func isRevealed(_ work: SavedWork) -> Bool {
        revealAll || revealedIDs.contains(work.id)
    }

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

    /// Whether a Privacy button should show for this currently-visible/filtered work
    /// list — the single rule every toolbar's Privacy-button condition shares.
    static func hasVisibleMatureWorks(in works: [SavedWork], hideMature: Bool) -> Bool {
        hideMature && works.contains(where: \.isAdult)
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
    /// Forwarded to the underlying `WorkRow` so a list's expand/collapse-all toggle
    /// reaches local cards too.
    var expandAll: Bool = false
    var openMode: LocalWorkRowOpenMode = .detail
    var onSelect: (() -> Void)?
    /// When true, taps toggle selection instead of navigating/revealing, and the
    /// row shows a selection bubble (mirrors the carousel's `SelectableWorkCoverCard`).
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)?
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var mode: MaturePrivacyMode = .obscure
    /// Drives the blurred row's own expand toggle — WorkRow's internal state isn't
    /// reachable since its expand button is suppressed (`showsExpandButton: false`)
    /// in favor of the unblurred external copy below.
    @State private var blurredExpanded = false

    private var blurred: Bool {
        hideMature && work.isAdult && mode == .obscure && !gate.isRevealed(work)
    }

    var body: some View {
        if blurred {
            // isSelecting/isSelected are deliberately NOT passed to WorkRow here —
            // its own inline selection bubble would otherwise be blurred into
            // illegibility along with the rest of the row. showsExpandButton: false
            // suppresses WorkRow's own expand control for the same reason; an
            // unblurred copy is overlaid below instead, bound to the same expanded
            // state via `externalExpanded` so it still expands the blurred content.
            // The card's selection outline comes from the enclosing `.cardRow(isSelected:)`
            // at the card's true edge, not from an overlay here (matches WorkRow).
            let isExpandableWork = WorkRow.isExpandable(for: work)
            let content = WorkRow(work: work, showsExpandButton: false, externalExpanded: $blurredExpanded)
                .blur(radius: 6)
                .overlay {
                    // Only while a tap would actually reveal — in select mode a tap
                    // toggles selection instead (use the toolbar's "Show mature" to
                    // reveal while selecting), so the label shouldn't promise otherwise.
                    if !isSelecting {
                        Label("Tap to reveal", systemImage: "eye.slash.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    // Rendered outside the blur so it stays legible and tappable —
                    // mirrors WorkRow's own top-trailing [expand][bubble] cluster.
                    HStack(spacing: 6) {
                        if isExpandableWork {
                            WorkRowExpandButton(expanded: $blurredExpanded)
                        }
                        if isSelecting {
                            WorkSelectionBubble(isSelected: isSelected)
                        }
                    }
                    .padding(8)
                }
            if isSelecting {
                // A real Button (not `.onTapGesture`) so the nested expand button
                // above reliably captures its own taps first — the same nesting
                // pattern `visibleRow`'s selecting branch already relies on.
                Button {
                    onToggleSelection?()
                } label: {
                    content
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(work.title)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
            } else {
                Button {
                    gate.reveal(work)
                } label: {
                    content
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hidden mature work. Activate to reveal.")
            }
        } else {
            visibleRow
        }
    }

    @ViewBuilder
    private var visibleRow: some View {
        let row = WorkRow(work: work, expandAll: expandAll, isSelecting: isSelecting, isSelected: isSelected)
            .localWorkContextMenu(work: work, onSelect: onSelect)
        if isSelecting {
            Button {
                onToggleSelection?()
            } label: {
                row
            }
            .buttonStyle(.plain)
            .accessibilityLabel(work.title)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            switch openMode {
            case .detail:
                row.cardNavigation(to: work)
            case .reader:
                row.cardNavigation(to: LocalWorkDestination.reader(work))
            }
        }
    }
}

/// A carousel card that respects content privacy, mirroring `SensitiveWorkRow` for
/// `WorkCoverCard`. When the work is Mature/Explicit and Blur mode is on, it blurs
/// the card and reveals on tap; in Hide mode the carousel filters the work out
/// before it reaches this view. Also covers the selection-mode carousel case
/// (`SelectableWorkCoverCard`), so a single component is the drop-in replacement
/// for both of `LibraryView`'s carousel-card branches.
struct SensitiveWorkCoverCard: View {
    let work: SavedWork
    var footer: String?
    var progress: Double?
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)?
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var mode: MaturePrivacyMode = .obscure

    private var blurred: Bool {
        hideMature && work.isAdult && mode == .obscure && !gate.isRevealed(work)
    }

    var body: some View {
        if blurred {
            let card = WorkCoverCard(work: work, footer: footer, progress: progress)
                .blur(radius: 6)
                .overlay {
                    // Only while a tap would actually reveal — in select mode a tap
                    // toggles selection instead (use the toolbar's "Show mature" to
                    // reveal while selecting), so the label shouldn't promise otherwise.
                    if !isSelecting {
                        Label("Tap to reveal", systemImage: "eye.slash.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
                .contentShape(Rectangle())
            if isSelecting {
                card
                    .overlay(alignment: .topTrailing) {
                        WorkSelectionBubble(isSelected: isSelected)
                            .padding(8)
                    }
                    // Matches SelectableWorkCoverCard's whole-card outline — without
                    // it, a blurred selected card only shows the small corner bubble,
                    // not the same selected-state ring unblurred cards get.
                    // allowsHitTesting(false): purely decorative — a stroked Shape
                    // overlay is still hit-testable across its full bounds by
                    // default, which would otherwise swallow the onTapGesture below.
                    .overlay {
                        RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                    .onTapGesture { onToggleSelection?() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(work.title)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
            } else {
                card
                    .onTapGesture { gate.reveal(work) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Hidden mature work. Activate to reveal.")
            }
        } else if isSelecting {
            Button {
                onToggleSelection?()
            } label: {
                SelectableWorkCoverCard(work: work, footer: footer, progress: progress, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(work.title)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            WorkCoverCard(work: work, footer: footer, progress: progress)
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
