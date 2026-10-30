import Foundation
import Testing
@testable import Kudos

@Suite(.serialized)
struct RankTop100Tests {
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date

        init(_ value: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
            self.value = value
        }

        func now() -> Date {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func advance(to deadline: Date) {
            lock.lock()
            value = max(value, deadline)
            lock.unlock()
        }

        func advance(by interval: TimeInterval) {
            lock.lock()
            value = value.addingTimeInterval(interval)
            lock.unlock()
        }

        var dependency: RankTop100Clock {
            RankTop100Clock(
                now: { self.now() },
                sleepUntil: { self.advance(to: $0) }
            )
        }
    }

    private actor Recorder {
        private(set) var pages: [Int] = []
        private(set) var starts: [Date] = []

        func record(_ page: Int, at date: Date) {
            pages.append(page)
            starts.append(date)
        }
    }

    private actor Signal {
        private var fired = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func fire() {
            fired = true
            waiters.forEach { $0.resume() }
            waiters = []
        }

        func wait() async {
            if fired { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    private struct StubFailure: LocalizedError, Sendable {
        var errorDescription: String? { "stub failed" }
    }

    private func defaultsAndStore() -> (UserDefaults, RankTop100Store) {
        let name = "RankTop100Tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, RankTop100Store(defaults: defaults))
    }

    private func request(_ page: Int, run: Int = 1) -> RankTop100PageRequest {
        RankTop100PageRequest(
            page: page,
            url: URL(string: "https://archiveofourown.org/works/search?run=\(run)&page=\(page)")!,
            scope: "anonymous"
        )
    }

    private func requests(run: Int = 1) -> [RankTop100PageRequest] {
        (2 ... 5).map { request($0, run: run) }
    }

    private func page(_ number: Int) -> AO3SearchPage {
        AO3SearchPage(
            works: [work(number)],
            currentPage: number,
            totalPages: 20,
            summary: nil
        )
    }

    private func work(_ id: Int) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: "Work \(id)",
            authors: [],
            authorIdentities: [],
            fandoms: [],
            rating: "",
            warnings: [],
            categories: [],
            isComplete: true,
            dateUpdated: "",
            tags: [],
            summary: "",
            language: "English",
            words: 1_000,
            chapters: "1/1",
            comments: 0,
            kudos: 1,
            bookmarks: 0,
            hits: 10,
            seriesTitle: nil,
            seriesURL: nil,
            seriesPosition: nil
        )
    }

    @Test func userAgentPurposeTagIsExactAndNilIsPlain() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let base = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 "
            + "KudosReader/\(version) (+https://github.com/cidy02/kudos-ao3-reader)"
        let tagged = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 "
            + "KudosReader/\(version) (+https://github.com/cidy02/kudos-ao3-reader; "
            + "feature=rank-top-100; reader-requested pages 2-5)"

        #expect(AO3RequestDefaults.userAgent == base)
        #expect(AO3RequestDefaults.userAgent(feature: nil) == AO3RequestDefaults.userAgent)
        #expect(AO3RequestDefaults.userAgent(feature: .rankTop100) == tagged)
        #expect(AO3AutomatedFeature.rankTop100.token == "feature=rank-top-100")
        #expect(AO3AutomatedFeature.rankTop100.phrase == "reader-requested pages 2-5")
    }

    @Test func pageCapIsFiveAndRollingBudgetStopsTheEleventhRequest() async {
        let (_, store) = defaultsAndStore()
        let clock = TestClock()
        let loader = RankTop100Loader(store: store, clock: clock.dependency)
        let recorder = Recorder()

        let source = RankTop100URLSource.search(filters: AO3SearchFilters(), additionalQueryClause: nil)
        #expect(source.requests(through: 99, scope: "anonymous").map(\.page) == [2, 3, 4, 5])

        var last: RankTop100Outcome?
        for run in 1 ... 3 {
            last = await loader.run(requests: requests(run: run), existingPages: [:]) { request in
                await recorder.record(request.page, at: clock.now())
                return page(request.page)
            }
        }
        #expect(await recorder.pages.count == 10)
        guard let last else { return }
        if case .unavailable(.budgetRenews) = last.stop {
            // expected
        } else {
            Issue.record("Expected the rolling budget to refuse request 11, got \(last.stop)")
        }
    }

    @Test func requestStartsAreStrictlySequentialAndAtLeastThreeSecondsApart() async {
        let (_, store) = defaultsAndStore()
        let clock = TestClock()
        let recorder = Recorder()
        let loader = RankTop100Loader(store: store, clock: clock.dependency)

        _ = await loader.run(requests: requests(), existingPages: [:]) { request in
            await recorder.record(request.page, at: clock.now())
            return page(request.page)
        }

        let starts = await recorder.starts
        #expect(await recorder.pages == [2, 3, 4, 5])
        #expect(zip(starts.dropFirst(), starts).allSatisfy { pair in
            pair.0.timeIntervalSince(pair.1) >= RankTop100Feature.requestSpacing
        })
    }

    @Test func everyErrorStopsBeforeTheNextPage() async {
        let failures: [AO3Error] = [
            AO3Error.rateLimited(retryAfter: nil),
            AO3Error.forbidden,
            AO3Error.server(status: 503)
        ]

        for failure in failures {
            let (_, store) = defaultsAndStore()
            let clock = TestClock()
            let recorder = Recorder()
            let loader = RankTop100Loader(store: store, clock: clock.dependency)
            let outcome = await loader.run(requests: requests(), existingPages: [:]) { request in
                await recorder.record(request.page, at: clock.now())
                if request.page == 3 { throw failure }
                return page(request.page)
            }
            #expect(await recorder.pages == [2, 3])
            #expect(outcome.pages.keys.sorted() == [2])
            #expect(outcome.stop != .completed)
        }

        let (_, store) = defaultsAndStore()
        let clock = TestClock()
        let recorder = Recorder()
        let loader = RankTop100Loader(store: store, clock: clock.dependency)
        let outcome = await loader.run(requests: requests(), existingPages: [:]) { request in
            await recorder.record(request.page, at: clock.now())
            if request.page == 3 { throw StubFailure() }
            return page(request.page)
        }
        #expect(await recorder.pages == [2, 3])
        #expect(outcome.pages.keys.sorted() == [2])
        #expect(outcome.stop == .failed("stub failed"))
    }

    @Test func retryAfterDisablesUntilItPasses() async {
        let (_, store) = defaultsAndStore()
        let clock = TestClock()
        let loader = RankTop100Loader(store: store, clock: clock.dependency)

        _ = await loader.run(requests: [request(2)], existingPages: [:]) { _ in
            throw AO3Error.rateLimited(retryAfter: 120)
        }
        if case let .retryAfter(until) = await store.availability(at: clock.now()) {
            #expect(until == clock.now().addingTimeInterval(120))
        } else {
            Issue.record("Retry-After did not disable Rank Top 100")
        }
        clock.advance(by: 121)
        #expect(await store.availability(at: clock.now()) == .available)
    }

    @Test func twoThrottledRunsTurnItOffForTwentyFourHoursThenRecover() async {
        let (_, store) = defaultsAndStore()
        let clock = TestClock()
        let loader = RankTop100Loader(store: store, clock: clock.dependency)

        for run in 1 ... 2 {
            _ = await loader.run(requests: [request(2, run: run)], existingPages: [:]) { _ in
                throw AO3Error.forbidden
            }
        }
        if case let .throttledUntil(until) = await store.availability(at: clock.now()) {
            #expect(until == clock.now().addingTimeInterval(RankTop100Feature.throttleCooldown))
        } else {
            Issue.record("Two throttled runs did not start the 24-hour cooldown")
        }
        clock.advance(by: RankTop100Feature.throttleCooldown + 1)
        #expect(await store.availability(at: clock.now()) == .available)
    }

    @Test func freshParsedPageCacheSkipsEveryRepeatRequest() async {
        let (_, store) = defaultsAndStore()
        let clock = TestClock()
        let recorder = Recorder()
        let loader = RankTop100Loader(store: store, clock: clock.dependency)
        let stub: @Sendable (RankTop100PageRequest) async throws -> AO3SearchPage = { request in
            await recorder.record(request.page, at: clock.now())
            return page(request.page)
        }

        _ = await loader.run(requests: requests(), existingPages: [:], load: stub)
        _ = await loader.run(requests: requests(), existingPages: [:], load: stub)
        #expect(await recorder.pages == [2, 3, 4, 5])
    }

    @Test func cancellingAnInFlightPagePreventsEveryLaterRequest() async {
        let (_, store) = defaultsAndStore()
        let clock = TestClock()
        let recorder = Recorder()
        let started = Signal()
        let release = Signal()
        let loader = RankTop100Loader(store: store, clock: clock.dependency)

        let task = Task {
            await loader.run(requests: requests(), existingPages: [:]) { request in
                await recorder.record(request.page, at: clock.now())
                await started.fire()
                await release.wait()
                try Task.checkCancellation()
                return page(request.page)
            }
        }
        await started.wait()
        task.cancel()
        await release.fire()
        let outcome = await task.value

        #expect(await recorder.pages == [2])
        #expect(outcome.pages.isEmpty)
        #expect(outcome.stop == .cancelled)
    }
}
