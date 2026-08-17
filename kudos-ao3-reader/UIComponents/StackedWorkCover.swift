import SwiftUI

/// A tile that reads as a shelf of works, not one abstract tile: up to 3 centered,
/// depth-scaled faces (front → back), each hued from its own work's title — the same
/// `CoverArt`/`carouselCardTint` treatment individual work cards already use, keyed
/// per-face instead of to the collection/queue's own name. No real cover art exists
/// anywhere in this app (AO3 has no mechanism for it), so this is a pure function of
/// the titles already in memory — no I/O, no cache, no loading state.
///
/// Converged design from `discussions/stacked-card-carousels.md` (Codex/Gemini/Grok +
/// app owner). Centered scaling (not a diagonal offset) so it's RTL-agnostic. Callers
/// own the single-work/empty fallback — this view assumes 2+ titles.
struct StackedWorkCover: View {
    /// Ordered work titles (collection/queue order); only the first 3 are drawn.
    let workTitles: [String]
    var cardSize = ScaledCarouselCardSize()

    @Environment(ThemeManager.self) private var themeManager

    /// Front-to-back. A 2-work stack drops the back layer entirely rather than
    /// reusing/duplicating a face.
    private var faces: [String] {
        Array(workTitles.prefix(3))
    }

    /// Relative to `cardSize` — front is already slightly inset from the full
    /// footprint so there's headroom for back faces to peek above its top edge.
    private static let faceScales: [CGFloat] = [0.97, 0.90, 0.83]
    /// Front's own downward nudge, leaving room above it for the stack to peek into.
    private static let frontOffsetY: CGFloat = 8

    /// Front-to-back Y offsets. The usable headroom is constrained by both the
    /// stack footprint's top edge and the full front-to-back vertical extent, then
    /// divided among the back faces at every face count.
    private var faceYOffsets: [CGFloat] {
        guard faces.count > 1 else { return [Self.frontOffsetY] }

        let frontHalfHeight = cardSize.height * Self.faceScales[0] / 2
        let totalExtentHeadroom = cardSize.height - 2 * frontHalfHeight
        let topBoundaryHeadroom = cardSize.height / 2 + Self.frontOffsetY - frontHalfHeight
        let availableHeadroom = max(0, min(totalExtentHeadroom, topBoundaryHeadroom))
        let peekPoints = availableHeadroom / CGFloat(faces.count - 1)

        var offsets: [CGFloat] = [Self.frontOffsetY]
        for depth in 1..<faces.count {
            let previousHalfHeight = cardSize.height * Self.faceScales[depth - 1] / 2
            let halfHeight = cardSize.height * Self.faceScales[depth] / 2
            offsets.append(offsets[depth - 1] - peekPoints - (previousHalfHeight - halfHeight))
        }
        return offsets
    }

    var body: some View {
        let offsets = faceYOffsets
        ZStack {
            ForEach(Array(faces.enumerated().reversed()), id: \.offset) { depth, title in
                face(title: title, depth: depth, offsetY: offsets[depth])
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        // The stack is decorative — CollectionCard/ReadingQueueCard's own title +
        // "N works" text right below already carries the accessible label; without
        // this, VoiceOver would stop on 2-3 unlabeled peeking rectangles first.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func face(title: String, depth: Int, offsetY: CGFloat) -> some View {
        let hue = CoverArt.hue(for: title)
        let isFront = depth == 0
        let scale = Self.faceScales[depth]
        let shape = RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)

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
            .offset(y: offsetY)
            .shadow(
                color: isFront ? themeManager.appTheme.carouselCardShadow.color : .clear,
                radius: isFront ? themeManager.appTheme.carouselCardShadow.radius : 0,
                y: isFront ? themeManager.appTheme.carouselCardShadow.y : 0
            )
    }
}
