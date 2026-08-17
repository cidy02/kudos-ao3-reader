import SwiftData
import SwiftUI

struct HomeResumeHero: View {
    let work: SavedWork
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)?
    var onSelect: (() -> Void)?

    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var mode: MaturePrivacyMode = .obscure

    private var blurred: Bool {
        hideMature && work.isAdult && mode == .obscure && !gate.isRevealed(work)
    }

    var body: some View {
        if blurred {
            let hero = UnblurredHomeResumeHero(work: work)
                .environment(\.ao3AuthorNavigationEnabled, false)
                .blur(radius: 6)
                .overlay {
                    if !isSelecting {
                        Label("Tap to reveal", systemImage: "eye.slash.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
                .contentShape(Rectangle())

            if isSelecting {
                hero
                    .overlay(alignment: .topTrailing) {
                        WorkSelectionBubble(isSelected: isSelected)
                            .padding(8)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                    .onTapGesture { onToggleSelection?() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(work.title)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
                    .localWorkContextMenu(work: work, onSelect: onSelect)
            } else {
                hero
                    .onTapGesture { gate.reveal(work) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Hidden mature work. Activate to reveal.")
                    .localWorkContextMenu(work: work, onSelect: onSelect)
            }
        } else if isSelecting {
            Button {
                onToggleSelection?()
            } label: {
                UnblurredHomeResumeHero(work: work)
                    .environment(\.ao3AuthorNavigationEnabled, false)
                    .overlay(alignment: .topTrailing) {
                        WorkSelectionBubble(isSelected: isSelected)
                            .padding(8)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(work.title)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .localWorkContextMenu(work: work, onSelect: onSelect)
        } else {
            NavigationLink(value: LocalWorkDestination.reader(work)) {
                UnblurredHomeResumeHero(work: work)
            }
            .buttonStyle(.plain)
            .localWorkContextMenu(work: work, onSelect: onSelect)
        }
    }
}

private struct UnblurredHomeResumeHero: View {
    let work: SavedWork
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace

    var body: some View {
        let hue = CoverArt.hue(for: work.title)
        // Clamp nil/out-of-range progress so the bar and percent never crash or
        // render negative/over-100 garbage. In-progress works can still lack a
        // stored fraction (e.g. lastReadDate only) — show 0% rather than invent one.
        let progressValue = min(1, max(0, work.readingProgress ?? 0))
        let percent = Int((progressValue * 100).rounded())
        // Left label is chapter context only. Do NOT use `readingProgressLabel` here:
        // on the Readium (iOS) path that property is itself a percent string, which
        // would duplicate the monospaced percent on the right. Legacy macOS reader
        // still surfaces "Ch N" via lastSpineIndex.
        let chapterLabel: String? = work.lastSpineIndex > 0
            ? "Ch \(work.lastSpineIndex + 1)"
            : nil

        return VStack(alignment: .leading, spacing: 12) {
            Text(work.title)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Author/fandom share the stat row's own component (not
            // CardMetaLabel) so their text and icons read at exactly the same
            // size as the rating/chapters/completion/word-count row below —
            // one metadata family, not two different scales.
            if !work.author.isEmpty {
                WorkStatLabel(
                    text: work.author,
                    symbol: "person",
                    accessibilityLabel: "Author: \(work.author)",
                    iconColor: themeManager.effectiveTint
                )
                .font(.caption)
            }

            if let fandom = work.workFandoms.first, !fandom.isEmpty {
                WorkStatLabel(
                    text: fandom,
                    symbol: "books.vertical",
                    accessibilityLabel: "Fandom: \(fandom)",
                    iconColor: themeManager.effectiveTint
                )
                .font(.caption)
            }

            // Same four-chip Rating/Pairings/Warnings/Completion row the
            // search-result cards show (WorkListStatsRow's top row), so the
            // hero reads as one identity-facts family with the rest of the
            // app instead of a compressed 4-stat line of its own.
            WorkTopStatsRow(
                rating: work.rating.isEmpty ? nil : work.rating,
                categories: work.workCategories,
                warnings: work.workWarnings,
                completion: work.completionStatus
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            // Language/words/chapters below the identity chips — the hero's
            // own shorter second row, not WorkListStatsRow's full one (which
            // always includes comments/kudos/bookmarks/hits too).
            FlowLayout(spacing: 10, rowSpacing: 6) {
                if !work.language.isEmpty {
                    WorkStatLabel(
                        text: work.language,
                        symbol: "globe",
                        accessibilityLabel: "Language: \(work.language)"
                    )
                }
                if work.wordCount > 0 {
                    WorkStatLabel(
                        text: work.wordCount.formatted(),
                        symbol: "textformat.size",
                        accessibilityLabel: "\(work.wordCount.formatted()) words"
                    )
                }
                if !work.chapters.isEmpty {
                    WorkStatLabel(text: work.chapters, symbol: "book", accessibilityLabel: "Chapters \(work.chapters)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(chapterLabel ?? "Reading")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(percent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(.tint)
                            .frame(width: geo.size.width * max(0.03, progressValue))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                .fill(themeManager.appTheme.carouselCardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                        .fill(themeManager.appTheme.carouselCardTint(hue: hue))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(themeManager.appTheme.carouselCardBorder(hue: hue), lineWidth: 0.5)
                )
                .shadow(color: themeManager.appTheme.carouselCardShadow.color,
                        radius: themeManager.appTheme.carouselCardShadow.radius,
                        x: 0,
                        y: themeManager.appTheme.carouselCardShadow.y)
        )
        .contentShape(RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous))
        .workCardZoomSource(work.id, in: zoomNamespace)
    }
}

/// The "More In Progress" strip's card shape — wide and short (a book-cover-first
/// row, like Apple Books' "Continue" carousel) rather than the tall, portrait
/// `WorkCoverCard` every other carousel on this page uses. Deliberately a
/// different silhouette from the hero above it: the hero is the single most
/// important beat on the page, this strip is a fast, scannable list of what
/// else is active. Mirrors `HomeResumeHero`'s blur/selection wrapper exactly —
/// this is still an in-progress work and needs the same privacy-gate handling.
struct HomeResumeStripCard: View {
    let work: SavedWork
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)?
    var onSelect: (() -> Void)?

    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var mode: MaturePrivacyMode = .obscure

    private var blurred: Bool {
        hideMature && work.isAdult && mode == .obscure && !gate.isRevealed(work)
    }

    var body: some View {
        if blurred {
            let card = UnblurredHomeResumeStripCard(work: work)
                .environment(\.ao3AuthorNavigationEnabled, false)
                .blur(radius: 6)
                .overlay {
                    if !isSelecting {
                        Label("Tap to reveal", systemImage: "eye.slash.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
                .contentShape(Rectangle())

            if isSelecting {
                card
                    .overlay(alignment: .topTrailing) {
                        WorkSelectionBubble(isSelected: isSelected)
                            .padding(6)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: HomeResumeStripCardMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                    .onTapGesture { onToggleSelection?() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(work.title)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
                    .localWorkContextMenu(work: work, onSelect: onSelect)
            } else {
                card
                    .onTapGesture { gate.reveal(work) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Hidden mature work. Activate to reveal.")
                    .localWorkContextMenu(work: work, onSelect: onSelect)
            }
        } else if isSelecting {
            Button {
                onToggleSelection?()
            } label: {
                UnblurredHomeResumeStripCard(work: work)
                    .environment(\.ao3AuthorNavigationEnabled, false)
                    .overlay(alignment: .topTrailing) {
                        WorkSelectionBubble(isSelected: isSelected)
                            .padding(6)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: HomeResumeStripCardMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(work.title)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .localWorkContextMenu(work: work, onSelect: onSelect)
        } else {
            NavigationLink(value: LocalWorkDestination.reader(work)) {
                UnblurredHomeResumeStripCard(work: work)
            }
            .buttonStyle(.plain)
            .localWorkContextMenu(work: work, onSelect: onSelect)
        }
    }
}

private enum HomeResumeStripCardMetrics {
    static let width: CGFloat = 280
    static let cornerRadius: CGFloat = CarouselCardMetrics.cornerRadius
    /// The mini "cover" swatch — no real cover art exists in this app (see
    /// `CoverArt.hue`), so this is a smaller version of the same hue-tint
    /// treatment every card uses, at roughly a paperback's aspect ratio.
    static let coverWidth: CGFloat = 64
    static let coverHeight: CGFloat = 92
}

private struct UnblurredHomeResumeStripCard: View {
    let work: SavedWork
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace

    var body: some View {
        let hue = CoverArt.hue(for: work.title)
        let progressValue = work.readingProgress.map { min(1, max(0, $0)) }
        let percent = progressValue.map { Int(($0 * 100).rounded()) }

        return HStack(alignment: .top, spacing: 12) {
            // Mini cover swatch — same tint the card background washes with
            // (Books extends the real cover's dominant color the same way),
            // just more saturated so it still reads as a distinct "cover".
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(themeManager.appTheme.carouselQueueTint(hue: hue))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(themeManager.appTheme.carouselCardBorder(hue: hue), lineWidth: 0.5)
                )
                .overlay {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(width: HomeResumeStripCardMetrics.coverWidth, height: HomeResumeStripCardMetrics.coverHeight)

            VStack(alignment: .leading, spacing: 4) {
                Text(work.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !work.author.isEmpty {
                    Text(work.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // "Reading • 41%", mirroring Books' "Book • 31%" format line —
                // same fact-only register the rest of this app's cards use.
                HStack(spacing: 4) {
                    Text("Reading")
                    if let percent {
                        Text("•")
                        Text("\(percent)%").monospacedDigit()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            .frame(height: HomeResumeStripCardMetrics.coverHeight, alignment: .topLeading)
        }
        .padding(12)
        .frame(width: HomeResumeStripCardMetrics.width, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: HomeResumeStripCardMetrics.cornerRadius, style: .continuous)
                .fill(themeManager.appTheme.carouselCardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: HomeResumeStripCardMetrics.cornerRadius, style: .continuous)
                        .fill(themeManager.appTheme.carouselCardTint(hue: hue))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HomeResumeStripCardMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(themeManager.appTheme.carouselCardBorder(hue: hue), lineWidth: 0.5)
                )
                .shadow(color: themeManager.appTheme.carouselCardShadow.color,
                        radius: themeManager.appTheme.carouselCardShadow.radius,
                        x: 0,
                        y: themeManager.appTheme.carouselCardShadow.y)
        )
        .contentShape(RoundedRectangle(cornerRadius: HomeResumeStripCardMetrics.cornerRadius, style: .continuous))
        .workCardZoomSource(work.id, in: zoomNamespace)
    }
}
