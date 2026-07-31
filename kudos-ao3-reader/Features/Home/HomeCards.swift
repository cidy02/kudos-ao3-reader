import SwiftData
import SwiftUI

/// The rating/chapters/completion/word-count stat row on a compact cover card.
/// Shared by `WorkCoverCard` (local `SavedWork`) and `AO3WorkCoverCard` (remote
/// `AO3WorkSummary`) — each derives these already-formatted, already-nil-checked
/// values from its own model shape and hands them here.
struct CoverCardStatsRow: View {
    var ratingShort: String?
    /// The full rating name ("Teen And Up Audiences"), announced instead of the
    /// visible one/two-letter `ratingShort` badge — "T" alone is meaningless to
    /// VoiceOver.
    var ratingFull: String?
    var chapters: String?
    var completion: (text: String, symbol: String)?
    var wordCount: Int?

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 5) {
            if let ratingShort {
                WorkStatLabel(
                    text: ratingShort,
                    symbol: "checkmark.shield",
                    accessibilityLabel: ratingFull ?? ratingShort
                )
            }
            if let chapters {
                WorkStatLabel(text: chapters, symbol: "book", accessibilityLabel: "Chapters \(chapters)")
            }
            if let completion {
                WorkStatLabel(text: completion.text, symbol: completion.symbol)
            }
            if let wordCount {
                WorkStatLabel(
                    text: wordCount.formatted(.number.notation(.compactName)),
                    symbol: "textformat.size",
                    accessibilityLabel: "\(wordCount.formatted()) words"
                )
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
}

/// Standard carousel card: a compact AO3 work summary surface with the title, author,
/// status, metadata, and reading progress all inside the tappable card.
struct WorkCoverCard: View {
    let work: SavedWork
    var footer: String?
    var progress: Double?

    @State private var showingStatus = false

    var body: some View {
        WorkSummaryCardSurface(hue: CoverArt.hue(for: work.title)) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 6) {
                    Text(work.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !allStatuses.isEmpty {
                        statusButton
                    }
                }

                if !work.author.isEmpty {
                    CardMetaLabel(text: work.author, symbol: "person", accessibilityLabel: "Author: \(work.author)")
                        .font(.caption)
                }

                if let fandom = work.workFandoms.first, !fandom.isEmpty {
                    CardMetaLabel(text: fandom, symbol: "books.vertical", accessibilityLabel: "Fandom: \(fandom)")
                        .font(.caption2)
                }

                cardStats

                // Only preservation stays on the card. It is the one status the app
                // exists to surface — "this is the last copy of a deleted work" — and
                // hiding that behind a tap would defeat the point. It also appears on
                // very few cards, so it costs space only where it matters most.
                // Everything else lives behind the ⓘ button, which is what the owner
                // asked for: statuses without the card paying for them.
                if let preservation = work.preservationState.badgeLabel {
                    WorkStateBadge(text: preservation, symbol: work.preservationState.badgeSymbol)
                        .font(.caption2)
                }

                Spacer(minLength: 4)

                if let progressValue {
                    progressGroup(progressValue)
                } else if let footer {
                    WorkStateBadge(text: footer, symbol: footerSymbol)
                        .font(.caption2)
                }
            }
        }
    }

    private var cardStats: some View {
        CoverCardStatsRow(
            ratingShort: WorkStat.ratingShort(work.rating),
            ratingFull: work.rating.isEmpty ? nil : work.rating,
            chapters: work.chapters.isEmpty ? nil : work.chapters,
            completion: completionStatus.map { ($0, work.isComplete ? "checkmark.seal" : "circle.dashed") },
            wordCount: work.wordCount > 0 ? work.wordCount : nil
        )
    }

    private var progressValue: Double? {
        if let progress { return min(1, max(0, progress)) }
        if work.isFinished { return 1 }
        return work.readingProgress.map { min(1, max(0, $0)) }
    }

    private var progressText: String {
        // The bar's trailing label already shows the percent, so don't echo a footer
        // that's itself a percentage (the Readium reading-progress label) — that's the
        // duplicate. A chapter footer ("Ch 3") carries different info and is kept.
        if let footer, !footer.hasSuffix("%") { return footer }
        guard let progressValue else { return "Progress" }
        return progressValue >= 1 ? "Finished" : "Reading"
    }

    private var completionStatus: String? {
        // An AO3 work always has a known status. A converted import only has one when
        // its source stated it, which the metadata page now carries through — so
        // "Complete" is shown when we actually know, and nothing is shown when we do
        // not, rather than defaulting a non-AO3 work to "WIP" and being wrong about it.
        if work.ao3WorkID != nil || WorkTags.ao3WorkID(from: work.sourceURL) != nil {
            return work.isComplete ? "Complete" : "WIP"
        }
        return work.isComplete ? "Complete" : nil
    }

    /// ⓘ in the card's top-right corner.
    ///
    /// A plain `Button` is safe here even though the whole card navigates: the card's
    /// `NavigationLink` lives in the *background* (see `CardNavigationModifier`), so a
    /// foreground control is hit-tested first and takes its own taps. That is precisely
    /// why the link is in the background rather than wrapping the content.
    private var statusButton: some View {
        Button {
            showingStatus = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                // 28pt of tappable area around a 13pt glyph. Still under the 44pt
                // guideline, deliberately: a larger target on a compact carousel card
                // would eat the title's width, and the same information is a long-press
                // away in Work Details.
                //
                // The glyph is pinned to the box's own top-trailing corner, and the
                // box is then pulled into the card's 12pt padding. Without both, the
                // slack between a 28pt target and a 13pt glyph left the ⓘ floating
                // roughly 19pt inside the corner instead of sitting in it. The tap
                // target keeps its full 28pt — only the layout moves.
                .frame(width: 28, height: 28, alignment: .topTrailing)
                .contentShape(Rectangle())
                .padding(.top, -4)
                .padding(.trailing, -6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Status and origin")
        // No `presentationCompactAdaptation(.popover)`: forcing a popover on iPhone
        // pinned this to a small fixed box that **clipped** the text, which is exactly
        // what the owner hit. Left to adapt, iPhone gets a sheet — which is the right
        // container for several paragraphs — while iPad and macOS keep the popover.
        .popover(isPresented: $showingStatus) {
            statusPopover
                .presentationDetents([.medium, .large])
        }
    }

    /// The ⓘ panel. Verbose on purpose: it costs no card space, so it explains
    /// provenance in sentences rather than compressing it into chips the way the card
    /// had to. Everything here is a fact about *this* work — nothing is inferred for
    /// the sake of filling the panel.
    private var statusPopover: some View {
        // Scrollable because this text grows: several provenance notes at an
        // accessibility text size will exceed any fixed container, and silently cutting
        // an explanation off is worse than making it scroll.
        ScrollView {
            statusPopoverContent
        }
    }

    private var statusPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(provenanceSentence)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: work.origin.symbolName)
                    .foregroundStyle(.secondary)
            }

            if !work.sourceURL.isEmpty {
                // The original posting. For a work its site has since deleted this is
                // often the only citation that still exists, so it is shown in full
                // rather than hidden behind the word "source".
                Text(work.sourceURL)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            ForEach(provenanceNotes, id: \.self) { note in
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !allStatuses.isEmpty {
                Divider()
                ForEach(allStatuses, id: \.text) { badge in
                    WorkStateBadge(text: badge.text, symbol: badge.symbol)
                }
            }
        }
        .font(.caption2)
        .padding(14)
        .frame(maxWidth: 280, alignment: .leading)
    }

    /// True for names iOS invents when a file is shared rather than picked — a bare
    /// UUID, which tells a reader nothing about the file it came from.
    private static func looksLikeGeneratedName(_ name: String) -> Bool {
        let base = (name as NSString).deletingPathExtension
        return UUID(uuidString: base) != nil
    }

    /// One sentence saying where this work came from.
    private var provenanceSentence: String {
        switch work.origin {
        case .archiveOfOurOwn:
            "From Archive of Our Own."
        case .importedFile:
            "Imported from a file. It records no source site, so where it was first "
                + "posted is unknown."
        case .archiveOfOurOwnMirror:
            "Imported work, originally posted on Archive of Our Own and saved through "
                + "a mirror."
        default:
            "Imported work, originally posted on \(work.origin.displayName)."
        }
    }

    /// Everything else worth saying, in the order someone would want to read it.
    private var provenanceNotes: [String] {
        var notes: [String] = []
        if let candidate = WorkReconversion.candidate(for: work) {
            let format = ImportedFileFormat(rawValue: candidate.record.format)?.displayName
                ?? candidate.record.format
            // iOS names a shared file with a bare UUID, and printing that adds nothing —
            // the owner's card read "(C8E89916-3E56-49B2-96FE-498B7B147EFE.pdf)".
            let name = candidate.record.originalFileName
            let named = Self.looksLikeGeneratedName(name)
                ? "The original file"
                : "The original file (\(name))"
            notes.append("Converted from \(format) on import. \(named) is kept alongside it, "
                + "so this work can be rebuilt without downloading anything.")
            if candidate.isStale {
                notes.append("A newer converter is available — rebuilding from the original would "
                    + "improve how this work reads.")
            }
        }
        if let explanation = work.preservationState.explanation(origin: work.origin) {
            notes.append(explanation)
        }
        if !work.origin.supportsLiveLookup {
            // Says plainly what the app cannot do, rather than leaving a reader to
            // wonder why tags never fill in and kudos is missing.
            notes.append("Kudos can't reach \(work.origin == .importedFile ? "its source" : work.origin.displayName), "
                + "so tags, stats and availability aren't refreshed for this work, and kudos and "
                + "comments aren't available.")
        }
        return notes
    }

    /// Every status worth reporting, uncapped — the popover has room, so the
    /// four-badge cap the card needed is gone.
    private var allStatuses: [(text: String, symbol: String)] {
        var badges: [(text: String, symbol: String)] = []
        // Preservation first: "this is the last copy in existence" outranks every
        // other thing a badge could say about a work.
        if let preservation = work.preservationState.badgeLabel {
            badges.append((text: preservation, symbol: work.preservationState.badgeSymbol))
        }
        // A chip only for non-AO3 origins: the popover names the source in full on its
        // own row, so an "AO3" chip would just repeat it. The exceptions earn a chip
        // because they behave differently — no live page to refresh, no kudos to give.
        let origin = work.origin
        if origin != .archiveOfOurOwn {
            badges.append((text: origin.shortLabel, symbol: origin.symbolName))
        }
        if work.isInSavedForLaterQueue { badges.append((text: "Later", symbol: "bookmark.fill")) }
        if work.isSaved { badges.append((text: "Saved", symbol: "bookmark.fill")) }
        if work.isFavorite { badges.append((text: "Favorite", symbol: "star.fill")) }
        // The *absence* of a downloaded file is what carries information, so this is
        // deliberately not an "Offline" badge.
        //
        // Every shelf except History filters on `hasEPUB`, and saved/favorited/queued
        // works are never freed (`isProtected` covers them), so "Offline" was true on
        // effectively every card that could show it — a badge on everything says
        // nothing. A work whose file was freed appears only in History, and *that* is
        // worth labelling. `goneWithNoCopy` already covers the freed-and-deleted case
        // above, so this does not double up with it.
        if !work.hasEPUB, !work.ao3Unavailable {
            badges.append((text: "Not downloaded", symbol: "arrow.down.circle"))
        }
        return badges
    }

    private var footerSymbol: String {
        if work.isFinished { return "checkmark.circle.fill" }
        if footer?.contains("new") == true { return "sparkle" }
        return "clock"
    }

    private func progressGroup(_ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(progressText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int((value * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(.tint)
                        .frame(width: geo.size.width * max(0.03, value))
                }
            }
            .frame(height: 5)
        }
    }
}

/// Carousel card for a remote AO3 work (Subscriptions / Recently Updated). It uses
/// the same self-contained summary shape as local Library/Home work cards.
struct AO3WorkCoverCard: View {
    let work: AO3WorkSummary

    var body: some View {
        WorkSummaryCardSurface(hue: CoverArt.hue(for: work.title)) {
            VStack(alignment: .leading, spacing: 7) {
                Text(work.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let author = work.authors.first, !author.isEmpty {
                    CardMetaLabel(text: author, symbol: "person", accessibilityLabel: "Author: \(author)")
                        .font(.caption)
                }

                if let fandom = work.fandoms.first, !fandom.isEmpty {
                    CardMetaLabel(
                        text: fandom, symbol: "books.vertical", lineLimit: 2,
                        accessibilityLabel: "Fandom: \(fandom)"
                    )
                    .font(.caption2)
                }

                cardStats

                Spacer(minLength: 4)

                if !work.dateUpdated.isEmpty {
                    WorkStateBadge(text: work.dateUpdated, symbol: "calendar")
                        .font(.caption2)
                }
            }
        }
        .remoteWorkContextMenu(work: work)
    }

    private var cardStats: some View {
        CoverCardStatsRow(
            ratingShort: WorkStat.ratingShort(work.rating),
            ratingFull: work.rating.isEmpty ? nil : work.rating,
            chapters: work.chapters.isEmpty ? nil : work.chapters,
            completion: work.isComplete.map {
                ($0 ? "Complete" : "WIP", $0 ? "checkmark.seal" : "circle.dashed")
            },
            wordCount: work.words
        )
    }
}

/// Selection-mode wrapper for local carousel cards. The full card remains the hit
/// target while the bubble mirrors iOS multi-select affordances without disturbing
/// the compact summary layout.
struct SelectableWorkCoverCard: View {
    let work: SavedWork
    var footer: String?
    var progress: Double?
    var isSelected: Bool

    var body: some View {
        WorkCoverCard(work: work, footer: footer, progress: progress)
            .overlay(alignment: .topTrailing) {
                WorkSelectionBubble(isSelected: isSelected)
                    .padding(8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
    }
}

struct WorkSelectionBubble: View {
    var isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
            if isSelected {
                Circle().fill(Color.accentColor)
            }
            Circle()
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.55), lineWidth: 1.25)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 28, height: 28)
        .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}

private struct WorkSummaryCardSurface<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager
    /// Stable per-title hue (0...1) used to tint the card so adjacent cards stay
    /// distinguishable — replaces the per-title cover art the summary layout dropped.
    var hue: Double?
    @ViewBuilder var content: () -> Content

    /// Scales width and height together so the card grows proportionally at
    /// large Dynamic Type sizes instead of only getting taller.
    var cardSize = ScaledCarouselCardSize()

    /// The card's scaled outer width minus the symmetric 12pt padding applied
    /// below — the exact width the content itself renders at.
    private var contentWidth: CGFloat {
        cardSize.width - 24
    }

    var body: some View {
        content()
            // Pins the content's width to a single, unambiguous value *before*
            // asking for its ideal height, rather than letting an outer
            // .frame(minWidth:maxWidth:) negotiate width across two separate
            // passes (once for the ideal-size query, once for placement).
            // FlowLayout's sizeThatFits reads whatever width it's proposed —
            // if the two passes disagree even slightly, it can wrap a
            // different number of rows in each, undershooting the reported
            // ideal height (and thus the floor .frame(minHeight:) grows to)
            // by a full row at large accessibility text sizes, since the
            // stats row is a FlowLayout. A single .frame(width:) is proposed
            // identically in every pass, so both queries wrap the same way.
            //
            // Deliberately no .fixedSize(vertical:) here (unlike an earlier
            // version of this fix): that would lock the content to its own
            // ideal height, decoupling it from a taller `minHeight` floor —
            // which is exactly what content's trailing Spacer(minLength:)
            // needs to expand into so the Reading-progress/footer group
            // pins to the card's true bottom instead of floating wherever
            // the metadata above it happens to end.
            .frame(width: contentWidth, alignment: .topLeading)
            .padding(12)
            .frame(minHeight: cardSize.height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                    .fill(themeManager.appTheme.carouselCardSurface)
                    .overlay(hueTint)
                    .overlay(
                        RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(themeManager.appTheme.carouselCardBorder(hue: hue), lineWidth: 0.5)
                    )
                    .shadow(color: themeManager.appTheme.carouselCardShadow.color,
                            radius: themeManager.appTheme.carouselCardShadow.radius,
                            x: 0,
                            y: themeManager.appTheme.carouselCardShadow.y)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
            )
    }

    @ViewBuilder
    private var hueTint: some View {
        if let hue {
            RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                .fill(themeManager.appTheme.carouselCardTint(hue: hue))
        }
    }
}

struct WorkStateBadge: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            // Two badges now share a card's width, so a long label ("SufficientVelocity",
            // "Not downloaded") shrinks a little rather than truncating to an ellipsis
            // that says nothing.
            .minimumScaleFactor(0.8)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}

/// Author/fandom meta row for work cards: a theme-tinted icon paired with
/// secondary text, matching the tinted-icon style of `WorkStatLabel`.
private struct CardMetaLabel: View {
    let text: String
    let symbol: String
    var lineLimit: Int = 1
    /// What VoiceOver announces instead of the bare `text` — a name or fandom on
    /// its own doesn't say what role it plays on the card ("Author: " / "Fandom: ").
    var accessibilityLabel: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .lineLimit(lineLimit)
        .combinedAccessibilityRow(accessibilityLabel ?? text)
    }
}

/// Fallback detail route for any legacy `SavedWork` link that still reaches Home.
/// Opening it also clears the work from Recently Updated.
struct HomeWorkDestination: View {
    let work: SavedWork
    @Environment(\.modelContext) private var context

    var body: some View {
        WorkDetailView(work: work)
            .onAppear {
                // Opening an updated work marks its current chapters as seen — clears
                // it from Recently Updated.
                if work.hasUpdate {
                    work.knownChapterCount = work.postedChapterCount
                    try? context.save()
                }
            }
    }
}
