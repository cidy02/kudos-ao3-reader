import CoreGraphics
import Testing
@testable import Kudos

/// T-461: a cover stack never draws outside its own frame (the old tilted backs ran
/// into the next card), a queue stacks straight up and a collection tilts.
@MainActor
@Suite
struct CoverStackLayoutTests {
    private static func isInside(_ inner: CGRect, _ outer: CGRect) -> Bool {
        let slack: CGFloat = 0.02
        return inner.minX >= outer.minX - slack && inner.minY >= outer.minY - slack
            && inner.maxX <= outer.maxX + slack && inner.maxY <= outer.maxY + slack
    }

    /// Frames the app draws: organizer rows, Home's queue card and the collection
    /// card at the default size and clamped at AX5 on a phone, a Duo pane's narrower
    /// card, the spec's 76 and 96pt stacks, and a few odd shapes.
    private static let sizes: [CGSize] = [
        CGSize(width: 48, height: 48), CGSize(width: 52, height: 52), CGSize(width: 76, height: 76),
        CGSize(width: 96, height: 96), CGSize(width: 150, height: 140), CGSize(width: 164, height: 153),
        CGSize(width: 164, height: 104), CGSize(width: 343, height: 320), CGSize(width: 343, height: 217.5),
        CGSize(width: 120, height: 112), CGSize(width: 30, height: 30), CGSize(width: 300, height: 40),
    ]

    /// Far taller than wide: the tilted pile cannot keep every card here, and must
    /// drop them rather than overflow.
    private static let degenerateSizes: [CGSize] = [
        CGSize(width: 10, height: 100), CGSize(width: 20, height: 200), CGSize(width: 1, height: 1),
    ]

    @Test(arguments: [CoverStackKind.collection, .queue])
    func everyCardStaysInsideItsFrameForOneToFiveCovers(kind: CoverStackKind) {
        for size in Self.sizes + Self.degenerateSizes {
            let frame = CGRect(origin: .zero, size: size)
            for covers in 1...5 {
                let layout = CoverStackLayout(kind: kind, size: size, backCount: covers - 1)
                #expect(Self.isInside(layout.front, frame), "\(kind) \(size) \(covers): front")
                for back in layout.backs {
                    #expect(Self.isInside(back.drawnBounds, frame), "\(kind) \(size) \(covers): \(back)")
                }
                if let ribbon = layout.ribbon {
                    let face = CGRect(origin: .zero, size: layout.front.size)
                    #expect(Self.isInside(ribbon, face), "\(kind) \(size): tab")
                }
            }
        }
    }

    @Test(arguments: [CoverStackKind.collection, .queue])
    func ordinaryFramesKeepUpToTwoCoversBehind(kind: CoverStackKind) {
        for size in Self.sizes {
            for covers in 1...5 {
                let layout = CoverStackLayout(kind: kind, size: size, backCount: covers - 1)
                #expect(layout.backs.count == min(covers - 1, CoverStackLayout.maxBacks), "\(kind) \(size)")
            }
        }
    }

    @Test func aQueueStacksStraightUpEachAPeekHigherAndAStepNarrower() {
        let layout = CoverStackLayout(kind: .queue, size: CGSize(width: 96, height: 96), backCount: 2)
        var nearer = layout.front
        for back in layout.backs {
            #expect(back.rotation == 0)
            #expect(back.frame.minY < nearer.minY)
            #expect(back.frame.width < nearer.width)
            #expect(abs(back.frame.midX - layout.front.midX) < 0.001)
            nearer = back.frame
        }
        #expect(layout.backs.last?.frame.minY == 0)
        #expect(abs(layout.front.maxY - 96) < 0.001)
    }

    @Test func aCollectionTiltsEachCardFurtherAndKeepsItsFrontLeading() {
        let layout = CoverStackLayout(kind: .collection, size: CGSize(width: 150, height: 140), backCount: 2)
        #expect(layout.front.minX == 0)
        #expect(layout.front.height == 140)
        #expect(layout.backs.map(\.rotation) == [5, 10])
        // Board 01's 150×140 pile keeps the spec's 72% cover rather than narrowing it.
        #expect(abs(layout.front.width - 100.8) < 0.001)
        // Each turned card's far bottom corner rests on the frame's bottom.
        for back in layout.backs {
            #expect(abs(back.drawnBounds.maxY - 140) < 0.01)
        }
    }

    @Test func theCornerTabNeedsASixtyFourPointCover() {
        #expect(CoverStackLayout(kind: .queue, size: CGSize(width: 48, height: 48), backCount: 2).ribbon == nil)
        #expect(CoverStackLayout(kind: .queue, size: CGSize(width: 96, height: 96), backCount: 2).ribbon != nil)
        #expect(CoverStackLayout(kind: .collection, size: CGSize(width: 150, height: 140), backCount: 0).ribbon != nil)
    }

    @Test func queueFrontKeepsTheDefaultCoverAspect() {
        let layout = CoverStackLayout(kind: .queue, size: CGSize(width: 72, height: 72), backCount: 2)
        #expect(abs(layout.front.width / layout.front.height - CoverStackLayout.coverAspect) < 0.001)
        #expect(abs(layout.front.midX - 36) < 0.001)
    }

    @Test func columnsAllowForAWiderGap() {
        // Two 164pt cards need 344 + 2×16 gutters at 12pt apart, 352 at 20pt.
        #expect(AdaptiveContentRegions.columns(in: 376, cardWidth: 164) == 2)
        #expect(AdaptiveContentRegions.columns(in: 376, cardWidth: 164, spacing: 20) == 1)
        #expect(AdaptiveContentRegions.columns(in: 380, cardWidth: 164, spacing: 20) == 2)
    }
}
