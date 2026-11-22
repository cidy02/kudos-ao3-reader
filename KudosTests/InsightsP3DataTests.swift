import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-536 (Insights data P3): D7 time on each chapter, D8 where a work came from, D9 kudos and
/// hits when saved, D10 chapter update events, D11 your own AO3 actions. Backup round trips are
/// in `InsightsP3BackupTests` (PersistenceGateSuites).
@MainActor
@Suite(.serialized)
struct InsightsP3DataTests {
    private func context() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self,
            ChapterUpdateEvent.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func summary(_ id: Int, kudos: Int? = nil, hits: Int? = nil, chapters: String = "1/1") -> AO3WorkSummary {
        AO3WorkSummary(
            id: id, title: "Work \(id)", authors: ["Writer"], fandoms: ["Fandom"],
            rating: "Teen And Up Audiences", warnings: [], categories: [],
            isComplete: true, dateUpdated: "2026-11-16", tags: [], summary: "Summary",
            language: "English", words: 100, chapters: chapters, comments: nil,
            kudos: kudos, hits: hits, seriesTitle: nil, seriesURL: nil, seriesPosition: nil
        )
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: D7 pure rules

    @Test func medianPaceNeedsTwentyChaptersOfHistory() {
        let sample = ChapterTiming.PaceSample(words: 3_000, seconds: 600) // 5 words a second
        #expect(ChapterTiming.medianWordsPerSecond(Array(repeating: sample, count: 19)) == nil)
        #expect(ChapterTiming.medianWordsPerSecond(Array(repeating: sample, count: 20)) == 5)
        // Samples with no words or no time are not history.
        let unusable = Array(repeating: ChapterTiming.PaceSample(words: 0, seconds: 10), count: 10)
        #expect(ChapterTiming.medianWordsPerSecond(Array(repeating: sample, count: 19) + unusable) == nil)
    }

    @Test func skimmedNeedsThreeHundredWordsAndUnderHalfTheTimeThePaceNeeds() {
        // 5 words a second: 3,000 words needs 600 s, so under 300 s is skimmed.
        let words = [4: 3_000, 5: 3_000, 6: 299, 7: 3_000]
        let seconds: [Int: Double] = [4: 299, 5: 300, 6: 1, 7: 600]
        #expect(ChapterTiming.skimmedChapters(seconds: seconds, words: words, medianWordsPerSecond: 5) == [4])
        // No pace yet: nothing is called skimmed.
        #expect(ChapterTiming.skimmedChapters(seconds: seconds, words: words, medianWordsPerSecond: nil).isEmpty)
        // A chapter never timed counts as zero seconds: skimmed, not skipped.
        #expect(ChapterTiming.skimmedChapters(seconds: [:], words: [9: 400], medianWordsPerSecond: 1) == [9])
    }

    @Test func aSkimmedChapterDoesNotFeedThePace() {
        let samples = ChapterTiming.paceSamples(
            seconds: [1: 100, 2: 5, 3: 80], words: [1: 500, 2: 500, 3: 400], skimmed: [2]
        )
        #expect(samples.map(\.words) == [500, 400])
    }

    @Test func endingAndPeekRules() {
        #expect(ChapterTiming.endedAtChapterEnd(chapterFraction: 0.95) == true)
        #expect(ChapterTiming.endedAtChapterEnd(chapterFraction: 0.94) == false)
        #expect(ChapterTiming.endedAtChapterEnd(chapterFraction: nil) == nil)
        // A jump from chapter 2 of 10 to the last chapter is a peek; reading on is not; the
        // second half is not; a short work is not.
        #expect(ChapterTiming.isPeek(toStoryChapter: 10, fromStoryChapter: 2, totalStoryChapters: 10, startProgress: 0))
        #expect(!ChapterTiming.isPeek(toStoryChapter: 10, fromStoryChapter: 9, totalStoryChapters: 10, startProgress: 0))
        #expect(!ChapterTiming.isPeek(toStoryChapter: 10, fromStoryChapter: 6, totalStoryChapters: 10, startProgress: 0))
        #expect(!ChapterTiming.isPeek(toStoryChapter: 10, fromStoryChapter: 2, totalStoryChapters: 10, startProgress: 0.6))
        #expect(!ChapterTiming.isPeek(toStoryChapter: 2, fromStoryChapter: 1, totalStoryChapters: 2, startProgress: 0))
    }

    @Test func chapterJSONRoundTripsAndRejectsDamage() {
        let seconds: [Int: Double] = [3: 41.5, 4: 120]
        let json = ChapterTiming.encode(seconds)
        #expect(json == "{\"3\":41.5,\"4\":120}")
        #expect(ChapterTiming.decodeDoubles(json) == seconds)
        #expect(ChapterTiming.encode([Int: Double]()) == nil)
        #expect(ChapterTiming.encode(list: []) == "[]")
        #expect(ChapterTiming.decodeList("[5,2,2]") == [2, 5])
        #expect(ChapterTiming.decodeDoubles("{\"3\":-1,\"x\":2}").isEmpty)
        #expect(!ChapterTiming.isValidSeconds("[1]"))
        #expect(!ChapterTiming.isValidWords("{\"1\":\"a\"}"))
        #expect(ChapterTiming.isValidList("[]"))
    }

    // MARK: D7 recording

    private func chapter(_ spine: Int) -> ReadingLogService.ChapterPosition {
        ReadingLogService.ChapterPosition(spineIndex: spine, storyChapter: spine - 1)
    }

    /// A 12-chapter work, one story chapter per spine item after a preface (spine 0).
    private func longWork(in context: ModelContext, wordsPerChapter: Int = 3_000) -> SavedWork {
        let work = SavedWork(title: "Long", author: "A")
        work.chapters = "12/12"
        work.chapterWordCounts = Array(repeating: wordsPerChapter, count: 12)
        work.wordUnitRaw = SavedWork.WordUnit.words.rawValue
        context.insert(work)
        return work
    }

    /// Reads spine items `range` one after another, `secondsPerChapter` in each, one sitting.
    private func readSitting(
        _ work: SavedWork, spines: ClosedRange<Int>, secondsPerChapter: Double, from start: Date
    ) {
        var clock = start
        ReadingLogService.startSession(for: work, now: clock)
        ReadingLogService.noteActivity(for: work, chapter: chapter(spines.lowerBound), now: clock.addingTimeInterval(1))
        clock = clock.addingTimeInterval(1)
        for spine in spines.dropFirst() {
            clock = clock.addingTimeInterval(secondsPerChapter)
            ReadingLogService.noteActivity(for: work, chapter: chapter(spine), now: clock)
        }
        ReadingLogService.endSession(for: work, now: clock.addingTimeInterval(1))
    }

    @Test func aSittingRecordsSecondsInEachChapterAndOnlyInteriorOnesAreMeasuredWhole() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = longWork(in: context)
        // 1 s to reach the first report, then 200 s per chapter through spine 2...5.
        readSitting(work, spines: 2 ... 5, secondsPerChapter: 200, from: t0)
        let session = try #require(try context.fetch(FetchDescriptor<ReadingSession>()).first)
        // Time before a move belongs to the chapter being left: 2, 3 and 4 get 200 each
        // (the first report's own second goes to spine 2), 5 has the closing second only.
        #expect(session.chapterSeconds[3] == 200)
        #expect(session.chapterSeconds[4] == 200)
        #expect((session.chapterSeconds[2] ?? 0) >= 200)
        // Spines 3 and 4 were entered from the one before and left for the next.
        #expect(Set(session.chapterWords.keys) == [3, 4])
        #expect(session.chapterWords[3] == 3_000)
        // Judgement was stored even though nothing could be skimmed without history.
        #expect(session.skimmedChaptersJSON == "[]")
        #expect(session.peekedAtEnding == false)
    }

    @Test func aSittingWithNoChapterSignalStoresNothing() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = longWork(in: context)
        ReadingLogService.startSession(for: work, now: t0)
        ReadingLogService.noteActivity(for: work, now: t0.addingTimeInterval(60))
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(90))
        let session = try #require(try context.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(session.chapterSecondsJSON == nil)
        #expect(session.chapterWordsJSON == nil)
        #expect(session.skimmedChaptersJSON == nil)
        #expect(session.endedAtChapterEnd == nil)
        #expect(session.peekedAtEnding == nil)
    }

    @Test func skimIsJudgedOnceFromPriorPaceAndStaysWhenPaceChanges() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = longWork(in: context)
        // Twenty earlier chapters at 5 words a second (3,000 words in 600 s).
        let history = ReadingSession(
            workID: work.id, startedAt: t0.addingTimeInterval(-90_000),
            endedAt: t0.addingTimeInterval(-80_000), durationSeconds: 12_000, modeRaw: "read"
        )
        var seconds: [Int: Double] = [:]
        var words: [Int: Int] = [:]
        for spine in 1 ... 20 {
            seconds[spine] = 600
            words[spine] = 3_000
        }
        history.chapterSeconds = seconds
        history.chapterWords = words
        history.skimmedChapters = []
        context.insert(history)

        // The new sitting spends 100 s in each of its interior chapters: under half of 600 s.
        readSitting(work, spines: 2 ... 6, secondsPerChapter: 100, from: t0)
        let fresh = try #require(try context.fetch(FetchDescriptor<ReadingSession>()).first { $0.id != history.id })
        #expect(fresh.skimmedChapters == [3, 4, 5])
        let skimmedAtSave = fresh.skimmedChapters

        // The reader slows down afterwards: a past sitting is never re-judged.
        history.chapterSeconds = seconds.mapValues { _ in 30 }
        try context.save()
        #expect(fresh.skimmedChapters == skimmedAtSave)
    }

    @Test func listenedSittingsAndCharacterWorksAreNeverJudged() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let listened = longWork(in: context)
        ReadingLogService.startSession(for: listened, mode: .listen, playbackRate: 1, now: t0)
        ReadingLogService.noteActivity(for: listened, chapter: chapter(2), now: t0.addingTimeInterval(1))
        ReadingLogService.noteActivity(for: listened, chapter: chapter(3), now: t0.addingTimeInterval(200))
        ReadingLogService.noteActivity(for: listened, chapter: chapter(4), now: t0.addingTimeInterval(400))
        ReadingLogService.endSession(for: listened, now: t0.addingTimeInterval(401))
        let listenRow = try #require(try context.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(listenRow.chapterSecondsJSON != nil)
        #expect(listenRow.skimmedChaptersJSON == nil)
        #expect(listenRow.chapterWordsJSON == nil)

        let characters = longWork(in: context)
        characters.wordUnitRaw = SavedWork.WordUnit.characters.rawValue
        readSitting(characters, spines: 2 ... 5, secondsPerChapter: 200, from: t0.addingTimeInterval(1_000))
        let row = try #require(try context.fetch(FetchDescriptor<ReadingSession>()).first { $0.workID == characters.id })
        #expect(row.skimmedChaptersJSON == nil)
    }

    @Test func jumpingToTheLastChapterFromTheStartIsAPeek() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = longWork(in: context)
        ReadingLogService.startSession(for: work, now: t0)
        ReadingLogService.noteActivity(for: work, chapter: chapter(2), now: t0.addingTimeInterval(20))
        ReadingLogService.noteActivity(for: work, chapter: chapter(13), now: t0.addingTimeInterval(80))
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(100))
        let session = try #require(try context.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(session.peekedAtEnding == true)
    }

    @Test func aSittingEndsOnAChapterWhenTheSavedPositionIsAtItsEnd() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = longWork(in: context)
        work.readiumLocator = "{\"href\":\"c3.xhtml\",\"locations\":{\"progression\":0.97,\"totalProgression\":0.3}}"
        readSitting(work, spines: 2 ... 4, secondsPerChapter: 30, from: t0)
        let row = try #require(try context.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(row.endedAtChapterEnd == true)
    }

    // MARK: D8

    @Test func importSourceIsSetOnceAndUnknownPathsRecordUnknown() {
        let work = SavedWork(title: "A", author: "B")
        #expect(work.importSource == nil)
        #expect(work.recordImportSource(.series, at: t0))
        #expect(!work.recordImportSource(.search, at: t0.addingTimeInterval(5)))
        #expect(work.importSource == .series)
        #expect(work.importSourceSince == t0)

        let unknownPath = SavedWork(title: "C", author: "D")
        unknownPath.recordImportSource(nil, at: t0)
        #expect(unknownPath.importSource == .unknown)
        #expect(unknownPath.importSourceSince == t0)

        // A raw string this build has no case for reads as unknown, and stays as written.
        let future = SavedWork(title: "E", author: "F")
        future.importSourceRaw = "carrierPigeon"
        #expect(future.importSource == .unknown)
        #expect(future.importSourceRaw == "carrierPigeon")
    }

    @Test func aQueueOriginMapsOntoTheSameFact() {
        #expect(WorkImportSource(origin: ReadingQueueMembershipOrigin(kind: .search, label: "Q")) == .search)
        #expect(WorkImportSource(origin: ReadingQueueMembershipOrigin(kind: .source)) == .search)
        #expect(WorkImportSource(origin: ReadingQueueMembershipOrigin(kind: .link)) == .pastedLink)
        #expect(WorkImportSource(origin: ReadingQueueMembershipOrigin(kind: .manual)) == nil)
        #expect(WorkImportSource(origin: nil) == nil)
        #expect(Set(WorkImportSource.allCases.map(\.rawValue)).count == WorkImportSource.allCases.count)
    }

    @Test func aWorkMadeFromABlurbRecordsItsSourceAndItsFigures() throws {
        let context = try context()
        let blurb = summary(7, kudos: 310, hits: 4_000)
        let work = try ReadingQueueService.ensureLocalMetadata(
            for: blurb, importSource: .fandom, in: context
        )
        #expect(work.importSource == .fandom)
        #expect(work.kudosAtSave == 310)
        #expect(work.hitsAtSave == 4_000)
        #expect(work.statsSavedAt != nil)
        // The same blurb again, as a refresh would bring it, changes nothing.
        let again = try ReadingQueueService.ensureLocalMetadata(
            for: summary(7, kudos: 1_530, hits: 9_000), importSource: .search, in: context
        )
        #expect(again.id == work.id)
        #expect(again.importSource == .fandom)
        #expect(again.kudosAtSave == 310)
    }

    @Test func aUserImportRecordsTheFileOrShareSheetPath() async throws {
        let context = try context()
        let outcome = try await importUserEPUB(
            try EPUBTests.sampleEPUB, importSource: .shareSheet, into: context
        )
        #expect(outcome.work.importSource == .shareSheet)
        // A duplicate arriving by another path does not rewrite how the first copy came.
        let second = try await importUserEPUB(try EPUBTests.sampleEPUB, into: context)
        #expect(second.work.id == outcome.work.id)
        #expect(second.work.importSource == .shareSheet)
        let plain = SavedWork(title: "P", author: "Q")
        plain.recordImportSource(.fileImport)
        #expect(plain.importSource == .fileImport)
    }

    // MARK: D9

    @Test func statsAtSaveAreWrittenOnceWithTheAgeFromThePostingDate() {
        let work = SavedWork(title: "A", author: "B")
        work.datePublished = "2026-11-01"
        let savedAt = ISO8601DateFormatter().date(from: "2026-11-11T12:00:00Z") ?? t0
        work.dateAdded = savedAt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        #expect(work.recordStatsAtSave(
            WorkStatsAtSave(kudos: 310, hits: 4_000, bookmarks: 12, fandomWorks: 9_000),
            at: savedAt, calendar: calendar
        ))
        #expect(work.kudosAtSave == 310)
        #expect(work.hitsAtSave == 4_000)
        #expect(work.bookmarksAtSave == 12)
        #expect(work.fandomWorksAtSave == 9_000)
        #expect(work.ageDaysAtSave == 10)
        // A second write, or an empty one, changes nothing.
        #expect(!work.recordStatsAtSave(WorkStatsAtSave(kudos: 999, hits: 1, bookmarks: 1, fandomWorks: nil)))
        #expect(work.kudosAtSave == 310)
        let empty = SavedWork(title: "C", author: "D")
        #expect(!empty.recordStatsAtSave(WorkStatsAtSave(kudos: nil, hits: nil, bookmarks: nil, fandomWorks: nil)))
        #expect(empty.statsSavedAt == nil)
    }

    @Test func aRefreshAfterTheSaveWindowNeverBecomesTheFiguresAtSave() {
        let fresh = SavedWork(title: "Fresh", author: "A")
        fresh.recordImportSource(.search, at: t0)
        fresh.dateAdded = t0
        #expect(fresh.recordStatsAtSaveIfJustSaved(
            kudos: 12, hits: 300, bookmarks: nil, now: t0.addingTimeInterval(60)
        ))
        #expect(fresh.kudosAtSave == 12)
        #expect(fresh.bookmarksAtSave == nil)

        let old = SavedWork(title: "Old", author: "A")
        old.recordImportSource(.search, at: t0)
        old.dateAdded = t0
        let later = t0.addingTimeInterval(SavedWork.saveStatsWindow + 1)
        #expect(!old.recordStatsAtSaveIfJustSaved(kudos: 5_000, hits: 90_000, bookmarks: 10, now: later))
        #expect(old.kudosAtSave == nil)
        #expect(old.statsSavedAt == nil)

        // Written once: a second refresh inside the window leaves it.
        #expect(!fresh.recordStatsAtSaveIfJustSaved(
            kudos: 40, hits: 900, bookmarks: nil, now: t0.addingTimeInterval(120)
        ))
        #expect(fresh.kudosAtSave == 12)
    }

    @Test func theAgeArrivesWithTheWorkPageAndTouchesNothingElse() {
        let work = SavedWork(title: "A", author: "B")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let savedAt = ISO8601DateFormatter().date(from: "2026-11-11T12:00:00Z") ?? t0
        work.dateAdded = savedAt
        work.recordStatsAtSave(WorkStatsAtSave(kudos: 5, hits: 50, bookmarks: nil, fandomWorks: nil), at: savedAt, calendar: calendar)
        #expect(work.ageDaysAtSave == nil)
        #expect(!work.completeAgeAtSave(calendar: calendar))
        work.datePublished = "2026-10-12"
        #expect(work.completeAgeAtSave(calendar: calendar))
        #expect(work.ageDaysAtSave == 30)
        #expect(work.kudosAtSave == 5)
        work.datePublished = "2020-01-01"
        #expect(!work.completeAgeAtSave(calendar: calendar))
        #expect(work.ageDaysAtSave == 30)
    }

    // MARK: D10

    @Test func aRiseInPostedChaptersWritesOneEventAndNothingElseDoes() throws {
        let context = try context()
        let work = SavedWork(title: "WIP", author: "A")
        work.chapters = "3/?"
        work.rating = "Mature"
        context.insert(work)
        // First sight is a baseline, and a count that did not rise is nothing.
        #expect(ChapterUpdateRecorder.recordRise(for: work, previousPosted: 0, newPosted: 3, in: context) == nil)
        #expect(ChapterUpdateRecorder.recordRise(for: work, previousPosted: 3, newPosted: 3, in: context) == nil)
        #expect(ChapterUpdateRecorder.recordRise(for: work, previousPosted: 4, newPosted: 3, in: context) == nil)

        let event = try #require(ChapterUpdateRecorder.recordRise(
            for: work, previousPosted: 3, newPosted: 6, postedDate: " 2026-11-12 ", at: t0, in: context
        ))
        #expect(event.firstNewChapter == 4)
        #expect(event.chapterCount == 6)
        #expect(event.postedDate == "2026-11-12")
        #expect(event.rating == "Mature")
        // The same chapters seen by a second check are not a second event.
        #expect(ChapterUpdateRecorder.recordRise(for: work, previousPosted: 3, newPosted: 6, in: context) == nil)
        // A later rise adds only its own tail.
        let tail = try #require(ChapterUpdateRecorder.recordRise(
            for: work, previousPosted: 3, newPosted: 8, at: t0.addingTimeInterval(86_400), in: context
        ))
        #expect(tail.previousChapterCount == 6)
        #expect(try context.fetch(FetchDescriptor<ChapterUpdateEvent>()).count == 2)
    }

    @Test func theUpdateCheckWritesTheEventFromItsOwnFetchOnly() async throws {
        let context = try context()
        let work = SavedWork(title: "WIP", author: "A", sourceURL: "https://archiveofourown.org/works/77")
        work.ao3WorkID = 77
        work.isSaved = true
        work.chapters = "3/?"
        work.knownChapterCount = 3
        context.insert(work)
        var requested: [Int] = []
        await WorkUpdateChecker.checkForUpdates(among: [work], in: context, fetchTags: { id in
            await MainActor.run { requested.append(id) }
            var groups = AO3WorkTagGroups()
            groups.fandoms = ["Fandom"]
            groups.chapters = "5/?"
            return groups
        })
        #expect(requested == [77])
        let events = try context.fetch(FetchDescriptor<ChapterUpdateEvent>())
        #expect(events.count == 1)
        #expect(events.first?.previousChapterCount == 3)
        #expect(events.first?.chapterCount == 5)
        #expect(events.first?.workID == work.id)
        #expect(events.first?.postedDate == "")
    }

    private func posting(_ day: String) throws -> Date {
        try #require(WorkStat.date(from: day))
    }

    private func reading(
        _ workID: UUID, at start: Date, highest: Int?, visit: Int, mode: String = "read"
    ) -> ReadingSession {
        let session = ReadingSession(
            workID: workID, startedAt: start, endedAt: start.addingTimeInterval(1_800),
            durationSeconds: 1_800, modeRaw: mode, chapterCountAtVisit: visit
        )
        session.highestStoryChapter = highest
        return session
    }

    @Test func eachNewChapterIsResolvedOnItsOwnFromTheHighestChapterReached() throws {
        let workID = UUID()
        let posted = try posting("2026-11-10")
        let event = ChapterUpdateEvent(
            workID: workID, chapterCount: 6, previousChapterCount: 3,
            detectedAt: posted.addingTimeInterval(20 * 3_600), postedDate: "2026-11-10"
        )
        // Reaches chapter 4 two days later; chapters 5 and 6 are still unread.
        let sittings = [reading(workID, at: posted.addingTimeInterval(2 * 86_400), highest: 4, visit: 6)]
        let figure = InsightsProvenance.newChapters(events: [event], sessions: sittings)
        #expect(figure.entries.map(\.chapter) == [4, 5, 6])
        #expect(abs((figure.entries[0].delay ?? 0) - 2 * 86_400) < 1)
        #expect(figure.entries[1].state == .unread)
        #expect(figure.entries[2].state == .unread)
        #expect(figure.unreadChapters == 2)
        #expect(figure.unknownChapters == 0)
        #expect(abs((figure.medianDelay ?? 0) - 2 * 86_400) < 1)
    }

    @Test func aLongFirstChapterIsNotMistakenForReachingALaterOne() throws {
        let workID = UUID()
        let posted = try posting("2026-11-10")
        let event = ChapterUpdateEvent(
            workID: workID, chapterCount: 6, previousChapterCount: 3, detectedAt: posted, postedDate: "2026-11-10"
        )
        // 60% through the work, but the highest chapter recorded is 1.
        let sitting = reading(workID, at: posted.addingTimeInterval(3_600), highest: 1, visit: 6)
        sitting.endingProgress = 0.6
        let figure = InsightsProvenance.newChapters(events: [event], sessions: [sitting])
        #expect(figure.unreadChapters == 3)
        #expect(figure.entries.allSatisfy { $0.delay == nil })
    }

    @Test func aSittingWithNoChapterSignalLeavesTheChapterUnknownNotUnread() throws {
        let workID = UUID()
        let posted = try posting("2026-11-10")
        let event = ChapterUpdateEvent(
            workID: workID, chapterCount: 5, previousChapterCount: 4, detectedAt: posted, postedDate: "2026-11-10"
        )
        let figure = InsightsProvenance.newChapters(
            events: [event], sessions: [reading(workID, at: posted.addingTimeInterval(60), highest: nil, visit: 5)]
        )
        #expect(figure.unknownChapters == 1)
        #expect(figure.unreadChapters == 0)
        #expect(figure.entries.first?.state == .unknown)
        #expect(InsightsProvenance.newChapters(events: [event], sessions: []).unreadChapters == 1)
    }

    @Test func overlappingEventsFromTwoDevicesCountEachChapterOnce() throws {
        let workID = UUID()
        let first = ChapterUpdateEvent(
            workID: workID, chapterCount: 5, previousChapterCount: 3, detectedAt: t0
        )
        let second = ChapterUpdateEvent(
            workID: workID, chapterCount: 6, previousChapterCount: 3, detectedAt: t0.addingTimeInterval(60)
        )
        let narrower = ChapterUpdateEvent(
            workID: workID, chapterCount: 6, previousChapterCount: 5, detectedAt: t0.addingTimeInterval(120)
        )
        for order in [[first, second, narrower], [narrower, second, first]] {
            let figure = InsightsProvenance.newChapters(events: order, sessions: [])
            #expect(figure.entries.map(\.chapter) == [4, 5, 6])
            #expect(figure.unreadChapters == 3)
            // Chapters 4 and 5 belong to the earliest sighting, whichever order they arrived in.
            #expect(figure.entries[0].eventID == first.id)
            #expect(figure.entries[2].eventID == second.id)
        }
    }

    @Test func listenedSittingsDoNotCountAsReadingANewChapter() throws {
        let workID = UUID()
        let posted = try posting("2026-11-10")
        let event = ChapterUpdateEvent(
            workID: workID, chapterCount: 5, previousChapterCount: 4, detectedAt: posted, postedDate: "2026-11-10"
        )
        let heard = reading(workID, at: posted.addingTimeInterval(60), highest: 5, visit: 5, mode: "listen")
        #expect(InsightsProvenance.newChapters(events: [event], sessions: [heard]).unreadChapters == 1)
    }

    @Test func aDamagedEventCannotOverflowTheFigure() {
        let workID = UUID()
        let damaged = ChapterUpdateEvent(
            workID: workID, chapterCount: 1, previousChapterCount: Int.min, detectedAt: t0
        )
        let huge = ChapterUpdateEvent(
            workID: workID, chapterCount: Int.max, previousChapterCount: 1, detectedAt: t0
        )
        let figure = InsightsProvenance.newChapters(events: [damaged, huge], sessions: [])
        #expect(figure.entries.isEmpty)
        let sitting = ReadingSession(workID: workID, startedAt: t0, endedAt: t0.addingTimeInterval(60), durationSeconds: 60)
        sitting.chapterWordsJSON = "{\"1\":9223372036854775807,\"2\":1}"
        sitting.skimmedChaptersJSON = "[1,2,2,1]"
        // Out-of-range words are dropped on decode, so the sum cannot overflow.
        let timing = InsightsProvenance.chapterTiming(sessions: [sitting])
        #expect(timing.skimmedChapters == 2)
        #expect(timing.skimmedWords == 1)
    }

    @Test func eventsForAPermanentlyDeletedWorkGoWithIt() throws {
        let context = try context()
        let work = SavedWork(title: "Gone", author: "A")
        work.chapters = "3/?"
        context.insert(work)
        let other = SavedWork(title: "Kept", author: "A")
        other.chapters = "3/?"
        context.insert(other)
        ChapterUpdateRecorder.recordRise(for: work, previousPosted: 3, newPosted: 5, in: context)
        ChapterUpdateRecorder.recordRise(for: other, previousPosted: 3, newPosted: 5, in: context)
        #expect(try context.fetch(FetchDescriptor<ChapterUpdateEvent>()).count == 2)
        // Recently Deleted keeps them so Restore finds them again.
        PreservedWorkService.softDelete(work, in: context)
        #expect(try context.fetch(FetchDescriptor<ChapterUpdateEvent>()).count == 2)
        WorkLifecycle.hardDelete(work, in: context)
        let left = try context.fetch(FetchDescriptor<ChapterUpdateEvent>())
        #expect(left.map(\.workID) == [other.id])
    }

    @Test func aSecondSightingOfTheSameChaptersOnlyAddsThePostingDay() throws {
        let context = try context()
        let work = SavedWork(title: "WIP", author: "A")
        work.chapters = "3/?"
        context.insert(work)
        let first = try #require(ChapterUpdateRecorder.recordRise(
            for: work, previousPosted: 3, newPosted: 5, at: t0, in: context
        ))
        #expect(first.postedDate.isEmpty)
        #expect(ChapterUpdateRecorder.recordRise(
            for: work, previousPosted: 3, newPosted: 5, postedDate: "2026-11-09", at: t0.addingTimeInterval(60), in: context
        ) == nil)
        #expect(first.postedDate == "2026-11-09")
        #expect(first.detectedAt == t0)
        #expect(try context.fetch(FetchDescriptor<ChapterUpdateEvent>()).count == 1)
    }

    @Test func theUpdateCheckCarriesThePostingDayFromItsOwnPage() async throws {
        let context = try context()
        let work = SavedWork(title: "WIP", author: "A", sourceURL: "https://archiveofourown.org/works/78")
        work.ao3WorkID = 78
        work.isSaved = true
        work.chapters = "3/?"
        context.insert(work)
        await WorkUpdateChecker.checkForUpdates(among: [work], in: context, fetchTags: { _ in
            var groups = AO3WorkTagGroups()
            groups.fandoms = ["Fandom"]
            groups.chapters = "4/?"
            groups.dateUpdated = "2026-11-12"
            return groups
        })
        #expect(try context.fetch(FetchDescriptor<ChapterUpdateEvent>()).first?.postedDate == "2026-11-12")
    }

    @Test func aWorksUnratedEarlierEventStaysHiddenOnceALaterOneIsAdult() throws {
        let context = try context()
        let gone = UUID()
        let early = ChapterUpdateEvent(workID: gone, chapterCount: 4, previousChapterCount: 3, detectedAt: t0, rating: "")
        let late = ChapterUpdateEvent(workID: gone, chapterCount: 5, previousChapterCount: 4, detectedAt: t0, rating: "Explicit")
        let locked = HomeReadingStats.insightsScope(.main, from: [], hideMature: true, revealed: false)
        #expect(locked.events([early, late], in: context).isEmpty)
        let revealed = HomeReadingStats.insightsScope(.hidden, from: [], hideMature: true, revealed: true)
        #expect(revealed.events([early, late], in: context).count == 2)
    }

    @Test func skimmedWordsLeaveTheWordsReadTotal() {
        let work = SavedWork(title: "W", author: "A")
        work.chapterWordCounts = [1_000, 1_000]
        work.wordUnitRaw = SavedWork.WordUnit.words.rawValue
        work.wordCount = 2_000
        work.chapters = "2/2"
        let sitting = ReadingSession(
            workID: work.id, startedAt: t0, endedAt: t0.addingTimeInterval(600), durationSeconds: 600,
            startProgress: 0, endingProgress: 1, wordCount: 2_000, chapterCountAtVisit: 2
        )
        #expect(ReadingLogService.wordsRead(sessions: [sitting], works: [work])[sitting.id] == 2_000)
        sitting.chapterWords = [5: 1_000]
        sitting.skimmedChapters = [5]
        sitting.skimmedStoryChapters = [1]
        #expect(ReadingLogService.wordsRead(sessions: [sitting], works: [work])[sitting.id] == 1_000)
        sitting.skimmedChapters = [5, 5]
        sitting.skimmedStoryChapters = [1, 1]
        #expect(ReadingLogService.wordsRead(sessions: [sitting], works: [work])[sitting.id] == 1_000)
    }

    @Test func aPausedAndResumedSittingKeepsTheJudgementItAlreadyMade() throws {
        ReadingLogService.resetOpenSessionsForTests()
        let context = try context()
        let work = longWork(in: context)
        let history = ReadingSession(
            workID: work.id, startedAt: t0.addingTimeInterval(-90_000),
            endedAt: t0.addingTimeInterval(-80_000), durationSeconds: 12_000, modeRaw: "read"
        )
        var seconds: [Int: Double] = [:]
        var words: [Int: Int] = [:]
        for spine in 1 ... 20 { seconds[spine] = 600; words[spine] = 3_000 }
        history.chapterSeconds = seconds
        history.chapterWords = words
        history.skimmedChapters = []
        context.insert(history)

        ReadingLogService.startSession(for: work, now: t0)
        ReadingLogService.noteActivity(for: work, chapter: chapter(2), now: t0.addingTimeInterval(1))
        ReadingLogService.noteActivity(for: work, chapter: chapter(3), now: t0.addingTimeInterval(101))
        ReadingLogService.noteActivity(for: work, chapter: chapter(4), now: t0.addingTimeInterval(201))
        ReadingLogService.noteActivity(for: work, chapter: chapter(5), now: t0.addingTimeInterval(301))
        ReadingLogService.pauseSession(for: work, now: t0.addingTimeInterval(302))
        let row = try #require(try context.fetch(FetchDescriptor<ReadingSession>()).first { $0.id != history.id })
        #expect(row.skimmedChapters == [3, 4])

        // The pace moves while the sitting is backgrounded: chapters 3 and 4 would no longer be skimmed.
        history.chapterSeconds = seconds.mapValues { _ in 20 }
        ReadingLogService.resumeSession(for: work, now: t0.addingTimeInterval(400))
        ReadingLogService.noteActivity(for: work, chapter: chapter(6), now: t0.addingTimeInterval(500))
        ReadingLogService.endSession(for: work, now: t0.addingTimeInterval(501))
        #expect(row.skimmedChapters.contains(3))
        #expect(row.skimmedChapters.contains(4))
        #expect(row.highestStoryChapter == 5)
    }

    @Test func aWorkSavedBeforeRecordingBeganNeverGainsAnAtSaveSnapshot() {
        let legacy = SavedWork(title: "Legacy", author: "A")
        legacy.dateAdded = t0
        // Upgrade five minutes after it was saved: still not eligible, it never recorded a source.
        #expect(!legacy.recordStatsAtSaveIfJustSaved(kudos: 9, hits: 9, bookmarks: 9, now: t0.addingTimeInterval(300)))
        let future = SavedWork(title: "Future", author: "A")
        future.recordImportSource(.search, at: t0)
        future.dateAdded = t0.addingTimeInterval(86_400)
        #expect(!future.recordStatsAtSaveIfJustSaved(kudos: 9, hits: 9, bookmarks: 9, now: t0))
        let edge = SavedWork(title: "Edge", author: "A")
        edge.recordImportSource(.search, at: t0)
        edge.dateAdded = t0
        #expect(edge.recordStatsAtSaveIfJustSaved(
            kudos: 9, hits: 9, bookmarks: 9, now: t0.addingTimeInterval(SavedWork.saveStatsWindow)
        ))
    }

    @Test func aFandomPageNamesItsSourceAndItsLoadedSize() throws {
        let origin = ReadingQueueMembershipOrigin(
            kind: .search, label: "Fandom", importSourceHint: .fandom, fandomWorks: 12_000
        )
        #expect(WorkImportSource(origin: origin) == .fandom)
        #expect(WorkStatsAtSave(summary: summary(3, kudos: 5), origin: origin).fandomWorks == 12_000)
        // A work not in that fandom does not take the page's total.
        var other = summary(4, kudos: 5)
        other.fandoms = ["Elsewhere"]
        #expect(WorkStatsAtSave(summary: other, origin: origin).fandomWorks == nil)
        let context = try context()
        let work = try ReadingQueueService.ensureLocalMetadata(
            for: summary(3, kudos: 5), importSource: WorkImportSource(origin: origin), origin: origin, in: context
        )
        #expect(work.importSource == .fandom)
        #expect(work.fandomWorksAtSave == 12_000)
    }

    // MARK: D11

    @Test func ownActionsMoveForwardAndKudosKeepsTheFirstTime() {
        let work = SavedWork(title: "A", author: "B")
        #expect(work.recordOwnAction(.bookmarked(isPrivate: false), at: t0))
        #expect(!work.bookmarkIsPrivate)
        // A later edit moves the time and the flag; an older report cannot move it back.
        #expect(work.recordOwnAction(.bookmarked(isPrivate: true), at: t0.addingTimeInterval(60)))
        #expect(work.bookmarkIsPrivate)
        #expect(!work.recordOwnAction(.bookmarked(isPrivate: false), at: t0))
        #expect(work.bookmarkedAt == t0.addingTimeInterval(60))

        #expect(work.recordOwnAction(.commented, at: t0))
        #expect(!work.recordOwnAction(.commented, at: t0))
        #expect(work.recordOwnAction(.commented, at: t0.addingTimeInterval(5)))
        #expect(work.lastCommentedAt == t0.addingTimeInterval(5))

        #expect(work.recordKudosGiven(at: t0.addingTimeInterval(30)))
        #expect(work.hasGivenKudos)
        // Kudos cannot be taken back: a later sighting never moves the first time.
        #expect(!work.recordKudosGiven(at: t0.addingTimeInterval(900)))
        #expect(work.kudosGivenAt == t0.addingTimeInterval(30))
        #expect(work.recordKudosGiven(at: t0))
        #expect(work.kudosGivenAt == t0)
    }

    @Test func aBookmarkSeenOnAFetchedPageOnlyFillsAnEmptyOne() {
        let work = SavedWork(title: "A", author: "B")
        #expect(work.recordSeenBookmark(isPrivate: true, at: t0))
        #expect(work.bookmarkIsPrivate)
        #expect(!work.recordSeenBookmark(isPrivate: false, at: t0.addingTimeInterval(60)))
        #expect(work.bookmarkedAt == t0)
        #expect(work.bookmarkIsPrivate)
    }

    @Test func theActionLogFindsTheSavedWorkAndSkipsOneItDoesNotHold() throws {
        let context = try context()
        let work = SavedWork(title: "A", author: "B")
        work.ao3WorkID = 41
        context.insert(work)
        let deleted = SavedWork(title: "Gone", author: "B")
        deleted.ao3WorkID = 42
        deleted.isPendingDeletion = true
        context.insert(deleted)
        #expect(OwnAO3ActionLog.record(.commented, ao3WorkID: 41, at: t0, in: context))
        #expect(OwnAO3ActionLog.record(.bookmarked(isPrivate: true), ao3WorkID: 41, at: t0, in: context))
        #expect(work.lastCommentedAt == t0)
        #expect(work.bookmarkIsPrivate)
        #expect(!OwnAO3ActionLog.record(.commented, ao3WorkID: 999, at: t0, in: context))
        #expect(!OwnAO3ActionLog.record(.commented, ao3WorkID: 42, at: t0, in: context))
        #expect(deleted.lastCommentedAt == nil)
        // With no context installed or given, nothing is recorded.
        OwnAO3ActionLog.install(nil)
        #expect(!OwnAO3ActionLog.record(.commented, ao3WorkID: 41))
    }

    // MARK: figures

    @Test func figuresCountOnlyWhatWasRecorded() {
        var works: [SavedWork] = []
        for source in [WorkImportSource.search, .search, .series] {
            let work = SavedWork(title: "W", author: "A")
            work.recordImportSource(source, at: t0.addingTimeInterval(works.count == 0 ? 100 : 500))
            works.append(work)
        }
        works.append(SavedWork(title: "Old", author: "A"))
        let arrival = InsightsProvenance.arrival(works: works)
        #expect(arrival.counts[.search] == 2)
        #expect(arrival.counts[.series] == 1)
        #expect(arrival.unrecorded == 1)
        #expect(arrival.recorded == 3)
        #expect(arrival.since == t0.addingTimeInterval(100))

        let early = SavedWork(title: "Early", author: "A")
        early.recordStatsAtSave(WorkStatsAtSave(kudos: 310, hits: 900, bookmarks: nil, fandomWorks: nil), at: t0)
        early.kudos = 1_530
        let flat = SavedWork(title: "Flat", author: "A")
        flat.recordStatsAtSave(WorkStatsAtSave(kudos: 100, hits: 900, bookmarks: nil, fandomWorks: nil), at: t0)
        flat.kudos = 110
        let unrecorded = SavedWork(title: "Before", author: "A")
        unrecorded.kudos = 5_000
        let found = InsightsProvenance.foundEarly(works: [flat, unrecorded, early])
        #expect(found.map(\.title) == ["Early", "Flat"])
        #expect(found.first?.kudosAtSave == 310)
        #expect(found.first?.kudosNow == 1_530)

        let bookmarked = SavedWork(title: "B", author: "A")
        bookmarked.recordOwnAction(.bookmarked(isPrivate: true), at: t0)
        let both = SavedWork(title: "C", author: "A")
        both.recordOwnAction(.bookmarked(isPrivate: false), at: t0)
        both.recordOwnAction(.commented, at: t0)
        let actions = InsightsProvenance.ownActions(works: [bookmarked, both, SavedWork(title: "D", author: "A")])
        #expect(actions == InsightsProvenance.OwnActionsFigure(
            works: 3, bookmarked: 2, bookmarkedPublic: 1, bookmarkedPrivate: 1, commented: 1, gaveKudos: 0
        ))
    }

    @Test func chapterTimingFigureSumsStoredJudgementsAndCountsPeekedWorksOnce() {
        let workA = UUID()
        let workB = UUID()
        func session(_ work: UUID) -> ReadingSession {
            ReadingSession(workID: work, startedAt: t0, endedAt: t0.addingTimeInterval(60), durationSeconds: 60)
        }
        let first = session(workA)
        first.chapterWords = [3: 3_000, 4: 2_000]
        first.skimmedChapters = [3, 4]
        first.endedAtChapterEnd = true
        first.peekedAtEnding = true
        let second = session(workA)
        second.skimmedChapters = []
        second.endedAtChapterEnd = false
        second.peekedAtEnding = true
        let third = session(workB)
        third.peekedAtEnding = false
        let unjudged = session(workB)
        let figure = InsightsProvenance.chapterTiming(sessions: [first, second, third, unjudged])
        #expect(figure.skimmedChapters == 2)
        #expect(figure.skimmedWords == 5_000)
        #expect(figure.judgedSittings == 2)
        #expect(figure.sittingsMeasured == 2)
        #expect(figure.sittingsEndedAtChapterEnd == 1)
        #expect(figure.peekedWorks == 1)
    }

    // MARK: Hide Mature applies to every new figure

    @Test func hiddenWorksNeverReachAnyP3FigureWhileLocked() throws {
        let context = try context()
        let plain = SavedWork(title: "Plain", author: "A")
        plain.rating = "General Audiences"
        let adult = SavedWork(title: "Adult", author: "A")
        adult.rating = "Explicit"
        context.insert(plain)
        context.insert(adult)
        plain.recordImportSource(.search, at: t0)
        adult.recordImportSource(.series, at: t0)
        plain.recordOwnAction(.commented, at: t0)
        adult.recordOwnAction(.commented, at: t0)

        let plainEvent = ChapterUpdateEvent(workID: plain.id, chapterCount: 4, previousChapterCount: 3, detectedAt: t0, rating: "General Audiences")
        // The adult work's event keeps its own rating, so it stays hidden after the work is gone.
        let adultEvent = ChapterUpdateEvent(workID: adult.id, chapterCount: 4, previousChapterCount: 3, detectedAt: t0, rating: "Explicit")
        let orphanAdultEvent = ChapterUpdateEvent(workID: UUID(), chapterCount: 4, previousChapterCount: 3, detectedAt: t0, rating: "Mature")
        context.insert(plainEvent)
        context.insert(adultEvent)
        context.insert(orphanAdultEvent)
        let allEvents = [plainEvent, adultEvent, orphanAdultEvent]

        let library = [plain, adult]
        let locked = HomeReadingStats.insightsScope(.main, from: library, hideMature: true, revealed: false)
        #expect(InsightsProvenance.arrival(works: locked.readingWorks).counts == [.search: 1])
        #expect(InsightsProvenance.ownActions(works: locked.readingWorks).commented == 1)
        #expect(locked.events(allEvents, in: context).map(\.id) == [plainEvent.id])
        let lockedHidden = HomeReadingStats.insightsScope(.hidden, from: library, hideMature: true, revealed: false)
        #expect(lockedHidden.events(allEvents, in: context).isEmpty)
        #expect(lockedHidden.readingWorks.isEmpty)

        let revealedHidden = HomeReadingStats.insightsScope(.hidden, from: library, hideMature: true, revealed: true)
        #expect(Set(revealedHidden.events(allEvents, in: context).map(\.id)) == [adultEvent.id, orphanAdultEvent.id])
        #expect(InsightsProvenance.arrival(works: revealedHidden.readingWorks).counts == [.series: 1])
        let combined = HomeReadingStats.insightsScope(.combined, from: library, hideMature: true, revealed: true)
        #expect(combined.events(allEvents, in: context).count == 3)
        #expect(InsightsProvenance.ownActions(works: combined.readingWorks).commented == 2)

        // With Hide Mature off every event is in the main view.
        let open = HomeReadingStats.insightsScope(.main, from: library, hideMature: false, revealed: false)
        #expect(open.events(allEvents, in: context).count == 3)
    }

    @Test func aHiddenWorksSittingsStayOutOfTheChapterTimingFigureWhileLocked() throws {
        let context = try context()
        let adult = SavedWork(title: "Adult", author: "A")
        adult.rating = "Explicit"
        context.insert(adult)
        let sitting = ReadingSession(
            workID: adult.id, startedAt: t0, endedAt: t0.addingTimeInterval(120), durationSeconds: 120
        )
        sitting.rating = "Explicit"
        sitting.peekedAtEnding = true
        sitting.skimmedChapters = [3]
        sitting.chapterWords = [3: 1_000]
        context.insert(sitting)
        let locked = HomeReadingStats.insightsScope(.main, from: [adult], hideMature: true, revealed: false)
        let visible = locked.sessions([sitting], in: context)
        #expect(visible.isEmpty)
        #expect(InsightsProvenance.chapterTiming(sessions: visible) == InsightsProvenance.ChapterTimingFigure())
        let revealed = HomeReadingStats.insightsScope(.hidden, from: [adult], hideMature: true, revealed: true)
        #expect(InsightsProvenance.chapterTiming(sessions: revealed.sessions([sitting], in: context)).peekedWorks == 1)
    }

    // MARK: review 2

    @Test func aChapterATooShortSittingCouldNotHaveReachedIsNotUnknown() throws {
        let workID = UUID()
        let posted = try posting("2026-11-10")
        let event = ChapterUpdateEvent(
            workID: workID, chapterCount: 6, previousChapterCount: 5, detectedAt: posted, postedDate: "2026-11-10"
        )
        // A five-chapter copy read after chapter 6 posted, with no locator signal (macOS).
        let short = reading(workID, at: posted.addingTimeInterval(86_400), highest: nil, visit: 5)
        #expect(InsightsProvenance.newChapters(events: [event], sessions: [short]).unreadChapters == 1)
        // A sitting that recorded no count at all stays genuinely unknown.
        let blank = reading(workID, at: posted.addingTimeInterval(86_400), highest: nil, visit: 0)
        #expect(InsightsProvenance.newChapters(events: [event], sessions: [blank]).unknownChapters == 1)
    }

    @Test func aSameCountRecheckFillsTheMissingPostingDayOnTheMatchingEvent() async throws {
        let context = try context()
        let work = SavedWork(title: "WIP", author: "A", sourceURL: "https://archiveofourown.org/works/79")
        work.ao3WorkID = 79
        work.isSaved = true
        work.chapters = "3/?"
        context.insert(work)
        func groups(_ day: String) -> @Sendable (Int) async throws -> AO3WorkTagGroups {
            { _ in
                var groups = AO3WorkTagGroups()
                groups.fandoms = ["Fandom"]
                groups.chapters = "5/?"
                groups.dateUpdated = day
                return groups
            }
        }
        await WorkUpdateChecker.checkForUpdates(among: [work], in: context, fetchTags: groups(""))
        #expect(try context.fetch(FetchDescriptor<ChapterUpdateEvent>()).first?.postedDate == "")
        work.lastUpdateCheck = nil
        await WorkUpdateChecker.checkForUpdates(among: [work], in: context, fetchTags: groups("2026-11-12"))
        let events = try context.fetch(FetchDescriptor<ChapterUpdateEvent>())
        #expect(events.count == 1)
        #expect(events.first?.postedDate == "2026-11-12")
    }

    @Test func aWindowThatCrossesMidnightStillCountsTheAgeOnTheSaveDay() throws {
        let work = SavedWork(title: "A", author: "B")
        work.datePublished = "2026-11-10"
        work.recordImportSource(.search, at: t0)
        let saved = ISO8601DateFormatter().date(from: "2026-11-10T23:58:00Z") ?? t0
        work.dateAdded = saved
        #expect(work.recordStatsAtSaveIfJustSaved(
            kudos: 1, hits: 1, bookmarks: nil, now: saved.addingTimeInterval(300)
        ))
        #expect(work.ageDaysAtSave == 0)
        // The same holds when the date arrives later.
        let later = SavedWork(title: "C", author: "D")
        later.recordImportSource(.search, at: t0)
        later.dateAdded = saved
        later.recordStatsAtSaveIfJustSaved(kudos: 1, hits: 1, bookmarks: nil, now: saved.addingTimeInterval(300))
        #expect(later.ageDaysAtSave == nil)
        later.datePublished = "2026-11-10"
        #expect(later.completeAgeAtSave())
        #expect(later.ageDaysAtSave == 0)
    }

    @Test func aChapterSkimmedInOneSittingIsCreditedWhenReadFullyInALaterOne() {
        let work = SavedWork(title: "W", author: "A")
        work.chapterWordCounts = [1_000, 1_000, 1_000]
        work.wordUnitRaw = SavedWork.WordUnit.words.rawValue
        work.wordCount = 3_000
        work.chapters = "3/3"
        // Sitting one passes through chapters 1 and 2 and skims chapter 2.
        let first = ReadingSession(
            workID: work.id, startedAt: t0, endedAt: t0.addingTimeInterval(600), durationSeconds: 600,
            startProgress: 0, endingProgress: 2.0 / 3.0, wordCount: 3_000, chapterCountAtVisit: 3
        )
        first.skimmedStoryChapters = [2]
        first.chapterWords = [9: 1_000]
        first.skimmedChapters = [9]
        // Sitting two goes back and reads chapter 2 properly.
        let second = ReadingSession(
            workID: work.id, startedAt: t0.addingTimeInterval(3_600), endedAt: t0.addingTimeInterval(4_800),
            durationSeconds: 1_200, startProgress: 1.0 / 3.0, endingProgress: 2.0 / 3.0,
            wordCount: 3_000, chapterCountAtVisit: 3
        )
        let read = ReadingLogService.wordsRead(sessions: [first, second], works: [work])
        #expect(read[first.id] == 1_000)
        #expect(read[second.id] == 1_000)
    }

    @Test func aMidnightFreeLegacyRefreshAlsoKeepsTheEventRatingEvidence() {
        #expect(ChapterUpdateRecorder.strongerRating("", "Explicit") == "Explicit")
        #expect(ChapterUpdateRecorder.strongerRating("Mature", "") == "Mature")
        #expect(ChapterUpdateRecorder.strongerRating("General Audiences", "Explicit") == "Explicit")
        #expect(ChapterUpdateRecorder.earlierPostingDay("", "2026-11-09") == "2026-11-09")
        #expect(ChapterUpdateRecorder.earlierPostingDay("2026-11-12", "2026-11-09") == "2026-11-09")
        #expect(ChapterUpdateRecorder.earlierPostingDay("2026-11-09", "2026-11-12") == "2026-11-09")
    }

    // MARK: review 3

    @Test func tiedOverlappingObservationsGiveTheSameStatesWhateverTheirIdsAre() throws {
        let workID = UUID()
        // Detected after both posting days, so neither day is clamped to the detection time.
        let detected = try posting("2026-11-20")
        // A sitting reaches chapter 6 on the 10th: after the narrow observation's posting day
        // (the 9th), before the wide one's (the 12th).
        let sitting = reading(workID, at: try posting("2026-11-10"), highest: 6, visit: 6)
        func chapterSix(wideID: UUID, narrowID: UUID, reversed: Bool) throws -> InsightsProvenance.NewChapterEntry {
            let wide = ChapterUpdateEvent(
                id: wideID, workID: workID, chapterCount: 6, previousChapterCount: 3,
                detectedAt: detected, postedDate: "2026-11-12"
            )
            let narrow = ChapterUpdateEvent(
                id: narrowID, workID: workID, chapterCount: 6, previousChapterCount: 5,
                detectedAt: detected, postedDate: "2026-11-09"
            )
            let figure = InsightsProvenance.newChapters(
                events: reversed ? [narrow, wide] : [wide, narrow], sessions: [sitting]
            )
            return try #require(figure.entries.first { $0.chapter == 6 })
        }
        let low = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let high = try #require(UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001"))
        for (wideID, narrowID) in [(low, high), (high, low)] {
            for reversed in [false, true] {
                let entry = try chapterSix(wideID: wideID, narrowID: narrowID, reversed: reversed)
                // The earlier posting day claims the tied chapter, so the sitting is read evidence.
                #expect(entry.postedAt == (try posting("2026-11-09")))
                if case .read = entry.state {} else { Issue.record("chapter 6 should be read, got \(entry.state)") }
            }
        }
    }

    @Test func aSkimmedChapterIsDeductedByTheWordsTheSittingRecordedNotTodaysCounts() {
        let work = SavedWork(title: "W", author: "A")
        // The work now has four 1,000-word chapters; the sitting saw an 8,000-word copy and
        // recorded 2,000 skimmed words in chapter 2.
        work.chapterWordCounts = [1_000, 1_000, 1_000, 1_000]
        work.wordUnitRaw = SavedWork.WordUnit.words.rawValue
        work.wordCount = 8_000
        work.chapters = "4/4"
        let sitting = ReadingSession(
            workID: work.id, startedAt: t0, endedAt: t0.addingTimeInterval(600), durationSeconds: 600,
            startProgress: 0.25, endingProgress: 0.5, wordCount: 8_000, chapterCountAtVisit: 4
        )
        sitting.chapterWords = [3: 2_000]
        sitting.skimmedChapters = [3]
        sitting.skimmedStoryChapters = [2]
        #expect(ReadingLogService.wordsRead(sessions: [sitting], works: [work])[sitting.id] == 0)
    }

    @Test func aBulkActionKeepsTheScreensOriginForArrivalAndFandomSize() async throws {
        let context = try context()
        let origin = ReadingQueueMembershipOrigin(
            kind: .search, label: "Fandom", importSourceHint: .fandom, fandomWorks: 12_000
        )
        var resolved: [SavedWork] = []
        let error = await resolveSelectedRemoteWorks(
            [summary(61, kudos: 40)], in: context, origin: origin
        ) { works in resolved = works }
        #expect(error == nil)
        let work = try #require(resolved.first)
        #expect(work.importSource == .fandom)
        #expect(work.fandomWorksAtSave == 12_000)
        #expect(work.kudosAtSave == 40)
    }

    @Test func aHiddenMatureSnapshotStillProtectsALaterUnratedEventInLockedInsights() throws {
        let context = try context()
        let gone = UUID()
        let mature = ChapterUpdateEvent(
            workID: gone, chapterCount: 4, previousChapterCount: 3, detectedAt: t0, rating: "Explicit"
        )
        // A tombstone dated after the Mature sighting hides it; a later observation is unrated.
        context.insert(SyncTombstone(recordID: gone, recordType: .savedWork, createdAt: t0.addingTimeInterval(86_400)))
        let later = ChapterUpdateEvent(
            workID: gone, chapterCount: 5, previousChapterCount: 4,
            detectedAt: t0.addingTimeInterval(2 * 86_400), rating: ""
        )
        context.insert(mature)
        context.insert(later)
        try context.save()
        let locked = HomeReadingStats.insightsScope(.main, from: [], hideMature: true, revealed: false)
        #expect(locked.events([mature, later], in: context).isEmpty)
    }
}
