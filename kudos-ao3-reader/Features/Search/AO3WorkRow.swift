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
    /// a long summary, any categorized tags — or fandoms the collapsed card folds
    /// into "+N others". Without that last clause a crossover with a short summary
    /// and no tags would hide its extra fandoms behind no control at all.
    private var isExpandable: Bool {
        work.summary.count > 120 || work.fandoms.count > 1 || !additionalTags.isEmpty
            || !work.relationships.isEmpty || !work.characters.isEmpty || !work.warnings.isEmpty
    }

    /// Collapsed, a card names the work's main fandom and counts the rest. AO3
    /// blurbs for a crossover can carry a dozen, each of them long — unfolded they
    /// pushed the summary off the card and made every result the same height.
    private var visibleFandoms: [String] {
        expanded ? work.fandoms : Array(work.fandoms.prefix(1))
    }

    private var hiddenFandomCount: Int {
        max(0, work.fandoms.count - visibleFandoms.count)
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
            // Title + author share a tight block so the hierarchy reads as one unit.
            // AO3's own quadrant tag grid trails the row, in this app's chip
            // colors/symbols (WorkStatusIconGrid) — a glanceable rating/category/
            // warnings/completion alongside the title, the same information
            // WorkListStatsRow's text chips repeat lower on the card. The updated
            // date moved down to bottom-left, beside the expand control.
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
                WorkStatusIconGrid(
                    rating: work.rating.isEmpty ? nil : work.rating,
                    categories: work.categories,
                    warnings: work.warnings,
                    completion: WorkCompletionStatus(isComplete: work.isComplete),
                    isExpanded: expanded,
                    // 1.5x the default (18) — this card has more room to spend
                    // on it than the Reading Queue mini-cards do.
                    tileSize: 27
                )
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
                        ForEach(visibleFandoms, id: \.self) { fandom in
                            Button { router.searchAO3(.fandom, fandom) } label: {
                                // A canonical AO3 fandom is long enough to wrap on
                                // its own ("僕のヒーローアカデミア | Boku no Hero
                                // Academia | My Hero Academia (Anime & Manga)"), and
                                // a Button centres its label by default — the second
                                // line drifted to the middle of the card.
                                Text(fandom).multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                        // Plain text, not a button: the card already has one expand
                        // control, and a second one that only opens the same card
                        // would be two affordances for one action.
                        if hiddenFandomCount > 0 {
                            Text("+\(hiddenFandomCount) other\(hiddenFandomCount == 1 ? "" : "s")")
                                .foregroundStyle(.tertiary)
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
                // No "Archive Warnings" group: expanding now turns the stats row's
                // "3 Warnings" chip into the three warnings themselves, and a
                // labelled section repeating them right above was the same list
                // twice. The stats row keeps AO3's red, which the neutral tag chips
                // here never had.
                chipGroup("Relationships", work.relationships, field: .relationship)
                chipGroup("Characters", work.characters, field: .character)
                chipGroup("Additional Tags", additionalTags, field: .freeform)
            }

            // Space, not a rule. The stats row is already a band of capsules with
            // its own edges — a hairline above it drew a second boundary in the
            // same place, and one card ended up with two horizontal lines through
            // it. Whitespace separates the content from the metadata on its own.
            Spacer(minLength: 0).frame(height: 4)

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
                hits: work.hits,
                // AO3WorkSummary (the Search-result blurb model) only carries a single
                // "revised_at" date, unlike SavedWork which tracks both — see WorkRow.
                // It shows in the card's bottom-left corner, not here.
                isExpanded: expanded
            )

            // Date bottom-left, expand control bottom-right — omitted
            // entirely (not just hidden) when there's nothing to show:
            // unlike an always-reserved slot, neither depends on the
            // other's alignment.
            if !work.dateUpdated.isEmpty || isExpandable {
                HStack {
                    WorkUpdatedDateBadge(dateUpdated: work.dateUpdated)
                    Spacer(minLength: 0)
                    if isExpandable {
                        expandButton
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Expand/collapse control, bottom-right of the card. A bordered circular
    /// button (not plain text) so it reads as a tappable affordance; borderless
    /// interaction would blend into the background. Captures its own tap so it
    /// never triggers the row's navigation link.
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
                        Button { router.searchAO3(field, tag) } label: { TagChip(text: tag, symbol: field.symbol) }
                            .buttonStyle(.borderless)
                            .minimumHitTarget(28)
                    }
                }
            }
            .padding(.top, 2)
        }
    }
}
