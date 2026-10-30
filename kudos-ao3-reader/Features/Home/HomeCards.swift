import SwiftData
import SwiftUI

enum WorkCoverMetadataStyle: Equatable {
    case standard
    case downloaded
}

enum WorkCoverMetadata {
    static func reading(chapters: String, progress: Double) -> String {
        let posted = SavedWork.postedChapterCount(from: chapters)
        let total = SavedWork.totalChapterCount(from: chapters)
        var parts: [String] = []
        if posted > 0 {
            parts.append(total.map { "Ch \(posted) of \($0)" } ?? "Ch \(posted)")
        }
        parts.append("\(Int((min(max(progress, 0), 1) * 100).rounded()))%")
        return parts.joined(separator: " · ")
    }

    static func downloaded(date: String?, size: String?) -> String? {
        let text = [date, size].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    static func summary(words: Int?, chapters: String) -> String? {
        var parts: [String] = []
        if let words, words > 0 { parts.append("\(words.compactCount) words") }
        if !chapters.isEmpty { parts.append(chapters) }
        let text = parts.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    static func updateBadge(from footer: String?) -> String? {
        guard let footer, footer.first == "+" else { return nil }
        let count = footer.dropFirst().prefix { $0.isNumber }
        return count.isEmpty ? footer : "+\(count)"
    }
}

/// Standard carousel card: a compact AO3 work summary surface with the title, author,
/// status, metadata, and reading progress all inside the tappable card.
struct WorkCoverCard: View {
    let work: SavedWork
    var footer: String?
    var progress: Double?
    var metadataStyle: WorkCoverMetadataStyle = .standard

    @Environment(DownloadQueue.self) private var downloads
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Set per tab stack; the pushed reader zooms out of this card. See
    /// `WorkCardZoomTransition.swift`.
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace

    var body: some View {
        WorkSummaryCardSurface(
            art: CoverArt.workArt(fandoms: work.workFandoms, title: work.title),
            title: work.title,
            author: work.author,
            fandom: primaryFandom
        ) {
            if downloads.isDownloading(work) {
                TimelineView(.animation) { context in
                    CoverProgressBar(
                        progress: downloads.downloadFraction(for: work, at: context.date) ?? 1,
                        accessibilityLabel: "Download progress"
                    )
                }
            } else if let progressValue {
                CoverProgressBar(
                    progress: progressValue,
                    accessibilityLabel: "Reading progress"
                )
            }
            cardStats
            coverMeta
            if let preservation = work.preservationState.badgeLabel {
                WorkStateBadge(text: preservation, symbol: work.preservationState.badgeSymbol)
                    .font(.caption2)
            }
        }
        .downloadDimmed(work)
        // The reader pushed from this card zooms out of it, and collapses back into
        // it on dismiss. No-ops where no namespace is provided.
        .workCardZoomSource(work.zoomKey, in: zoomNamespace)
    }

    private var cardStats: some View {
        WorkStatusIconGrid(
            rating: work.rating.isEmpty ? nil : work.rating,
            categories: work.workCategories,
            warnings: work.workWarnings,
            completion: work.completionStatus,
            tileSize: 24,
            announcesToVoiceOver: true,
            arrangement: .strip
        )
    }

    private var primaryFandom: String? {
        work.workFandoms.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(FandomDisplayName.bareTitle)
    }

    private var progressValue: Double? {
        Self.resolvedProgress(
            explicit: progress,
            footer: footer,
            isFinished: work.isFinished,
            saved: work.readingProgress
        )
    }

    /// Explicit caller intent wins. A caller-supplied footer with no explicit
    /// progress is an update/status presentation and must not be replaced by the
    /// model's incidental reading progress (Recently Updated's `+N new` case).
    static func resolvedProgress(
        explicit: Double?,
        footer: String?,
        isFinished: Bool,
        saved: Double?
    ) -> Double? {
        if let explicit { return min(1, max(0, explicit)) }
        guard footer == nil else { return nil }
        if isFinished { return 1 }
        return saved.map { min(1, max(0, $0)) }
    }

    private var coverMeta: some View {
        HStack(spacing: 6) {
            Text(metaLine ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let badge = WorkCoverMetadata.updateBadge(from: footer) {
                updateBadge(badge)
            }
        }
    }

    private var metaLine: String? {
        if metadataStyle == .downloaded {
            let date = work.downloadedAt?.formatted(.dateTime.month(.abbreviated).day())
            let values = try? work.fileURL.resourceValues(forKeys: [.fileSizeKey])
            let size = values?.fileSize.map { LocalStorageFootprint.formatted(bytes: Int64($0)) }
            return WorkCoverMetadata.downloaded(date: date, size: size)
        }
        if let progressValue {
            return WorkCoverMetadata.reading(chapters: work.chapters, progress: progressValue)
        }
        if let footer, WorkCoverMetadata.updateBadge(from: footer) == nil { return footer }
        return WorkCoverMetadata.summary(words: work.wordCount, chapters: work.chapters)
    }

    private func updateBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit().weight(.bold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .frame(minHeight: 16)
            .padding(.horizontal, 6)
            .background(.accentFill, in: Capsule())
            .combinedAccessibilityRow(text)
    }
}

/// Carousel card for a remote AO3 work (Subscriptions / Recently Updated). It uses
/// the same self-contained summary shape as local Library/Home work cards.
struct AO3WorkCoverCard: View {
    let work: AO3WorkSummary
    /// Draws `AO3ProvenanceBadge`. Only where remote and local cards share a row.
    var showsProvenanceBadge = false

    /// See `WorkCoverCard.zoomNamespace`.
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace

    /// Deliberately the same stack as `WorkCoverCard`, slot for slot: kicker,
    /// title, centre badge, author, signal strip. A Subscriptions carousel draws
    /// remote and local cards side by side — a remote work the reader has saved
    /// is local, the rest are not — so any difference in shape reads as two
    /// designs in one row rather than as "this one isn't downloaded".
    ///
    /// Two slots differ, and only because the data does: a remote work has no
    /// reading progress, so the centre slot takes its update date (the local
    /// card's "+N new" slot), and there is no preservation state to report.
    var body: some View {
        WorkSummaryCardSurface(
            art: CoverArt.workArt(fandoms: work.fandoms, title: work.title),
            title: work.title,
            author: work.authorText,
            fandom: primaryFandom
        ) {
            cardStats
            Text(remoteMeta ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            if showsProvenanceBadge {
                AO3ProvenanceBadge()
                    .padding(AO3ProvenanceBadge.edgeInset)
            }
        }
        .workCardZoomSource(work.zoomKey, in: zoomNamespace)
        .remoteWorkContextMenu(work: work)
    }

    private var cardStats: some View {
        WorkStatusIconGrid(
            rating: work.rating.isEmpty ? nil : work.rating,
            categories: work.categories,
            warnings: work.warnings,
            completion: WorkCompletionStatus(isComplete: work.isComplete),
            tileSize: 24,
            announcesToVoiceOver: true,
            arrangement: .strip
        )
    }

    /// The fandom the kicker prints — it replaces the `books.vertical` metadata
    /// row this card used to carry, so no fact left the card with it.
    private var primaryFandom: String? {
        work.fandoms.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(FandomDisplayName.bareTitle)
    }

    /// Words, chapters and the updated date all stay. The previous card printed
    /// the date as its own badge; dropping it once words exist hid an AO3 field.
    private var remoteMeta: String? {
        var parts: [String] = []
        if let words = work.words { parts.append("\(words.compactCount) words") }
        if !work.chapters.isEmpty { parts.append(work.chapters) }
        if !work.dateUpdated.isEmpty { parts.append(work.dateUpdated) }
        let text = parts.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }
}

/// The small "AO3" tag in a remote card's top-right corner — board 1b draws it on
/// Home's Subscriptions cards, measured in `docs/REDESIGN_PLAN.md` (radius 5,
/// black 40 %, `700 8px`, `.08em`, white 80 %; 3×6 padding, 10pt from the
/// edges). It exists because that row mixes the two kinds: a subscribed work
/// the reader has saved renders as its local card, the rest are on AO3 only,
/// and the cards are otherwise drawn alike on purpose. Fixed 8pt, as measured.
struct AO3ProvenanceBadge: View {
    static let edgeInset: CGFloat = 10
    /// About 30pt of badge ("AO3" at 8pt, plus 6pt each side) and its 10pt inset,
    /// less the card's 12pt content padding, plus 4pt of air.
    static let clearance: CGFloat = 32

    var body: some View {
        Text("AO3")
            .font(.system(size: 8, weight: .bold))
            .tracking(8 * 0.08)
            .foregroundStyle(Color.white.opacity(0.8))
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(Color.black.opacity(0.4), in: Capsule())
            .accessibilityLabel("From AO3")
    }
}

/// Selection-mode wrapper for local carousel cards. The full card remains the hit
/// target while the bubble mirrors iOS multi-select affordances without disturbing
/// the compact summary layout.
struct SelectableWorkCoverCard: View {
    let work: SavedWork
    var footer: String?
    var progress: Double?
    var metadataStyle: WorkCoverMetadataStyle = .standard
    var isSelected: Bool

    var body: some View {
        WorkCoverCard(work: work, footer: footer, progress: progress, metadataStyle: metadataStyle)
            .overlay(alignment: .topTrailing) {
                WorkSelectionBubble(isSelected: isSelected)
                    .padding(8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear), lineWidth: 2)
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
                Circle().fill(.accentFill)
            }
            Circle()
                .strokeBorder(
                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.55)),
                    lineWidth: 1.25
                )
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
    let art: CoverArt.WorkArt
    let title: String
    let author: String
    let fandom: String?
    @ViewBuilder var content: () -> Content

    /// Scales width and height together so the card grows proportionally at
    /// large Dynamic Type sizes instead of only getting taller.
    var cardSize = ScaledCarouselCardSize()

    /// Set by the enclosing carousel/grid so every card there matches the tallest.
    /// `nil` in a container that doesn't coordinate — the card keeps its own floor.
    @Environment(\.uniformWorkCardHeight) private var uniformHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeneratedWorkCoverArt(
                art: art,
                title: title,
                author: author,
                fandom: fandom,
                width: cardSize.width
            )
            .frame(width: cardSize.width, height: cardSize.width * 1.42)

            VStack(alignment: .leading, spacing: 6) { content() }
                .frame(width: cardSize.width, alignment: .leading)
        }
            .frame(width: cardSize.width, alignment: .topLeading)
            .frame(minHeight: max(cardSize.height, uniformHeight ?? 0), alignment: .topLeading)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: WorkCardHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            )
            .contentShape(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
            )
    }
}

private struct GeneratedWorkCoverArt: View {
    let art: CoverArt.WorkArt
    let title: String
    let author: String
    let fandom: String?
    let width: CGFloat

    @Environment(ThemeManager.self) private var themeManager

    private var scale: CGFloat { width / CarouselCardMetrics.width }

    var body: some View {
        ZStack {
            CoverArt.workGradient(for: art)
            initial
            layout
                .padding(width * 0.1)
        }
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(
            color: themeManager.appTheme.carouselCardShadow.color,
            radius: themeManager.appTheme.carouselCardShadow.radius,
            x: 0,
            y: themeManager.appTheme.carouselCardShadow.y
        )
        .environment(\.colorScheme, .dark)
    }

    private var initial: some View {
        Text(title.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "")
            .font(.system(size: width * 1.05, weight: .semibold, design: .serif))
            .foregroundStyle(Color.white.opacity(0.15))
            .fixedSize()
            .offset(initialOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: initialAlignment)
            .accessibilityHidden(true)
    }

    private var initialAlignment: Alignment {
        art.layout == 0 ? .topTrailing : art.layout == 1 ? .bottomTrailing : .bottomLeading
    }

    private var initialOffset: CGSize {
        switch art.layout {
        case 0: CGSize(width: width * 0.07, height: -width * 0.17)
        case 1: CGSize(width: width * 0.07, height: width * 0.29)
        default: CGSize(width: -width * 0.07, height: width * 0.29)
        }
    }

    @ViewBuilder
    private var layout: some View {
        switch art.layout {
        case 0:
            VStack(alignment: .leading, spacing: 4 * scale) {
                fandomLabel
                Spacer(minLength: 0)
                titleLabel
                authorLabel
            }
        case 1:
            VStack(alignment: .leading, spacing: 4 * scale) {
                titleLabel
                authorLabel
                Spacer(minLength: 0)
                fandomLabel
            }
        default:
            VStack(alignment: .leading, spacing: 4 * scale) {
                fandomLabel
                titleLabel.multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 6 * scale)
                authorLabel.frame(maxWidth: .infinity, alignment: .trailing)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var fandomLabel: some View {
        if let fandom, !fandom.isEmpty {
            Text(fandom.uppercased())
                .font(.system(size: max(8, width * 0.075), weight: .semibold))
                .tracking(0.8 * scale)
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(2)
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(.system(size: max(13, width * 0.135), weight: .semibold, design: .serif))
            .foregroundStyle(.white)
            .lineLimit(4)
            .minimumScaleFactor(0.78)
    }

    @ViewBuilder
    private var authorLabel: some View {
        if !author.isEmpty {
            Text(author)
                .font(.system(size: max(10, width * 0.092)).italic())
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(2)
        }
    }
}

private struct CoverProgressBar: View {
    let progress: Double
    let accessibilityLabel: String

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let fraction = min(max(progress, 0), 1)
        GeometryReader { geometry in
            Capsule()
                .fill(themeManager.appTheme.glassFill(0.14))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.accentFill)
                        .frame(width: geometry.size.width * fraction)
                }
        }
        .frame(height: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
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
