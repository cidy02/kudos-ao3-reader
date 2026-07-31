import SwiftData
import SwiftUI

/// The ⓘ panel: where a work came from, what state it is in, and what can be done about
/// it.
///
/// Built as a `Form` of `Section`s with `.cardRow()`, `.appThemedScroll()` and
/// `.appThemedRows()` — the same construction as Settings and Work Details. The first
/// version was a bare `VStack` of `Text`, which read as a different app; grouped rows are
/// what every other explanatory surface here uses, and they also solve the clipping the
/// hand-rolled layout had.
struct WorkStatusSheet: View {
    let work: SavedWork

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    @State private var rebuilding = false
    @State private var rebuildError: String?
    @State private var rebuilt = false
    @State private var confirmingRedundantRebuild = false

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    originSection
                    if !statuses.isEmpty { statusSection }
                    if candidate != nil { conversionSection }
                }
                .appThemedRows()
            }
            .formStyle(.grouped)
            .appThemedScroll()
            .navigationTitle("Work Info")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Rebuild this work?",
                isPresented: $confirmingRedundantRebuild,
                titleVisibility: .visible
            ) {
                Button("Rebuild") { Task { await rebuild() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This work was already built with the latest converter, so the text is "
                    + "unlikely to change. Rebuilding is still useful if its details look wrong — "
                    + "it re-reads everything from the original file.")
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
        }
        .tint(theme.effectiveTint)
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
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: work.origin.symbolName)
                        .foregroundStyle(.secondary)
                }
                if !work.sourceURL.isEmpty {
                    // Selectable and shown in full: for a work its site has deleted, this
                    // is often the only citation that still exists.
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
                    Text("The original file is kept alongside this work, so it can be rebuilt "
                        + "without downloading anything.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Always offered, never conditional on staleness. A rebuild is also
                    // how a work picks up an *importer* fix — recovered metadata, for
                    // instance — which the converter version cannot know about, so
                    // hiding the button on an up-to-date work took away the only way to
                    // apply those. An already-current work asks for confirmation instead.
                    if !candidate.isStale, !rebuilt {
                        LabeledContent("Conversion", value: "Up to date")
                    }
                    if rebuilt {
                        Label("Rebuilt with the current converter", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

    /// Every status worth reporting. Uncapped — a sheet has room, unlike the card.
    private var statuses: [(text: String, symbol: String)] {
        var badges: [(text: String, symbol: String)] = []
        if let preservation = work.preservationState.badgeLabel {
            badges.append((text: preservation, symbol: work.preservationState.badgeSymbol))
        }
        if work.isInSavedForLaterQueue { badges.append((text: "Later", symbol: "bookmark.fill")) }
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
