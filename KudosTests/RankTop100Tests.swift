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

    private func stubClient(
        waits: RankTop100PaceRecorder? = nil
    ) -> AO3Client {
        let config = AO3Client.makeAnonymousSessionConfiguration()
        config.protocolClasses = [RankTop100StubProtocol.self]
        return AO3Client(
            session: URLSession(configuration: config),
            paceSleep: { delay in await waits?.record(delay) }
        )
    }

    private func clientError(
        status: Int,
        headers: [String: String] = [:]
    ) async -> AO3Error? {
        RankTop100StubProtocol.reset(status: status, headers: headers)
        do {
            _ = try await stubClient().rankTop100Page(request(2))
            Issue.record("Expected HTTP \(status) to fail")
            return nil
        } catch let error as AO3Error {
            return error
        } catch {
            Issue.record("Expected AO3Error, got \(error)")
            return nil
        }
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

    @Test func everyAutomatedFeaturePhraseIsHeaderSafeASCII() {
        for feature in AO3AutomatedFeature.allCases {
            #expect(feature.token.unicodeScalars.allSatisfy(\.isASCII))
            #expect(feature.phrase.unicodeScalars.allSatisfy(\.isASCII))
            #expect(!feature.token.contains("("))
            #expect(!feature.token.contains(")"))
            #expect(!feature.token.contains("\\"))
            #expect(!feature.phrase.contains("("))
            #expect(!feature.phrase.contains(")"))
            #expect(!feature.phrase.contains("\\"))
        }
    }

    @Test func taggedUserAgentReachesTheWire() async throws {
        RankTop100StubProtocol.reset()
        _ = try await stubClient().rankTop100Page(request(2))

        let hit = try #require(RankTop100StubProtocol.recorded().only)
        #expect(hit.userAgent == AO3RequestDefaults.userAgent(feature: .rankTop100))
    }

    @Test func throttledResponsesAreSentExactlyOnceWithoutRetry() async {
        for status in [429, 503] {
            _ = await clientError(status: status)
            #expect(RankTop100StubProtocol.recorded().count == 1)
        }
    }

    @Test func realClientRejectsLookalikeHostBeforeDispatch() async {
        RankTop100StubProtocol.reset()
        let foreign = RankTop100PageRequest(
            page: 2,
            url: URL(string: "https://archiveofourown.org.evil.example/works/search?page=2")!,
            scope: "anonymous"
        )
        do {
            _ = try await stubClient().rankTop100Page(foreign)
            Issue.record("Lookalike host reached the client")
        } catch AO3Error.untrustedHost {
            // expected
        } catch {
            Issue.record("Expected untrustedHost, got \(error)")
        }
        #expect(RankTop100StubProtocol.recorded().isEmpty)
    }

    @Test func retryAfterParsesSecondsAndHTTPDateThroughTheRealClient() async {
        let secondsError = await clientError(status: 429, headers: ["Retry-After": "180"])
        if case let .rateLimited(delay) = secondsError {
            #expect(delay == 180)
        } else {
            Issue.record("Seconds Retry-After was not parsed")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let date = formatter.string(from: Date().addingTimeInterval(300))
        let dateError = await clientError(status: 429, headers: ["Retry-After": date])
        if case let .rateLimited(delay) = dateError {
            #expect((295 ... 300).contains(delay ?? -1))
        } else {
            Issue.record("HTTP-date Retry-After was not parsed")
        }
    }

    @Test func realClientAppliesTheThreeSecondRankPaceFloor() async throws {
        let waits = RankTop100PaceRecorder()
        RankTop100StubProtocol.reset()
        let client = stubClient(waits: waits)

        _ = try await client.rankTop100Page(request(2, run: 10))
        _ = try await client.rankTop100Page(request(3, run: 10))

        #expect(await waits.values.contains { $0 >= RankTop100Feature.requestSpacing - 0.1 })
        #expect(RankTop100StubProtocol.recorded().count == 2)
    }

    @Test func realClientNormalizesURLSessionCancellation() async {
        RankTop100StubProtocol.reset(failure: .cancelled)
        do {
            _ = try await stubClient().rankTop100Page(request(2))
            Issue.record("Cancelled URLSession load unexpectedly succeeded")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
        #expect(RankTop100StubProtocol.recorded().count == 1)
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
            AO3Error.server(status: 502),
            AO3Error.server(status: 503),
            AO3Error.server(status: 504)
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
            if run == 1 { clock.advance(by: RankTop100Feature.minimumThrottleCooldown + 1) }
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

    @Test func rollingBudgetAndCacheExpireAfterTenMinutes() async {
        let (_, store) = defaultsAndStore()
        let clock = TestClock()
        for _ in 0 ..< RankTop100Feature.requestBudget {
            #expect(await store.reserveRequest(at: clock.now()) == .available)
        }
        if case .budgetRenews = await store.reserveRequest(at: clock.now()) {
            // expected
        } else {
            Issue.record("Budget did not stop request eleven")
        }

        let cachedRequest = request(2, run: 200)
        await store.remember(page(2), for: cachedRequest, at: clock.now())
        #expect(await store.cachedPage(for: cachedRequest, at: clock.now()) != nil)
        clock.advance(by: RankTop100Feature.cacheLifetime + 1)
        #expect(await store.availability(at: clock.now()) == .available)
        #expect(await store.cachedPage(for: cachedRequest, at: clock.now()) == nil)
    }

    @Test func cacheIsIsolatedByScopeAndURLAndCappedAtSixtyFour() async {
        let (_, store) = defaultsAndStore()
        let clock = TestClock()
        let first = request(2, run: 300)
        await store.remember(page(2), for: first, at: clock.now())
        let otherScope = RankTop100PageRequest(page: 2, url: first.url, scope: "auth:1")
        let otherURL = request(2, run: 301)
        #expect(await store.cachedPage(for: otherScope, at: clock.now()) == nil)
        #expect(await store.cachedPage(for: otherURL, at: clock.now()) == nil)

        for run in 301 ... 364 {
            clock.advance(by: 1)
            await store.remember(page(run), for: request(2, run: run), at: clock.now())
        }
        #expect(await store.cachedPage(for: first, at: clock.now()) == nil)
        #expect(await store.cachedPage(for: request(2, run: 364), at: clock.now()) != nil)
        await store.purgeCache()
        #expect(await store.cachedPage(for: request(2, run: 364), at: clock.now()) == nil)
    }

    @Test func loaderSkipsEveryPageOutsideTwoThroughFive() async {
        let (_, store) = defaultsAndStore()
        let clock = TestClock()
        let recorder = Recorder()
        let loader = RankTop100Loader(store: store, clock: clock.dependency)
        let candidates = [request(6), request(2), request(1), request(5), request(0)]

        _ = await loader.run(requests: candidates, existingPages: [:]) { request in
            await recorder.record(request.page, at: clock.now())
            return page(request.page)
        }
        #expect(await recorder.pages == [2, 5])
    }

    @Test func finalReservationGateSeesThrottleRecordedByAnotherRun() async {
        let (_, store) = defaultsAndStore()
        let clock = TestClock()
        let recorder = Recorder()
        let loader = RankTop100Loader(store: store, clock: clock.dependency)

        let outcome = await loader.run(requests: [request(2), request(3)], existingPages: [:]) { request in
            await recorder.record(request.page, at: clock.now())
            _ = await store.recordThrottle(.forbidden, at: clock.now())
            return page(request.page)
        }

        #expect(await recorder.pages == [2])
        if case .unavailable(.retryAfter) = outcome.stop {
            // The second page reached reserveRequest only after its spacing wait.
        } else {
            Issue.record("Final gate did not observe the persisted throttle: \(outcome.stop)")
        }
    }

    @Test func throttleStatePersistsAcrossStoresAndAlwaysHasACooldown() async {
        let (defaults, firstStore) = defaultsAndStore()
        let clock = TestClock()
        _ = await firstStore.recordThrottle(.forbidden, at: clock.now())
        let secondStore = RankTop100Store(defaults: defaults)
        if case let .retryAfter(until) = await secondStore.availability(at: clock.now()) {
            #expect(until == clock.now().addingTimeInterval(RankTop100Feature.minimumThrottleCooldown))
        } else {
            Issue.record("Throttle state did not survive a new store")
        }

        for error in [
            AO3Error.rateLimited(retryAfter: nil), .forbidden,
            .server(status: 502), .server(status: 503), .server(status: 504)
        ] {
            let (_, store) = defaultsAndStore()
            if case let .retryAfter(until) = await store.recordThrottle(error, at: clock.now()) {
                #expect(until >= clock.now().addingTimeInterval(RankTop100Feature.minimumThrottleCooldown))
            } else {
                Issue.record("\(error) did not apply the minimum cooldown")
            }
        }
    }

    @Test func throttleRunsUseARollingTwentyFourHourBoundary() async {
        let (_, insideStore) = defaultsAndStore()
        let insideClock = TestClock()
        _ = await insideStore.recordThrottle(.forbidden, at: insideClock.now())
        insideClock.advance(by: RankTop100Feature.throttleCooldown - 1)
        #expect(
            await insideStore.recordThrottle(.forbidden, at: insideClock.now())
                == .throttledUntil(insideClock.now().addingTimeInterval(RankTop100Feature.throttleCooldown))
        )

        let (_, boundaryStore) = defaultsAndStore()
        let boundaryClock = TestClock()
        _ = await boundaryStore.recordThrottle(.forbidden, at: boundaryClock.now())
        boundaryClock.advance(by: RankTop100Feature.throttleCooldown)
        if case .retryAfter = await boundaryStore.recordThrottle(.forbidden, at: boundaryClock.now()) {
            // Exactly 24 hours old is outside the rolling window.
        } else {
            Issue.record("Exact rolling-window boundary counted as a second run")
        }
    }

    @Test func retryAfterIsValidatedClampedAndFarFutureStoredDatesAreIgnored() async {
        let clock = TestClock()
        let (_, hugeStore) = defaultsAndStore()
        _ = await hugeStore.recordThrottle(.rateLimited(retryAfter: 1e10), at: clock.now())
        #expect(
            await hugeStore.availability(at: clock.now())
                == .retryAfter(clock.now().addingTimeInterval(RankTop100Feature.throttleCooldown))
        )

        for invalid in [TimeInterval.infinity, -1] {
            let (_, store) = defaultsAndStore()
            _ = await store.recordThrottle(.rateLimited(retryAfter: invalid), at: clock.now())
            #expect(
                await store.availability(at: clock.now())
                    == .retryAfter(clock.now().addingTimeInterval(RankTop100Feature.minimumThrottleCooldown))
            )
        }

        let farFuture = clock.now()
            .addingTimeInterval(RankTop100Feature.throttleCooldown + 1)
            .timeIntervalSince1970
        for key in ["ao3.rankTop100.retryAfter", "ao3.rankTop100.throttledUntil"] {
            let (defaults, _) = defaultsAndStore()
            defaults.set(farFuture, forKey: key)
            #expect(await RankTop100Store(defaults: defaults).availability(at: clock.now()) == .available)
        }
    }

    @Test func injectedOffSwitchRefusesEveryReservation() async {
        let name = "RankTop100Tests-Off-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let store = RankTop100Store(defaults: defaults, isEnabled: false)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(await store.availability(at: now) == .releaseDisabled)
        #expect(await store.reserveRequest(at: now) == .releaseDisabled)
    }

    @MainActor @Test func doubleTapDoesNotRestartARunningController() async {
        let (_, store) = defaultsAndStore()
        let clock = TestClock()
        let recorder = Recorder()
        let started = Signal()
        let release = Signal()
        let controller = RankTop100Controller(loader: RankTop100Loader(store: store, clock: clock.dependency))
        let load: @Sendable (RankTop100PageRequest) async throws -> AO3SearchPage = { request in
            await recorder.record(request.page, at: clock.now())
            await started.fire()
            await release.wait()
            return page(request.page)
        }

        controller.start(requests: [request(2)], existingPages: [:], load: load, onPages: { _ in })
        controller.start(requests: [request(2)], existingPages: [:], load: load, onPages: { _ in })
        await started.wait()
        #expect(await recorder.pages == [2])
        await release.fire()
        for _ in 0 ..< 5 { await Task.yield() }
    }

    @MainActor @Test func controllerReenablesWhenPersistedCooldownPasses() async {
        let (_, store) = defaultsAndStore()
        let clock = TestClock()
        _ = await store.recordThrottle(.forbidden, at: clock.now())
        let controller = RankTop100Controller(
            loader: RankTop100Loader(store: store, clock: clock.dependency)
        )

        await controller.refreshAvailability()
        for _ in 0 ..< 5 { await Task.yield() }

        #expect(controller.availability == .available)
        #expect(controller.canStart)
    }
}

private actor RankTop100PaceRecorder {
    private(set) var values: [TimeInterval] = []
    func record(_ value: TimeInterval) { values.append(value) }
}

/// Local-only session transport: every request is intercepted, recorded and
/// answered from memory, so these policy tests can never contact AO3.
private final class RankTop100StubProtocol: URLProtocol, @unchecked Sendable {
    struct Hit: Sendable {
        let url: URL?
        let userAgent: String?
    }

    private static let lock = NSLock()
    private static var hits: [Hit] = []
    private static var status = 200
    private static var headers: [String: String] = [:]
    private static var failure: URLError.Code?

    static func reset(
        status: Int = 200,
        headers: [String: String] = [:],
        failure: URLError.Code? = nil
    ) {
        lock.lock()
        hits = []
        self.status = status
        self.headers = headers
        self.failure = failure
        lock.unlock()
    }

    static func recorded() -> [Hit] {
        lock.lock()
        defer { lock.unlock() }
        return hits
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.hits.append(Hit(
            url: request.url,
            userAgent: request.value(forHTTPHeaderField: "User-Agent")
        ))
        let status = Self.status
        let headers = Self.headers
        let failure = Self.failure
        Self.lock.unlock()

        if let failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }

        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: status,
                  httpVersion: "HTTP/1.1",
                  headerFields: headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("<html><body></body></html>".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}
