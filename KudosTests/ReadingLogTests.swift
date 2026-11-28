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
            SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
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

    @Test func activeGapsAndPauseResume() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Active", author: "A")
        context.insert(work)
        let t0 = Date(timeIntervalSince1970: 10_000)
        #expect(ReadingLogService.activeGap(from: t0, to: t0.addingTimeInterval(120)) == 120)
        #expect(ReadingLogService.activeGap(from: t0, to: t0.addingTimeInterval(300)) == 300)
        #expect(ReadingLogService.activeGap(from: t0, to: t0.addingTimeInterval(480)) == 300)
        #expect(ReadingLogService.activeGap(from: t0, to: t0.addingTimeInterval(-1)) == 0)

        ReadingLogService.startSession(for: work, now: t0)
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(120))
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(420))
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(900))
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(890))
        ReadingLogService.pauseSession(for: work, now: t0.addingTimeInterval(930))
        ReadingLogService.resumeSession(for: work, now: t0.addingTimeInterval(2_000))
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(2_120))
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(2_200))
        let session = try #require(try context.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(session.activeSeconds == 950)
        #expect(session.durationSeconds == 1_130)
    }

    @Test func startProgressUsesOnlyStoredOverallProgress() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let unread = SavedWork(title: "Unread", author: "A")
        unread.chapters = "5/10"
        // The reader can stamp this before the session starts.
        unread.lastReadDate = Date(timeIntervalSince1970: 10_000)
        context.insert(unread)
        let legacy = SavedWork(title: "Legacy", author: "A")
        legacy.chapters = "5/10"
        legacy.lastSpineIndex = 3
        context.insert(legacy)
        let t0 = Date(timeIntervalSince1970: 10_000)
        ReadingLogService.startSession(for: unread, now: t0)
        ReadingLogService.endSession(for: unread, now: t0.addingTimeInterval(20))
        ReadingLogService.startSession(for: legacy, now: t0)
        ReadingLogService.endSession(for: legacy, now: t0.addingTimeInterval(20))
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(sessions.first(where: { $0.workID == unread.id })?.startProgress == 0)
        #expect(sessions.first(where: { $0.workID == legacy.id })?.startProgress == nil)
    }

    @Test func startFactsKeepTheirOriginalValuesAndInstallID() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Start", author: "A")
        work.readiumLocator = locator(progress: 0.25)
        work.lastSpineIndex = 3
        context.insert(work)
        let suiteName = "ReadingLogTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let firstID = ReadingLogService.deviceID(defaults: defaults)
        let relaunchedDefaults = try #require(UserDefaults(suiteName: suiteName))
        #expect(ReadingLogService.deviceID(defaults: relaunchedDefaults) == firstID)
        let t0 = Date(timeIntervalSince1970: 10_000)
        let zone = try #require(TimeZone(secondsFromGMT: 5 * 3600 + 1800))
        ReadingLogService.startSession(for: work, now: t0, timeZone: zone, defaults: defaults)
        work.readiumLocator = locator(progress: 0.75)
        work.lastSpineIndex = 8
        ReadingLogService.setMode(.listen, for: work, playbackRate: 1.25, now: t0)
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(60))
        let session = try #require(try context.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(session.tzOffsetSeconds == 19_800)
        #expect(session.startProgress == 0.25)
        #expect(session.startSpineIndex == 3)
        #expect(session.mode == .listen)
        #expect(session.playbackRate == 1.25)
        #expect(session.activeSeconds == 60)
        #expect(session.deviceID == firstID)
        #expect(session.rulesVersion == 1)
        let settingsJSON = try String(decoding: JSONEncoder().encode(
            KudosBackupSettings.capture(defaults: defaults)
        ), as: UTF8.self)
        #expect(!settingsJSON.contains(firstID))
        #expect(!settingsJSON.contains("readingLogDeviceID"))
    }

    @Test func laterCheckpointUpdatesListeningFactsOnTheSameRowWhenStayingInListeningMode() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Checkpoint", author: "A")
        context.insert(work)
        let t0 = Date(timeIntervalSince1970: 10_000)
        ReadingLogService.startSession(for: work, mode: .listen, playbackRate: 1.0, now: t0)
        ReadingLogService.pauseSession(for: work, now: t0.addingTimeInterval(20))
        ReadingLogService.resumeSession(for: work, now: t0.addingTimeInterval(30))
        ReadingLogService.setMode(
            .listen, for: work, playbackRate: 1.25, now: t0.addingTimeInterval(30)
        )
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(50))
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.mode == .listen)
        #expect(sessions.first?.playbackRate == 1.25)
        #expect(sessions.first?.activeSeconds == 40)
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

    @Test func currentTotalDurationDoesNotCountAPausedSessionTwice() throws {
        // `pauseSession` persists the open row and keeps the session open, so the
        // sum must not add that row plus `accumulatedSeconds`. Revert the
        // `recordID` exclusion in `currentTotalDuration` and this reads 1200.
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = SavedWork(title: "Session Work", author: "A")
        context.insert(work)
        try context.save()

        let t0 = Date(timeIntervalSince1970: 1_000)
        ReadingLogService.startSession(for: work, now: t0)
        ReadingLogService.pauseSession(for: work, now: t0.addingTimeInterval(600))
        #expect(try context.fetch(FetchDescriptor<ReadingSession>()).count == 1)
        #expect(ReadingLogService.currentTotalDuration(
            of: work.id, in: context, now: t0.addingTimeInterval(600)) == 600)
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

    /// 1ai's "Move back to In progress": the undo must be *stored*, so the same
    /// 21-day rule that abandoned the work cannot abandon it again, and the work
    /// must land in the In progress bucket rather than vanish from both.
    @Test func moveBackToInProgressStoresTheOverrideAndRebuckets() throws {
        let context = try context()
        let now = Date()
        let work = SavedWork(title: "Dusty", author: "A")
        work.hasEPUB = true
        work.readiumLocator = locator(progress: 0.4)
        work.lastReadDate = now.addingTimeInterval(-30 * 24 * 3600)
        context.insert(work)
        try context.save()
        let before = work.lastModifiedAt
        #expect(ReadingLogService.isAbandoned(work: work, now: now))

        WorkLifecycle.keepInProgress(work, in: context)

        #expect(work.keepInProgressOverride)
        #expect(work.lastModifiedAt >= before)
        #expect(!ReadingLogService.isAbandoned(work: work, now: now))
        // Still stale by the threshold — only the override keeps it out.
        #expect(!ReadingLogService.isAbandoned(work: work, now: now.addingTimeInterval(365 * 24 * 3600)))
        let buckets = LibraryHistoryGrouping.groups(
            .state, works: [work], now: now,
            isAbandoned: { ReadingLogService.isAbandoned(work: $0, now: now) }
        )
        #expect(buckets.map(\.title) == [LibraryHistoryGrouping.inProgressTitle])
    }

    @Test func wordsPerHourUsesStoredWordCount() throws {
        // Each is its work's first sitting and reads it to the end, so it read all of it.
        let slow = ReadingSession(
            workID: UUID(),
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 3600),
            durationSeconds: 3600,
            endingProgress: 1,
            wordCount: 10_000
        )
        let fast = ReadingSession(
            workID: UUID(),
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 1800),
            durationSeconds: 1800,
            endingProgress: 1,
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
        #expect(ReadingLogService.wordsPerHour(sessions: [slow, fast, ignored], works: []) == 20_000)
        #expect(ReadingLogService.wordsPerHour(sessions: [], works: []) == 0)
    }

    @Test func aSittingCountsWhatItReadNotTheWholeWork() {
        // Owner Q27 (2026-10-20): a 22-second look at an 18,000-word work was 2,977,444 an hour.
        let work = UUID()
        func row(_ day: Double, _ progress: Double, finished: Bool = false, of id: UUID = work) -> ReadingSession {
            ReadingSession(
                workID: id,
                startedAt: Date(timeIntervalSince1970: day * 86_400),
                endedAt: Date(timeIntervalSince1970: day * 86_400 + 3600),
                durationSeconds: 3600, endingProgress: progress, wordCount: 100_000,
                didFinish: finished
            )
        }
        let c = row(3, 1.0, finished: true), a = row(1, 0.1), b = row(2, 0.4)
        let d = row(4, 0.2), e = row(5, 0.1), f = row(6, 0.3), x = row(1, 0.05, of: UUID())
        let read = ReadingLogService.wordsRead(sessions: [c, a, b, d, e, f, x], works: [])
        // A reread starts from the beginning (d); going back reads nothing (e).
        #expect([a, b, c, d, e, f, x].map { read[$0.id] } == [10_000, 30_000, 60_000, 20_000, 0, 20_000, 5_000])
        #expect(ReadingLogService.wordsPerHour(sessions: [a, b], works: []) == 20_000)
    }

    @Test func wipGrowthCreditsOnlyTheNewWordsAfterCatchingUp() {
        let work = UUID()
        let caughtUp = ReadingSession(
            workID: work,
            startedAt: Date(timeIntervalSince1970: 86_400),
            endedAt: Date(timeIntervalSince1970: 86_400 + 3600),
            durationSeconds: 3600,
            endingProgress: 1.0,
            wordCount: 10_000,
            didFinish: false
        )
        let newChapters = ReadingSession(
            workID: work,
            startedAt: Date(timeIntervalSince1970: 2 * 86_400),
            endedAt: Date(timeIntervalSince1970: 2 * 86_400 + 1800),
            durationSeconds: 1800,
            endingProgress: 1.0,
            wordCount: 14_000,
            didFinish: false
        )
        let read = ReadingLogService.wordsRead(sessions: [caughtUp, newChapters], works: [])
        #expect(read[caughtUp.id] == 10_000)
        #expect(read[newChapters.id] == 4_000)
    }

    @Test func wipGrowthCreditsOnlyTheNewWordsAfterAFinishedSitting() {
        let work = UUID()
        let finishedEarlier = ReadingSession(
            workID: work,
            startedAt: Date(timeIntervalSince1970: 86_400),
            endedAt: Date(timeIntervalSince1970: 86_400 + 3600),
            durationSeconds: 3600,
            endingProgress: 1.0,
            wordCount: 10_000,
            didFinish: true
        )
        let newChapters = ReadingSession(
            workID: work,
            startedAt: Date(timeIntervalSince1970: 2 * 86_400),
            endedAt: Date(timeIntervalSince1970: 2 * 86_400 + 1800),
            durationSeconds: 1800,
            endingProgress: 1.0,
            wordCount: 14_000,
            didFinish: true
        )
        let read = ReadingLogService.wordsRead(sessions: [finishedEarlier, newChapters], works: [])
        #expect(read[finishedEarlier.id] == 10_000)
        #expect(read[newChapters.id] == 4_000)
    }

    @Test func sittingWithStartProgressUsesItAndWithoutFallsBackToPreviousSitting() {
        let work = UUID()
        let withExplicitStart = ReadingSession(
            workID: work,
            startedAt: Date(timeIntervalSince1970: 86_400),
            endedAt: Date(timeIntervalSince1970: 86_400 + 1800),
            durationSeconds: 1800,
            startProgress: 0.25,
            endingProgress: 0.60,
            wordCount: 10_000
        )
        let withoutExplicitStart = ReadingSession(
            workID: work,
            startedAt: Date(timeIntervalSince1970: 2 * 86_400),
            endedAt: Date(timeIntervalSince1970: 2 * 86_400 + 1800),
            durationSeconds: 1800,
            startProgress: nil,
            endingProgress: 0.85,
            wordCount: 10_000
        )
        let jumpedAhead = ReadingSession(
            workID: work,
            startedAt: Date(timeIntervalSince1970: 3 * 86_400),
            endedAt: Date(timeIntervalSince1970: 3 * 86_400 + 900),
            durationSeconds: 900,
            startProgress: 0.90,
            endingProgress: 1.0,
            wordCount: 10_000
        )
        let read = ReadingLogService.wordsRead(
            sessions: [withExplicitStart, withoutExplicitStart, jumpedAhead],
            works: []
        )
        #expect(read[withExplicitStart.id] == 3_500)
        #expect(read[withoutExplicitStart.id] == 2_500)
        #expect(read[jumpedAhead.id] == 1_000)
    }

    @Test func rereadMovingBackThenForwardNeverCreditsNegativeWords() {
        let work = UUID()
        let first = ReadingSession(
            workID: work,
            startedAt: Date(timeIntervalSince1970: 86_400),
            endedAt: Date(timeIntervalSince1970: 86_400 + 1800),
            durationSeconds: 1800,
            startProgress: 0.0,
            endingProgress: 0.70,
            wordCount: 10_000
        )
        let movedBack = ReadingSession(
            workID: work,
            startedAt: Date(timeIntervalSince1970: 2 * 86_400),
            endedAt: Date(timeIntervalSince1970: 2 * 86_400 + 600),
            durationSeconds: 600,
            startProgress: 0.70,
            endingProgress: 0.20,
            wordCount: 10_000
        )
        let movedForward = ReadingSession(
            workID: work,
            startedAt: Date(timeIntervalSince1970: 3 * 86_400),
            endedAt: Date(timeIntervalSince1970: 3 * 86_400 + 1800),
            durationSeconds: 1800,
            startProgress: nil,
            endingProgress: 0.50,
            wordCount: 12_000
        )
        let read = ReadingLogService.wordsRead(sessions: [first, movedBack, movedForward], works: [])
        #expect(read[first.id] == 7_000)
        #expect(read[movedBack.id] == 0)
        #expect(read[movedForward.id] == 4_000)
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

    @Test func boundedTimelineAndHomeMatchFullLogAcrossWeekEdges() throws {
        let context = try context()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        calendar.firstWeekday = 2
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let week = try #require(calendar.dateInterval(of: .weekOfYear, for: now))
        let reread = SavedWork(title: "Reread", author: "A")
        reread.chapters = "5/5"
        reread.wordCount = 10_000
        reread.chapterWordCounts = [1_000, 2_000, 3_000, 4_000]
        let other = SavedWork(title: "Other visible work", author: "A")
        let excluded = SavedWork(title: "Excluded", author: "A")
        for work in [reread, other, excluded] { context.insert(work) }
        let deletedID = UUID()

        @discardableResult
        func insert(_ id: UUID, at start: Date, seconds: Double = 300,
                    progress: Double = 0, startProgress: Double? = nil, finished: Bool = false,
                    words: Int = 0, chapters: Int = 0) -> ReadingSession {
            let row = ReadingSession(
                workID: id, startedAt: start, endedAt: start.addingTimeInterval(seconds),
                durationSeconds: seconds, startProgress: startProgress, endingProgress: progress,
                wordCount: words, chapterCountAtVisit: chapters, didFinish: finished
            )
            context.insert(row)
            return row
        }

        for day in -2...5 {
            let start = try #require(calendar.date(byAdding: .day, value: day, to: week.start))
            if day == -1 {
                insert(reread.id, at: start, progress: 1, finished: true, words: 10_000, chapters: 5)
            } else if day == 0 {
                insert(reread.id, at: start, progress: 0.25, words: 10_000, chapters: 5)
            } else {
                insert(other.id, at: start)
            }
        }
        let beforeStreak = try #require(calendar.date(byAdding: .day, value: -3, to: week.start))
        insert(deletedID, at: beforeStreak)
        insert(excluded.id, at: beforeStreak)
        insert(deletedID, at: now, finished: true)
        insert(excluded.id, at: now, finished: true)
        let acrossMidnight = insert(
            reread.id, at: week.end.addingTimeInterval(-300), seconds: 900,
            progress: 0.75, startProgress: 0, words: 10_000, chapters: 5
        )
        // This visit validates the EPUB's chapter counts for earlier visits.
        let atEnd = insert(reread.id, at: week.end, progress: 1, finished: true, words: 10_000, chapters: 4)
        try context.save()

        let all = try context.fetch(FetchDescriptor<ReadingSession>())
        let works = [reread, other]
        let visible = all.filter { [reread.id, other.id].contains($0.workID) }
        let fullFacts = ReadingLogService.facts(from: visible, works: works)
        let full = ReadingHistoryTimeline.make(
            scope: .week, containing: now, facts: fullFacts, now: now, calendar: calendar
        )
        let bounded = try ReadingHistoryTimeline.make(
            scope: .week, containing: now, works: works, in: context, now: now, calendar: calendar
        )
        let sittings = bounded.days.flatMap(\.sittings)
        #expect(bounded == full)
        #expect(bounded.streakDays == 9)
        #expect(bounded.wordsRead == 7_500)
        #expect(sittings.first { $0.id == acrossMidnight.id }?.readThrough == 2)
        #expect(sittings.first { $0.id == acrossMidnight.id }?.durationSeconds == 900)
        #expect(!sittings.contains { $0.id == atEnd.id || $0.workID == deletedID || $0.workID == excluded.id })

        let homeFacts = ReadingLogService.facts(
            from: all.sorted { $0.startedAt > $1.startedAt }, works: [reread, other, excluded]
        )
        let home = try HomeReadingStats.calculate(in: context, now: now, calendar: calendar)
        #expect(home == HomeReadingStats.calculate(facts: homeFacts, now: now, calendar: calendar))
        #expect(home.streakDays == 10)
        #expect(home.finishedCount == 3)
    }

    /// A streak longer than several lookback windows (7, 14, 28 … days) still counts every day, and stops at the gap.
    @Test func boundedStreakCrossesManyLookbackWindows() throws {
        let context = try context()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let work = SavedWork(title: "Daily", author: "A")
        context.insert(work)
        for back in 0..<40 {
            let start = try #require(calendar.date(byAdding: .day, value: -back, to: now))
            context.insert(ReadingSession(
                workID: work.id, startedAt: start, endedAt: start.addingTimeInterval(300), durationSeconds: 300,
                startProgress: nil, endingProgress: 0, wordCount: 0, chapterCountAtVisit: 0, didFinish: false
            ))
        }
        // A day off, then older reading that must not join the streak.
        let older = try #require(calendar.date(byAdding: .day, value: -45, to: now))
        context.insert(ReadingSession(
            workID: work.id, startedAt: older, endedAt: older.addingTimeInterval(300), durationSeconds: 300,
            startProgress: nil, endingProgress: 0, wordCount: 0, chapterCountAtVisit: 0, didFinish: false
        ))
        try context.save()
        let bounded = try ReadingLogService.streak(through: now, isToday: true, calendar: calendar, in: context)
        let facts = ReadingLogService.facts(from: try context.fetch(FetchDescriptor<ReadingSession>()), works: [work])
        #expect(bounded == 40)
        #expect(bounded == ReadingHistoryTimeline.streak(through: now, isToday: true, facts: facts, calendar: calendar))
    }

    @Test func homeStatsMatchFullLogAfterSessionSaves() throws {
        let context = try context()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.firstWeekday = 2
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 12)))
        let week = try #require(calendar.dateInterval(of: .weekOfYear, for: now))
        let workID = UUID()
        let start = week.start
        let current = ReadingSession(
            workID: workID, startedAt: start, endedAt: start.addingTimeInterval(120), durationSeconds: 120
        )
        let previous = ReadingSession(
            workID: workID, startedAt: start.addingTimeInterval(-600), endedAt: start, durationSeconds: 600
        )
        context.insert(previous)
        context.insert(current)
        try context.save()

        func fullStats() throws -> HomeReadingStats {
            let all = try context.fetch(FetchDescriptor<ReadingSession>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            ))
            return HomeReadingStats.calculate(
                facts: ReadingLogService.facts(from: all, works: []), now: now, calendar: calendar
            )
        }

        let initial = try HomeReadingStats.calculate(in: context, now: now, calendar: calendar)
        let initialFull = try fullStats()
        #expect(initial == initialFull)
        #expect(initial.streakDays == 2)

        // The same rows can change figures without changing their modification dates.
        current.durationSeconds = 600
        current.didFinish = true
        context.delete(previous)
        try context.save()
        let refreshed = try HomeReadingStats.calculate(in: context, now: now, calendar: calendar)
        let refreshedFull = try fullStats()
        #expect(refreshed == refreshedFull)
        #expect(refreshed == HomeReadingStats(durationSeconds: 600, finishedCount: 1, streakDays: 1))
    }

    @Test func historyPeriodsAndOffTimelineRowsMatchFullLog() throws {
        let context = try context()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.firstWeekday = 2
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 12)))
        let active = SavedWork(title: "Reread", author: "A")
        let older = SavedWork(title: "Read last year", author: "B")
        let abandoned = SavedWork(title: "Abandoned", author: "C")
        let unlogged = SavedWork(title: "No sessions", author: "D")
        let excluded = SavedWork(title: "Outside the filter", author: "E")
        let works = [active, older, abandoned, unlogged]
        for work in works + [excluded] { context.insert(work) }

        func insert(_ work: SavedWork, daysAgo: Int, finished: Bool = false) throws {
            let start = try #require(calendar.date(byAdding: .day, value: -daysAgo, to: now))
            context.insert(ReadingSession(
                workID: work.id, startedAt: start, endedAt: start.addingTimeInterval(300), durationSeconds: 300,
                endingProgress: finished ? 1 : 0.5, wordCount: 4_000, chapterCountAtVisit: 4, didFinish: finished
            ))
        }

        try insert(active, daysAgo: 5, finished: true)
        try insert(active, daysAgo: 1)
        try insert(older, daysAgo: 400)
        try insert(abandoned, daysAgo: 60)
        try insert(abandoned, daysAgo: 31)
        try insert(excluded, daysAgo: 0)
        try context.save()

        let visibleIDs = Set(works.map(\.id))
        let all = try context.fetch(FetchDescriptor<ReadingSession>())
        let fullFacts = ReadingLogService.facts(
            from: all.filter { visibleIDs.contains($0.workID) }, works: works
        )
        for scope in ReadingHistoryScope.allCases {
            let previous = try #require(calendar.date(byAdding: scope.component, value: -1, to: now))
            for anchor in [now, previous] {
                let full = ReadingHistoryTimeline.make(
                    scope: scope, containing: anchor, facts: fullFacts, now: now, calendar: calendar
                )
                let bounded = try ReadingHistoryTimeline.make(
                    scope: scope, containing: anchor, works: works, in: context, now: now, calendar: calendar
                )
                #expect(bounded == full)
            }
        }

        let offTimeline = try ReadingHistoryTimeline.OffTimeline.load(
            visibleWorkIDs: visibleIDs, abandonedWorkIDs: [abandoned.id], in: context
        )
        let fullSummaries = ReadingLogService.summaries(in: context)
        let fullUnlogged = visibleIDs.filter { $0 != abandoned.id && fullSummaries[$0] == nil }
        #expect(offTimeline.unloggedWorkIDs == fullUnlogged)
        #expect(offTimeline.unloggedWorkIDs == [unlogged.id])
        #expect(offTimeline.summaries == fullSummaries.filter { $0.key == abandoned.id })
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
