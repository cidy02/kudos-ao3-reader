import Foundation
import OSLog

/// App-scoped subscriptions scan. The user starts it; nothing here runs on
/// launch, from a BGTask, or on a timer. One coordinator slot, then a pause
/// between requests no shorter than series preservation.
@MainActor
@Observable
final class SubscriptionScanService {
    private(set) var phase: SubscriptionScanPhase = .idle
    private(set) var checked = 0
    private(set) var total = 0
    private(set) var username = ""
    private(set) var remaining: Duration?
    private(set) var statusNote: String?
    private(set) var file: SubscriptionScanFile

    var updates: [SubscriptionUpdate] { file.updates }
    var snapshots: [SubscriptionScanSnapshot] { file.snapshots }
    var isActive: Bool { phase == .running || phase == .paused || phase == .stopped }

    var goneWorkIDs: Set<Int> {
        Set(file.snapshots.filter(\.gone).map(\.workID))
    }

    var dueCount: Int {
        let now = timing.now()
        return file.followedWorkIDs.filter { id in
            guard let checkedAt = file.snapshot(for: id)?.checkedAt else { return true }
            return now.timeIntervalSince(checkedAt) >= WorkUpdateChecker.minInterval
        }.count
    }

    var latestCheckedAt: Date? {
        file.snapshots.map(\.checkedAt).max()
    }

    /// Baselines already recorded while this scan has not finished every follow,
    /// including a scan that stopped partway. Sorted by AO3's updated date.
    /// These are not "new chapter" claims.
    var partialBaselines: [SubscriptionScanSnapshot] {
        guard phase == .running || phase == .paused || phase == .stopped else { return [] }
        guard total == 0 || checked < total else { return [] }
        return file.snapshots
            .filter { snapshot in
                !snapshot.gone && file.followedWorkIDs.contains(snapshot.workID)
            }
            .sorted { lhs, rhs in
                switch (lhs.updatedAt, rhs.updatedAt) {
                case let (left?, right?):
                    return left == right
                        ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                        : left > right
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none):
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
    }

    private let timing: SubscriptionScanTiming
    private let coordinator: AO3RequestCoordinator
    private var store: SubscriptionScanStore
    private var storeLocked = false
    private var library: [Int: SubscriptionScanLibraryHint] = [:]
    private var task: Task<Void, Never>?
    private var isExecuting = false
    private var stopRequested = false
    private var pauseRequested = false
    private var resumeContinuation: CheckedContinuation<Void, Error>?
    private var requestSamples: [TimeInterval] = []
    /// Bumped on account switch so an in-flight scan cannot write the next account's file.
    private var generation = 0
    private var loopGeneration = 0
    /// True after this scan has made a request, so the next request waits out the pause.
    private var didRequest = false

    /// How many times a 429 may pause this scan before the scan stops and says so.
    private static let maxRateLimitWaits = 3
    /// A broken `totalPages` must not walk forever. Real lists stop earlier.
    private static let maxSubscriptionPages = 100

    init(
        store: SubscriptionScanStore = SubscriptionScanStore(
            directoryURL: SubscriptionScanStore.defaultDirectory,
            authenticationScope: "anonymous"
        ),
        timing: SubscriptionScanTiming = .live,
        coordinator: AO3RequestCoordinator = AO3RequestCoordinator(limit: 1)
    ) {
        self.store = store
        self.timing = timing
        self.coordinator = coordinator
        file = .empty(scope: store.authenticationScope)
        reloadStore()
    }

    #if DEBUG
    /// Frozen display state for snapshots. Does not start a scan or read an account file.
    convenience init(
        snapshot phase: SubscriptionScanPhase,
        checked: Int = 0,
        total: Int = 0,
        remaining: Duration? = nil,
        statusNote: String? = nil
    ) {
        self.init(
            store: SubscriptionScanStore(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("kudos-subscription-scan-snapshot", isDirectory: true),
                authenticationScope: "snapshot"
            )
        )
        self.phase = phase
        self.checked = checked
        self.total = total
        self.remaining = remaining
        self.statusNote = statusNote
    }
    #endif

    func adopt(authenticationScope: String) {
        guard store.authenticationScope != authenticationScope else { return }
        generation += 1
        cancel()
        isExecuting = false
        store = SubscriptionScanStore(
            directoryURL: store.directoryURL,
            authenticationScope: authenticationScope
        )
        reloadStore()
        if !storeLocked { statusNote = nil }
        phase = .idle
        checked = 0
        total = 0
        remaining = nil
        username = ""
    }

    func applying(_ work: AO3WorkSummary) -> AO3WorkSummary {
        guard let snapshot = file.snapshot(for: work.id), !snapshot.gone else { return work }
        var copy = work
        if let isComplete = snapshot.isComplete {
            copy.isComplete = isComplete
        }
        return copy
    }

    func start(
        username: String,
        fetcher: any SubscriptionScanFetching,
        library: [Int: SubscriptionScanLibraryHint] = [:]
    ) {
        guard !isExecuting else { return }
        guard !username.isEmpty else {
            phase = .stopped
            statusNote = "Log in to AO3 before scanning subscriptions."
            return
        }
        isExecuting = true
        let token = generation
        task = Task { [weak self] in
            guard let self else { return }
            await self.loop(username: username, fetcher: fetcher, library: library)
            if self.generation == token { self.isExecuting = false }
        }
    }

    func pause() {
        guard phase == .running else { return }
        pauseRequested = true
        phase = .paused
    }

    func resume() {
        guard pauseRequested || phase == .paused else { return }
        pauseRequested = false
        phase = .running
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    /// Stop between works. Snapshots and Waiting rows already recorded stay.
    func cancel() {
        stopRequested = true
        pauseRequested = false
        let continuation = resumeContinuation
        resumeContinuation = nil
        continuation?.resume(throwing: CancellationError())
        task?.cancel()
        if !isExecuting {
            phase = .idle
            statusNote = nil
        }
    }

    /// Test entry. Production starts through `start`, which owns the task.
    func run(
        username: String,
        fetcher: any SubscriptionScanFetching,
        library: [Int: SubscriptionScanLibraryHint] = [:]
    ) async {
        guard !isExecuting else { return }
        isExecuting = true
        let token = generation
        defer { if generation == token { isExecuting = false } }
        await loop(username: username, fetcher: fetcher, library: library)
    }

    private func reloadStore() {
        do {
            file = try store.load()
            storeLocked = false
        } catch {
            file = .empty(scope: store.authenticationScope)
            storeLocked = true
            statusNote = "Saved scan data for this account couldn't be read."
        }
    }

    private func loop(
        username: String,
        fetcher: any SubscriptionScanFetching,
        library: [Int: SubscriptionScanLibraryHint]
    ) async {
        self.username = username
        self.library = library
        checked = 0
        total = 0
        remaining = nil
        statusNote = storeLocked ? statusNote : nil
        requestSamples = []
        stopRequested = false
        pauseRequested = false
        didRequest = false
        loopGeneration = generation
        phase = .running
        Log.network.info("Subscription scan starting")
        do {
            statusNote = "Reading your subscriptions…"
            let follows = try await loadFollows(fetcher)
            try ensureAccount()
            if statusNote == "Reading your subscriptions…" { statusNote = nil }
            file.followedWorkIDs = follows.map(\.workID)
            persist()
            total = follows.count
            try await checkAll(follows, fetcher: fetcher)
            guard generation == loopGeneration else { return }
            phase = stopRequested ? .idle : .finished
            if phase == .finished, statusNote == "Reading your subscriptions…" { statusNote = nil }
            remaining = phase == .finished ? .zero : remaining
        } catch is CancellationError {
            guard generation == loopGeneration else { return }
            phase = .idle
        } catch {
            guard generation == loopGeneration else { return }
            phase = .stopped
            statusNote = Self.message(for: error)
            remaining = nil
            Log.network.info("Subscription scan stopped: \(self.statusNote ?? "", privacy: .public)")
        }
    }

    private func loadFollows(
        _ fetcher: any SubscriptionScanFetching
    ) async throws -> [SubscriptionScanFollow] {
        var page = 1
        var follows: [SubscriptionScanFollow] = []
        var seen = Set<Int>()
        var requested = false
        while page <= Self.maxSubscriptionPages {
            try await checkpoint()
            if requested { try await pauseBetween() }
            let started = timing.now()
            let listed = try await perform { try await fetcher.subscriptionPage(page) }
            try ensureAccount()
            recordSample(since: started)
            requested = true
            didRequest = true
            if listed.works.isEmpty { break }
            var added = 0
            for work in listed.works where seen.insert(work.workID).inserted {
                follows.append(work)
                added += 1
            }
            if added == 0 || page >= max(listed.totalPages, 1) { break }
            if page == Self.maxSubscriptionPages {
                statusNote = "Stopped after \(Self.maxSubscriptionPages) subscription pages."
                break
            }
            page += 1
        }
        return follows
    }

    private func checkAll(
        _ follows: [SubscriptionScanFollow],
        fetcher: any SubscriptionScanFetching
    ) async throws {
        for (index, follow) in follows.enumerated() {
            try await checkpoint()
            if shouldSkip(follow.workID) {
                checked += 1
                refreshRemaining(follows, after: index)
                continue
            }
            if didRequest { try await pauseBetween() }
            try await checkpoint()
            try await checkOne(follow, fetcher: fetcher)
            didRequest = true
            checked += 1
            refreshRemaining(follows, after: index)
        }
    }

    private func checkOne(
        _ follow: SubscriptionScanFollow,
        fetcher: any SubscriptionScanFetching
    ) async throws {
        let started = timing.now()
        do {
            let facts = try await perform { try await fetcher.workFacts(workID: follow.workID) }
            try ensureAccount()
            recordSample(since: started)
            let decision = SubscriptionScanJudge.decide(
                follow: follow,
                previous: file.snapshot(for: follow.workID),
                facts: facts,
                localPosted: library[follow.workID]?.postedChapters,
                now: timing.now(),
                nextUpdateUID: file.nextUpdateUID
            )
            file.upsert(decision.snapshot)
            file.nextUpdateUID = decision.nextUpdateUID
            if let update = decision.update {
                file.updates.append(update)
                trimUpdates()
            }
            persist()
        } catch AO3Error.notFound {
            try ensureAccount()
            recordSample(since: started)
            file.upsert(SubscriptionScanJudge.gone(
                follow: follow,
                previous: file.snapshot(for: follow.workID),
                now: timing.now()
            ))
            persist()
        } catch AO3Error.parse {
            try ensureAccount()
            recordSample(since: started)
            file.upsert(SubscriptionScanJudge.unreadable(
                follow: follow,
                previous: file.snapshot(for: follow.workID),
                now: timing.now()
            ))
            persist()
        }
    }

    private func perform<T>(_ body: () async throws -> T) async throws -> T {
        var waits = 0
        while true {
            try await checkpoint()
            do {
                return try await coordinator.withSlot { try await body() }
            } catch let error as AO3Error {
                guard case let .rateLimited(retryAfter) = error else { throw error }
                waits += 1
                if waits > Self.maxRateLimitWaits { throw error }
                try await wait(for: retryAfter)
            }
        }
    }

    private func wait(for retryAfter: TimeInterval?) async throws {
        let pause = SubscriptionScanClock.seconds(timing.pause)
        let seconds = max(retryAfter ?? pause, pause)
        statusNote = "AO3 asked us to wait."
        try await timing.sleep(SubscriptionScanClock.duration(seconds: seconds))
        if statusNote == "AO3 asked us to wait." { statusNote = nil }
        try await checkpoint()
    }

    private func pauseBetween() async throws {
        try await checkpoint()
        guard SubscriptionScanClock.seconds(timing.pause) > 0 else { return }
        try await timing.sleep(timing.pause)
        try await checkpoint()
    }

    private func ensureAccount() throws {
        if generation != loopGeneration { throw CancellationError() }
    }

    private func checkpoint() async throws {
        try ensureAccount()
        if stopRequested { throw CancellationError() }
        try Task.checkCancellation()
        guard pauseRequested else { return }
        phase = .paused
        try await withCheckedThrowingContinuation { continuation in
            resumeContinuation = continuation
        }
        resumeContinuation = nil
        try ensureAccount()
        if stopRequested { throw CancellationError() }
        try Task.checkCancellation()
        phase = .running
    }

    private func shouldSkip(_ workID: Int) -> Bool {
        if isFresh(file.snapshot(for: workID)?.checkedAt) { return true }
        if isFresh(library[workID]?.lastChecked) { return true }
        return false
    }

    private func isFresh(_ date: Date?) -> Bool {
        guard let date else { return false }
        return timing.now().timeIntervalSince(date) < WorkUpdateChecker.minInterval
    }

    private func recordSample(since start: Date) {
        let elapsed = timing.now().timeIntervalSince(start)
        guard elapsed >= 0 else { return }
        requestSamples.append(elapsed)
    }

    private func refreshRemaining(_ follows: [SubscriptionScanFollow], after index: Int) {
        guard let mean = meanSample else {
            remaining = nil
            return
        }
        let left = follows.suffix(from: follows.index(after: index)).filter { !shouldSkip($0.workID) }.count
        let each = mean + SubscriptionScanClock.seconds(timing.pause)
        remaining = SubscriptionScanClock.duration(seconds: each * Double(left))
    }

    private var meanSample: TimeInterval? {
        guard !requestSamples.isEmpty else { return nil }
        return requestSamples.reduce(0, +) / Double(requestSamples.count)
    }

    private func trimUpdates() {
        let limit = SubscriptionUpdateState.limit
        guard file.updates.count > limit else { return }
        file.updates = Array(file.updates.suffix(limit))
    }

    private func persist() {
        guard !storeLocked else { return }
        do {
            try store.save(file)
        } catch {
            statusNote = "Couldn't save this scan on this device."
        }
    }

    private static func message(for error: Error) -> String {
        if let ao3 = error as? AO3Error {
            return ao3.errorDescription ?? "The scan stopped."
        }
        return error.localizedDescription
    }
}

/// Production fetcher. Subscription list: the signed-in user's own
/// `?type=works` page. Each follow: `AO3Client.workMetadata`, the same
/// `/works/<id>?view_adult=true` page update checks already parse.
///
/// `/works/<id>/navigate` is not enough. otwarchive `452391b6` (2026-11-01)
/// `app/views/works/navigate.html.erb` renders only chapter titles and
/// `published_at`. Posted/expected chapters, words, and Updated/Completed come
/// from `WorksHelper#work_meta_list` (`app/helpers/works_helper.rb`), embedded
/// by `app/views/works/_meta.html.erb`. `chapter_total_display` is `posted/expected`.
@MainActor
struct LiveSubscriptionScanFetcher: SubscriptionScanFetching {
    let auth: AO3AuthService

    func subscriptionPage(_ page: Int) async throws -> SubscriptionScanListPage {
        guard auth.isLoggedIn, let username = auth.username,
              let url = AO3Client.subscriptionsURL(username: username, page: page)
        else { throw AO3Error.authenticationRequired }
        let request = try auth.authenticatedRequest(for: url)
        let listed = try await AO3Client.shared.subscriptionsPage(for: request, page: page)
        return SubscriptionScanListPage(
            works: listed.works.map {
                SubscriptionScanFollow(workID: $0.id, title: $0.title, author: $0.authorText)
            },
            totalPages: listed.totalPages
        )
    }

    func workFacts(workID: Int) async throws -> SubscriptionScanWorkFacts {
        guard let url = URL(string: "https://archiveofourown.org/works/\(workID)?view_adult=true") else {
            throw AO3Error.network("Bad work URL.")
        }
        let request = try auth.authenticatedRequest(for: url)
        let metadata = try await AO3Client.shared.workMetadata(workID: workID, request: request)
        return SubscriptionScanWorkFacts(metadata: metadata)
    }
}
