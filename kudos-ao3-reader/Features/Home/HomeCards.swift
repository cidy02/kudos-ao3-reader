import SwiftData
import SwiftUI

/// Shared stable hue helper for non-work decorative tiles, such as Collections.
enum CoverArt {
    /// A stable hue in 0...1 derived from the title (djb2-ish hash).
    static func hue(for string: String) -> Double {
        let hash = string.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        return Double(hash % 360) / 360
    }
}

enum WorkSummaryCardMetrics {
    static let width: CGFloat = 164
    static let height: CGFloat = 228
    static let cornerRadius: CGFloat = 12
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
                Text(work.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !work.author.isEmpty {
                    CardMetaLabel(text: work.author, symbol: "person")
                        .font(.caption)
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

                if let author = work.authors.first, !author.isEmpty {
                    CardMetaLabel(text: author, symbol: "person")
                        .font(.caption)
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
                RoundedRectangle(cornerRadius: WorkSummaryCardMetrics.cornerRadius, style: .continuous)
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
            .frame(width: WorkSummaryCardMetrics.width,
                   height: WorkSummaryCardMetrics.height,
                   alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: WorkSummaryCardMetrics.cornerRadius, style: .continuous)
                    .fill(themeManager.appTheme.carouselCardSurface)
                    .overlay(hueTint)
                    .overlay(
                        RoundedRectangle(cornerRadius: WorkSummaryCardMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(themeManager.appTheme.carouselCardBorder(hue: hue), lineWidth: 0.5)
                    )
                    .shadow(color: themeManager.appTheme.carouselCardShadow.color,
                            radius: themeManager.appTheme.carouselCardShadow.radius,
                            x: 0,
                            y: themeManager.appTheme.carouselCardShadow.y)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: WorkSummaryCardMetrics.cornerRadius, style: .continuous)
            )
    }

    @ViewBuilder
    private var hueTint: some View {
        if let hue {
            RoundedRectangle(cornerRadius: WorkSummaryCardMetrics.cornerRadius, style: .continuous)
                .fill(themeManager.appTheme.carouselCardTint(hue: hue))
        }
    }
}

private struct WorkStateBadge: View {
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

private struct CarouselCardShadow {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}

private extension ReaderTheme {
    var carouselCardSurface: Color {
        #if os(iOS)
        appElevatedBackground ?? Color(uiColor: .secondarySystemGroupedBackground)
        #else
        appElevatedBackground ?? Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// A per-title hue wash over the elevated surface so neighbouring cards read as
    /// distinct works. Kept subtle — saturation/opacity stay low enough that title and
    /// metadata text remain legible on every theme.
    func carouselCardTint(hue: Double) -> Color {
        switch self {
        case .dark:
            Color(hue: hue, saturation: 0.55, brightness: 0.85).opacity(0.16)
        case .light:
            Color(hue: hue, saturation: 0.60, brightness: 0.80).opacity(0.14)
        case .sepia:
            Color(hue: hue, saturation: 0.45, brightness: 0.75).opacity(0.12)
        }
    }

    func carouselCardBorder(hue: Double?) -> Color {
        if let hue {
            switch self {
            case .dark:
                return Color(hue: hue, saturation: 0.50, brightness: 0.90).opacity(0.28)
            case .light:
                return Color(hue: hue, saturation: 0.55, brightness: 0.55).opacity(0.24)
            case .sepia:
                return Color(hue: hue, saturation: 0.40, brightness: 0.55).opacity(0.22)
            }
        }
        switch self {
        case .dark:
            return Color.white.opacity(0.12)
        case .light:
            return Color.black.opacity(0.08)
        case .sepia:
            return Color(red: 0.34, green: 0.22, blue: 0.08).opacity(0.18)
        }
    }

    var carouselCardShadow: CarouselCardShadow {
        switch self {
        case .dark:
            CarouselCardShadow(color: Color.black.opacity(0.34), radius: 8, y: 4)
        case .light:
            CarouselCardShadow(color: Color.black.opacity(0.13), radius: 8, y: 3)
        case .sepia:
            CarouselCardShadow(
                color: Color(red: 0.34, green: 0.22, blue: 0.08).opacity(0.22),
                radius: 8,
                y: 3
            )
        }
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
