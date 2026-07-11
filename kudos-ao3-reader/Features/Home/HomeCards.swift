import SwiftData
import SwiftUI

/// Standard carousel card: a compact AO3 work summary surface with the title, author,
/// status, metadata, and reading progress all inside the tappable card.
struct WorkCoverCard: View {
    let work: SavedWork
    var footer: String?
    var progress: Double?

    var body: some View {
        WorkSummaryCardSurface(hue: CoverArt.hue(for: work.title)) {
            VStack(alignment: .leading, spacing: 7) {
                Text(work.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !work.author.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "person")
                            .foregroundStyle(.tint)
                        AO3AuthorBylineView(
                            displayText: work.author,
                            identities: work.verifiedAuthorIdentities,
                            includesBy: false,
                            font: .caption,
                            compact: true
                        )
                    }
                }

                if let fandom = work.workFandoms.first, !fandom.isEmpty {
                    CardMetaLabel(text: fandom, symbol: "books.vertical")
                        .font(.caption2)
                }

                cardStats

                if !stateBadges.isEmpty {
                    FlowLayout(spacing: 6, rowSpacing: 5) {
                        ForEach(stateBadges, id: \.text) { badge in
                            WorkStateBadge(text: badge.text, symbol: badge.symbol)
                        }
                    }
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
        FlowLayout(spacing: 8, rowSpacing: 5) {
            let ratingShort = WorkStat.ratingShort(work.rating)
            if let ratingShort {
                WorkStatLabel(text: ratingShort, symbol: "checkmark.shield")
            }
            if !work.chapters.isEmpty {
                WorkStatLabel(text: work.chapters, symbol: "book")
            }
            if let completion = completionStatus {
                WorkStatLabel(text: completion, symbol: work.isComplete ? "checkmark.seal" : "circle.dashed")
            }
            if work.wordCount > 0 {
                WorkStatLabel(text: work.wordCount.formatted(.number.notation(.compactName)), symbol: "textformat.size")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
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
        guard work.ao3WorkID != nil || WorkTags.ao3WorkID(from: work.sourceURL) != nil else { return nil }
        return work.isComplete ? "Complete" : "WIP"
    }

    private var stateBadges: [(text: String, symbol: String)] {
        var badges: [(text: String, symbol: String)] = []
        if work.isInSavedForLaterQueue { badges.append((text: "Later", symbol: "bookmark.fill")) }
        if work.isSaved { badges.append((text: "Saved", symbol: "bookmark.fill")) }
        if work.hasEPUB { badges.append((text: "Offline", symbol: "arrow.down.circle.fill")) }
        if work.isFavorite { badges.append((text: "Favorite", symbol: "star.fill")) }
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

                if !work.authors.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "person")
                            .foregroundStyle(.tint)
                        AO3AuthorBylineView(
                            names: work.authors,
                            identities: work.authorIdentities,
                            includesBy: false,
                            font: .caption,
                            compact: true
                        )
                    }
                }

                if let fandom = work.fandoms.first, !fandom.isEmpty {
                    CardMetaLabel(text: fandom, symbol: "books.vertical", lineLimit: 2)
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
        FlowLayout(spacing: 8, rowSpacing: 5) {
            let ratingShort = WorkStat.ratingShort(work.rating)
            if let ratingShort {
                WorkStatLabel(text: ratingShort, symbol: "checkmark.shield")
            }
            if !work.chapters.isEmpty {
                WorkStatLabel(text: work.chapters, symbol: "book")
            }
            if let isComplete = work.isComplete {
                WorkStatLabel(text: isComplete ? "Complete" : "WIP",
                              symbol: isComplete ? "checkmark.seal" : "circle.dashed")
            }
            if let words = work.words {
                WorkStatLabel(text: words.formatted(.number.notation(.compactName)), symbol: "textformat.size")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
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

    var body: some View {
        content()
            .padding(12)
            .frame(width: CarouselCardMetrics.width,
                   height: CarouselCardMetrics.height,
                   alignment: .topLeading)
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .lineLimit(lineLimit)
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
