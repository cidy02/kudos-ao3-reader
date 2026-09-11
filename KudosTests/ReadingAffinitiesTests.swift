import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Favorites' Authors / Fandoms / Tags scopes — artboards 1ak, 1bc, 1bd.
@MainActor
@Suite(.serialized)
struct ReadingAffinitiesTests {
    private func work(
        _ title: String,
        author: String = "",
        fandoms: [String] = [],
        freeforms: [String] = [],
        started: Bool = false,
        hasEPUB: Bool = true,
        savedForLater: Bool = false,
        lastRead: Date? = nil
    ) -> SavedWork {
        let work = SavedWork(title: title, author: author)
        work.workFandoms = fandoms
        work.workFreeforms = freeforms
        if started { work.lastSpineIndex = 3 }
        work.hasEPUB = hasEPUB
        work.isSaved = savedForLater
        work.lastReadDate = lastRead
        return work
    }

    private func summary(seconds: Double, lastEnded: Date? = nil) -> WorkReadingSummary {
        WorkReadingSummary(
            totalSeconds: seconds, visitCount: 1, finishCount: 0, lastEndedAt: lastEnded
        )
    }

    // MARK: What counts as read

    @Test func onlyNamesWithSomethingReadBehindThemAppear() {
        let read = work("Read", author: "kestrelmoon", started: true)
        let shelved = work("Shelved", author: "neveropened")
        let rows = ReadingAffinities.authors(works: [read, shelved], summaries: [:])

        // A byline carried solely by works still sitting unopened is a shelf, not an
        // affinity.
        #expect(rows.map(\.name) == ["kestrelmoon"])
    }

    @Test func aWorkWithTwoTagsIsCountedByBothRatherThanSplit() {
        let both = work("Both", freeforms: ["Slow Burn", "Fix-It"], started: true)
        let rows = ReadingAffinities.tags(works: [both], summaries: [:])

        // Unlike ReadingInsights' fandom shares, which partition a fixed total,
        // "N works read carry this tag" is a count about that tag alone.
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.worksRead == 1 })
    }

    // MARK: The library line

    @Test func unreadCountsSplitOutDownloadsAndSavedForLater() {
        let read = work("Read", freeforms: ["Slow Burn"], started: true)
        let unreadDownloaded = work("Waiting", freeforms: ["Slow Burn"], hasEPUB: true)
        let unreadQueued = work("Queued", freeforms: ["Slow Burn"], hasEPUB: false,
                                savedForLater: true)
        let rows = ReadingAffinities.tags(
            works: [read, unreadDownloaded, unreadQueued], summaries: [:]
        )

        #expect(rows.count == 1)
        #expect(rows.first?.worksRead == 1)
        #expect(rows.first?.unreadInLibrary == 2)
        #expect(rows.first?.downloadedInLibrary == 1)
        #expect(rows.first?.savedForLater == 1)
    }

    // MARK: Ordering

    @Test func mostReadAndMostTimeAreDifferentAnswers() {
        let short1 = work("S1", author: "prolific", started: true)
        let short2 = work("S2", author: "prolific", started: true)
        let epic = work("Epic", author: "oneBigBook", started: true)
        let summaries: [UUID: WorkReadingSummary] = [
            short1.id: summary(seconds: 600),
            short2.id: summary(seconds: 600),
            epic.id: summary(seconds: 40_000)
        ]
        let works = [short1, short2, epic]

        // Two short works beat one enormous one on count and lose on time. Both are
        // legitimate senses of "favourite", which is why the order is a control.
        #expect(ReadingAffinities.authors(works: works, summaries: summaries, order: .mostRead)
            .map(\.name) == ["prolific", "oneBigBook"])
        #expect(ReadingAffinities.authors(works: works, summaries: summaries, order: .mostTime)
            .map(\.name) == ["oneBigBook", "prolific"])
    }

    @Test func tiesBreakOnNameSoTheListDoesNotReshuffleBetweenRenders() {
        let b = work("B", author: "bravo", started: true)
        let a = work("A", author: "alpha", started: true)
        // Identical on every ranked field; only the name separates them.
        let rows = ReadingAffinities.authors(works: [b, a], summaries: [:], order: .mostRead)
        #expect(rows.map(\.name) == ["alpha", "bravo"])
    }

    @Test func recentOrderUsesTheSessionEndNotJustTheWorksLastReadDate() {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let recent = Date(timeIntervalSince1970: 2_000_000)
        let quiet = work("Quiet", author: "quiet", started: true, lastRead: recent)
        let logged = work("Logged", author: "logged", started: true, lastRead: old)
        let summaries: [UUID: WorkReadingSummary] = [
            logged.id: summary(seconds: 60, lastEnded: recent.addingTimeInterval(100))
        ]

        #expect(ReadingAffinities.authors(works: [quiet, logged], summaries: summaries)
            .map(\.name) == ["logged", "quiet"])
    }

    // MARK: Hygiene

    @Test func blankAndWhitespaceOnlyNamesAreDropped() {
        let blank = work("Blank", author: "   ", fandoms: ["", "  "], started: true)
        #expect(ReadingAffinities.authors(works: [blank], summaries: [:]).isEmpty)
        #expect(ReadingAffinities.fandoms(works: [blank], summaries: [:]).isEmpty)
    }

    @Test func namesAreTrimmedSoOneFandomDoesNotBecomeTwoRows() {
        let padded = work("A", fandoms: [" Naruto "], started: true)
        let plain = work("B", fandoms: ["Naruto"], started: true)
        let rows = ReadingAffinities.fandoms(works: [padded, plain], summaries: [:])

        #expect(rows.count == 1)
        #expect(rows.first?.worksRead == 2)
    }
}
