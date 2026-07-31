import SwiftUI
import Testing
@testable import Kudos

/// Pins the reader skeleton's fill arithmetic.
///
/// The skeleton exists to make an opening work look like a page rather than a
/// spinner, and the owner's report was that its lines stopped well short of the
/// bottom. That is one pure function — how many paragraphs of how many lines fit a
/// given height — so it is worth testing directly rather than by eye on a device.
@MainActor
struct ReaderPageSkeletonTests {
    /// Total height the emitted blocks actually occupy, mirroring the `VStack`:
    /// heading + its 4pt pad + `paragraphSpacing` before each paragraph block.
    private func renderedHeight(_ paragraphs: [[CGFloat?]]) -> CGFloat {
        let heading = ReaderPageSkeleton.headingHeight + 4
        return paragraphs.reduce(heading) { total, widths in
            total + ReaderPageSkeleton.paragraphSpacing
                + ReaderPageSkeleton.paragraphHeight(lineCount: widths.count)
        }
    }

    @Test func theFillNeverOverflowsTheHeightItIsGiven() {
        // The bug this covers: the gap under the heading was not subtracted, so the
        // fill overshot by exactly one `paragraphSpacing` and clipped its last line.
        for height in stride(from: 120.0, through: 1400.0, by: 37.0) {
            let paragraphs = ReaderPageSkeleton.paragraphs(filling: height)
            #expect(
                renderedHeight(paragraphs) <= height,
                "overflowed at height \(height): \(renderedHeight(paragraphs))"
            )
        }
    }

    @Test func aTallPageIsFilledRatherThanLeftShort() {
        // The reported symptom. A phone-sized page must not come back with the old
        // fixed four paragraphs and a gap beneath them.
        let paragraphs = ReaderPageSkeleton.paragraphs(filling: 700)
        let used = renderedHeight(paragraphs)
        #expect(paragraphs.count >= 5)
        // Within one line + its spacing of the bottom is as close as whole
        // paragraphs can get.
        let slack = ReaderPageSkeleton.paragraphHeight(lineCount: 1)
            + ReaderPageSkeleton.paragraphSpacing
        #expect(used > 700 - slack - ReaderPageSkeleton.paragraphSpacing)
    }

    @Test func everyParagraphEndsShortLikeProse() {
        for widths in ReaderPageSkeleton.paragraphs(filling: 700) {
            #expect(widths.last??.isFinite == true, "last line should be a fixed short width")
            #expect(widths.dropLast().allSatisfy { $0 == nil }, "body lines should run full width")
        }
    }

    @Test func aVanishinglyShortPageStillDrawsSomething() {
        // Degenerate heights must not produce an empty wireframe — a blank screen
        // reads as a broken open, which is the state this whole view exists to avoid.
        for height in [0.0, 1.0, 20.0, 60.0] {
            #expect(!ReaderPageSkeleton.paragraphs(filling: height).isEmpty)
        }
    }
}
