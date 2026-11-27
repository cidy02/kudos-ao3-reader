import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
@Suite(.serialized)
struct InsightsGatherTests {
    private let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self,
            ReadingAnnotation.self, ReadingSession.self, ReadingFavorite.self,
            FandomReadWatermark.self, FollowedTag.self, TagAlias.self, SavedSeries.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func date(year: Int = 2026, month: Int, day: Int, hour: Int = 12) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private var aug: DateInterval {
        utcCalendar.dateInterval(of: .month, for: date(month: 8, day: 1))!
    }

    private var jul: DateInterval {
        utcCalendar.dateInterval(of: .month, for: date(month: 7, day: 1))!
    }

    /// Deterministic suspension gate for testing cancellation and stale-result dropping without sleeps.
    private actor TestGate {
        private var entered = false
        private var released = false
        private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
        private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

        func enterAndWait() async {
            signalEntered()
            guard !released else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if released {
                    continuation.resume()
                } else {
                    releaseWaiters.append(continuation)
                }
            }
        }

        func signalEntered() {
            entered = true
            let waiters = enteredWaiters
            enteredWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        func waitUntilEntered() async {
            guard !entered else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if entered {
                    continuation.resume()
                } else {
                    enteredWaiters.append(continuation)
                }
            }
        }

        func release() {
            released = true
            let waiters = releaseWaiters
            releaseWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let liveWorks: [SavedWork]
        let excludedWork: SavedWork
        let staleWork: SavedWork
        let now: Date
    }

    private func makeFixture() throws -> Fixture {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let now = date(month: 8, day: 25)

        func makeWork(
            title: String,
            words: Int,
            fandom: String,
            daysAddedBeforeNow: Int,
            ao3ID: Int? = nil
        ) -> SavedWork {
            let work = SavedWork(title: title, author: "Author \(title)")
            work.wordCount = words
            work.workFandoms = [fandom]
            work.workFreeforms = ["Slow Burn"]
            work.workTags = ["Slow Burn"]
            work.isSaved = true
            work.ao3WorkID = ao3ID
            work.dateAdded = now.addingTimeInterval(TimeInterval(-daysAddedBeforeNow * 86_400))
            return work
        }

        // 1. Live saved finished work read across multiple days + previous month + series + provenance.
        let mainFinished = makeWork(
            title: "Main Finished Fic",
            words: 12_000,
            fandom: "Alias Fandom",
            daysAddedBeforeNow: 45,
            ao3ID: 1001
        )
        mainFinished.isFinished = true
        mainFinished.hasGivenKudos = true
        mainFinished.isComplete = true
        mainFinished.ao3SeriesID = 42
        mainFinished.seriesPosition = 1
        mainFinished.seriesTitle = "Twin Stars"
        mainFinished.kudos = 900
        mainFinished.kudosAtSave = 200
        mainFinished.statsSavedAt = mainFinished.dateAdded
        mainFinished.importSourceRaw = WorkImportSource.search.rawValue
        mainFinished.importSourceSince = mainFinished.dateAdded

        // 2. Live in-progress stale work -> triggers StillReadingCandidate.
        let staleWork = makeWork(
            title: "Untouched Midpoint",
            words: 18_000,
            fandom: "Fandom One",
            daysAddedBeforeNow: 40,
            ao3ID: 1002
        )
        staleWork.hasEPUB = true
        staleWork.chapters = "6/10"
        staleWork.lastSpineIndex = 2
        staleWork.legacyReaderProgress = 0.45
        staleWork.lastReadDate = date(month: 8, day: 1)

        // 3. Queue-only finished work (counts in reading figures, excluded from library inventory).
        let queueOnly = makeWork(
            title: "Queue Only Fic",
            words: 6_000,
            fandom: "Queue Fandom",
            daysAddedBeforeNow: 15,
            ao3ID: 1003
        )
        queueOnly.isSaved = false
        queueOnly.isQueuedForLater = true
        queueOnly.isFinished = true

        // 4. Adult-rated live work (moves between Hidden and Combined).
        let matureWork = makeWork(
            title: "Explicit Live Fic",
            words: 15_000,
            fandom: "Secret Fandom",
            daysAddedBeforeNow: 12,
            ao3ID: 1004
        )
        matureWork.rating = "Explicit"
        matureWork.isFinished = true

        // 5. Work excluded by InsightsOptions.excludedWorkIDs.
        let excludedWork = makeWork(
            title: "Excluded By ID",
            words: 9_000,
            fandom: "Fandom One",
            daysAddedBeforeNow: 10
        )
        excludedWork.isFinished = true

        // 6. Work excluded by InsightsOptions.excludedFandoms.
        let excludedFandomWork = makeWork(
            title: "Excluded Fandom Fic",
            words: 7_000,
            fandom: "Muted Fandom",
            daysAddedBeforeNow: 8
        )
        excludedFandomWork.isFinished = true

        // 7. Unread backlog work.
        let unreadWork = makeWork(
            title: "Unread Backlog",
            words: 20_000,
            fandom: "Fandom One",
            daysAddedBeforeNow: 5
        )

        // 8. Soft-deleted mature work (`isPendingDeletion == true`).
        let softDeletedMature = makeWork(
            title: "Soft Deleted Mature",
            words: 11_000,
            fandom: "Trash Mature Fandom",
            daysAddedBeforeNow: 20
        )
        softDeletedMature.rating = "Mature"
        softDeletedMature.isPendingDeletion = true

        let allWorks = [
            mainFinished, staleWork, queueOnly, matureWork,
            excludedWork, excludedFandomWork, unreadWork, softDeletedMature
        ]
        allWorks.forEach { context.insert($0) }

        // Sittings across days and across Jul -> Aug, including read-aloud, chapter timing,
        // soft-deleted mature, and hard-deleted works (both general and mature).
        func addSession(
            workID: UUID,
            ao3WorkID: Int? = nil,
            title: String,
            month: Int,
            day: Int,
            hour: Int = 12,
            seconds: Double,
            startProgress: Double,
            endingProgress: Double,
            words: Int,
            fandom: String,
            rating: String = "General Audiences",
            modeRaw: String = "read",
            didFinish: Bool = false
        ) -> ReadingSession {
            let start = date(month: month, day: day, hour: hour)
            let session = ReadingSession(
                workID: workID,
                ao3WorkID: ao3WorkID,
                workTitle: title,
                startedAt: start,
                endedAt: start.addingTimeInterval(seconds),
                durationSeconds: seconds,
                startProgress: startProgress,
                modeRaw: modeRaw,
                playbackRate: modeRaw == "listen" ? 1.25 : nil,
                endingProgress: endingProgress,
                wordCount: words,
                chapterCountAtVisit: 4,
                didFinish: didFinish
            )
            session.fandoms = [fandom]
            session.rating = rating
            session.endedAtChapterEnd = true
            context.insert(session)
            return session
        }

        // Previous period (July) sitting so period-over-period deltas are populated.
        _ = addSession(
            workID: mainFinished.id, ao3WorkID: mainFinished.ao3WorkID, title: mainFinished.title,
            month: 7, day: 10, seconds: 900, startProgress: 0, endingProgress: 0.4,
            words: mainFinished.wordCount, fandom: "Alias Fandom"
        )
        // August sittings across multiple days on mainFinished (read + listen).
        _ = addSession(
            workID: mainFinished.id, ao3WorkID: mainFinished.ao3WorkID, title: mainFinished.title,
            month: 8, day: 3, hour: 21, seconds: 1_200, startProgress: 0.4, endingProgress: 0.75,
            words: mainFinished.wordCount, fandom: "Alias Fandom"
        )
        _ = addSession(
            workID: mainFinished.id, ao3WorkID: mainFinished.ao3WorkID, title: mainFinished.title,
            month: 8, day: 4, hour: 23, seconds: 600, startProgress: 0.75, endingProgress: 1.0,
            words: mainFinished.wordCount, fandom: "Alias Fandom", modeRaw: "listen", didFinish: true
        )
        // Queue-only sitting.
        _ = addSession(
            workID: queueOnly.id, ao3WorkID: queueOnly.ao3WorkID, title: queueOnly.title,
            month: 8, day: 6, seconds: 480, startProgress: 0, endingProgress: 1.0,
            words: queueOnly.wordCount, fandom: "Queue Fandom", didFinish: true
        )
        // Mature live sitting.
        _ = addSession(
            workID: matureWork.id, ao3WorkID: matureWork.ao3WorkID, title: matureWork.title,
            month: 8, day: 7, seconds: 1_000, startProgress: 0, endingProgress: 1.0,
            words: matureWork.wordCount, fandom: "Secret Fandom", rating: "Explicit", didFinish: true
        )
        // Excluded works' sittings (must be excluded identically by both paths).
        _ = addSession(
            workID: excludedWork.id, title: excludedWork.title,
            month: 8, day: 8, seconds: 500, startProgress: 0, endingProgress: 1.0,
            words: excludedWork.wordCount, fandom: "Fandom One", didFinish: true
        )
        _ = addSession(
            workID: excludedFandomWork.id, title: excludedFandomWork.title,
            month: 8, day: 9, seconds: 400, startProgress: 0, endingProgress: 1.0,
            words: excludedFandomWork.wordCount, fandom: "Muted Fandom", didFinish: true
        )
        // Soft-deleted mature work sitting with blank snapshot rating.
        _ = addSession(
            workID: softDeletedMature.id, title: softDeletedMature.title,
            month: 8, day: 11, seconds: 700, startProgress: 0, endingProgress: 1.0,
            words: softDeletedMature.wordCount, fandom: "Trash Mature Fandom", rating: "", didFinish: true
        )
        // Hard-deleted general work (no SavedWork row in store).
        let hardDeletedGeneralID = UUID()
        _ = addSession(
            workID: hardDeletedGeneralID, title: "Purged General Fic",
            month: 8, day: 12, seconds: 600, startProgress: 0, endingProgress: 1.0,
            words: 8_000, fandom: "Purged Fandom", rating: "Teen And Up Audiences", didFinish: true
        )
        // Hard-deleted mature work (no SavedWork row in store).
        let hardDeletedMatureID = UUID()
        _ = addSession(
            workID: hardDeletedMatureID, title: "Purged Explicit Fic",
            month: 8, day: 13, seconds: 800, startProgress: 0, endingProgress: 1.0,
            words: 10_000, fandom: "Purged Secret Fandom", rating: "Explicit", didFinish: true
        )

        // Tag aliases and series snapshots (multiple rows so batchSize: 2 exercises paging on them too).
        context.insert(TagAlias(name: "Alias Fandom", canonicalName: "Fandom One", kind: .fandom, learnedAt: now))
        context.insert(TagAlias(name: "Slowburn", canonicalName: "Slow Burn", kind: .freeform, learnedAt: now))
        context.insert(TagAlias(name: "Queue Alias", canonicalName: "Queue Fandom", kind: .fandom, learnedAt: now))
        context.insert(SavedSeries(
            ao3SeriesID: 42,
            title: "Twin Stars",
            partCount: 2,
            isComplete: true,
            wordCount: 30_000,
            partWorkIDs: [1001, 1002],
            checkedAt: now
        ))
        context.insert(SavedSeries(
            ao3SeriesID: 99,
            title: "Second Series",
            partCount: 3,
            isComplete: false,
            wordCount: 45_000,
            partWorkIDs: [2001, 2002, 2003],
            checkedAt: now
        ))
        context.insert(SavedSeries(
            ao3SeriesID: 100,
            title: "Third Series",
            partCount: 1,
            isComplete: true,
            wordCount: 5_000,
            partWorkIDs: [3001],
            checkedAt: now
        ))

        try context.save()

        let liveWorks = try context.fetch(FetchDescriptor<SavedWork>(
            predicate: #Predicate { !$0.isPendingDeletion },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse), SortDescriptor(\.id)]
        ))
        return Fixture(
            container: container,
            context: context,
            liveWorks: liveWorks,
            excludedWork: excludedWork,
            staleWork: staleWork,
            now: now
        )
    }

    @Test func actorGatherMatchesMainActorGatherAcrossScopesExclusionsAndDeletedWorks() async throws {
        let f = try makeFixture()
        let options = InsightsOptions(
            countRereads: true,
            countReadAloud: true,
            askAboutUntouched: true,
            untouchedDays: 14,
            excludedFandoms: ["Muted Fandom"],
            excludedWorkIDs: [f.excludedWork.id.uuidString]
        )

        let cases: [(scope: InsightsScope, hideMature: Bool, revealed: Bool, includesHidden: Bool)] = [
            (.main, true, false, false),
            (.main, true, true, true),
            (.combined, true, true, true),
            (.main, false, false, false)
        ]

        let workCountBefore = try f.context.fetchCount(FetchDescriptor<SavedWork>())
        let sessionCountBefore = try f.context.fetchCount(FetchDescriptor<ReadingSession>())
        let modifiedBefore = Dictionary(
            f.liveWorks.map { ($0.id, $0.lastModifiedAt) },
            uniquingKeysWith: { first, _ in first }
        )

        for testCase in cases {
            let mainScope = HomeReadingStats.insightsScope(
                testCase.scope,
                from: f.liveWorks,
                hideMature: testCase.hideMature,
                revealed: testCase.revealed
            )
            let legacyMain = ReadingLogService.gatherInsights(
                for: aug,
                previousPeriod: jul,
                scope: mainScope,
                periodMonths: 1,
                calendar: utcCalendar,
                context: f.context,
                options: options,
                now: f.now
            )
            let legacyHidden = testCase.includesHidden
                ? ReadingLogService.gatherInsights(
                    for: aug,
                    previousPeriod: jul,
                    scope: HomeReadingStats.insightsScope(
                        .hidden,
                        from: f.liveWorks,
                        hideMature: testCase.hideMature,
                        revealed: testCase.revealed
                    ),
                    periodMonths: 1,
                    calendar: utcCalendar,
                    context: f.context,
                    options: options,
                    now: f.now
                )
                : nil
            let legacyDigest = InsightsReloadDigest.snapshot(
                works: f.liveWorks,
                context: f.context,
                now: f.now,
                calendar: utcCalendar
            )

            let request = InsightsGatherRequest(
                period: aug,
                previousPeriod: jul,
                periodMonths: 1,
                calendar: utcCalendar,
                options: options,
                scope: testCase.scope,
                hideMature: testCase.hideMature,
                revealed: testCase.revealed,
                includesHiddenSection: testCase.includesHidden,
                computesDigest: true,
                now: f.now,
                batchSize: 2
            )
            let actor = InsightsGatherActor(modelContainer: f.container)
            let output = try await actor.gather(request)
            let hasUnsaved = await actor.hasUnsavedChanges

            #expect(!hasUnsaved)
            #expect(output.fetches.largestBatch <= 2)
            #expect(output.fetches.workBatches >= 4)
            #expect(output.fetches.sessionBatches >= 5)
            #expect(output.fetches.aliasBatches >= 2)
            #expect(output.fetches.seriesBatches >= 2)
            #expect(output.fetches.softDeletedWorkBatches == 1)

            #expect(output.main.insights == legacyMain.insights)
            #expect(output.main.taste == legacyMain.taste)
            #expect(output.main.habits == legacyMain.habits)
            #expect(output.main.chapterTiming == legacyMain.chapterTiming)
            #expect(output.main.library == legacyMain.library)
            #expect(output.main.libraryStats == legacyMain.libraryStats)
            #expect(output.main.finishedWorkIDs == legacyMain.finishedWorksInPeriod.map(\.id))
            #expect(output.main.finishedWorks(in: f.liveWorks).map(\.id) == legacyMain.finishedWorksInPeriod.map(\.id))
            #expect(output.main.discreetMasker == legacyMain.discreetMasker)

            if let legacyHidden {
                let actorHidden = try #require(output.hidden)
                #expect(actorHidden.insights == legacyHidden.insights)
                #expect(actorHidden.discreetMasker == legacyHidden.discreetMasker)
            } else {
                #expect(output.hidden == nil)
            }

            let actorDigest = try #require(output.digest)
            #expect(actorDigest.digest == legacyDigest.digest)
            #expect(actorDigest.liveWorkSignatures == legacyDigest.liveWorkSignatures)
            #expect(actorDigest.softDeletedAdultFlags == legacyDigest.softDeletedAdultFlags)
        }

        // Confirm the still-reading candidate survived as a plain value type with no model object.
        let checkRequest = InsightsGatherRequest(
            period: aug,
            previousPeriod: jul,
            periodMonths: 1,
            calendar: utcCalendar,
            options: options,
            scope: .main,
            hideMature: true,
            revealed: false,
            includesHiddenSection: false,
            computesDigest: false,
            now: f.now,
            batchSize: 2
        )
        let checkOutput = try await InsightsGatherActor(modelContainer: f.container).gather(checkRequest)
        #expect(checkOutput.main.library.stillReadingCandidate?.id == f.staleWork.id)
        #expect(checkOutput.digest == nil)

        // Gather must never write or mutate stored rows.
        #expect(try f.context.fetchCount(FetchDescriptor<SavedWork>()) == workCountBefore)
        #expect(try f.context.fetchCount(FetchDescriptor<ReadingSession>()) == sessionCountBefore)
        let worksAfter = try f.context.fetch(FetchDescriptor<SavedWork>(predicate: #Predicate { !$0.isPendingDeletion }))
        for work in worksAfter {
            #expect(work.lastModifiedAt == modifiedBefore[work.id])
        }
    }

    @Test func actorDigestMatchesMainActorDigestAndStreamsInBoundedBatches() async throws {
        let f = try makeFixture()
        let legacyDigest = InsightsReloadDigest.snapshot(
            works: f.liveWorks,
            context: f.context,
            now: f.now,
            calendar: utcCalendar
        )

        let actor = InsightsGatherActor(modelContainer: f.container)
        let actorDigest = try await actor.digest(batchSize: 2, now: f.now, calendar: utcCalendar)
        let stats = await actor.fetchStatistics
        let hasUnsaved = await actor.hasUnsavedChanges

        #expect(!hasUnsaved)
        #expect(actorDigest.digest == legacyDigest.digest)
        #expect(actorDigest.liveWorkSignatures == legacyDigest.liveWorkSignatures)
        #expect(actorDigest.softDeletedAdultFlags == legacyDigest.softDeletedAdultFlags)
        #expect(stats.largestBatch <= 2)
        #expect(stats.workBatches >= 4)
        #expect(stats.sessionBatches >= 5)
        #expect(stats.aliasBatches >= 2)
        #expect(stats.seriesBatches >= 2)
    }

    @Test func cancellationStopsGatherBetweenBatches() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let now = date(month: 8, day: 25)

        let work = SavedWork(title: "Long Series", author: "Author")
        work.isSaved = true
        work.wordCount = 10_000
        work.workFandoms = ["Fandom One"]
        context.insert(work)

        // 50 sittings at batchSize 5 -> 10 session batches if not cancelled.
        for index in 0..<50 {
            let start = date(month: 8, day: 1).addingTimeInterval(TimeInterval(index * 3_600))
            let session = ReadingSession(
                workID: work.id,
                workTitle: work.title,
                startedAt: start,
                endedAt: start.addingTimeInterval(300),
                durationSeconds: 300,
                startProgress: 0,
                endingProgress: 0.1,
                wordCount: 10_000
            )
            context.insert(session)
        }
        try context.save()

        let request = InsightsGatherRequest(
            period: aug,
            previousPeriod: jul,
            periodMonths: 1,
            calendar: utcCalendar,
            options: InsightsOptions(),
            scope: .main,
            hideMature: false,
            revealed: false,
            includesHiddenSection: false,
            computesDigest: false,
            now: now,
            batchSize: 5
        )
        let actor = InsightsGatherActor(modelContainer: container)
        let firstBatchGate = TestGate()

        let task = Task<InsightsGatherOutput, Error> {
            try await actor.gather(request) {
                await firstBatchGate.enterAndWait()
            }
        }

        await firstBatchGate.waitUntilEntered()
        task.cancel()
        await firstBatchGate.release()

        var threwCancellation = false
        do {
            _ = try await task.value
        } catch is CancellationError {
            threwCancellation = true
        }

        let stats = await actor.fetchStatistics
        #expect(threwCancellation)
        #expect(stats.sessionBatches == 1)
        #expect(stats.sessionsFetched == 5)
    }

    @Test func runnerCancelsPriorRunAndNeverAppliesStaleResult() async {
        let runner = InsightsGatherRunner<String>()
        let firstGate = TestGate()
        var applied: [String] = []

        // First run ignores cancellation on purpose so this also proves generation gating.
        runner.start(
            gather: {
                await firstGate.enterAndWait()
                return "stale"
            },
            apply: { value in
                applied.append(value)
            }
        )

        await firstGate.waitUntilEntered()
        #expect(runner.isRunning)

        // Starting a second run cancels the first and takes ownership of the generation.
        runner.start(
            gather: { "fresh" },
            apply: { value in
                applied.append(value)
            }
        )

        await runner.waitForCurrent()
        await firstGate.release()
        await Task.yield()

        #expect(applied == ["fresh"])
        #expect(!runner.isRunning)

        // Explicit cancel() also drops any in-flight result.
        let thirdGate = TestGate()
        runner.start(
            gather: {
                await thirdGate.enterAndWait()
                return "cancelled"
            },
            apply: { value in
                applied.append(value)
            }
        )
        await thirdGate.waitUntilEntered()
        runner.cancel()
        await thirdGate.release()
        await Task.yield()

        #expect(applied == ["fresh"])
        #expect(!runner.isRunning)
    }

    @Test func coordinatorOffMainDigestIgnoresPositionSavesAndDropsCancelledDigest() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // `noteSave` classifies with `Date()` and `Calendar.current` (the screen's
        // clock). A baseline frozen on an older `now` changes `openedRecencyBucket`
        // and Abandoned, so a locator write looks like a relevant save.
        let now = Date()
        let work = SavedWork(title: "A", author: "Author")
        work.isSaved = true
        work.rating = "General Audiences"
        work.isComplete = false
        work.readiumLocator = #"{"href":"c1.xhtml","locations":{"totalProgression":0.2}}"#
        work.lastReadDate = now
        context.insert(work)
        try context.save()

        let coordinator = InsightsReloadCoordinator(interval: .milliseconds(25))
        coordinator.tracker.recordBaseline(works: [work], context: context)

        final class NotificationCapture: @unchecked Sendable {
            private let lock = NSLock()
            private var items: [Notification] = []
            func append(_ note: Notification) { lock.withLock { items.append(note) } }
            var last: Notification? { lock.withLock { items.last } }
        }
        let notes = NotificationCapture()
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { notes.append($0) }
        defer { NotificationCenter.default.removeObserver(observer) }

        var digestCalls = 0
        var reloadedDigests: [String] = []

        // 1. Mid-chapter position save (locator, spine, in-chapter scroll — what the
        // reader writes) is ignored in O(k) without calling the off-main digest.
        work.applyDebouncedReadiumLocator(#"{"href":"c2.xhtml","locations":{"totalProgression":0.3}}"#, at: now)
        work.lastSpineIndex = 1
        work.lastScrollFraction = 0.3
        try context.save()
        let posNote = try #require(notes.last)
        #expect(coordinator.tracker.classifySave(posNote, context: context) == .ignored)
        coordinator.noteSave(
            posNote,
            works: { [work] },
            context: context,
            isOnScreen: { true },
            reload: { reloadedDigests.append($0.digest) },
            digest: {
                digestCalls += 1
                return try? await InsightsGatherActor(modelContainer: container).digest()
            }
        )
        try await Task.sleep(for: .milliseconds(80))
        #expect(digestCalls == 0)
        #expect(reloadedDigests.isEmpty)

        // 2. Relevant save invokes off-main digest and reloads once.
        work.rating = "Explicit"
        try context.save()
        let ratingNote = try #require(notes.last)
        let reloadDone = TestGate()
        coordinator.noteSave(
            ratingNote,
            works: { [work] },
            context: context,
            isOnScreen: { true },
            reload: { snapshot in
                reloadedDigests.append(snapshot.digest)
                coordinator.tracker.adopt(snapshot)
                Task { await reloadDone.signalEntered() }
            },
            digest: {
                digestCalls += 1
                return try? await InsightsGatherActor(modelContainer: container).digest()
            }
        )
        await reloadDone.waitUntilEntered()
        #expect(digestCalls == 1)
        #expect(reloadedDigests.count == 1)

        // 3. Cancelling while an off-main digest is suspended prevents reload from firing.
        // The closure calls the gather only after `cancel`, so that gather sees the
        // cancelled task and returns nil. `finished` is reached only then; a single
        // `Task.yield` could assert before that return.
        let started = TestGate()
        let finished = TestGate()
        work.title = "Renamed"
        try context.save()
        let renameNote = try #require(notes.last)
        coordinator.noteSave(
            renameNote,
            works: { [work] },
            context: context,
            isOnScreen: { true },
            reload: { reloadedDigests.append($0.digest) },
            digest: {
                await started.enterAndWait()
                let snapshot = try? await InsightsGatherActor(modelContainer: container).digest()
                await finished.signalEntered()
                return snapshot
            }
        )
        await started.waitUntilEntered()
        coordinator.cancel()
        await started.release()
        await finished.waitUntilEntered()
        #expect(reloadedDigests.count == 1)
    }

    @Test func largeSyntheticLibraryCompletesInBoundedBatches() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let now = date(month: 8, day: 25)

        let workCount = 100
        let totalSessions = 20_000
        let batchSize = 2_000

        var works: [SavedWork] = []
        works.reserveCapacity(workCount)
        for index in 0..<workCount {
            let work = SavedWork(title: "Work \(index)", author: "Author \(index % 10)")
            work.wordCount = 10_000
            work.workFandoms = ["Fandom \(index % 5)"]
            work.isSaved = true
            work.isFinished = true
            work.dateAdded = now.addingTimeInterval(TimeInterval(-(index + 1) * 3_600))
            context.insert(work)
            works.append(work)
        }
        try context.save()

        let augStart = date(month: 8, day: 1, hour: 8)
        for index in 0..<totalSessions {
            let work = works[index % workCount]
            let dayOffset = index % 20
            let start = augStart.addingTimeInterval(TimeInterval(dayOffset * 86_400 + (index / 20)))
            let session = ReadingSession(
                workID: work.id,
                workTitle: work.title,
                startedAt: start,
                endedAt: start.addingTimeInterval(60),
                durationSeconds: 60,
                startProgress: 0,
                endingProgress: 0.1,
                wordCount: 10_000,
                didFinish: false
            )
            session.fandoms = work.workFandoms
            context.insert(session)
            if (index + 1) % 5_000 == 0 {
                try context.save()
            }
        }
        try context.save()

        let request = InsightsGatherRequest(
            period: aug,
            previousPeriod: jul,
            periodMonths: 1,
            calendar: utcCalendar,
            options: InsightsOptions(),
            scope: .main,
            hideMature: false,
            revealed: false,
            includesHiddenSection: false,
            computesDigest: false,
            now: now,
            batchSize: batchSize
        )
        let actor = InsightsGatherActor(modelContainer: container)
        let output = try await actor.gather(request)
        let hasUnsaved = await actor.hasUnsavedChanges

        #expect(!hasUnsaved)
        #expect(output.fetches.worksFetched == workCount)
        #expect(output.fetches.workBatches == 1)
        #expect(output.fetches.sessionsFetched == totalSessions)
        #expect(output.fetches.sessionBatches == totalSessions / batchSize)
        #expect(output.fetches.largestBatch <= batchSize)
        #expect(output.main.insights.totalSeconds == Double(totalSessions * 60))
        #expect(output.main.insights.totalWordsRead > 0)
        #expect(output.main.libraryStats.totalWorks == workCount)
    }
}
