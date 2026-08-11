import SwiftData
import SwiftUI

/// Where a work came from, what state it is in, and what can be done about it —
/// as sections of Work Details rather than a sheet of its own.
///
/// This began as `WorkStatusSheet`, presented by the card's ⓘ button. That was one
/// screen too many: Work Details is already the place that answers "what is this
/// work", so provenance belongs beside the publication and stats cards instead of in
/// a parallel surface reachable only from a carousel. The ⓘ now pushes Work Details,
/// which also makes it useful on *every* card rather than only on works that happened
/// to have a badge worth showing.
///
/// Built to the same construction as the rest of Work Details — `Section` +
/// `.cardRow()` — so it inherits that screen's chrome and theming rather than
/// carrying its own.
struct WorkProvenanceSections: View {
    let work: SavedWork

    @Environment(\.modelContext) private var context

    @State private var rebuilding = false
    @State private var rebuildError: String?
    @State private var rebuilt = false
    @State private var confirmingRedundantRebuild = false

    var body: some View {
        originSection
        if !statuses.isEmpty { statusSection }
        if candidate != nil { conversionSection }
    }

    private var candidate: WorkReconversion.Candidate? {
        WorkReconversion.candidate(for: work)
    }

    // MARK: - Sections

    private var originSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(originSentence)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: work.origin.symbolName)
                        .foregroundStyle(.secondary)
                }
                if !work.sourceURL.isEmpty {
                    // Selectable and shown in full: for a work its site has deleted,
                    // this is often the only citation that still exists.
                    Text(work.sourceURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if !work.origin.supportsLiveLookup {
                    Text("Kudos can't reach \(unreachableName), so tags, stats and availability "
                        + "aren't refreshed for this work, and kudos and comments aren't available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .cardRow()
        } header: {
            Text("Origin")
        }
    }

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(statuses, id: \.text) { badge in
                    WorkStateBadge(text: badge.text, symbol: badge.symbol)
                        .font(.caption2)
                }
                if let explanation = work.preservationState.explanation(origin: work.origin) {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .cardRow()
        } header: {
            Text("Status")
        }
    }

    @ViewBuilder
    private var conversionSection: some View {
        if let candidate {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Converted from", value: formatName(candidate.record.format))
                    // iOS names a *shared* file with a bare UUID, which tells a reader
                    // nothing, so it is omitted rather than printed.
                    if !isGeneratedName(candidate.record.originalFileName) {
                        LabeledContent("Original file", value: candidate.record.originalFileName)
                    }
                    if !candidate.isStale, !rebuilt {
                        LabeledContent("Conversion", value: "Up to date")
                    }
                    if rebuilt {
                        Label("Rebuilt with the current converter", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("The original file is kept alongside this work, so it can be rebuilt "
                        + "without downloading anything.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Always offered, never conditional on staleness. A rebuild is also
                    // how a work picks up an *importer* fix — recovered metadata, for
                    // instance — which the converter version cannot describe, so hiding
                    // the button on an up-to-date work took away the only way to apply
                    // those. An already-current work asks for confirmation instead.
                    Button {
                        if candidate.isStale {
                            Task { await rebuild() }
                        } else {
                            confirmingRedundantRebuild = true
                        }
                    } label: {
                        Label(
                            rebuilding ? "Rebuilding…" : "Rebuild from Original",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .buttonStyle(.borderless)
                    .disabled(rebuilding)
                    Text(candidate.isStale
                        ? "A newer converter is available. Rebuilding re-reads the original file "
                            + "and keeps your progress, tags and collections."
                        : "Re-reads the original file. Your progress, tags and collections are kept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .cardRow()
                .confirmationDialog(
                    "Rebuild this work?",
                    isPresented: $confirmingRedundantRebuild,
                    titleVisibility: .visible
                ) {
                    Button("Rebuild") { Task { await rebuild() } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This work was already built with the latest converter, so the text is "
                        + "unlikely to change. Rebuilding is still useful if its details look "
                        + "wrong — it re-reads everything from the original file.")
                }
                .alert(
                    "Couldn't Rebuild",
                    isPresented: Binding(
                        get: { rebuildError != nil },
                        set: { if !$0 { rebuildError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { rebuildError = nil }
                } message: {
                    Text(rebuildError ?? "")
                }
            } header: {
                Text("Conversion")
            }
        }
    }

    // MARK: - Content

    private var originSentence: String {
        switch work.origin {
        case .archiveOfOurOwn:
            "From Archive of Our Own."
        case .importedFile:
            "Imported from a file. It records no source site, so where it was first posted "
                + "is unknown."
        case .archiveOfOurOwnMirror:
            "Imported work, originally posted on Archive of Our Own and saved through a mirror."
        default:
            "Imported work, originally posted on \(work.origin.displayName)."
        }
    }

    private var unreachableName: String {
        work.origin == .importedFile ? "its source" : work.origin.displayName
    }

    /// Every status worth reporting. Uncapped — a full screen has room, unlike the card.
    private var statuses: [(text: String, symbol: String)] {
        var badges: [(text: String, symbol: String)] = []
        if let preservation = work.preservationState.badgeLabel {
            badges.append((text: preservation, symbol: work.preservationState.badgeSymbol))
        }
        if work.isInSavedForLaterQueue {
            badges.append((text: "Later", symbol: WorkActionLabels.savedForLaterSymbol))
        }
        if work.isSaved { badges.append((text: "Saved", symbol: "bookmark.fill")) }
        if work.isFavorite { badges.append((text: "Favorite", symbol: "star.fill")) }
        if work.isFinished { badges.append((text: "Finished", symbol: "checkmark.circle.fill")) }
        if !work.hasEPUB, !work.ao3Unavailable {
            badges.append((text: "Not downloaded", symbol: "arrow.down.circle"))
        }
        return badges
    }

    private func formatName(_ raw: String) -> String {
        ImportedFileFormat(rawValue: raw)?.displayName ?? raw
    }

    private func isGeneratedName(_ name: String) -> Bool {
        UUID(uuidString: (name as NSString).deletingPathExtension) != nil
    }

    private func rebuild() async {
        rebuilding = true
        defer { rebuilding = false }
        do {
            try await WorkReconversion.reconvert(work, in: context)
            rebuilt = true
        } catch {
            rebuildError = error.localizedDescription
        }
    }
}
