import SwiftUI

// Building blocks for the redesigned Work Details hub: the work identity hero
// card, the Overview quick-action grid tile, and the pure label/state helpers
// behind them. Visual language matches the Account tab (AccountShortcutGridTile,
// `.cardRow()` surfaces, native segmented Pickers) so Work Details reads as a
// sibling of Account and Author Profiles.

/// The four top-level Work Details sections, mirroring Account's
/// Overview / Reading / Writing / Activity segmented control.
enum WorkDetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case tags = "Tags"
    case discussion = "Discussion"
    case library = "Library"

    var id: String { rawValue }
}

/// The work identity hero card shown above the section control: title, tappable
/// author byline, fandoms, and the at-a-glance stat row. The full summary, tag
/// chips, and personal library state live in their sections, not here.
struct WorkDetailHeroCard: View {
    let title: String
    let authors: [String]
    let identities: [AO3AuthorIdentity]
    let fandoms: [String]
    let rating: String
    let status: String?
    let chapters: String
    let words: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if !authors.isEmpty {
                // A real Label (not a hand-rolled HStack) so the icon lines up
                // with the Fandoms Label right below it — a raw HStack can't
                // reproduce Label's exact icon size/gap/baseline alignment.
                Label {
                    AO3AuthorBylineView(
                        names: authors,
                        identities: identities,
                        includesBy: false,
                        font: .subheadline
                    )
                } icon: {
                    Image(systemName: "person")
                        .foregroundStyle(.secondary)
                }
            }

            if !fandoms.isEmpty {
                Label(fandoms.joined(separator: ", "), systemImage: "books.vertical")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            FlowLayout(spacing: 10, rowSpacing: 6) {
                if !rating.isEmpty {
                    WorkStatLabel(text: rating, symbol: "checkmark.shield")
                }
                if !chapters.isEmpty {
                    WorkStatLabel(text: chapters, symbol: "book")
                }
                if let status {
                    WorkStatLabel(
                        text: status,
                        symbol: status == "Complete" ? "checkmark.seal" : "circle.dashed"
                    )
                }
                if let words {
                    WorkStatLabel(text: words.formatted(), symbol: "textformat.size")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            // Only the stat pills merge into one VoiceOver element. The card
            // itself must stay `.contain` so the byline's individually routed
            // co-author buttons remain separately focusable/activatable.
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 4)
    }
}

/// One state-aware shortcut tile for the Overview quick-action grid. Same card
/// chrome as `AccountShortcutGridTile`; `detail` carries the current state
/// ("In 2 Queues"), and `isBusy` swaps the glyph for a spinner while a
/// download/import is in flight.
struct WorkQuickActionTile: View {
    @Environment(ThemeManager.self) private var theme

    let title: String
    let systemImage: String
    var detail: String?
    var isBusy = false

    private let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.tint)
                }
            }
            .frame(width: 36, height: 36)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.appTheme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                )
                .shadow(
                    color: theme.appTheme.cardShadow.color,
                    radius: theme.appTheme.cardShadow.radius,
                    x: 0,
                    y: theme.appTheme.cardShadow.y
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Pure label/state derivations for the Work Details quick actions and Library
/// rows, extracted from the old single-list view so the moved logic stays
/// unit-testable.
enum WorkDetailPresentation {
    static func readAction(
        hasEPUB: Bool, working: Bool, continueReading: Bool = false
    ) -> (title: String, systemImage: String) {
        if working { return ("Downloading…", "arrow.down.circle") }
        guard hasEPUB else { return ("Download & Read", "arrow.down.circle") }
        return continueReading ? ("Continue Reading", "book") : ("Read", "book")
    }

    static func savedAction(isSaved: Bool) -> (title: String, systemImage: String) {
        isSaved ? ("Saved", "bookmark.fill") : ("Save to Keep", "bookmark")
    }

    /// Compact tile labels; the Library row uses `WorkActionLabels.savedForLater`'s
    /// full wording for the same toggle.
    static func laterAction(isQueued: Bool) -> (title: String, systemImage: String) {
        isQueued ? ("Remove from Later", "bookmark.slash") : ("Save for Later", "clock.badge")
    }

    static func queueLabel(count: Int) -> String {
        count == 0 ? "Add to Queue" : "In \(count) Queue\(count == 1 ? "" : "s")"
    }

    static func collectionLabel(count: Int) -> String {
        count == 0 ? "Add to Collection" : "In \(count) Collection\(count == 1 ? "" : "s")"
    }

    /// What the detail should do after "Remove from Later" possibly soft-deleted
    /// a queue-only record: keep showing the (still-live) local work, fall back
    /// to remote state, or — with no remote source to fall back to — dismiss so
    /// the screen can't keep mutating a Recently Deleted record.
    enum PostRemovalAction: Equatable {
        case keepLocal
        case showRemote
        case dismiss
    }

    static func postRemovalAction(
        isPendingDeletion: Bool, hasRemoteSource: Bool
    ) -> PostRemovalAction {
        guard isPendingDeletion else { return .keepLocal }
        return hasRemoteSource ? .showRemote : .dismiss
    }

    /// Long summaries start collapsed behind a Show More affordance; short ones
    /// render in full with no extra control.
    static func summaryCollapses(_ summary: String) -> Bool {
        summary.count > 600
    }

    static func preservationStatusLabel(_ status: EPUBPreservationStatus) -> String {
        switch status {
        case .preserved: "Preserved offline"
        case .preserving: "Preserving…"
        case .queued: "Preservation queued"
        case .failed, .missingFile: "Needs restore"
        case .notPreserved: "Not preserved"
        }
    }

    /// On-disk EPUB size, formatted, or nil when the file doesn't exist.
    static func fileSizeLabel(forFileAt url: URL) -> String? {
        guard let value = try? FileManager.default.attributesOfItem(atPath: url.path)[.size],
              let bytes = (value as? NSNumber)?.int64Value
        else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
