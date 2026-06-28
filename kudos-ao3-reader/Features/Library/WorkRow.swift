import SwiftUI

/// One row representing a saved work, reused across Library and Bookmarks. Mirrors
/// the Search result card (`AO3WorkRow`) — title, author, fandoms, summary, and a
/// stats line — so the two lists read consistently, plus a Library-specific
/// favorite marker. The richer fields (fandoms, word count, chapters, kudos) fill
/// in once the work has been refreshed from AO3 in the background.
struct WorkRow: View {
    let work: SavedWork
    /// Driven by a list's "expand/collapse all" toggle; each card follows it and can
    /// still be toggled individually afterwards. Mirrors `AO3WorkRow`.
    var expandAll: Bool = false

    @Environment(AppRouter.self) private var router
    @State private var expanded = false

    private var summaryText: String { work.summary.strippingHTML() }

    /// Real content warnings only — AO3's "No Archive Warnings Apply" / "Creator
    /// Chose Not To Use Archive Warnings" aren't warnings worth flagging.
    private var warnings: [String] {
        work.workWarnings.filter {
            !$0.localizedCaseInsensitiveContains("No Archive Warnings")
                && !$0.localizedCaseInsensitiveContains("Chose Not To Use")
        }
    }

    /// Worth an expand toggle only when there's more to reveal than the clamped view:
    /// a long summary or any categorized tags.
    private var isExpandable: Bool {
        summaryText.count > 120 || !work.workRelationships.isEmpty
            || !work.workCharacters.isEmpty || !work.workFreeforms.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + author, with the favorite star and expand control pinned top-trailing.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 6) {
                    Text(work.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if work.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    if isExpandable { expandButton }
                }
                if !work.author.isEmpty {
                    Text("by \(work.author)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if !work.workFandoms.isEmpty {
                // Tight icon→text gap + bold accent glyph, matching the stats row.
                HStack(spacing: 4) {
                    Image(systemName: "books.vertical")
                        .fontWeight(.bold)
                    Text(work.workFandoms.joined(separator: ", "))
                }
                .font(.caption)
                .foregroundStyle(.tint)
                .lineLimit(expanded ? nil : 1)
            }

            if !summaryText.isEmpty {
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .multilineTextAlignment(.leading)
            }

            if !warnings.isEmpty {
                Label(warnings.joined(separator: ", "), systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(expanded ? nil : 1)
            }

            // Categorized tags appear when expanded — the same blurb shape as AO3WorkRow.
            if expanded {
                chipGroup("Relationships", work.workRelationships, field: .relationship)
                chipGroup("Characters", work.workCharacters, field: .character)
                chipGroup("Additional Tags", work.workFreeforms, field: .freeform)
            }

            // Thin divider separates the textual content from the metadata stats,
            // matching the Search and Browse-by-fandom cards.
            Divider().padding(.top, 1)

            // Stats wrap rather than truncate (matches AO3WorkRow).
            FlowLayout(spacing: 18, rowSpacing: 5) {
                if !work.rating.isEmpty { WorkStatLabel(text: work.rating, symbol: "checkmark.shield") }
                if work.wordCount > 0 { WorkStatLabel(text: work.wordCount.formatted(), symbol: "textformat.size") }
                if !work.chapters.isEmpty { WorkStatLabel(text: work.chapters, symbol: "book") }
                if work.kudos > 0 { WorkStatLabel(text: work.kudos.formatted(), symbol: "heart") }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 1)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Follow the list's expand/collapse-all toggle (also on first appearance so
        // cards scrolled into view match the current state).
        .onChange(of: expandAll, initial: true) { _, value in expanded = value }
    }

    /// Top-right expand/collapse control, matching AO3WorkRow. A bordered circular
    /// button captures its own tap so it never triggers the row's navigation link.
    private var expandButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .tint(.accentColor)
        .accessibilityLabel(expanded ? "Show less" : "Show more")
    }

    /// A labeled group of tappable tag chips; each runs an AO3 search for that tag
    /// (matching AO3WorkRow). Borderless so a chip tap doesn't trigger navigation.
    @ViewBuilder
    private func chipGroup(_ label: String, _ tags: [String], field: AO3TagSearch.Field) -> some View {
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Button { router.searchAO3(field, tag) } label: { TagChip(text: tag) }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.top, 2)
        }
    }
}
