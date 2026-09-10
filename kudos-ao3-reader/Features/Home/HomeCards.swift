import SwiftData
import SwiftUI

/// Standard carousel card: a compact AO3 work summary surface with the title, author,
/// status, metadata, and reading progress all inside the tappable card.
struct WorkCoverCard: View {
    let work: SavedWork
    var footer: String?
    var progress: Double?

    @Environment(ThemeManager.self) private var themeManager
    @ScaledMetric(relativeTo: .headline) private var ringDiameter: CGFloat = 68
    /// Set per tab stack; the pushed reader zooms out of this card. See
    /// `WorkCardZoomTransition.swift`.
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace

    var body: some View {
        WorkSummaryCardSurface(hue: hue) {
            VStack(alignment: .leading, spacing: 5) {
                if let primaryFandom {
                    SubjectKicker(text: primaryFandom, palette: palette, size: 9)
                        .padding(.bottom, 2)
                }

                Text(work.title)
                    .font(.headline)
                    // Two lines, then "…". A third line costs real card height
                    // for a fraction of a title, and long fandom titles are
                    // common enough that they decided the card's size more often
                    // than the metadata below them did.
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                if let progressValue {
                    progressRing(progressValue)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let footer {
                    updateBadge(footer)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Spacer(minLength: 0)

                if !work.author.isEmpty {
                    Text(work.author)
                        .font(.caption)
                        .foregroundStyle(Color.primary.opacity(0.78))
                        .lineLimit(1)
                        .combinedAccessibilityRow("Author: \(work.author)")
                }

                // Only preservation stays on the card. It is the one status the app
                // exists to surface — "this is the last copy of a deleted work" — and
                // hiding that would defeat the point. It also appears on very few
                // cards, so it costs space only where it matters most. Work Details
                // is on the long-press menu, not a corner control.
                if let preservation = work.preservationState.badgeLabel {
                    WorkStateBadge(text: preservation, symbol: work.preservationState.badgeSymbol)
                        .font(.caption2)
                }

                cardStats
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)
            }
        }
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
            arrangement: .strip,
            showsTray: true
        )
    }

    private var primaryFandom: String? {
        work.workFandoms.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var hue: Double {
        CoverArt.workHue(fandoms: work.workFandoms, title: work.title)
    }

    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: hue)
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

    private func progressRing(_ value: Double) -> some View {
        WorkProgressRing(
            progress: value,
            state: value >= 1 ? "Finished" : "Reading",
            diameter: min(ringDiameter, 82)
        )
    }

    private func updateBadge(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.monospacedDigit().weight(.bold))
            .tracking(0.5)
            .lineLimit(1)
            // Spec 1b draws this white on a white-16% capsule, not in the
            // subject accent: it says "this changed since you looked", which is
            // a fact about the card, not part of the fandom's identity.
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(themeManager.appTheme.glassFill(0.16), in: Capsule())
            .combinedAccessibilityRow(text)
    }
}

/// Carousel card for a remote AO3 work (Subscriptions / Recently Updated). It uses
/// the same self-contained summary shape as local Library/Home work cards.
struct AO3WorkCoverCard: View {
    let work: AO3WorkSummary

    /// See `WorkCoverCard.zoomNamespace`.
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace

    var body: some View {
        WorkSummaryCardSurface(hue: CoverArt.workHue(fandoms: work.fandoms, title: work.title)) {
            VStack(alignment: .leading, spacing: 7) {
                // Matches the local card — see `WorkCoverCard`.
                Text(work.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Matches the local card's grouping — see `WorkCoverCard`.
                Spacer(minLength: 4)

                cardStats
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 4)

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

                if !work.dateUpdated.isEmpty {
                    WorkStateBadge(text: work.dateUpdated, symbol: "calendar")
                        .font(.caption2)
                }
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
            tileSize: 27,
            announcesToVoiceOver: true
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
                RoundedRectangle(cornerRadius: CarouselCardMetrics.workCornerRadius, style: .continuous)
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
    /// Stable per-fandom hue (0...1) used to tint the card so the same subject has
    /// one visual identity across surfaces.
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
                RoundedRectangle(cornerRadius: CarouselCardMetrics.workCornerRadius, style: .continuous)
                    .fill(themeManager.appTheme.carouselCardSurface)
                    .overlay(hueTint)
                    .overlay(
                        RoundedRectangle(cornerRadius: CarouselCardMetrics.workCornerRadius, style: .continuous)
                            .strokeBorder(
                                hue.map { themeManager.appTheme.subjectPalette(hue: $0).cardBorder }
                                    ?? themeManager.appTheme.carouselCardBorder(hue: nil),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: themeManager.appTheme.carouselCardShadow.color,
                            radius: themeManager.appTheme.carouselCardShadow.radius,
                            x: 0,
                            y: themeManager.appTheme.carouselCardShadow.y)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: CarouselCardMetrics.workCornerRadius, style: .continuous)
            )
    }

    @ViewBuilder
    private var hueTint: some View {
        if let hue {
            RoundedRectangle(cornerRadius: CarouselCardMetrics.workCornerRadius, style: .continuous)
                .fill(themeManager.appTheme.subjectPalette(hue: hue).cardWash)
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
struct CardMetaLabel: View {
    let text: String
    let symbol: String
    var lineLimit: Int = 1
    /// What VoiceOver announces instead of the bare `text` — a name or fandom on
    /// its own doesn't say what role it plays on the card ("Author: " / "Fandom: ").
    var accessibilityLabel: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
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
