import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Owner, 2026-11-19: queue-only reading counts in the main figures; hidden (Hide Mature)
/// works get their own section, shown only while revealed; a combined view adds them in.
@MainActor
@Suite struct InsightsHiddenScopeTests {
    private let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self,
            ReadingAnnotation.self, ReadingSession.self, ReadingFavorite.self,
            FandomReadWatermark.self, TagAlias.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func date(day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: 12))!
    }

    private var aug: DateInterval {
        utcCalendar.dateInterval(of: .month, for: date(day: 1))!
    }

    private var jul: DateInterval {
        utcCalendar.dateInterval(of: .month, for: date(day: 1).addingTimeInterval(-86_400 * 5))!
    }

    private struct Fixture {
        let context: ModelContext
        let library: [SavedWork]
        let visible: SavedWork
        let mature: SavedWork
        let queueOnly: SavedWork
        let sessions: [ReadingSession]
    }

    private func makeFixture() throws -> Fixture {
        let context = try makeContext()
        func work(_ title: String, words: Int, fandom: String) -> SavedWork {
            let work = SavedWork(title: title, author: "A")
            work.wordCount = words
            work.workFandoms = [fandom]
            work.isSaved = true
            return work
        }
        let visible = work("Visible Fic", words: 10_000, fandom: "Fandom One")
        let mature = work("Explicit Fic", words: 20_000, fandom: "Secret Fandom")
        mature.rating = "Explicit"
        let queueOnly = work("Queued Fic", words: 6_000, fandom: "Queue Fandom")
        queueOnly.isSaved = false
        queueOnly.isQueuedForLater = true

        func finished(_ work: SavedWork, day: Int, seconds: Double) -> ReadingSession {
            let start = date(day: day)
            let session = ReadingSession(
                workID: work.id, workTitle: work.title,
                startedAt: start, endedAt: start.addingTimeInterval(seconds),
                durationSeconds: seconds,
                startProgress: 0, endingProgress: 1.0, wordCount: work.wordCount, didFinish: true
            )
            session.fandoms = work.workFandoms
            return session
        }
        let library = [visible, mature, queueOnly]
        library.forEach { context.insert($0) }
        let sessions = [
            finished(visible, day: 2, seconds: 600),
            finished(mature, day: 3, seconds: 1_200),
            finished(queueOnly, day: 4, seconds: 300)
        ]
        sessions.forEach { context.insert($0) }
        try context.save()
        return Fixture(
            context: context, library: library,
            visible: visible, mature: mature, queueOnly: queueOnly, sessions: sessions
        )
    }

    private func gather(_ scope: InsightsScope, revealed: Bool, _ f: Fixture) -> ReadingLogService.InsightsGatherResult {
        ReadingLogService.gatherInsights(
            for: aug, previousPeriod: jul,
            scope: HomeReadingStats.insightsScope(scope, from: f.library, hideMature: true, revealed: revealed),
            calendar: utcCalendar, context: f.context,
            now: date(day: 20)
        )
    }

    private func fandoms(_ result: ReadingLogService.InsightsGatherResult) -> Set<String> {
        Set(result.insights.fandomWordsShares.filter { !$0.isRemainder }.map(\.name))
    }

    @Test func mainExcludesHiddenAndCountsQueueOnlyLockedOrRevealed() throws {
        let f = try makeFixture()
        for revealed in [false, true] {
            let main = gather(.main, revealed: revealed, f)
            #expect(main.insights.totalWordsRead == 16_000)
            #expect(main.insights.totalSeconds == 900)
            #expect(main.insights.finishedWorksCount == 2)
            #expect(fandoms(main) == ["Fandom One", "Queue Fandom"])
            // Inventory figures describe the saved library: no queue-only, no hidden work.
            #expect(main.libraryStats.totalWorks == 1)
            #expect(!main.filteredSessions.contains { $0.workID == f.mature.id })
        }
    }

    @Test func hiddenScopeHoldsOnlyHiddenWorks() throws {
        let f = try makeFixture()
        let hidden = gather(.hidden, revealed: true, f)
        #expect(hidden.insights.totalWordsRead == 20_000)
        #expect(hidden.insights.totalSeconds == 1_200)
        #expect(hidden.insights.finishedWorksCount == 1)
        #expect(fandoms(hidden) == ["Secret Fandom"])
        #expect(hidden.filteredSessions.map(\.workID) == [f.mature.id])
        #expect(hidden.libraryStats.totalWorks == 1)
    }

    @Test func combinedIsMainPlusHidden() throws {
        let f = try makeFixture()
        let main = gather(.main, revealed: true, f)
        let hidden = gather(.hidden, revealed: true, f)
        let combined = gather(.combined, revealed: true, f)
        #expect(combined.insights.totalWordsRead == main.insights.totalWordsRead + hidden.insights.totalWordsRead)
        #expect(combined.insights.totalSeconds == main.insights.totalSeconds + hidden.insights.totalSeconds)
        #expect(combined.insights.finishedWorksCount
            == main.insights.finishedWorksCount + hidden.insights.finishedWorksCount)
        #expect(fandoms(combined) == fandoms(main).union(fandoms(hidden)))
        #expect(combined.libraryStats.totalWorks == 2)
    }

    @Test func lockedComputesAndExportsNothingHidden() throws {
        let f = try makeFixture()
        let lockedHidden = HomeReadingStats.insightsScope(.hidden, from: f.library, hideMature: true, revealed: false)
        #expect(lockedHidden.readingWorks.isEmpty)
        #expect(lockedHidden.libraryWorks.isEmpty)
        #expect(lockedHidden.sessions(f.sessions).isEmpty)
        let hidden = gather(.hidden, revealed: false, f)
        #expect(hidden.insights.totalWordsRead == 0)
        #expect(hidden.filteredSessions.isEmpty)

        // Locked, "combined" is the main view, so its export carries no hidden work.
        let lockedCombined = gather(.combined, revealed: false, f)
        #expect(lockedCombined.insights.totalWordsRead == 16_000)
        for scope in [InsightsScope.main, .combined, .hidden] {
            let selection = HomeReadingStats.insightsScope(scope, from: f.library, hideMature: true, revealed: false)
            let csv = InsightsExportService.csvString(
                works: selection.libraryWorks,
                sessions: selection.sessions(f.sessions)
            )
            #expect(!csv.contains("Explicit Fic"))
            #expect(!csv.contains("Secret Fandom"))
        }

        // Revealed and combined, the export follows the screen and includes it.
        let revealed = HomeReadingStats.insightsScope(.combined, from: f.library, hideMature: true, revealed: true)
        let csv = InsightsExportService.csvString(
            works: revealed.libraryWorks,
            sessions: revealed.sessions(f.sessions)
        )
        #expect(csv.contains("Explicit Fic"))
        #expect(csv.contains("Queued Fic"))
    }

    @Test func hideMatureOffHasNoHiddenWorks() throws {
        let f = try makeFixture()
        #expect(HomeReadingStats.insightsHiddenWorkIDs(from: f.library, hideMature: false).isEmpty)
        let main = HomeReadingStats.insightsScope(.main, from: f.library, hideMature: false, revealed: false)
        #expect(main.excludedWorkIDs.isEmpty)
        #expect(main.sessions(f.sessions).count == 3)
    }
}
