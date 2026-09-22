import Foundation
import Testing
@testable import Kudos

/// Spec 1p's "X New" badge. The store is a per-device convenience, so the tests
/// that matter are about *when a badge appears*, which is the part that would
/// annoy a reader if it were wrong in either direction.
@MainActor
@Suite(.serialized)
struct SubscriptionWatermarkTests {
    private func summary(id: Int, chapters: String) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: "Work \(id)",
            authors: ["someone"],
            fandoms: [],
            rating: "",
            warnings: [],
            categories: [],
            dateUpdated: "",
            tags: [],
            summary: "",
            language: "",
            chapters: chapters
        )
    }

    private func defaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "SubscriptionWatermarkTests-\(UUID().uuidString)")
        return suite ?? .standard
    }

    // MARK: When a badge appears

    @Test func aWorkNeverSeenBeforeDoesNotBadge() {
        let work = summary(id: 1, chapters: "12/20")
        // Otherwise a reader opening this screen for the first time meets a badge on
        // every row — each technically true, collectively meaningless.
        #expect(SubscriptionWatermarks.newChapterCount(for: work, watermarks: [:]) == 0)
    }

    @Test func firstSightBaselinesRatherThanBadging() {
        let work = summary(id: 1, chapters: "12/20")
        let baselined = SubscriptionWatermarks.baseline([work], into: [:])
        let marks = try? #require(baselined)

        #expect(marks?[1]?.postedChapterCount == 12)
        #expect(SubscriptionWatermarks.newChapterCount(for: work, watermarks: marks ?? [:]) == 0)
    }

    @Test func aBadgeSurvivesTheLoadThatDisplaysIt() {
        let seen = [1: SubscriptionWatermark(postedChapterCount: 12, seenAt: Date())]
        let grown = summary(id: 1, chapters: "14/20")

        // `baseline` must only ever *add*. If it refreshed existing entries, the
        // badge would be cleared by the very page load that drew it.
        #expect(SubscriptionWatermarks.baseline([grown], into: seen) == nil)
        #expect(SubscriptionWatermarks.newChapterCount(for: grown, watermarks: seen) == 2)
    }

    @Test func chapterCountsThatFallDoNotProduceANegativeBadge() {
        let seen = [1: SubscriptionWatermark(postedChapterCount: 20, seenAt: Date())]
        // AO3 counts fall when a chapter is deleted. "−2 new chapters" is not a thing.
        #expect(SubscriptionWatermarks.newChapterCount(
            for: summary(id: 1, chapters: "18/20"), watermarks: seen
        ) == 0)
    }

    /// The subscriptions index has no chapters string. Baselining that as 0
    /// makes the work page's real total look like every chapter is new.
    @Test func anEmptyChaptersStringIsNotAFirstSight() {
        let sparse = AO3WorkSummary.subscription(id: 4, title: "Work", authors: ["someone"])
        let known = summary(id: 5, chapters: "3/3")

        #expect(SubscriptionWatermarks.hasKnownPostedChapterCount("") == false)
        #expect(SubscriptionWatermarks.hasKnownPostedChapterCount(sparse.chapters) == false)
        #expect(SubscriptionWatermarks.hasKnownPostedChapterCount("14/20"))
        #expect(SubscriptionWatermarks.hasKnownPostedChapterCount("7/?"))
        #expect(SubscriptionWatermarks.baseline([sparse], into: [:]) == nil)

        let marks = SubscriptionWatermarks.baseline([sparse, known], into: [:])
        #expect(marks?[4] == nil)
        #expect(marks?[5]?.postedChapterCount == 3)
    }

    /// Mark All as Seen runs on whatever summary the screen has. A row that
    /// is still the empty index blurb must not overwrite a real watermark with 0.
    @Test func markingSeenDoesNotReplaceACountWithAnUnknownOne() {
        let seen = [4: SubscriptionWatermark(postedChapterCount: 12, seenAt: Date())]
        let sparse = AO3WorkSummary.subscription(id: 4, title: "Work", authors: ["someone"])
        let after = SubscriptionWatermarks.markSeen([sparse], in: seen)

        #expect(after[4]?.postedChapterCount == 12)
        #expect(SubscriptionWatermarks.newChapterCount(
            for: summary(id: 4, chapters: "14/20"), watermarks: after
        ) == 2)
    }

    @Test func markingSeenClearsTheBadgeAtTheCurrentCount() {
        let seen = [1: SubscriptionWatermark(postedChapterCount: 12, seenAt: Date())]
        let grown = summary(id: 1, chapters: "14/20")
        let cleared = SubscriptionWatermarks.markSeen([grown], in: seen)

        #expect(SubscriptionWatermarks.newChapterCount(for: grown, watermarks: cleared) == 0)
        #expect(cleared[1]?.postedChapterCount == 14)
    }

    // MARK: Bounds and round-trip

    @Test func theStoreIsBoundedAndDropsTheLeastRecentlySeen() {
        var marks: [Int: SubscriptionWatermark] = [:]
        let base = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<(SubscriptionWatermarks.entryLimit + 10) {
            marks[index] = SubscriptionWatermark(
                postedChapterCount: 1,
                seenAt: base.addingTimeInterval(Double(index))
            )
        }
        let bounded = SubscriptionWatermarks.bound(marks)

        #expect(bounded.count == SubscriptionWatermarks.entryLimit)
        // The ten oldest go; the most recent survive.
        #expect(bounded[0] == nil)
        #expect(bounded[SubscriptionWatermarks.entryLimit + 9] != nil)
    }

    @Test func watermarksRoundTripThroughDefaultsWithIntegerKeys() {
        let store = defaults()
        let marks = [
            77: SubscriptionWatermark(postedChapterCount: 3,
                                      seenAt: Date(timeIntervalSince1970: 9_000))
        ]
        SubscriptionWatermarks.save(marks, to: store)

        // JSON object keys are strings; the work id is an Int. The mapping back has
        // to survive or every badge resets on relaunch.
        #expect(SubscriptionWatermarks.load(from: store)[77]?.postedChapterCount == 3)
    }

    @Test func anEmptyOrCorruptStoreLoadsAsEmptyRatherThanCrashing() {
        let store = defaults()
        #expect(SubscriptionWatermarks.load(from: store).isEmpty)
        store.set(Data("not json".utf8), forKey: "ao3.subscriptions.watermarks")
        #expect(SubscriptionWatermarks.load(from: store).isEmpty)
    }
}
