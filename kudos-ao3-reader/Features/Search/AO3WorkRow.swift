import SwiftUI

/// One search result row: title, author, fandoms, summary, and key stats. The
/// summary is clamped to a few lines; an expand toggle reveals the full summary
/// plus the work's tags (like AO3's blurb) without opening the work.
struct AO3WorkRow: View {
    let work: AO3WorkSummary
    /// Driven by the list's "expand/collapse all" toggle; each card follows it
    /// (and can still be toggled individually afterwards).
    var expandAll: Bool = false
    /// When true, a selection bubble takes the top-right corner (mirrors `WorkRow`)
    /// and the caller is expected to route taps to selection instead of navigation.
    var isSelecting: Bool = false
    var isSelected: Bool = false

    @Environment(AppRouter.self) private var router
    @State private var expanded = false

    /// Worth an expand toggle only when there's more to show than the clamped view:
    /// a long summary or any categorized tags.
    private var isExpandable: Bool {
        work.summary.count > 120 || !additionalTags.isEmpty || !work.relationships.isEmpty
            || !work.characters.isEmpty || !work.warnings.isEmpty
    }

    var body: some View {
        Group {
            if isSelecting {
                card
            } else {
                card.remoteWorkContextMenu(work: work)
            }
        }
        // Follow the global expand/collapse-all toggle (also applies on first
        // appearance so cards scrolled into view match the current state).
        .onChange(of: expandAll, initial: true) { _, value in expanded = value }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + author share a tight block so the hierarchy reads as one unit;
            // the expand control sits at the card's top-right corner.
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(work.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    AO3AuthorBylineView(
                        names: work.authors,
                        identities: work.authorIdentities,
                        font: .subheadline,
                        compact: true
                    )
                }
                Spacer(minLength: 0)
                WorkUpdatedDateBadge(dateUpdated: work.dateUpdated)
                if isExpandable { expandButton }
                if isSelecting {
                    WorkSelectionBubble(isSelected: isSelected)
                }
            }

            if !work.fandoms.isEmpty {
                // Each fandom is individually tappable → AO3 search for that fandom.
                // Only the icon is tinted — fandom text stays readable/secondary like
                // the rest of the metadata (CardMetaLabel's convention), not
                // accent-colored like a link.
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "books.vertical")
                        .fontWeight(.bold)
                        .foregroundStyle(.tint)
                    FlowLayout(spacing: 4, rowSpacing: 2) {
                        ForEach(work.fandoms, id: \.self) { fandom in
                            Button { router.searchAO3(.fandom, fandom) } label: { Text(fandom) }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption)
            }

            if !work.summary.isEmpty {
                Text(work.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .multilineTextAlignment(.leading)
                    // Belt-and-braces against an *ancestor* animation: the
                    // toggle itself no longer animates, but if any caller ever
                    // wraps `expandAll` in a `withAnimation`, this keeps the
                    // reflow out of it. SwiftUI can't interpolate one text
                    // layout into another — it cross-fades the clamped and full
                    // renderings, and the glyphs visibly ghost past each other.
                    .animation(nil, value: expanded)
            }

            // Categorized tags appear when expanded — they can be numerous on AO3.
            if expanded {
                // Sentinels filtered: a "No Archive Warnings Apply" chip next to
                // the stats row's "No Warnings" badge just says it twice.
                chipGroup("Archive Warnings", WorkStat.realWarnings(work.warnings), field: .warning)
                chipGroup("Relationships", work.relationships, field: .relationship)
                chipGroup("Characters", work.characters, field: .character)
                chipGroup("Additional Tags", additionalTags, field: .freeform)
            }

            // Thin divider separates the textual content from the metadata stats,
            // matching the Browse-by-fandom cards.
            Divider().padding(.top, 1)

            // Stats wrap to a second line rather than truncating when they don't fit
            // (long ratings like "Teen And Up Audiences" no longer clip the row).
            WorkListStatsRow(
                rating: work.rating.isEmpty ? nil : work.rating,
                categories: work.categories,
                warnings: work.warnings,
                completion: WorkCompletionStatus(isComplete: work.isComplete),
                language: work.language,
                wordCount: work.words,
                chapters: work.chapters,
                comments: work.comments,
                kudos: work.kudos,
                bookmarks: work.bookmarks,
                hits: work.hits
                // AO3WorkSummary (the Search-result blurb model) only carries a single
                // "revised_at" date, unlike SavedWork which tracks both — see WorkRow.
                // It shows in the card's top-right corner, not here.
            )
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Top-right expand/collapse control. A bordered circular button (not plain
    /// text) so it reads as a tappable affordance; borderless interaction would
    /// blend into the title. Captures its own tap so it never triggers the row's
    /// navigation link.
    private var expandButton: some View {
        Button {
            // No `withAnimation`: these rows live in a `List`, and animating a
            // row's height change makes it composite a snapshot of the old cell
            // over the new one. The two layouts differ in height, so every
            // element — title, byline, fandom, stats — ghosts over the expanded
            // summary and chips for the duration. Toggling instantly relayouts
            // in one frame with nothing to cross-fade.
            expanded.toggle()
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

    /// AO3's freeform/additional tags, defensively filtered against the categorized
    /// groups before display so expanded cards never repeat a tag across sections.
    private var additionalTags: [String] {
        let categorized = Set((work.fandoms + work.warnings + work.relationships + work.characters)
            .map(normalizedTag))
        var seen = Set<String>()
        return work.tags.filter { tag in
            let key = normalizedTag(tag)
            guard !categorized.contains(key), seen.insert(key).inserted else { return false }
            return true
        }
    }

    private func normalizedTag(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// A labeled group of tappable tag chips; each chip runs an AO3 search for that
    /// tag. Borderless so a chip tap doesn't trigger the row's navigation link.
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
                            .minimumHitTarget(28)
                    }
                }
            }
            .padding(.top, 2)
        }
    }
}
