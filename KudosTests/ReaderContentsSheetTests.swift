#if os(iOS)
import Testing
@testable import Kudos

struct ReaderContentsSheetTests {
    @Test func annotationCountsAppearOnlyWhenNonzero() {
        #expect(ReaderContentsLabels.segmentTitle(.chapters, count: 8) == "Contents")
        #expect(ReaderContentsLabels.segmentTitle(.bookmarks, count: 3) == "Bookmarks · 3")
        #expect(ReaderContentsLabels.segmentTitle(.notes, count: 2) == "Highlights · 2")
        #expect(ReaderContentsLabels.segmentTitle(.bookmarks, count: 0) == "Bookmarks")
        #expect(ReaderContentsLabels.segmentTitle(.notes, count: 0) == "Highlights")
    }

    @Test func progressIncludesExistingWorkEstimateWhenAvailable() {
        #expect(
            ReaderContentsLabels.progress(percent: 22, remainingPositions: 273)
                == "22% of the work · about 4 hr 10 min left"
        )
    }

    @Test func progressKeepsThePercentWhenNoEstimateIsAvailable() {
        #expect(ReaderContentsLabels.progress(percent: 22, remainingPositions: nil) == "22% of the work")
    }
}
#endif
