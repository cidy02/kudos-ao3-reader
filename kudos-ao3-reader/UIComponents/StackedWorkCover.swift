import SwiftUI

/// What a stack of covers stands for (owner, 2026-10-28; canvas `CoverStack`). A
/// collection is a pile: its own card in front, the works inside tilted behind it.
/// A queue is a line waiting its turn: the next covers stacked straight up behind
/// the front one, each a peek higher and a step narrower. The corner tab says which
/// as well: plain for a collection, a numbered list (an order) for a queue. Neither
/// is a 2×2 grid any more, which read as AO3's four-tag square.
enum CoverStackKind {
    case collection
    case queue
}

/// Where each card of a cover stack is drawn inside its frame. Pure geometry, so the
/// stack's one promise (nothing is drawn outside the frame, so a stack never runs
/// into the card beside it) is tested (`CoverStackLayoutTests`) rather than padded.
struct CoverStackLayout: Equatable {
    struct Back: Equatable {
        /// The card's frame before it turns.
        var frame: CGRect
        /// Degrees clockwise about the frame's bottom-leading corner; 0 in a queue.
        var rotation: Double
        /// How much darker than its own colour the card is drawn, 0…1.
        var dimming: Double

        /// The area the card covers once turned.
        var drawnBounds: CGRect {
            let angle = rotation * .pi / 180
            let cosine = CGFloat(cos(angle))
            let sine = CGFloat(sin(angle))
            // Corners relative to the pivot (bottom-leading), turned clockwise in
            // y-down coordinates.
            let corners = [
                CGPoint(x: 0, y: 0), CGPoint(x: frame.width, y: 0),
                CGPoint(x: 0, y: -frame.height), CGPoint(x: frame.width, y: -frame.height),
            ].map {
                CGPoint(
                    x: frame.minX + $0.x * cosine - $0.y * sine,
                    y: frame.maxY + $0.x * sine + $0.y * cosine
                )
            }
            let xs = corners.map(\.x)
            let ys = corners.map(\.y)
            let minX = xs.min() ?? 0
            let minY = ys.min() ?? 0
            return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
        }
    }

    /// The spec's cover proportion: a cover is 72% as wide as it is tall.
    static let coverAspect: CGFloat = 0.72
    /// The spec draws at most two covers behind the front one.
    static let maxBacks = 2

    var front: CGRect
    /// Nearest first.
    var backs: [Back]
    var cornerRadius: CGFloat
    /// The corner tab, in the front card's own coordinates. Nil on a stack too small
    /// for one to read (the spec's 64pt cover).
    var ribbon: CGRect?

    /// - Parameter frontAspect: the front card's width ÷ height, capped by the frame.
    ///   A cover by default; Home's queue card passes a wider one for its landscape face.
    init(
        kind: CoverStackKind,
        size: CGSize,
        backCount: Int,
        frontAspect: CGFloat = CoverStackLayout.coverAspect
    ) {
        let width = max(0, size.width)
        let height = max(0, size.height)
        let count = min(max(0, backCount), Self.maxBacks)
        let hasTab = min(width, height * Self.coverAspect) >= 64
        let front: CGRect
        let piled: [Back]

        switch kind {
        case .queue:
            // Spec: each back card peeks 7% of the height above the one in front
            // (at least 4pt); capped at 10% so a tiny stack keeps most of its front.
            let peek = count > 0 ? min(max(4, height * 0.07), height * 0.1) : 0
            let frontHeight = height - peek * CGFloat(count)
            let coverWidth = min(width, frontHeight * frontAspect)
            let frontLeft = (width - coverWidth) / 2
            front = CGRect(x: frontLeft, y: peek * CGFloat(count), width: coverWidth, height: frontHeight)
            piled = (0..<count).map { index in
                let step = CGFloat(index + 1)
                let backWidth = coverWidth * (1 - 0.1 * step)
                return Back(
                    frame: CGRect(x: frontLeft + (coverWidth - backWidth) / 2,
                                  y: peek * (CGFloat(count) - step),
                                  width: backWidth, height: frontHeight),
                    rotation: 0,
                    dimming: 0.12 * Double(step)
                )
            }
        case .collection:
            // Spec: 5° more per card behind (3° on a small stack), each 4% smaller and
            // 12% of the front's width further right, turned about its bottom-leading
            // corner. The spec let the turned top corner rise above the frame and only
            // narrowed the front for the right edge; here the height gives way at the
            // top and the front narrows until the right edge fits.
            let turn: Double = hasTab ? 5 : 3
            func pile(_ coverWidth: CGFloat) -> [Back] {
                let shift = count > 0 ? max(4, coverWidth * 0.12) : 0
                return (0..<count).map { index in
                    let step = CGFloat(index + 1)
                    let scale = 1 - 0.04 * step
                    let degrees = turn * Double(step)
                    let sine = CGFloat(sin(degrees * .pi / 180))
                    let cosine = CGFloat(cos(degrees * .pi / 180))
                    let backWidth = coverWidth * scale
                    // Tall enough to match the front, short enough that the turned top
                    // corner stays at or below the frame's top.
                    let backHeight = max(0, min(height * scale, (height - backWidth * sine) / cosine))
                    return Back(
                        // The far bottom corner lands on the frame's bottom once turned.
                        frame: CGRect(x: coverWidth - backWidth + step * shift,
                                      y: height - backHeight - backWidth * sine,
                                      width: backWidth, height: backHeight),
                        rotation: degrees,
                        dimming: 0.1 * Double(step)
                    )
                }
            }
            func reach(_ coverWidth: CGFloat) -> CGFloat {
                pile(coverWidth).map(\.drawnBounds.maxX).reduce(coverWidth) { Swift.max($0, $1) }
            }
            let widest = min(width, height * frontAspect)
            var coverWidth = widest
            if reach(widest) > width {
                // `reach` grows with the front's width, so halve the gap to the
                // widest front that fits. Below half the frame's natural cover the
                // pile gives up its far cards instead (the filter below).
                var fits = widest / 2
                var tooWide = widest
                for _ in 0..<24 {
                    let middle = (fits + tooWide) / 2
                    if reach(middle) <= width { fits = middle } else { tooWide = middle }
                }
                coverWidth = fits
            }
            front = CGRect(x: 0, y: 0, width: coverWidth, height: height)
            piled = pile(coverWidth)
        }

        // Only a degenerate frame (far taller than wide) gets here with a card that
        // still does not fit; it is left out rather than drawn over the neighbour.
        let bounds = CGRect(x: 0, y: 0, width: width, height: height).insetBy(dx: -0.01, dy: -0.01)
        self.front = front
        backs = Array(piled.prefix { bounds.contains($0.drawnBounds) })
        // Spec: 9% of a cover's width, 4pt at least. The shorter side stands in for
        // the width on a landscape face.
        cornerRadius = max(4, 0.09 * min(front.width, front.height))
        if hasTab {
            // Spec: 20% of the cover's width, 1.45 times as tall, 9% of the width in
            // from the trailing edge.
            let cover = min(front.width, front.height * Self.coverAspect)
            let tabWidth = cover * 0.2
            ribbon = CGRect(x: front.width - cover * 0.09 - tabWidth, y: 0,
                            width: tabWidth, height: tabWidth * 1.45)
        } else {
            ribbon = nil
        }
    }
}

/// A collection's or a queue's cover stack (`CoverStackKind`), drawn by
/// `CoverStackLayout`. The covers behind are the works' own: each in its fandom's
/// colour family (`CoverArt.workArt`, the same gradient as the shelf cover), never the app's
/// red. The front is the collection's or queue's own colour and initial
/// (`init(kind:name:hue:pickedHex:backs:size:)`), or a face the caller draws.
///
/// The covers name nothing, but their colour is a work's fandom, so a caller leaves
/// out every work the privacy setting is keeping back before passing `backs`.
struct StackedWorkCover<Face: View>: View {
    let kind: CoverStackKind
    let size: CGSize
    /// The works behind the front card, nearest first. Only the first two are drawn.
    let backs: [SavedWork]
    let frontAspect: CGFloat
    /// The front card's content; the stack clips it, outlines it and puts the corner
    /// tab over it. Gets the layout so text can step around the tab.
    let face: (CoverStackLayout) -> Face

    @Environment(ThemeManager.self) private var themeManager

    init(
        kind: CoverStackKind,
        size: CGSize,
        backs: [SavedWork],
        frontAspect: CGFloat = CoverStackLayout.coverAspect,
        @ViewBuilder face: @escaping (CoverStackLayout) -> Face
    ) {
        self.kind = kind
        self.size = size
        self.backs = backs
        self.frontAspect = frontAspect
        self.face = face
    }

    var body: some View {
        let layout = CoverStackLayout(kind: kind, size: size, backCount: backs.count, frontAspect: frontAspect)
        let theme = themeManager.appTheme
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
        let shadow = theme.carouselCardShadow
        ZStack(alignment: .topLeading) {
            // Farthest first, so each nearer card lies over the one behind it.
            ForEach(layout.backs.indices.reversed(), id: \.self) { index in
                let back = layout.backs[index]
                backCover(backs[index], dimming: back.dimming, shape: shape)
                    .frame(width: back.frame.width, height: back.frame.height)
                    .rotationEffect(.degrees(back.rotation), anchor: .bottomLeading)
                    .offset(x: back.frame.minX, y: back.frame.minY)
            }
            face(layout)
                .frame(width: layout.front.width, height: layout.front.height)
                .clipShape(shape)
                .overlay(shape.strokeBorder(theme.glassStroke(0.12), lineWidth: 0.5))
                .overlay(alignment: .topLeading) { cornerTab(layout.ribbon) }
                .shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
                .offset(x: layout.front.minX, y: layout.front.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// A work's cover seen from behind the front card: the same generated art
    /// the shelf cover uses, with the hairline the old mosaic's cells had.
    private func backCover(_ work: SavedWork, dimming: Double, shape: RoundedRectangle) -> some View {
        let theme = themeManager.appTheme
        let art = CoverArt.workArt(fandoms: work.workFandoms, title: work.title)
        return shape
            .fill(CoverArt.workGradient(for: art))
            .overlay(shape.strokeBorder(theme.glassStroke(0.10), lineWidth: 0.5))
            .brightness(-dimming)
            .accessibilityHidden(true)
    }

    /// The spec's ribbon: a black-24% tab with a notch cut up into its foot. A queue's
    /// carries a numbered list, centred; a collection's is plain.
    @ViewBuilder
    private func cornerTab(_ rect: CGRect?) -> some View {
        if let rect {
            CoverStackRibbonShape()
                .fill(Color.black.opacity(0.24))
                .frame(width: rect.width, height: rect.height)
                .overlay(alignment: .top) {
                    if kind == .queue {
                        Image(systemName: "list.number")
                            .resizable()
                            .scaledToFit()
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.white.opacity(0.92))
                            .frame(width: rect.width * 0.6, height: rect.width * 0.6)
                            .padding(.top, rect.width * 0.2)
                    }
                }
                .offset(x: rect.minX, y: rect.minY)
                .accessibilityHidden(true)
        }
    }
}

extension StackedWorkCover where Face == CoverStackNameFace {
    /// The stack a collection or queue draws for itself: its own colour, with the
    /// first letter of its name, in front.
    init(kind: CoverStackKind, name: String, hue: Double, pickedHex: String?, backs: [SavedWork], size: CGSize) {
        self.init(kind: kind, size: size, backs: backs) { layout in
            CoverStackNameFace(name: name, hue: hue, pickedHex: pickedHex, coverWidth: layout.front.width)
        }
    }
}

/// A collection's or queue's own card: its colour (`carouselCollectionGradient`, the
/// tile gradient collections already had) with its initial set large and faint in
/// New York across the bottom-leading corner, as the spec's generated covers do.
struct CoverStackNameFace: View {
    let name: String
    let hue: Double
    let pickedHex: String?
    let coverWidth: CGFloat

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let gradient = themeManager.appTheme.carouselCollectionGradient(hue: hue, pickedHex: pickedHex)
        let initial = name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() }
        LinearGradient(colors: [gradient.start, gradient.end], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .bottomLeading) {
                Text(initial ?? "")
                    .font(.system(size: coverWidth * 1.05, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.15))
                    .fixedSize()
                    // Spec: the letter's baseline sits 11% of the width below the card.
                    .alignmentGuide(.bottom) { $0[.lastTextBaseline] }
                    .offset(x: -coverWidth * 0.06, y: coverWidth * 0.11)
            }
            .accessibilityHidden(true)
    }
}

/// The corner tab's outline: a rectangle with a notch cut up 20% into its foot.
struct CoverStackRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.8))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
