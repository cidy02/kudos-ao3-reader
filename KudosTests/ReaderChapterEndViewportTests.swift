#if os(iOS)
import Testing
@testable import Kudos

/// The chapter-end trigger, from the viewport's resources to a spine index. These drive the
/// production `ReadiumReaderCompletion` helper, so a broken detector fails here.
struct ReaderChapterEndViewportTests {
    private let order = ["a.xhtml", "b.xhtml", "c.xhtml"]

    @Test func aTrailingEdgeJustUnderOneStillCountsAsTheChapterEnd() {
        // 0.999667 is what a fractional scroll offset against integer DOM sizes can leave.
        #expect(ReadiumReaderCompletion.endingSpineIndex(
            visible: [("a.xhtml", 0.999667)], readingOrderHrefs: order) == 0)
        #expect(ReadiumReaderCompletion.endingSpineIndex(
            visible: [("b.xhtml", 1.0)], readingOrderHrefs: order) == 1)
    }

    @Test func contentStillBelowTheViewportIsNotTheChapterEnd() {
        #expect(ReadiumReaderCompletion.endingSpineIndex(
            visible: [("a.xhtml", 0.99)], readingOrderHrefs: order) == nil)
        #expect(ReadiumReaderCompletion.endingSpineIndex(visible: [], readingOrderHrefs: order) == nil)
    }

    @Test func theLastVisibleResourceOfASpreadDecides() {
        #expect(ReadiumReaderCompletion.endingSpineIndex(
            visible: [("a.xhtml", 1.0), ("b.xhtml", 0.4)], readingOrderHrefs: order) == nil)
        #expect(ReadiumReaderCompletion.endingSpineIndex(
            visible: [("a.xhtml", 0.3), ("b.xhtml", 1.0)], readingOrderHrefs: order) == 1)
    }

    @Test func anUnknownResourceIsNeverAChapterEnd() {
        #expect(ReadiumReaderCompletion.endingSpineIndex(
            visible: [("z.xhtml", 1.0)], readingOrderHrefs: order) == nil)
    }
}
#endif
