import SwiftUI

// Building blocks for the Work Details hub: the Overview quick-action grid tile
// and the pure label/state helpers behind it. Visual language matches the
// Account tab where the two hubs are playing the same role — the segmented
// section Picker uses Account's own `accountControlCardRow()` chrome, and
// `WorkQuickActionTile` shares `AccountShortcutGridTile`'s `CardRadius.tile` —
// but work-content cards (tag/status/stats sections) deliberately keep the
// Library's standard `.cardRow()` geometry instead, exactly as
// `AccountControlStyle.swift` documents ("Work cards deliberately retain the
// library's standard geometry"). The two hubs are siblings in
// navigation-chrome, not in every card radius.
//
// The work's own identity — header, figure strip, resume card — moved to
// `WorkDetailIdentityBlock.swift` when it took artboard 1a's treatment: it is
// no longer a card, so it no longer belongs in a file about card chrome.

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

    private let cornerRadius: CGFloat = CardRadius.tile

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
        // .combine (not .isButton) — this tile's only call site (quickAction(_:)
        // in WorkDetailOverviewSections.swift) already wraps it in a real Button,
        // which supplies the trait on its own; adding it again here doubled the
        // "Button" announcement (HIG audit UI-2).
        .accessibilityElement(children: .combine)
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

    /// Compact tile labels for the keep-offline toggle. Menus use
    /// `WorkActionLabels.saved`'s full wording ("Download" / "Remove Download").
    static func savedAction(isSaved: Bool) -> (title: String, systemImage: String) {
        isSaved
            ? ("Downloaded", WorkActionLabels.downloadedSymbol)
            : ("Download", WorkActionLabels.downloadEmptySymbol)
    }

    /// Compact tile labels; the Library row uses `WorkActionLabels.savedForLater`'s
    /// full wording for the same toggle. Icons match that pair (clock, not bookmark).
    static func laterAction(isQueued: Bool) -> (title: String, systemImage: String) {
        let icons = WorkActionLabels.savedForLater(isQueued: isQueued)
        return (
            isQueued ? "Remove from Later" : "Save for Later",
            icons.systemImage
        )
    }

    /// The one line under "My copy" — spec 1a's "Downloaded · 2 queues · 1 tag".
    /// Only states what is true: a work in no queues says nothing about queues
    /// rather than "0 queues", and a work with nothing local at all says so in
    /// as many words instead of showing an empty line.
    static func myCopySummary(
        isDownloaded: Bool,
        queueCount: Int,
        tagCount: Int,
        collectionCount: Int
    ) -> String {
        var segments: [String] = []
        if isDownloaded {
            segments.append("Downloaded")
        }
        if queueCount > 0 {
            segments.append(pluralised(queueCount, "queue"))
        }
        if collectionCount > 0 {
            segments.append(pluralised(collectionCount, "collection"))
        }
        if tagCount > 0 {
            segments.append(pluralised(tagCount, "tag"))
        }
        if segments.isEmpty {
            return "Nothing saved on this device yet"
        }
        return segments.joined(separator: " · ")
    }

    private static func pluralised(_ count: Int, _ noun: String) -> String {
        if count == 1 {
            return "1 " + noun
        }
        return String(count) + " " + noun + "s"
    }

    static func queueLabel(count: Int) -> String {
        count == 0 ? "Add to Queue" : "In \(count) Queue\(count == 1 ? "" : "s")"
    }

    static func collectionLabel(count: Int) -> String {
        count == 0 ? "Add to Collection" : "In \(count) Collection\(count == 1 ? "" : "s")"
    }

    /// What the detail should do after "Remove from Later" possibly soft-deleted
    /// a queue-only record: keep showing the (still-live) local work, fall back
    /// to remote/AO3 state, or — only when there is nothing left to show — dismiss
    /// so the screen can't keep mutating a Recently Deleted record.
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

    /// Sparse AO3 blurb built from a local record so Work Details can stay open
    /// after a queue-only remove soft-deletes the local copy (opened from Library
    /// with no separate `remote` payload).
    static func summaryFromLocal(_ work: SavedWork) -> AO3WorkSummary? {
        guard let id = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) else {
            return nil
        }
        let authors = work.author
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return AO3WorkSummary(
            id: id,
            title: work.title,
            authors: authors,
            authorIdentities: work.verifiedAuthorIdentities,
            fandoms: work.workFandoms,
            rating: work.rating,
            warnings: work.workWarnings,
            categories: work.workCategories,
            relationships: work.workRelationships,
            characters: work.workCharacters,
            isComplete: work.isComplete,
            dateUpdated: work.dateUpdated,
            tags: work.workFreeforms,
            summary: work.summary,
            language: work.language,
            words: work.wordCount > 0 ? work.wordCount : nil,
            chapters: work.chapters,
            comments: work.comments > 0 ? work.comments : nil,
            kudos: work.kudos > 0 ? work.kudos : nil,
            bookmarks: work.bookmarks > 0 ? work.bookmarks : nil,
            hits: work.hits > 0 ? work.hits : nil,
            seriesTitle: work.seriesTitle.isEmpty ? nil : work.seriesTitle,
            seriesURL: work.seriesURL.isEmpty ? nil : work.seriesURL,
            seriesPosition: work.seriesPosition > 0 ? work.seriesPosition : nil
        )
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
