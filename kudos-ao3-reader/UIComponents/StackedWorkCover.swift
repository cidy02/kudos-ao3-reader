import SwiftUI

/// A tile that reads as a shelf of works, not one abstract tile: up to 3 centered,
/// depth-scaled faces (front → back), each hued from its own work's title — the same
/// `CoverArt`/`carouselCardTint` treatment individual work cards already use, keyed
/// per-face instead of to the collection/queue's own name. No real cover art exists
/// anywhere in this app (AO3 has no mechanism for it), so this is a pure function of
/// the titles already in memory — no I/O, no cache, no loading state.
///
/// Converged design from `discussions/stacked-card-carousels.md` (Codex/Gemini/Grok +
/// app owner). Centered scaling (not a diagonal offset) so it's RTL-agnostic in its
/// `.vertical` axis; `.horizontal` deliberately trades that off for a sideways peek
/// (Reading Queues' own request) and stays RTL-correct instead by mirroring the peek
/// direction off `layoutDirection`. Callers own the single-work/empty fallback — this
/// view assumes at least 1 title.
struct StackedWorkCover: View {
    /// Ordered work titles (collection/queue order); only the first 3 are drawn.
    let workTitles: [String]
    var cardSize = ScaledCarouselCardSize()
    /// Which way back faces peek out from behind the front one.
    var axis: Axis = .vertical
    /// Always draws exactly 3 faces, cycling through `workTitles` to pad out fewer
    /// than 3, instead of drawing only as many faces as there are titles. For
    /// callers that want every stack in a carousel to read at the same depth
    /// regardless of how many works a particular queue/collection actually holds.
    var padToThree = false

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.layoutDirection) private var layoutDirection

    /// Front-to-back. A 2-work stack drops the back layer entirely rather than
    /// reusing/duplicating a face — unless `padToThree`, which cycles the titles
    /// that do exist so a 1-work queue still reads as a 3-deep stack.
    private var faces: [String] {
        guard !workTitles.isEmpty else { return [] }
        if padToThree {
            return (0..<3).map { workTitles[$0 % workTitles.count] }
        }
        return Array(workTitles.prefix(3))
    }

    /// Relative to `cardSize` — front is already slightly inset from the full
    /// footprint so there's headroom for back faces to peek past its front edge.
    /// `.vertical` only: `.horizontal` faces are all the same size (see `face`).
    private static let faceScales: [CGFloat] = [0.97, 0.90, 0.83]
    /// Front's own downward nudge for `.vertical`, leaving room above it for the
    /// stack to peek into.
    private static let frontOffset: CGFloat = 8
    /// `.horizontal` only: how much of each back face shows past the one in front
    /// of it, as a fraction of the card's own width. Faces are full-size (unlike
    /// `.vertical`'s shrink-for-headroom trick), so this is a plain fixed peek
    /// rather than something computed from a size delta — big enough to read as a
    /// deliberate stack of same-size books, not a hairline sliver.
    private static let horizontalPeekFraction: CGFloat = 0.15

    /// Front-to-back offsets along `axis`, as positive magnitudes growing from the
    /// front face outward — sign and axis are resolved by `face(title:depth:)`.
    private var faceOffsets: [CGFloat] {
        if axis == .horizontal {
            let peek = cardSize.width * Self.horizontalPeekFraction
            return (0..<faces.count).map { CGFloat($0) * peek }
        }

        guard faces.count > 1 else { return [Self.frontOffset] }

        // `.vertical`: the usable headroom is constrained by both the stack
        // footprint's own edge and the full front-to-back extent, then divided
        // among the back faces at every count.
        let extent = cardSize.height
        let frontHalfExtent = extent * Self.faceScales[0] / 2
        let totalExtentHeadroom = extent - 2 * frontHalfExtent
        let edgeHeadroom = extent / 2 + Self.frontOffset - frontHalfExtent
        let availableHeadroom = max(0, min(totalExtentHeadroom, edgeHeadroom))
        let peekPoints = availableHeadroom / CGFloat(faces.count - 1)

        var offsets: [CGFloat] = [Self.frontOffset]
        for depth in 1..<faces.count {
            let previousHalfExtent = extent * Self.faceScales[depth - 1] / 2
            let halfExtent = extent * Self.faceScales[depth] / 2
            offsets.append(offsets[depth - 1] - peekPoints - (previousHalfExtent - halfExtent))
        }
        return offsets
    }

    var body: some View {
        let offsets = faceOffsets
        ZStack {
            ForEach(Array(faces.enumerated().reversed()), id: \.offset) { depth, title in
                face(title: title, depth: depth, offset: offsets[depth])
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        // The stack is decorative — CollectionCard/ReadingQueueCard's own title +
        // "N works" text right below already carries the accessible label; without
        // this, VoiceOver would stop on 2-3 unlabeled peeking rectangles first.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func face(title: String, depth: Int, offset: CGFloat) -> some View {
        let hue = CoverArt.hue(for: title)
        let isFront = depth == 0
        let shape = RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
        // `.horizontal` peeks toward the trailing edge, mirrored for RTL so back
        // faces still peek toward reading-trailing, not a fixed screen side.
        // `.vertical` peeks upward (screen-space, so no RTL concern).
        let trailingSign: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
        // `.horizontal` faces are all the same size — offset alone creates the
        // peek, the way same-size books stacked side by side would. `.vertical`
        // keeps its original shrink-for-headroom look (unchanged).
        let scale = axis == .horizontal ? 1 : Self.faceScales[depth]

        shape
            .fill(themeManager.appTheme.carouselCardSurface)
            .overlay { shape.fill(themeManager.appTheme.carouselCardTint(hue: hue)) }
            .overlay {
                if isFront {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    // Reads as "behind," without hiding the hue — Round 1 proposed
                    // 15-30% here; corrected down since there's no real cover art
                    // to protect legibility for, just the tint itself.
                    shape.fill(.black.opacity(0.1))
                }
            }
            .overlay { shape.strokeBorder(themeManager.appTheme.carouselCardBorder(hue: hue), lineWidth: 0.75) }
            .frame(width: cardSize.width * scale, height: cardSize.height * scale)
            .offset(
                x: axis == .horizontal ? offset * trailingSign : 0,
                y: axis == .vertical ? offset : 0
            )
            .shadow(
                color: isFront ? themeManager.appTheme.carouselCardShadow.color : .clear,
                radius: isFront ? themeManager.appTheme.carouselCardShadow.radius : 0,
                y: isFront ? themeManager.appTheme.carouselCardShadow.y : 0
            )
    }
}
