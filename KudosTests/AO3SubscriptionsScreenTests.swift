import Foundation
import Testing
@testable import Kudos

/// Subscriptions' pure pieces: which pill a row survives, which group it falls
/// in, and the chapter range under an updated row. Nothing here signs in or posts.
@MainActor
struct AO3SubscriptionsScreenTests {
    private struct Row: Equatable {
        var name: String
        var updated: Bool
    }

    private let rows = [
        Row(name: "updated-first", updated: true),
        Row(name: "plain", updated: false),
        Row(name: "updated-second", updated: true),
        Row(name: "plain-second", updated: false)
    ]

    private func sections(
        _ rows: [Row],
        filter: AO3SubscriptionsFilter
    ) -> [AO3SubscriptionsSection<Row>] {
        AO3SubscriptionsGrouping.sections(rows, filter: filter, isUpdated: \.updated)
    }

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

    /// All is the two runs: updated rows first, in page order, then everyone
    /// else. An empty run is omitted rather than drawn as 0.
    @Test func allSplitsUpdatedAheadOfEverythingElse() {
        let split = sections(rows, filter: .all)

        #expect(split.map(\.group) == [.updatedSinceYouLooked, .everythingElse])
        #expect(split.map(\.showsHeader) == [true, true])
        #expect(split[0].items.map(\.name) == ["updated-first", "updated-second"])
        #expect(split[1].items.map(\.name) == ["plain", "plain-second"])
    }

    @Test func allDropsAnEmptyRun() {
        let onlyUpdated = rows.filter(\.updated)
        let split = sections(onlyUpdated, filter: .all)

        #expect(split.map(\.group) == [.updatedSinceYouLooked])
        #expect(split[0].showsHeader)
    }

    /// The Updated pill is one list, without a header that would repeat the pill.
    @Test func updatedPillIsOneList() {
        let updated = sections(rows, filter: .updated)
        #expect(updated.count == 1)
        #expect(updated[0].showsHeader == false)
        #expect(updated[0].group == .updatedSinceYouLooked)
        #expect(updated[0].items.map(\.name) == ["updated-first", "updated-second"])
    }

    @Test func updatedPillDropsAPageWithNothingNew() {
        let plain = rows.filter { !$0.updated }
        #expect(sections(plain, filter: .updated).isEmpty)
    }

    @Test func updatedMeansChaptersGrewSinceTheSubscriptionsWatermark() {
        let grown = summary(id: 4, chapters: "14/20")
        let seen = [4: SubscriptionWatermark(postedChapterCount: 12, seenAt: Date())]

        #expect(AO3SubscriptionsClassification.isUpdated(work: grown, watermarks: seen))
        // First sight is not "updated". Otherwise the updated run is the whole page.
        #expect(!AO3SubscriptionsClassification.isUpdated(work: grown, watermarks: [:]))
        #expect(!AO3SubscriptionsClassification.isUpdated(
            work: summary(id: 4, chapters: "10/20"),
            watermarks: seen
        ))
        #expect(!AO3SubscriptionsClassification.isUpdated(work: grown, watermarks: [
            4: SubscriptionWatermark(postedChapterCount: 14, seenAt: Date())
        ]))
    }

    /// The number before the slash is the posted count. "14/20" with a
    /// watermark of 12 is chapters 13 and 14, not 13 through 20.
    @Test func chapterRangeIsTheGapAfterTheWatermark() {
        #expect(AO3SubscriptionsChapterRange.label(seenPosted: 5, currentPosted: 7) == "Chapters 6-7 new")
        #expect(AO3SubscriptionsChapterRange.label(seenPosted: 5, currentPosted: 6) == "Chapter 6 new")
        #expect(AO3SubscriptionsChapterRange.label(seenPosted: 12, currentPosted: 14) == "Chapters 13-14 new")
    }

    @Test func aCountThatDidNotGrowHasNoRange() {
        #expect(AO3SubscriptionsChapterRange.label(seenPosted: 5, currentPosted: 5) == nil)
        // A deleted chapter is not a negative range.
        #expect(AO3SubscriptionsChapterRange.label(seenPosted: 7, currentPosted: 5) == nil)
        #expect(AO3SubscriptionsChapterRange.label(seenPosted: 0, currentPosted: 0) == nil)
    }

    /// A stored 0 is a baseline, not a missing watermark. Chapters 1 through
    /// the current posted count are the gap. A missing watermark says nothing.
    @Test func rangeFollowsTheWatermarkAndThePostedSideOfTheChaptersString() {
        let grown = summary(id: 4, chapters: "14/20")
        let seen = [4: SubscriptionWatermark(postedChapterCount: 12, seenAt: Date())]
        let fromZero = [4: SubscriptionWatermark(postedChapterCount: 0, seenAt: Date())]

        #expect(SubscriptionWatermarks.newChapterCount(for: grown, watermarks: seen) == 2)
        #expect(
            AO3SubscriptionsChapterRange.label(work: grown, watermarks: seen) == "Chapters 13-14 new"
        )
        #expect(AO3SubscriptionsChapterRange.label(work: grown, watermarks: [:]) == nil)
        #expect(AO3SubscriptionsChapterRange.label(work: grown, watermarks: [
            4: SubscriptionWatermark(postedChapterCount: 14, seenAt: Date())
        ]) == nil)
        #expect(
            AO3SubscriptionsChapterRange.label(work: grown, watermarks: fromZero) == "Chapters 1-14 new"
        )
        // The subscriptions blurb carries no chapter total. Empty is not a range.
        #expect(AO3SubscriptionsChapterRange.label(
            work: summary(id: 4, chapters: ""),
            watermarks: seen
        ) == nil)
    }

    /// The line exists exactly when the watermark says the posted count grew.
    @Test func rangeAgreesWithTheNewChapterCount() {
        let samples = ["", "1/1", "7/?", "14/20", "10/20"]
        let marks = [
            4: SubscriptionWatermark(postedChapterCount: 12, seenAt: Date())
        ]
        for chapters in samples {
            let work = summary(id: 4, chapters: chapters)
            let grew = SubscriptionWatermarks.newChapterCount(for: work, watermarks: marks) > 0
            #expect((AO3SubscriptionsChapterRange.label(work: work, watermarks: marks) != nil) == grew)
        }
        let unseen = summary(id: 4, chapters: "14/20")
        #expect(SubscriptionWatermarks.newChapterCount(for: unseen, watermarks: [:]) == 0)
        #expect(AO3SubscriptionsChapterRange.label(work: unseen, watermarks: [:]) == nil)
    }

    @Test func subtitleNamesNewChaptersOnlyOnAll() {
        #expect(
            AO3SubscriptionsCopy.subtitle(
                shownCount: 12, updatedCount: 2, filter: .all, currentPage: 1, totalPages: 1
            ) == "12 works · 2 with new chapters"
        )
        #expect(
            AO3SubscriptionsCopy.subtitle(
                shownCount: 1, updatedCount: 1, filter: .all, currentPage: 2, totalPages: 4
            ) == "1 work · 1 with new chapters · page 2 of 4"
        )
        #expect(
            AO3SubscriptionsCopy.subtitle(
                shownCount: 2, updatedCount: 2, filter: .updated, currentPage: 2, totalPages: 4
            ) == "2 works · page 2 of 4"
        )
        #expect(
            AO3SubscriptionsCopy.subtitle(
                shownCount: 0, updatedCount: 0, filter: .updated, currentPage: 1, totalPages: 1
            ) == "0 works"
        )
    }

    @Test func footerUsesTheRealPageNumbers() {
        #expect(
            AO3SubscriptionsCopy.footer(currentPage: 2, totalPages: 4)
                == "Subscriptions live on AO3 — unsubscribing here unsubscribes there. "
                + "Pagination follows the list: 2 of 4 pages."
        )
        #expect(
            AO3SubscriptionsCopy.footer(currentPage: 1, totalPages: 1)
                == "Subscriptions live on AO3 — unsubscribing here unsubscribes there. "
                + "Pagination follows the list: 1 of 1 page."
        )
    }
}
