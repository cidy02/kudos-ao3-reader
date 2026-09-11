import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
@Suite(.serialized)
struct ReadingLogTests {
    private func schema() -> Schema {
        Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
        ])
    }

    private func context() throws -> ModelContext {
        let schema = schema()
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func locator(progress: Double) -> String {
        """
        {"href":"c1.xhtml","type":"application/xhtml+xml","title":"Chapter 2",\
        "locations":{"totalProgression":\(progress)}}
        """
    }

    @Test func startEndPersistsDurationAndDropsSub15s() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Session Work", author: "A")
        work.wordCount = 12_000
        work.chapters = "3/10"
        work.readiumLocator = locator(progress: 0.4)
        work.lastSpineIndex = 2
        context.insert(work)
        try context.save()

        let t0 = Date(timeIntervalSince1970: 1_000)
        ReadingLogService.startSession(for: work, now: t0)
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(10))
        #expect(try context.fetch(FetchDescriptor<ReadingSession>()).isEmpty)

        ReadingLogService.startSession(for: work, now: t0)
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(20))
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.workID == work.id)
        #expect(session.workTitle == "Session Work")
        #expect(session.durationSeconds == 20)
        #expect(session.wordCount == 12_000)
        #expect(session.chapterCountAtVisit == 3)
        #expect(session.chapterTitle == "Chapter 2")
        #expect(session.endingProgress == 0.4)
        #expect(session.lastSpineIndex == 2)
        #expect(!session.didFinish)
    }

    // MARK: Surviving a backgrounded app that iOS never lets back in

    @Test func pauseWritesTheRowSoAReclaimedAppKeepsTheSession() throws {
        // The reader's onDisappear never fires when iOS jettisons a backgrounded
        // app, so a session held only in memory was lost entirely. Pause has to
        // leave a row behind. Revert the persist call in `pauseSession` and this
        // fails: the fetch finds nothing.
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Backgrounded", author: "A")
        work.readiumLocator = locator(progress: 0.3)
        context.insert(work)
        try context.save()

        let t0 = Date(timeIntervalSince1970: 2_000)
        ReadingLogService.startSession(for: work, now: t0)
        ReadingLogService.pauseSession(for: work, now: t0.addingTimeInterval(600))

        // No endSession — this is the process dying.
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(sessions.count == 1)
        #expect(try #require(sessions.first).durationSeconds == 600)
    }

    @Test func aResumedVisitStaysOneRowRatherThanOnePerStretch() throws {
        // Three stretches of one visit must not become three rows, or a single
        // finish would be counted three times by `finishCount`.
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Resumed", author: "A")
        work.readiumLocator = locator(progress: 0.5)
        context.insert(work)
        try context.save()

        let t0 = Date(timeIntervalSince1970: 3_000)
        ReadingLogService.startSession(for: work, now: t0)
        ReadingLogService.pauseSession(for: work, now: t0.addingTimeInterval(60))
        ReadingLogService.resumeSession(for: work, now: t0.addingTimeInterval(300))
        ReadingLogService.pauseSession(for: work, now: t0.addingTimeInterval(360))
        ReadingLogService.resumeSession(for: work, now: t0.addingTimeInterval(600))
        work.isFinished = true
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(660))

        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        // 60 + 60 + 60 read; the two 240s gaps were backgrounded and excluded.
        #expect(session.durationSeconds == 180)
        #expect(session.didFinish)
        #expect(ReadingLogService.finishCount(of: work.id, in: context) == 1)
    }

    @Test func aFinishAlreadyRecordedIsNotClearedByALaterPause() throws {
        // A visit that finished the work must not be un-marked by a later pause,
        // and the *next* visit — which opens on an already-finished work — must
        // not count as a second finish.
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Finished then backgrounded", author: "A")
        work.readiumLocator = locator(progress: 1)
        context.insert(work)
        try context.save()

        let t0 = Date(timeIntervalSince1970: 4_000)
        ReadingLogService.startSession(for: work, now: t0)
        ReadingLogService.pauseSession(for: work, now: t0.addingTimeInterval(30))
        ReadingLogService.resumeSession(for: work, now: t0.addingTimeInterval(40))
        work.isFinished = true
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(70))
        ReadingLogService.startSession(for: work, now: t0.addingTimeInterval(80))
        ReadingLogService.pauseSession(for: work, now: t0.addingTimeInterval(200))

        let finished = try context.fetch(FetchDescriptor<ReadingSession>()).filter(\.didFinish)
        #expect(finished.count == 1)
    }

    @Test func aFinishSurvivesTheAppBeingReclaimedWhileBackgrounded() throws {
        // The bug this covers: finish an initially-unfinished work, background the
        // app, and let iOS jettison it. `endSession` never runs. If the background
        // flush wrote didFinish: false — which it did — the finish was lost for
        // good, because reopening starts a session on an already-finished work and
        // its own transition is false too.
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Finished, then reclaimed", author: "A")
        work.readiumLocator = locator(progress: 1)
        context.insert(work)
        try context.save()

        let t0 = Date(timeIntervalSince1970: 7_000)
        ReadingLogService.startSession(for: work, now: t0)
        work.isFinished = true
        // Backgrounded. No endSession — the process is gone after this.
        ReadingLogService.pauseSession(for: work, now: t0.addingTimeInterval(120))

        let rows = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(rows.count == 1)
        #expect(rows.first?.didFinish == true)
    }

    @Test func aSecondStartForTheSameWorkDoesNotOpenAnotherSession() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Once", author: "A")
        context.insert(work)
        try context.save()
        let t0 = Date(timeIntervalSince1970: 2_000)
        ReadingLogService.startSession(for: work, now: t0)
        ReadingLogService.startSession(for: work, now: t0.addingTimeInterval(5))
        #expect(ReadingLogService.hasOpenSession(for: work.id))
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(25))
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.startedAt == t0)
        #expect(sessions.first?.durationSeconds == 25)
    }

    @Test func finishCountIncrementsOnlyOnDidFinish() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Reread", author: "A")
        context.insert(work)
        try context.save()
        let t0 = Date(timeIntervalSince1970: 3_000)
        // A reread is two *transitions* into finished, which means the work has to
        // be un-finished in between — exactly what WorkLifecycle.markStillReading
        // does. Ending twice while it stays finished is one read-through someone
        // reopened, and counting that twice is the bug this rule prevents.
        ReadingLogService.startSession(for: work, now: t0)
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(30))
        ReadingLogService.startSession(for: work, now: t0.addingTimeInterval(40))
        work.isFinished = true
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(80))
        work.isFinished = false
        ReadingLogService.startSession(for: work, now: t0.addingTimeInterval(90))
        work.isFinished = true
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(130))
        #expect(ReadingLogService.finishCount(of: work.id, in: context) == 2)
        #expect(ReadingLogService.totalDuration(of: work.id, in: context) == 110)
        #expect(ReadingLogService.lastSession(of: work.id, in: context)?.didFinish == true)
    }

    @Test func groupingKeyIsWorkUUIDNotTitle() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let first = SavedWork(title: "Shared Title", author: "A")
        let second = SavedWork(title: "Shared Title", author: "B")
        context.insert(first)
        context.insert(second)
        try context.save()
        let t0 = Date(timeIntervalSince1970: 4_000)
        ReadingLogService.startSession(for: first, now: t0)
        first.isFinished = true
        ReadingLogService.endSession(for: first, now: t0.addingTimeInterval(30))
        ReadingLogService.startSession(for: second, now: t0)
        ReadingLogService.endSession(for: second, now: t0.addingTimeInterval(30))
        #expect(ReadingLogService.finishCount(of: first.id, in: context) == 1)
        #expect(ReadingLogService.finishCount(of: second.id, in: context) == 0)
        #expect(ReadingLogService.totalDuration(of: first.id, in: context) == 30)
        #expect(ReadingLogService.totalDuration(of: second.id, in: context) == 30)
    }

    @Test func abandonedIsDerivedAndOverrideSticks() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let work = SavedWork(title: "Dusty", author: "A")
        work.hasEPUB = true
        work.readiumLocator = locator(progress: 0.4)
        work.lastReadDate = now.addingTimeInterval(-30 * 24 * 3600)
        #expect(ReadingLogService.isAbandoned(work: work, now: now))

        work.keepInProgressOverride = true
        #expect(!ReadingLogService.isAbandoned(work: work, now: now))

        work.keepInProgressOverride = false
        work.readiumLocator = locator(progress: 0.02)
        #expect(!ReadingLogService.isAbandoned(work: work, now: now))

        work.readiumLocator = locator(progress: 0.4)
        work.lastReadDate = now.addingTimeInterval(-2 * 24 * 3600)
        #expect(!ReadingLogService.isAbandoned(work: work, now: now))

        work.isFinished = true
        work.lastReadDate = now.addingTimeInterval(-30 * 24 * 3600)
        #expect(!ReadingLogService.isAbandoned(work: work, now: now))
    }

    @Test func wordsPerHourUsesStoredWordCount() throws {
        let slow = ReadingSession(
            workID: UUID(),
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 3600),
            durationSeconds: 3600,
            wordCount: 10_000
        )
        let fast = ReadingSession(
            workID: UUID(),
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 1800),
            durationSeconds: 1800,
            wordCount: 20_000
        )
        let ignored = ReadingSession(
            workID: UUID(),
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 0),
            durationSeconds: 0,
            wordCount: 99_999
        )
        // 30_000 words / 1.5 hours = 20_000. The live work's wordCount is not consulted.
        #expect(ReadingLogService.wordsPerHour(sessions: [slow, fast, ignored]) == 20_000)
        #expect(ReadingLogService.wordsPerHour(sessions: []) == 0)
    }

    @Test func hoursByWeekBucketsBySessionStart() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 1
        let weekA = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 7, hour: 12
        )))
        let weekB = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 14, hour: 12
        )))
        let work = SavedWork(title: "Weekly", author: "A")
        context.insert(work)
        context.insert(ReadingSession(
            workID: work.id, startedAt: weekA, endedAt: weekA.addingTimeInterval(100),
            durationSeconds: 100
        ))
        context.insert(ReadingSession(
            workID: work.id, startedAt: weekA.addingTimeInterval(3600),
            endedAt: weekA.addingTimeInterval(4600), durationSeconds: 50
        ))
        context.insert(ReadingSession(
            workID: work.id, startedAt: weekB, endedAt: weekB.addingTimeInterval(80),
            durationSeconds: 80
        ))
        try context.save()

        let interval = DateInterval(start: weekA.addingTimeInterval(-86400), end: weekB.addingTimeInterval(86400))
        let bars = ReadingLogService.hoursByWeek(in: interval, calendar: calendar, context: context)
        #expect(bars.count == 2)
        #expect(bars[0].seconds == 150)
        #expect(bars[1].seconds == 80)
        #expect(bars[0].weekStart < bars[1].weekStart)
    }

    @Test func tagCountsCountEachTagOncePerWorkWithASession() throws {
        let firstID = UUID()
        let secondID = UUID()
        let first = SavedWork(id: firstID, title: "Shared Title", author: "A")
        first.workTags = ["Hurt/Comfort", "Angst"]
        let second = SavedWork(id: secondID, title: "Shared Title", author: "B")
        second.workTags = ["Hurt/Comfort"]
        let unread = SavedWork(title: "No session", author: "C")
        unread.workTags = ["Fluff"]
        let sessions = [
            ReadingSession(
                workID: firstID, startedAt: Date(), endedAt: Date(), durationSeconds: 30
            ),
            ReadingSession(
                workID: secondID, startedAt: Date(), endedAt: Date(), durationSeconds: 30
            )
        ]
        let counts = ReadingLogService.tagCounts(from: sessions, works: [first, second, unread])
        #expect(counts.contains { $0.tag == "Hurt/Comfort" && $0.count == 2 })
        #expect(counts.contains { $0.tag == "Angst" && $0.count == 1 })
        #expect(!counts.contains { $0.tag == "Fluff" })
    }

    @Test func pauseDoesNotCountBackgroundTime() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Paused", author: "A")
        context.insert(work)
        try context.save()
        let t0 = Date(timeIntervalSince1970: 5_000)
        ReadingLogService.startSession(for: work, now: t0)
        ReadingLogService.pauseSession(for: work, now: t0.addingTimeInterval(10))
        ReadingLogService.resumeSession(for: work, now: t0.addingTimeInterval(1_000))
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(1_020))
        let session = try #require(try context.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(session.durationSeconds == 30)
    }

    @Test func favoriteUnfavoriteIsUniqueAndTombstones() throws {
        let context = try context()
        let work = SavedWork(title: "Starred", author: "A")
        context.insert(work)
        try context.save()
        let key = ReadingFavorite.workTargetKey(work)
        let first = ReadingLogService.setFavorite(
            true, kind: .work, targetKey: key, displayName: work.title, in: context
        )
        let favoriteID = try #require(first?.id)
        let second = ReadingLogService.setFavorite(
            true, kind: .work, targetKey: key, displayName: work.title, in: context
        )
        #expect(second?.id == favoriteID)
        #expect(try context.fetch(FetchDescriptor<ReadingFavorite>()).count == 1)
        #expect(ReadingLogService.isFavorite(kind: .work, targetKey: key, in: context))

        ReadingLogService.setFavorite(
            false, kind: .work, targetKey: key, displayName: work.title, in: context
        )
        #expect(try context.fetch(FetchDescriptor<ReadingFavorite>()).isEmpty)
        let tombs = try context.fetch(FetchDescriptor<SyncTombstone>())
        #expect(tombs.contains { $0.recordType == .readingFavorite && $0.recordID == favoriteID })
    }

    @Test func markVisitedUpdatesExistingWatermark() throws {
        let context = try context()
        let newest = SavedWork(title: "Newest in Fandom", author: "A")
        newest.ao3WorkID = 99
        context.insert(newest)
        try context.save()
        let t0 = Date(timeIntervalSince1970: 6_000)
        ReadingLogService.markVisited(
            fandom: "The Untamed (TV)", newestWork: newest, in: context, now: t0
        )
        ReadingLogService.markVisited(
            fandom: "The Untamed (TV)", newestWork: newest, in: context,
            now: t0.addingTimeInterval(60)
        )
        let rows = try context.fetch(FetchDescriptor<FandomReadWatermark>())
        #expect(rows.count == 1)
        #expect(rows.first?.fandomName == "The Untamed (TV)")
        #expect(rows.first?.newestWorkIDSeen == 99)
        #expect(rows.first?.newestWorkTitleSeen == "Newest in Fandom")
        #expect(rows.first?.lastVisitedAt == t0.addingTimeInterval(60))
    }
}
