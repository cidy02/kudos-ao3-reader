import SwiftData
import SwiftUI

/// The rating/chapters/completion/word-count stats on a compact cover card.
/// Shared by `WorkCoverCard` (local `SavedWork`) and `AO3WorkCoverCard` (remote
/// `AO3WorkSummary`) — each derives these already-formatted, already-nil-checked
/// values from its own model shape and hands them here.
///
/// **One stat per row.** This was a `FlowLayout` that packed as many stats onto a line
/// as fit, which is why the values were abbreviated to the point of being cryptic ("M",
/// "112K", "WIP"). A column gives each stat room to say what it means, and removes
/// the two-pass sizing hazard `WorkSummaryCardSurface` documents: a `VStack`'s height
/// does not depend on the width it is proposed, so it cannot wrap differently between
/// the ideal-size query and placement.
struct CoverCardStatsRow: View {
    var ratingName: String?
    /// The full AO3 rating ("Teen And Up Audiences"), announced in place of the visible
    /// shortened name.
    var ratingFull: String?
    var chapters: String?
    var completion: WorkCompletionStatus?
    var wordCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let ratingName {
                WorkStatLabel(
                    text: ratingName,
                    symbol: "checkmark.shield",
                    accessibilityLabel: ratingFull ?? ratingName,
                    iconColor: ratingFull.flatMap(WorkStat.ratingColor)
                )
            }
            if let chapters {
                WorkStatLabel(
                    text: chapterText(chapters),
                    symbol: "book",
                    accessibilityLabel: "Chapters \(chapters)"
                )
            }
            if let completion {
                WorkStatLabel(
                    text: completion.text,
                    symbol: completion.symbol,
                    accessibilityLabel: "Status: \(completion.text)",
                    iconColor: completion.color
                )
            }
            if let wordCount {
                WorkStatLabel(
                    text: wordText(wordCount),
                    symbol: "textformat.size",
                    accessibilityLabel: "\(wordCount.formatted()) words"
                )
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    /// A bare "31/31" or "112K" leaves the icon as the only clue to what is being
    /// counted. The noun is cheap now that the row is not shared.
    private func chapterText(_ chapters: String) -> String {
        chapters == "1" ? "1 chapter" : "\(chapters) chapters"
    }

    private func wordText(_ count: Int) -> String {
        count == 1 ? "1 word" : "\(count.formatted(.number.notation(.compactName))) words"
    }
}

/// A short centred hairline between a card's attribution (author, fandom) and its
/// counted stats.
///
/// Spacing alone had to carry that split before, and at the card's 7pt rhythm the two
/// groups still read as one list. Inset well short of the card's width and drawn in
/// `.quaternary` so it reads as a breath rather than a rule — the same treatment the
/// progress track uses, so it inherits the theme instead of hard-coding a grey.
struct CardMetaSeparator: View {
    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(width: 48, height: 1)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityHidden(true)
    }
}

/// Standard carousel card: a compact AO3 work summary surface with the title, author,
/// status, metadata, and reading progress all inside the tappable card.
struct WorkCoverCard: View {
    let work: SavedWork
    var footer: String?
    var progress: Double?

    /// Set per tab stack; the pushed reader zooms out of this card. See
    /// `WorkCardZoomTransition.swift`.
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace

    var body: some View {
        WorkSummaryCardSurface(hue: CoverArt.hue(for: work.title)) {
            VStack(alignment: .leading, spacing: 7) {
                Text(work.title)
                    .font(.subheadline.weight(.semibold))
                    // Two lines, then "…". A third line costs real card height
                    // for a fraction of a title, and long fandom titles are
                    // common enough that they decided the card's size more often
                    // than the metadata below them did.
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Three groups on this card — what it is, who wrote it, what it
                // measures — and the uniform 7pt rhythm ran them together. The extra
                // space sits on the *title* rather than on the author row so the gap
                // survives a work with no author, and on `cardStats` so the counted
                // stats read as their own block below the attribution. Both are
                // absorbed by the trailing `Spacer(minLength:)`, so the card stays at
                // its height floor and carousel cards stay uniform.
                .padding(.bottom, 3)

                if !work.author.isEmpty {
                    CardMetaLabel(text: work.author, symbol: "person", accessibilityLabel: "Author: \(work.author)")
                        .font(.caption)
                }

                if let fandom = work.workFandoms.first, !fandom.isEmpty {
                    CardMetaLabel(text: fandom, symbol: "books.vertical", accessibilityLabel: "Fandom: \(fandom)")
                        .font(.caption2)
                }

                if !work.author.isEmpty || !(work.workFandoms.first ?? "").isEmpty {
                    CardMetaSeparator()
                }

                cardStats

                // Only preservation stays on the card. It is the one status the app
                // exists to surface — "this is the last copy of a deleted work" — and
                // hiding that would defeat the point. It also appears on very few
                // cards, so it costs space only where it matters most. Work Details
                // is on the long-press menu, not a corner control.
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
        // The reader pushed from this card zooms out of it, and collapses back into
        // it on dismiss. No-ops where no namespace is provided.
        .workCardZoomSource(work.id, in: zoomNamespace)
    }

    private var cardStats: some View {
        CoverCardStatsRow(
            ratingName: WorkStat.ratingName(work.rating),
            ratingFull: work.rating.isEmpty ? nil : work.rating,
            chapters: work.chapters.isEmpty ? nil : work.chapters,
            completion: work.completionStatus,
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

    /// See `WorkCoverCard.zoomNamespace`.
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace

    var body: some View {
        WorkSummaryCardSurface(hue: CoverArt.hue(for: work.title)) {
            VStack(alignment: .leading, spacing: 7) {
                Text(work.title)
                    .font(.subheadline.weight(.semibold))
                    // Matches the local card — see `WorkCoverCard`.
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Matches the local card's grouping — see `WorkCoverCard`.
                .padding(.bottom, 3)

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

                if work.authors.first?.isEmpty == false || work.fandoms.first?.isEmpty == false {
                    CardMetaSeparator()
                }

                cardStats

                Spacer(minLength: 4)

                if !work.dateUpdated.isEmpty {
                    WorkStateBadge(text: work.dateUpdated, symbol: "calendar")
                        .font(.caption2)
                }
            }
        }
        .workCardZoomSource(work.id, in: zoomNamespace)
        .remoteWorkContextMenu(work: work)
    }

    private var cardStats: some View {
        CoverCardStatsRow(
            ratingName: WorkStat.ratingName(work.rating),
            ratingFull: work.rating.isEmpty ? nil : work.rating,
            chapters: work.chapters.isEmpty ? nil : work.chapters,
            completion: WorkCompletionStatus(isComplete: work.isComplete),
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

    /// Set by the enclosing carousel/grid so every card there matches the tallest.
    /// `nil` in a container that doesn't coordinate — the card keeps its own floor.
    @Environment(\.uniformWorkCardHeight) private var uniformHeight

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
            // Wrapping content reads whatever width it's proposed — if the two
            // passes disagree even slightly, it can wrap a different number of
            // lines in each, undershooting the reported ideal height (and thus
            // the floor .frame(minHeight:) grows to) by a full line at large
            // accessibility text sizes. A single .frame(width:) is proposed
            // identically in every pass, so both queries wrap the same way.
            // Originally written for the stats row's FlowLayout; that is a
            // fixed-line VStack now, but the wrapping title has the same
            // property, so the frame stays.
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
            // The floor is the card tile, or the container's resolved height once it
            // has measured every card — see `uniformWorkCardHeights()`. A floor, not
            // a clamp: content taller than it still reports its real height below,
            // which is what lets one render both display and measure.
            .frame(minHeight: max(cardSize.height, uniformHeight ?? 0), alignment: .topLeading)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: WorkCardHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            )
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
