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
                    // Nested author byline would otherwise fight this Button for the
                    // same tap in selection mode — disabled here the same way the
                    // blurred branch above already disables it.
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
            // .cardNavigation, not a NavigationLink wrapping the visible hero as its
            // label: the hero's author name is its own tappable byline now (see
            // UnblurredHomeResumeHero), and a Button/NavigationLink nested inside
            // another NavigationLink's label doesn't reliably get its own
            // independent tap. cardNavigation instead puts an invisible background
            // NavigationLink behind the content — the same technique AO3WorkRow and
            // WorkRow already use for exactly this reason — so a tap on the byline
            // opens the author (and briefly suppresses the background link via
            // AppRouter.cardNavigationSuppressed) while a tap anywhere else on the
            // card still opens the reader.
            UnblurredHomeResumeHero(work: work)
                .cardNavigation(to: LocalWorkDestination.reader(work), accessibilityLabel: work.title)
                .localWorkContextMenu(work: work, onSelect: onSelect)
        }
    }
}

private struct UnblurredHomeResumeHero: View {
    let work: SavedWork
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace

    /// Individual author names for the byline — matches WorkDetailView's
    /// `displayAuthorList` derivation for the same work.
    private var authorNames: [String] {
        work.verifiedAuthorIdentities.isEmpty
            ? (work.author.isEmpty ? [] : [work.author])
            : work.verifiedAuthorIdentities.map(\.displayName)
    }

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
            // Tag grid decoupled into a top-trailing overlay on the title, not
            // an HStack sibling of it — an HStack top-aligns both, and since
            // the 2x2 grid (tileSize 27, ~60pt tall) is much taller than a
            // single line of title text, the VStack's spacing to the *next*
            // row (author) measured from the grid's bottom, not the shorter
            // title's — a large dead gap that had nothing to do with the
            // 12pt spacing value itself. An overlay lets the title's own
            // height drive the VStack's rhythm while the grid just floats in
            // the corner.
            Text(work.title)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 60)
                .overlay(alignment: .topTrailing) {
                    WorkStatusIconGrid(
                        rating: work.rating.isEmpty ? nil : work.rating,
                        categories: work.workCategories,
                        warnings: work.workWarnings,
                        completion: work.completionStatus,
                        tileSize: 27,
                        announcesToVoiceOver: true
                    )
                }

            // Real Label + AO3AuthorBylineView (matching WorkDetailHeroCard, not
            // WorkStatLabel) so the author name is tappable, same as everywhere
            // else authors show up in the app. expandsHitTarget: false — its
            // default (true) gives each name its own top-aligned 28pt hit box,
            // which reads fine beside plain inline text but visibly desyncs this
            // icon from the byline's vertical center once the box is taller than
            // the .caption text itself (see WorkDetailHeroCard's matching fix).
            if !work.author.isEmpty {
                Label {
                    AO3AuthorBylineView(
                        names: authorNames,
                        identities: work.verifiedAuthorIdentities,
                        includesBy: false,
                        font: .caption,
                        expandsHitTarget: false
                    )
                } icon: {
                    Image(systemName: "person")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            if let fandom = work.workFandoms.first, !fandom.isEmpty {
                WorkStatLabel(
                    text: fandom,
                    symbol: "books.vertical",
                    accessibilityLabel: "Fandom: \(fandom)"
                )
                .font(.caption)
            }

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
