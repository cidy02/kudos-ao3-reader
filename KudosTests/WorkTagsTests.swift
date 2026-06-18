import Testing
@testable import Kudos

/// Tests for `SavedWork.normalizedWorkTags`, which cleans EPUB subjects into a
/// work's tag list (drops the rating, trims, de-duplicates, preserves order).
@MainActor
struct WorkTagsTests {
    @Test func dropsRatingTrimsAndDeduplicates() {
        let subjects = ["Teen And Up Audiences", "Fluff", "Fluff", "  Angst  ", ""]
        let tags = SavedWork.normalizedWorkTags(subjects, excludingRating: "Teen And Up Audiences")
        #expect(tags == ["Fluff", "Angst"])
    }

    @Test func preservesFirstSeenOrder() {
        let tags = SavedWork.normalizedWorkTags(["B", "A", "B", "C"], excludingRating: "")
        #expect(tags == ["B", "A", "C"])
    }

    @Test func emptyInputYieldsEmpty() {
        #expect(SavedWork.normalizedWorkTags([], excludingRating: "Mature").isEmpty)
    }
}
