import Foundation
import Testing
@testable import Kudos

/// Covers `ReaderSearchGrouping`'s chapter grouping/ordering: current chapter
/// pinned first, everything else descending, and results with no matching
/// section still surface rather than being silently dropped.
struct ReaderSearchGroupingTests {
    private func sections() -> [ReaderSection] {
        [
            ReaderSection(href: "ch1.xhtml", title: "Chapter 1", kind: .chapter, spineIndex: 0, storyChapterIndex: 1),
            ReaderSection(href: "ch2.xhtml", title: "Chapter 2", kind: .chapter, spineIndex: 1, storyChapterIndex: 2),
            ReaderSection(href: "ch3.xhtml", title: "Chapter 3", kind: .chapter, spineIndex: 2, storyChapterIndex: 3)
        ]
    }

    @Test func currentChapterIsPinnedFirstRegardlessOfIndex() {
        // Current chapter (index 2, the *last* one) has the highest spine
        // index, yet must still come first — not simply "lowest index first".
        // Its title also carries the AO3 story-chapter number (3, from this
        // section's storyChapterIndex), not the raw spine position.
        let groups = ReaderSearchGrouping.grouped(
            ["ch1.xhtml", "ch2.xhtml", "ch3.xhtml"],
            hrefKey: { $0 },
            sections: sections(),
            currentSpineIndex: 2
        )
        #expect(groups.map(\.title) == ["This Chapter (Ch. 3)", "Chapter 1", "Chapter 2"])
    }

    @Test func currentChapterSuffixNamesAO3FrontAndBackMatterHonestly() {
        // AO3's Preface/Summary/Afterword are not story chapters — reusing the
        // "Chapter N" phrasing for them would be the exact bug already fixed
        // for the position card (`ReaderPositionSummary.Place`).
        let mixedSections: [ReaderSection] = [
            ReaderSection(href: "pre.xhtml", title: "Preface", kind: .preface, spineIndex: 0, storyChapterIndex: nil),
            ReaderSection(href: "sum.xhtml", title: "Summary", kind: .summary, spineIndex: 1, storyChapterIndex: nil),
            ReaderSection(
                href: "end.xhtml", title: "Afterword", kind: .afterword, spineIndex: 2, storyChapterIndex: nil
            ),
            ReaderSection(href: "misc.xhtml", title: "Section 4", kind: .other, spineIndex: 3, storyChapterIndex: nil)
        ]
        let cases = [
            (index: 0, href: "pre.xhtml", suffix: " (Preface)"),
            (index: 1, href: "sum.xhtml", suffix: " (Summary)"),
            (index: 2, href: "end.xhtml", suffix: " (Afterword)"),
            (index: 3, href: "misc.xhtml", suffix: "")
        ]
        for testCase in cases {
            let groups = ReaderSearchGrouping.grouped(
                [testCase.href], hrefKey: { $0 }, sections: mixedSections, currentSpineIndex: testCase.index
            )
            #expect(groups.first?.title == "This Chapter" + testCase.suffix)
        }
    }

    @Test func remainingChaptersAreAscendingWhenNoCurrentChapterMatches() {
        let groups = ReaderSearchGrouping.grouped(
            ["ch1.xhtml", "ch2.xhtml", "ch3.xhtml"],
            hrefKey: { $0 },
            sections: sections(),
            currentSpineIndex: nil
        )
        #expect(groups.map(\.title) == ["Chapter 1", "Chapter 2", "Chapter 3"])
    }

    @Test func multipleHitsInOneChapterStayInOneGroup() {
        let groups = ReaderSearchGrouping.grouped(
            ["ch2.xhtml", "ch2.xhtml", "ch1.xhtml"],
            hrefKey: { $0 },
            sections: sections(),
            currentSpineIndex: nil
        )
        #expect(groups.count == 2)
        // Ascending, so ch1 (index 0) is first — the assertion should hold
        // regardless of ordering, not depend on it, unlike the two tests above
        // whose whole point *is* the ordering.
        #expect(groups.first { $0.title == "Chapter 2" }?.results.count == 2)
    }

    @Test func unmatchedHrefStillSurfacesRatherThanBeingDropped() {
        let groups = ReaderSearchGrouping.grouped(
            ["unknown.xhtml"],
            hrefKey: { $0 },
            sections: sections(),
            currentSpineIndex: nil
        )
        #expect(groups.count == 1)
        #expect(groups.first?.results == ["unknown.xhtml"])
    }

    @Test func emptyResultsProduceNoGroups() {
        #expect(
            ReaderSearchGrouping.grouped(
                [String](), hrefKey: { $0 }, sections: sections(), currentSpineIndex: 0
            ).isEmpty
        )
    }
}
