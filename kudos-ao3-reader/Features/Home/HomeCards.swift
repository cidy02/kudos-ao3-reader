import SwiftUI
import SwiftData

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
        WorkSummaryCardSurface {
            VStack(alignment: .leading, spacing: 7) {
                Text(work.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !work.author.isEmpty {
                    Label(work.author, systemImage: "person")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let fandom = work.workFandoms.first, !fandom.isEmpty {
                    Label(fandom, systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

    @ViewBuilder
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
        guard let progressValue else { return footer ?? "Progress" }
        if let footer { return footer }
        return progressValue >= 1 ? "Finished" : "Progress"
    }

    private var completionStatus: String? {
        guard WorkTags.ao3WorkID(from: work.sourceURL) != nil else { return nil }
        return work.isComplete ? "Complete" : "WIP"
    }

    private var stateBadges: [(text: String, symbol: String)] {
        var badges: [(text: String, symbol: String)] = []
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
        WorkSummaryCardSurface {
            VStack(alignment: .leading, spacing: 7) {
                Text(work.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let author = work.authors.first, !author.isEmpty {
                    Label(author, systemImage: "person")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let fandom = work.fandoms.first, !fandom.isEmpty {
                    Label(fandom, systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                cardStats

                Spacer(minLength: 4)

                if !work.dateUpdated.isEmpty {
                    WorkStateBadge(text: work.dateUpdated, symbol: "calendar")
                        .font(.caption2)
                }
            }
        }
    }

    @ViewBuilder
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

private struct WorkSummaryCardSurface<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager
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
                    .overlay(
                        RoundedRectangle(cornerRadius: WorkSummaryCardMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(themeManager.appTheme.carouselCardBorder, lineWidth: 0.5)
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

    var carouselCardBorder: Color {
        switch self {
        case .dark: .clear
        case .light: Color.black.opacity(0.06)
        case .sepia: Color(red: 0.34, green: 0.22, blue: 0.08).opacity(0.15)
        }
    }

    var carouselCardShadow: CarouselCardShadow {
        switch self {
        case .dark:
            CarouselCardShadow(color: .clear, radius: 0, y: 0)
        case .light:
            CarouselCardShadow(color: Color.black.opacity(0.10), radius: 4, y: 2)
        case .sepia:
            CarouselCardShadow(
                color: Color(red: 0.34, green: 0.22, blue: 0.08).opacity(0.18),
                radius: 4,
                y: 2
            )
        }
    }
}

/// How the dashboard opens a tapped work: the canonical Work Detail, the same screen
/// every other entry point lands on (tap a card → detail; the detail's Read button
/// opens the reader). Opening it also clears the work from Recently Updated.
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
