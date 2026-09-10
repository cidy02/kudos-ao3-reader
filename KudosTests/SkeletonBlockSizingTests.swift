#if canImport(UIKit)
import SwiftUI
import Testing
@testable import Kudos

/// Pins `SkeletonBlock`'s two-sided width contract. Both ways of getting it
/// wrong have now shipped and been seen on device, and each fix caused the
/// other bug, so the two directions are pinned together:
///
///   * `.frame(maxWidth:)` alone is only an upper bound, and a bare
///     `RoundedRectangle` has no intrinsic width to fall back on — so a layout
///     that asks for this view's *ideal* size (`FlowLayout` does, when
///     wrapping) got a sliver instead of the width the caller asked for.
///   * `.frame(width:)` is a minimum as well as a maximum — so a
///     `CategoryCardSkeleton` placed in a narrow column on
///     Browse rendered ~50pt wider than its column and visibly overlapped the
///     card beside it.
///
/// `ImageRenderer` is the cheapest way to ask for the size SwiftUI actually
/// laid the view out at, rather than the size we believe it should pick.
@MainActor
struct SkeletonBlockSizingTests {
    private func renderedWidth(width: CGFloat?, proposal: ProposedViewSize) -> CGFloat {
        let renderer = ImageRenderer(content: SkeletonBlock(height: 12, width: width))
        renderer.proposedSize = proposal
        renderer.scale = 1
        return renderer.uiImage?.size.width ?? .nan
    }

    @Test func anAskedForWidthSurvivesAnIdealSizeQuery() {
        // FlowLayout measures with `.unspecified` before it decides where a
        // chip goes; a sliver here is the "recently read" placeholders bug.
        #expect(abs(renderedWidth(width: 116, proposal: .unspecified) - 116) < 0.5)
    }

    @Test func aBlockShrinksIntoSpaceNarrowerThanItsWidth() {
        // The Browse masonry column: ~175pt wide on a 393pt phone, minus the
        // card's own 16pt padding on each side, leaves ~143pt of content width
        // for bars asked to be 160. They have to give.
        let width = renderedWidth(width: 160, proposal: ProposedViewSize(width: 96, height: nil))
        #expect(width <= 96)
    }

    @Test func aWidthlessBlockStillFillsWhatItIsOffered() {
        let width = renderedWidth(width: nil, proposal: ProposedViewSize(width: 210, height: nil))
        #expect(abs(width - 210) < 0.5)
    }
}
#endif
