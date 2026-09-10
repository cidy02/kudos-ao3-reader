import SwiftUI

/// One row representing a saved work, reused across Library and Bookmarks. Mirrors
/// the Search result card (`AO3WorkRow`) — title, author, fandoms, summary, and a
/// stats line — so the two lists read consistently, plus a Library-specific
/// favorite marker. The richer fields (fandoms, word count, chapters, kudos) fill
/// in once the work has been refreshed from AO3 in the background.
struct WorkRow: View {
    /// Which of the two shapes the redesign gives a saved work this row should
    /// take. `.standard` is the established card — title, author, fandoms,
    /// summary, expandable tags and the full stats row. `.ledger` is the
    /// redesign's compact washed row (spec 1c/1d, 1ad, 1o, 1t, 1u, 1x, 1ah): a
    /// leading progress ring, the fandom kicker over its rule, the title, one
    /// dot-separated metadata line, and the four-signal tray.
    ///
    /// Two presentations rather than a replacement, matching what `AO3WorkRow`
    /// already does for remote works: the screens convert one at a time, and a
    /// screen that has not converted keeps exactly the row it had.
    enum Presentation: Equatable {
        case standard
        case ledger
    }

    let work: SavedWork
    /// Driven by a list's "expand/collapse all" toggle; each card follows it and can
    /// still be toggled individually afterwards. Mirrors `AO3WorkRow`.
    var expandAll: Bool = false
    /// When true, a selection bubble takes the top-right corner (where the expand
    /// control normally sits) and the expand control shifts to its left instead of
    /// disappearing.
    var isSelecting: Bool = false
    var isSelected: Bool = false
    /// False suppresses the row's own expand/collapse button — used when a caller
    /// (SensitiveWorkRow's blurred branch) renders its own copy externally instead,
    /// so the two don't compete for the same top-trailing corner.
    var showsExpandButton: Bool = true
    /// Lets a caller drive (and observe) this row's expanded state from outside —
    /// used by SensitiveWorkRow's blurred branch, which renders its own unblurred
    /// expand button but still needs it to expand the blurred content underneath.
    /// Falls back to purely-internal state when nil.
    var externalExpanded: Binding<Bool>?
    var presentation: Presentation = .standard

    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @State private var internalExpanded = false

    private var expandedBinding: Binding<Bool> {
        externalExpanded ?? $internalExpanded
    }

    /// Worth an expand toggle only when there's more to reveal than the clamped view:
    /// a long summary or any categorized tags. Exposed statically so SensitiveWorkRow
    /// can decide whether to render an external expand button without building a row.
    static func isExpandable(for work: SavedWork) -> Bool {
        isExpandable(strippedSummary: work.summary.strippingHTML(), for: work)
    }

    /// Core of `isExpandable(for:)`, taking an already-stripped summary so `body`
    /// (which needs the stripped text anyway) strips it once per render, not per use.
    private static func isExpandable(strippedSummary: String, for work: SavedWork) -> Bool {
        strippedSummary.count > 120 || !work.workRelationships.isEmpty
            || !work.workCharacters.isEmpty || !work.workFreeforms.isEmpty
            || (!work.hasCategorizedWorkTags && !work.workTags.isEmpty)
    }

    @ViewBuilder
    var body: some View {
        Group {
            switch presentation {
            case .standard: standardRow
            case .ledger:
                VStack(alignment: .leading, spacing: 8) {
                    ledgerRow
                    if expandedBinding.wrappedValue { expandedLedgerDetails }
                }
            }
        }
        .onChange(of: expandAll, initial: true) { _, value in expandedBinding.wrappedValue = value }
    }

    // MARK: - Ledger presentation

    private var subjectHue: Double {
        CoverArt.workHue(fandoms: work.workFandoms, title: work.title)
    }

    private var subjectPalette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: subjectHue)
    }

    private var nonemptyFandomNames: [String] {
        work.workFandoms.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Author · words · chapters — the three facts the spec's ledger row prints.
    /// Deliberately shorter than `WorkListStatsRow`: the row is one line tall and
    /// the four signals to its right already carry rating, category, warnings and
    /// completion, so repeating them here would spend the line on what is
    /// already on screen.
    private var ledgerMetadataSegments: [String] {
        WorkStat.localWorkMetadata(
            author: work.author, wordCount: work.wordCount, chapters: work.chapters
        )
    }

    /// The washed background is left to the enclosing `List` row
    /// (`.cardRow(tintHue:)`), which paints it at the card's true outer edge —
    /// the same place the selection outline is drawn. A row that painted its own
    /// would sit half a point inside that, drawing the hairline twice.
    private var ledgerRow: some View {
        WorkLedgerRow(
            palette: subjectPalette,
            kicker: nonemptyFandomNames.first,
            additionalKickerCount: max(0, nonemptyFandomNames.count - 1),
            title: work.title,
            metadataSegments: ledgerMetadataSegments,
            // The spec's green tick: this copy is on the device and will open
            // with no network. It leads the line because it is the one fact
            // there that changes what happens when you tap the row.
            metadataPrefixSymbol: work.hasEPUB ? "checkmark.circle.fill" : nil,
            metadataPrefixTint: work.hasEPUB ? theme.appTheme.statusSuccessColor : nil,
            leading: {
                WorkProgressRing(
                    progress: work.readingProgress ?? 0,
                    state: nil,
                    diameter: 44,
                    showsPercentSuffix: false
                )
            },
            trailing: {
                VStack(alignment: .trailing, spacing: 4) {
                    if showsExpandButton { expandButton }
                    WorkStatusIconGrid(
                        rating: work.rating.isEmpty ? nil : work.rating,
                        categories: work.workCategories,
                        warnings: work.workWarnings,
                        completion: work.completionStatus,
                        tileSize: 22,
                        announcesToVoiceOver: true,
                        showsTray: true
                    )
                    if isSelecting {
                        WorkSelectionBubble(isSelected: isSelected)
                    }
                }
            },
            drawsBackground: false
        )
    }

    // MARK: - Standard presentation

    /// `@ViewBuilder` because the body opens with two `let` bindings before its
    /// view expression. `View.body` is a builder implicitly; a plain computed
    /// property is not, and would need an explicit `return` instead.
    @ViewBuilder
    private var standardRow: some View {
        let summaryText = work.summary.strippingHTML()
        let isExpandable = Self.isExpandable(strippedSummary: summaryText, for: work)
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
                            .foregroundStyle(theme.appTheme.favoriteColor)
                    }
                    WorkUpdatedDateBadge(
                        dateUpdated: work.dateUpdated,
                        datePublished: work.datePublished
                    )
                    if isExpandable && showsExpandButton { expandButton }
                    if isSelecting {
                        WorkSelectionBubble(isSelected: isSelected)
                    }
                }
                if !work.author.isEmpty {
                    AO3AuthorBylineView(
                        displayText: work.author,
                        identities: work.verifiedAuthorIdentities,
                        font: .subheadline,
                        compact: true
                    )
                }
            }

            if !work.workFandoms.isEmpty {
                // Tight icon→text gap + bold accent glyph, matching the stats row. Only
                // the icon is tinted — fandom text stays readable/secondary like the
                // rest of the metadata (CardMetaLabel's convention).
                HStack(spacing: 4) {
                    Image(systemName: "books.vertical")
                        .fontWeight(.bold)
                        .foregroundStyle(.tint)
                    Text(work.workFandoms.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .lineLimit(expandedBinding.wrappedValue ? nil : 1)
                // Snap the reflow — see AO3WorkRow: guards against an ancestor
                // animation cross-fading two different text layouts.
                .animation(nil, value: expandedBinding.wrappedValue)
            }

            workDetails(summaryText: summaryText)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)

    }

    private var expandedLedgerDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !work.author.isEmpty {
                AO3AuthorBylineView(
                    displayText: work.author,
                    identities: work.verifiedAuthorIdentities,
                    font: .subheadline,
                    compact: true
                )
            }
            if !work.workFandoms.isEmpty {
                Text(work.workFandoms.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            WorkUpdatedDateBadge(dateUpdated: work.dateUpdated, datePublished: work.datePublished)
            workDetails(summaryText: work.summary.strippingHTML())
        }
    }

    @ViewBuilder
    private func workDetails(summaryText: String) -> some View {
        if !summaryText.isEmpty {
            Text(summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(expandedBinding.wrappedValue ? nil : 3)
                .multilineTextAlignment(.leading)
                // Snap the reflow — see AO3WorkRow: guards against an
                // ancestor animation cross-fading two text layouts.
                .animation(nil, value: expandedBinding.wrappedValue)
        }

        // Categorized tags appear when expanded — the same blurb shape as AO3WorkRow.
        if expandedBinding.wrappedValue {
            // The stats row's badge only says how many warnings apply, so
            // without this the names would be unreachable on a saved work.
            // No "Archive Warnings" group: expanding turns the stats row's
            // count chip into the warnings themselves, so a labelled section
            // right above was the same list twice. Matches AO3WorkRow.
            if work.hasCategorizedWorkTags {
                chipGroup("Relationships", work.workRelationships, field: .relationship)
                chipGroup("Characters", work.workCharacters, field: .character)
                chipGroup("Additional Tags", work.workFreeforms, field: .freeform)
            } else {
                chipGroup("Tags", work.workTags, field: .freeform)
            }
        }

        // Space, not a rule — matching AO3WorkRow. The stats row below is
        // already a band of capsules with its own edges, so a hairline against
        // it drew a second boundary in the same place.
        Spacer(minLength: 0).frame(height: 4)

        // Stats wrap rather than truncate (matches AO3WorkRow).
        WorkListStatsRow(
            rating: work.rating.isEmpty ? nil : work.rating,
            categories: work.workCategories,
            warnings: work.workWarnings,
            completion: work.completionStatus,
            language: work.language,
            wordCount: work.wordCount,
            chapters: work.chapters,
            comments: work.comments,
            kudos: work.kudos,
            bookmarks: work.bookmarks,
            hits: work.hits,
            datePublished: work.datePublished.isEmpty ? nil : work.datePublished,
            isExpanded: expandedBinding.wrappedValue
        )
    }

    /// Top-right expand/collapse control, matching AO3WorkRow.
    private var expandButton: some View {
        WorkRowExpandButton(expanded: expandedBinding)
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

/// The bordered circular expand/collapse toggle shared by `WorkRow` and
/// `SensitiveWorkRow`'s blurred branch (which renders its own copy outside the
/// blur so it stays legible and tappable, driving the row's content via a
/// `Binding` rather than owning its own state).
struct WorkRowExpandButton: View {
    @Binding var expanded: Bool

    var body: some View {
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
        .minimumHitTarget()
        .accessibilityLabel(expanded ? "Show less" : "Show more")
    }
}
