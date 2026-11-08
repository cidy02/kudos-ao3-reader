import Foundation
import Testing
@testable import Kudos

@MainActor
struct SubscriptionScanTests {
    @Test func pacesBetweenRequestStartsAndStaysSequential() async throws {
        let harness = ScanHarness()
        harness.page([follow(1), follow(2), follow(3)])
        harness.facts(1, posted: 2)
        harness.facts(2, posted: 4)
        harness.facts(3, posted: 1)
        let service = try harness.service()

        await service.run(username: "ada", fetcher: harness.fetcher)

        #expect(harness.events == [
            "page 1", "sleep 2", "work 1", "sleep 2", "work 2", "sleep 2", "work 3"
        ])
        #expect(harness.maxInFlight == 1)
        #expect(service.phase == .finished)
        #expect(service.updates.isEmpty)
        #expect(service.snapshots.map(\.workID).sorted() == [1, 2, 3])
    }

    @Test func pauseStopsBetweenWorksAndResumeContinues() async throws {
        let harness = ScanHarness()
        harness.page([follow(1), follow(2)])
        harness.facts(1, posted: 1)
        harness.facts(2, posted: 1)
        let service = try harness.service()
        harness.onWork = { id in
            if id == 1 { service.pause() }
        }

        let task = Task { await service.run(username: "ada", fetcher: harness.fetcher) }
        for _ in 0 ..< 1_000 where service.phase != .paused {
            await Task.yield()
        }

        #expect(service.phase == .paused)
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        #expect(harness.events.contains("work 2") == false)
        service.resume()
        await task.value
        #expect(service.phase == .finished)
        #expect(harness.events.contains("work 2"))
    }

    @Test func cancelKeepsTheWorksAlreadyChecked() async throws {
        let harness = ScanHarness()
        harness.page([follow(1), follow(2)])
        harness.facts(1, posted: 6, title: "Kept")
        harness.facts(2, posted: 1)
        let service = try harness.service()
        harness.onWork = { id in
            if id == 1 { service.cancel() }
        }

        await service.run(username: "ada", fetcher: harness.fetcher)

        #expect(service.phase == .idle)
        #expect(harness.events.contains("work 2") == false)
        let kept = try #require(service.snapshots.first { $0.workID == 1 })
        #expect(kept.title == "Kept")
        #expect(kept.chaptersPosted == 6)
        #expect(kept.gone == false)
        let reloaded = try ScanHarness(directory: harness.directory, scope: harness.scope).service()
        #expect(reloaded.snapshots.first { $0.workID == 1 }?.chaptersPosted == 6)
    }

    @Test func rateLimitWaitsAtLeastRetryAfterBeforeTheSameWork() async throws {
        let harness = ScanHarness()
        harness.page([follow(7)])
        harness.facts(7, posted: 2)
        harness.failOnce[7] = AO3Error.rateLimited(retryAfter: 30)
        let service = try harness.service()

        await service.run(username: "ada", fetcher: harness.fetcher)

        #expect(harness.events == ["page 1", "sleep 2", "work 7", "sleep 30", "work 7"])
        #expect(service.phase == .finished)
        #expect(service.snapshots.first?.chaptersPosted == 2)
    }

    @Test func forbiddenStopsAndMarksNothingGone() async throws {
        let harness = ScanHarness()
        harness.page([follow(1), follow(2), follow(3)])
        harness.facts(1, posted: 1)
        harness.facts(2, posted: 1)
        harness.facts(3, posted: 1)
        harness.failOnce[2] = AO3Error.forbidden
        let service = try harness.service()

        await service.run(username: "ada", fetcher: harness.fetcher)

        #expect(service.phase == .stopped)
        #expect(service.statusNote?.contains("403") == true)
        #expect(harness.events.contains("work 3") == false)
        #expect(service.snapshots.contains { $0.workID == 1 })
        #expect(service.snapshots.contains { $0.gone } == false)
    }

    @Test func notFoundMarksGoneAndDoesNotTouchTheLibraryHint() async throws {
        let harness = ScanHarness()
        harness.page([follow(4, title: "Gone Dark")])
        harness.failOnce[4] = AO3Error.notFound
        var library = [4: SubscriptionScanLibraryHint(postedChapters: 3, lastChecked: nil)]
        let original = library
        let service = try harness.service()

        await service.run(username: "ada", fetcher: harness.fetcher, library: library)

        #expect(library == original)
        let gone = try #require(service.snapshots.first)
        #expect(gone.gone)
        #expect(gone.title == "Gone Dark")
        #expect(service.updates.isEmpty)
    }

    @Test func maintenanceStopsOnTheFirstResponseAndMarksNothingGone() async throws {
        let harness = ScanHarness()
        let previous = snapshot(workID: 4, posted: 3, checkedAt: Date(timeIntervalSince1970: 10))
        try harness.seed(snapshots: [previous])
        harness.pageError = AO3Error.maintenance
        harness.page([follow(4)])
        let service = try harness.service()

        await service.run(username: "ada", fetcher: harness.fetcher)

        #expect(service.phase == .stopped)
        #expect(service.statusNote == SubscriptionScanCopy.maintenance)
        #expect(harness.events == ["page 1"])
        let kept = try #require(service.snapshots.first)
        #expect(kept.gone == false)
        #expect(kept.chaptersPosted == 3)
    }

    @Test func aRecentCheckIsNotRequested() async throws {
        let harness = ScanHarness()
        harness.page([follow(1), follow(2)])
        harness.facts(1, posted: 9)
        harness.facts(2, posted: 1)
        let fresh = snapshot(workID: 1, posted: 4, checkedAt: harness.now)
        try harness.seed(snapshots: [fresh], followed: [1])
        let service = try harness.service()

        await service.run(username: "ada", fetcher: harness.fetcher)

        #expect(harness.events.contains("work 1") == false)
        #expect(harness.events.contains("work 2"))
        #expect(service.snapshots.first { $0.workID == 1 }?.chaptersPosted == 4)
    }

    @Test func aLibraryCheckInsideTheCooldownIsNotRequested() async throws {
        let harness = ScanHarness()
        harness.page([follow(1)])
        harness.facts(1, posted: 5)
        let service = try harness.service()

        await service.run(
            username: "ada",
            fetcher: harness.fetcher,
            library: [1: SubscriptionScanLibraryHint(postedChapters: 2, lastChecked: harness.now)]
        )

        #expect(harness.events == ["page 1"])
        #expect(service.snapshots.isEmpty)
        #expect(service.updates.isEmpty)
    }

    @Test func firstScanIsABaselineAndALaterScanCanWait() async throws {
        let harness = ScanHarness()
        harness.page([follow(1, title: "Lantern"), follow(2, title: "Harbour")])
        harness.facts(1, posted: 3, title: "Lantern", words: 100, updated: "02 Jan 2026")
        harness.facts(2, posted: 8)
        let first = try harness.service()
        await first.run(
            username: "ada",
            fetcher: harness.fetcher,
            library: [1: SubscriptionScanLibraryHint(postedChapters: 1, lastChecked: nil)]
        )
        #expect(first.updates.isEmpty)
        #expect(first.snapshots.first { $0.workID == 1 }?.chaptersPosted == 3)
        #expect(first.snapshots.first { $0.workID == 1 }?.words == 100)
        #expect(first.snapshots.first { $0.workID == 1 }?.updatedAt != nil)

        harness.now.addTimeInterval(WorkUpdateChecker.minInterval + 60)
        harness.events.removeAll()
        harness.facts(1, posted: 4, title: "Lantern", words: 120, updated: "03 Jan 2026")
        let second = try harness.service()
        await second.run(username: "ada", fetcher: harness.fetcher)

        #expect(second.updates.count == 1)
        let update = try #require(second.updates.first)
        #expect(update.certainty == .confirmed)
        #expect(update.change == .newChapter(number: 4))
        #expect(update.source == .work)
        #expect(update.workTitle == "Lantern")
        #expect(second.snapshots.contains { $0.workID == 2 && $0.lastReportedPosted == nil })

        harness.now.addTimeInterval(WorkUpdateChecker.minInterval + 60)
        let third = try harness.service()
        await third.run(username: "ada", fetcher: harness.fetcher)
        #expect(third.updates.count == 1)
    }

    @Test func aheadOfTheLibraryCopyWaitsOnce() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let follow = SubscriptionScanFollow(workID: 5, title: "Salt", author: "Ada")
        let previous = snapshot(workID: 5, posted: 8, checkedAt: now)
        let facts = SubscriptionScanWorkFacts(
            title: "Salt",
            author: "Ada",
            chaptersPosted: 8,
            chaptersTotal: nil,
            words: nil,
            updatedText: "",
            updatedAt: nil,
            isComplete: false
        )
        let decision = SubscriptionScanJudge.decide(
            follow: follow,
            previous: previous,
            facts: facts,
            localPosted: 5,
            now: now,
            nextUpdateUID: 1
        )
        #expect(decision.update?.change == .newChapter(number: nil))
        let again = SubscriptionScanJudge.decide(
            follow: follow,
            previous: decision.snapshot,
            facts: facts,
            localPosted: 5,
            now: now,
            nextUpdateUID: decision.nextUpdateUID
        )
        #expect(again.update == nil)
    }

    @Test func parsesWorkPageChapterAndDateFacts() throws {
        var metadata = AO3WorkMetadata(id: 9)
        metadata.chapters = "1,002/1,002"
        metadata.words = 50
        metadata.dateUpdated = "02 Jan 2026"
        metadata.isComplete = true
        metadata.title = "Counted"
        let facts = SubscriptionScanWorkFacts(metadata: metadata)
        #expect(facts.chaptersPosted == 1_002)
        #expect(facts.chaptersTotal == 1_002)
        #expect(facts.words == 50)
        #expect(facts.isComplete == true)
        let updated = try #require(facts.updatedAt)
        let parts = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(secondsFromGMT: 0) ?? .gmt,
            from: updated
        )
        #expect(parts.year == 2026)
        #expect(parts.month == 1)
        #expect(parts.day == 2)
        #expect(SubscriptionScanWorkFacts.chapterCounts("12/?").posted == 12)
        #expect(SubscriptionScanWorkFacts.chapterCounts("12/?").total == nil)
        #expect(SubscriptionScanWorkFacts.parseUpdatedDate("2 Jan 2026") != nil)
    }

    @Test func snapshotsDoNotCrossAccounts() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let alice = SubscriptionScanStore(directoryURL: directory, authenticationScope: "signed-in:alice")
        var file = SubscriptionScanFile.empty(scope: "signed-in:alice")
        file.upsert(snapshot(workID: 1, posted: 2, checkedAt: Date(timeIntervalSince1970: 5)))
        try alice.save(file)

        let bob = SubscriptionScanStore(directoryURL: directory, authenticationScope: "signed-in:bob")
        let bobFile = try bob.load()
        #expect(bobFile.snapshots.isEmpty)

        let aliceAgain = try alice.load()
        #expect(aliceAgain.snapshots.map(\.workID) == [1])

        let planted = try JSONEncoder().encode(file)
        try planted.write(to: bob.fileURL, options: .atomic)
        let before = try Data(contentsOf: bob.fileURL)
        #expect(throws: SubscriptionScanStoreError.notWritable) { try bob.load() }
        #expect(throws: SubscriptionScanStoreError.notWritable) { try bob.save(file) }
        #expect(try Data(contentsOf: bob.fileURL) == before)
    }
}

@MainActor
private final class ScanHarness {
    let directory: URL
    let scope: String
    let log = ScanLog()
    let fetcher: FakeSubscriptionScanFetcher
    var now: Date {
        get { log.now }
        set { log.now = newValue }
    }

    var events: [String] {
        get { log.events }
        set { log.events = newValue }
    }

    var maxInFlight: Int { fetcher.maxInFlight }
    var onWork: ((Int) -> Void)? {
        get { fetcher.onWork }
        set { fetcher.onWork = newValue }
    }

    var pageError: Error? {
        get { fetcher.pageError }
        set { fetcher.pageError = newValue }
    }

    var failOnce: [Int: Error] {
        get { fetcher.failOnce }
        set { fetcher.failOnce = newValue }
    }

    init(directory: URL? = nil, scope: String = "signed-in:ada") {
        self.directory = directory ?? temporaryDirectory()
        fetcher = FakeSubscriptionScanFetcher(log: log)
        self.scope = scope
    }

    func service() throws -> SubscriptionScanService {
        let store = SubscriptionScanStore(directoryURL: directory, authenticationScope: scope)
        return SubscriptionScanService(store: store, timing: log.timing(pause: .seconds(2)))
    }

    func page(_ works: [SubscriptionScanFollow]) {
        fetcher.pages[1] = SubscriptionScanListPage(works: works, totalPages: 1)
    }

    func facts(
        _ workID: Int,
        posted: Int,
        title: String = "Work",
        words: Int? = nil,
        updated: String = ""
    ) {
        fetcher.facts[workID] = SubscriptionScanWorkFacts(
            title: title,
            author: "Ada",
            chaptersPosted: posted,
            chaptersTotal: nil,
            words: words,
            updatedText: updated,
            updatedAt: SubscriptionScanWorkFacts.parseUpdatedDate(updated),
            isComplete: false
        )
    }

    func seed(
        snapshots: [SubscriptionScanSnapshot],
        followed: [Int] = []
    ) throws {
        var file = SubscriptionScanFile.empty(scope: scope)
        file.followedWorkIDs = followed
        for snapshot in snapshots { file.upsert(snapshot) }
        try SubscriptionScanStore(directoryURL: directory, authenticationScope: scope).save(file)
    }
}

@MainActor
private final class ScanLog {
    var events: [String] = []
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    func timing(pause: Duration) -> SubscriptionScanTiming {
        // The scan service is MainActor, so its calls into these closures run there.
        SubscriptionScanTiming(
            now: { MainActor.assumeIsolated { self.now } },
            sleep: { duration in await self.advance(by: duration) },
            pause: pause
        )
    }

    func advance(by duration: Duration) {
        let seconds = SubscriptionScanClock.seconds(duration)
        events.append(String(format: "sleep %.0f", seconds))
        now = now.addingTimeInterval(seconds)
    }
}

@MainActor
private final class FakeSubscriptionScanFetcher: SubscriptionScanFetching {
    let log: ScanLog
    var pages: [Int: SubscriptionScanListPage] = [:]
    var facts: [Int: SubscriptionScanWorkFacts] = [:]
    var pageError: Error?
    var failOnce: [Int: Error] = [:]
    var onWork: ((Int) -> Void)?
    private var attempts: [Int: Int] = [:]
    private var inFlight = 0
    private(set) var maxInFlight = 0

    init(log: ScanLog) { self.log = log }

    func subscriptionPage(_ page: Int) async throws -> SubscriptionScanListPage {
        try await occupy("page \(page)")
        if page == 1, let pageError { throw pageError }
        return pages[page] ?? SubscriptionScanListPage(works: [], totalPages: page)
    }

    func workFacts(workID: Int) async throws -> SubscriptionScanWorkFacts {
        attempts[workID, default: 0] += 1
        try await occupy("work \(workID)")
        onWork?(workID)
        if attempts[workID] == 1, let error = failOnce[workID] { throw error }
        guard let facts = facts[workID] else { throw AO3Error.parse }
        return facts
    }

    private func occupy(_ event: String) async throws {
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        await Task.yield()
        inFlight -= 1
        log.events.append(event)
    }
}

private func follow(_ id: Int, title: String = "Work") -> SubscriptionScanFollow {
    SubscriptionScanFollow(workID: id, title: title, author: "Ada")
}

private func snapshot(workID: Int, posted: Int, checkedAt: Date) -> SubscriptionScanSnapshot {
    SubscriptionScanSnapshot(
        workID: workID,
        title: "Saved",
        author: "Ada",
        chaptersPosted: posted,
        chaptersTotal: nil,
        words: nil,
        updatedText: "",
        updatedAt: nil,
        isComplete: false,
        gone: false,
        checkedAt: checkedAt,
        lastReportedPosted: nil
    )
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("subscription-scan-\(UUID().uuidString)", isDirectory: true)
}
