import SwiftData
import SwiftUI

/// The rating/chapters/completion/word-count stats on a compact cover card.
/// Shared by `WorkCoverCard` (local `SavedWork`) and `AO3WorkCoverCard` (remote
/// `AO3WorkSummary`) — each derives these already-formatted, already-nil-checked
/// values from its own model shape and hands them here.
///
/// **One stat per row.** This was a `FlowLayout` that packed as many stats onto a line
/// as fit, which is why the values were abbreviated to the point of being cryptic ("M",
/// "112K", "WIP"). The status badges that used to compete for the same space now live
/// behind the card's ⓘ button, so the vertical room exists and each stat can say what
/// it means. A column also removes the two-pass sizing hazard `WorkSummaryCardSurface`
/// documents: a `VStack`'s height does not depend on the width it is proposed, so it
/// cannot wrap differently between the ideal-size query and placement.
struct CoverCardStatsRow: View {
    var ratingName: String?
    /// The full AO3 rating ("Teen And Up Audiences"), announced in place of the visible
    /// shortened name.
    var ratingFull: String?
    var chapters: String?
    var completion: (text: String, symbol: String)?
    var wordCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let ratingName {
                WorkStatLabel(
                    text: ratingName,
                    symbol: "checkmark.shield",
                    accessibilityLabel: ratingFull ?? ratingName
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
                WorkStatLabel(text: completion.text, symbol: completion.symbol)
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

    var body: some View {
        WorkSummaryCardSurface(hue: CoverArt.hue(for: work.title)) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 6) {
                    Text(work.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    statusButton
                }
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
            ratingName: WorkStat.ratingName(work.rating),
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
        // not, rather than defaulting a non-AO3 work to In Progress and being wrong about it.
        if work.ao3WorkID != nil || WorkTags.ao3WorkID(from: work.sourceURL) != nil {
            return work.isComplete ? "Complete" : "In Progress"
        }
        return work.isComplete ? "Complete" : nil
    }

    /// ⓘ in the card's top-right corner: pushes Work Details.
    ///
    /// Shown on **every** card. It used to appear only when the work had a badge worth
    /// showing, because it opened a sheet that would otherwise have been empty; now that
    /// it goes to Work Details — which always has something to say — a card without one
    /// would just be a card missing its shortcut.
    ///
    /// A foreground `NavigationLink` is safe even though the whole card navigates: the
    /// card's own link lives in the *background* (see `CardNavigationModifier`), so a
    /// foreground control is hit-tested first and takes its own taps. That is precisely
    /// why the card's link is in the background rather than wrapping the content. The
    /// card opens the reader; this opens the work.
    private var statusButton: some View {
        NavigationLink(value: LocalWorkDestination.detail(work)) {
            Image(systemName: "info.circle")
                // Body size, matching the same ⓘ in the card's long-press menu — at
                // .caption it read as decoration rather than a control.
                .font(.body)
                .foregroundStyle(.secondary)
                // 30pt of tappable area around a 17pt glyph. Still under the 44pt
                // guideline, deliberately: a larger target on a compact carousel card
                // would eat the title's width, and Work Details is also reachable by
                // long-pressing the card.
                //
                // The glyph is pinned to the box's own top-trailing corner, and the
                // box is then pulled into the card's 12pt padding. Without both, the
                // slack between a 28pt target and a 13pt glyph left the ⓘ floating
                // roughly 19pt inside the corner instead of sitting in it. The tap
                // target keeps its full 28pt — only the layout moves.
                .frame(width: 30, height: 30, alignment: .topTrailing)
                .contentShape(Rectangle())
                .padding(.top, -4)
                .padding(.trailing, -6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Work details")
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
                HStack(alignment: .top, spacing: 6) {
                    Text(work.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    detailButton
                }
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
        .remoteWorkContextMenu(work: work)
    }

    /// ⓘ → Work Details for the remote work. Same placement and target size as the
    /// local card's (see `WorkCoverCard.statusButton`).
    private var detailButton: some View {
        NavigationLink(value: work) {
            Image(systemName: "info.circle")
                // Body size, matching the same ⓘ in the card's long-press menu — at
                // .caption it read as decoration rather than a control.
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30, alignment: .topTrailing)
                .contentShape(Rectangle())
                .padding(.top, -4)
                .padding(.trailing, -6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Work details")
    }

    private var cardStats: some View {
        CoverCardStatsRow(
            ratingName: WorkStat.ratingName(work.rating),
            ratingFull: work.rating.isEmpty ? nil : work.rating,
            chapters: work.chapters.isEmpty ? nil : work.chapters,
            completion: work.isComplete.map {
                ($0 ? "Complete" : "In Progress", $0 ? "checkmark.seal" : "circle.dashed")
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
