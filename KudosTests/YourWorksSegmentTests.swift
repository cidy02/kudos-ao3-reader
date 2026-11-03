import Testing
@testable import Kudos

@Suite("YourWorksSegment tests")
struct YourWorksSegmentTests {
    @Test("Segment title formatting with counts")
    func segmentTitlesWithCounts() {
        #expect(YourWorksSegment.works.title(count: "6") == "Works · 6")
        #expect(YourWorksSegment.series.title(count: "1") == "Series · 1")
        #expect(YourWorksSegment.drafts.title(count: "2") == "Drafts · 2")
    }

    @Test("Segment title formatting without counts")
    func segmentTitlesWithoutCounts() {
        #expect(YourWorksSegment.works.title(count: nil) == "Works")
        #expect(YourWorksSegment.series.title(count: nil) == "Series")
        #expect(YourWorksSegment.drafts.title(count: nil) == "Drafts")
    }

    @Test("Segment title formatting with empty or whitespace count")
    func segmentTitlesWithEmptyCount() {
        #expect(YourWorksSegment.formatTitle(label: "Works", count: "") == "Works")
        #expect(YourWorksSegment.formatTitle(label: "Works", count: "   ") == "Works")
    }

    @Test("Segment title formatting with formatted counts")
    func segmentTitlesWithFormattedCounts() {
        #expect(YourWorksSegment.formatTitle(label: "Works", count: "12") == "Works · 12")
        #expect(YourWorksSegment.formatTitle(label: "Works", count: "220+") == "Works · 220+")
    }
}
