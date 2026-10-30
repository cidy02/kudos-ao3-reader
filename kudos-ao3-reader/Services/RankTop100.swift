import Foundation
import Observation
import SwiftUI

/// The release-time off switch for AO3's reader-requested lookahead feature.
/// A point release can set this to false without changing any call site.
enum RankTop100Feature {
    static let isEnabled = true
    static let maximumPage = 5
    static let requestSpacing: TimeInterval = 3
    static let cacheLifetime: TimeInterval = 10 * 60
    static let requestBudget = 10
    static let throttleCooldown: TimeInterval = 24 * 60 * 60
    static let minimumThrottleCooldown: TimeInterval = 120
    static let cacheEntryLimit = 64
}

/// The exact listing URL family currently on screen. Pages are derived here so
/// every lookahead request changes only AO3's `page` query item.
enum RankTop100URLSource: Sendable {
    case search(filters: AO3SearchFilters, additionalQueryClause: String?)
    case fandom(String, filters: AO3SearchFilters)
    case tag(URL, filters: AO3SearchFilters)

    func url(page: Int) -> URL? {
        switch self {
        case let .search(filters, clause):
            AO3Client.searchURL(filters: filters, page: page, additionalQueryClause: clause)
        case let .fandom(fandom, filters):
            AO3Client.fandomWorksURL(fandom: fandom, filters: filters, page: page)
        case let .tag(url, filters):
            AO3Client.filteredWorksURL(url, filters: filters, page: page)
        }
    }

    func requests(through totalPages: Int, scope: String) -> [RankTop100PageRequest] {
        guard totalPages >= 2 else { return [] }
        return (2 ... min(totalPages, RankTop100Feature.maximumPage)).compactMap { page in
            url(page: page).map { RankTop100PageRequest(page: page, url: $0, scope: scope) }
        }
    }
}

struct RankTop100PageRequest: Hashable, Sendable {
    let page: Int
    let url: URL
    /// Anonymous or one authenticated session generation. Cached private rows
    /// can never cross an account transition.
    let scope: String
}

struct RankTop100Clock: Sendable {
    let now: @Sendable () async -> Date
    let sleepUntil: @Sendable (Date) async throws -> Void

    static let system = RankTop100Clock(
        now: { Date() },
        sleepUntil: { deadline in
            let delay = deadline.timeIntervalSinceNow
            if delay > 0 {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    )
}

enum RankTop100Availability: Equatable, Sendable {
    case available
    case releaseDisabled
    case retryAfter(Date)
    case throttledUntil(Date)
    case budgetRenews(Date)

    var allowsRun: Bool { self == .available }
}

enum RankTop100Stop: Equatable, Sendable {
    case completed
    case cancelled
    case unavailable(RankTop100Availability)
    case throttled(status: Int, retryAfterUntil: Date?)
    case failed(String)
}

struct RankTop100Outcome: Sendable {
    let pages: [Int: AO3SearchPage]
    let stop: RankTop100Stop
}

private struct RankTop100CacheKey: Hashable, Sendable {
    let url: URL
    let scope: String
}

private struct RankTop100CachedPage: Sendable {
    let value: AO3SearchPage
    let fetchedAt: Date
}

/// Session-wide budget and ten-minute parsed-page cache. Throttle dates alone
/// are persisted; pages and request starts intentionally die with the session.
actor RankTop100Store {
    static let shared = RankTop100Store()

    private enum Keys {
        static let retryAfter = "ao3.rankTop100.retryAfter"
        static let throttledUntil = "ao3.rankTop100.throttledUntil"
        static let throttleRuns = "ao3.rankTop100.throttleRuns"
    }

    private var cache: [RankTop100CacheKey: RankTop100CachedPage] = [:]
    private var requestStarts: [Date] = []
    private let defaults: UserDefaults
    private let isEnabled: Bool

    init(defaults: UserDefaults = .standard, isEnabled: Bool = RankTop100Feature.isEnabled) {
        self.defaults = defaults
        self.isEnabled = isEnabled
    }

    func availability(at now: Date) -> RankTop100Availability {
        guard isEnabled else { return .releaseDisabled }
        if let until = storedFutureDate(forKey: Keys.throttledUntil, at: now) {
            return .throttledUntil(until)
        }
        if let until = storedFutureDate(forKey: Keys.retryAfter, at: now) {
            return .retryAfter(until)
        }
        requestStarts.removeAll { now.timeIntervalSince($0) >= RankTop100Feature.cacheLifetime }
        if requestStarts.count >= RankTop100Feature.requestBudget, let first = requestStarts.first {
            return .budgetRenews(first.addingTimeInterval(RankTop100Feature.cacheLifetime))
        }
        return .available
    }

    func cachedPage(for request: RankTop100PageRequest, at now: Date) -> AO3SearchPage? {
        let key = RankTop100CacheKey(url: request.url, scope: request.scope)
        guard let cached = cache[key],
              now.timeIntervalSince(cached.fetchedAt) < RankTop100Feature.cacheLifetime
        else {
            cache[key] = nil
            return nil
        }
        return cached.value
    }

    func remember(_ page: AO3SearchPage, for request: RankTop100PageRequest, at now: Date) {
        let key = RankTop100CacheKey(url: request.url, scope: request.scope)
        if cache[key] == nil, cache.count >= RankTop100Feature.cacheEntryLimit,
           let oldest = cache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key {
            cache[oldest] = nil
        }
        cache[key] = RankTop100CachedPage(
            value: page,
            fetchedAt: now
        )
    }

    func purgeCache() {
        cache.removeAll(keepingCapacity: false)
    }

    /// Reserves one of the ten rolling-window starts immediately before the
    /// loader hands the request to AO3Client. This is the single final gate: a
    /// throttle recorded by another live controller during our sleep stops us.
    func reserveRequest(at now: Date) -> RankTop100Availability {
        let current = availability(at: now)
        guard current.allowsRun else { return current }
        requestStarts.append(now)
        return .available
    }

    @discardableResult
    func recordThrottle(_ error: AO3Error, at now: Date) -> RankTop100Availability? {
        let retryAfter: TimeInterval?
        switch error {
        case let .rateLimited(serverDelay):
            retryAfter = Self.validRetryAfter(serverDelay)
        case .forbidden:
            retryAfter = nil
        case .server(status: 502), .server(status: 503), .server(status: 504):
            retryAfter = nil
        default:
            return nil
        }

        let cooldown = max(RankTop100Feature.minimumThrottleCooldown, retryAfter ?? 0)
        let retryUntil = now.addingTimeInterval(min(cooldown, RankTop100Feature.throttleCooldown))
        defaults.set(retryUntil.timeIntervalSince1970, forKey: Keys.retryAfter)

        var runs = (defaults.array(forKey: Keys.throttleRuns) as? [Double] ?? [])
            .map { Date(timeIntervalSince1970: $0) }
            .filter {
                let age = now.timeIntervalSince($0)
                return age >= 0 && age < RankTop100Feature.throttleCooldown
            }
        runs.append(now)
        defaults.set(runs.map(\.timeIntervalSince1970), forKey: Keys.throttleRuns)
        if runs.count >= 2 {
            let until = now.addingTimeInterval(RankTop100Feature.throttleCooldown)
            defaults.set(until.timeIntervalSince1970, forKey: Keys.throttledUntil)
            return .throttledUntil(until)
        }
        return .retryAfter(retryUntil)
    }

    private static func validRetryAfter(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return min(value, RankTop100Feature.throttleCooldown)
    }

    private func storedFutureDate(forKey key: String, at now: Date) -> Date? {
        guard defaults.object(forKey: key) != nil else { return nil }
        let seconds = defaults.double(forKey: key)
        guard seconds.isFinite else {
            defaults.removeObject(forKey: key)
            return nil
        }
        let date = Date(timeIntervalSince1970: seconds)
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0, remaining <= RankTop100Feature.throttleCooldown else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return date
    }
}

struct RankTop100Loader: Sendable {
    static let shared = RankTop100Loader(store: .shared, clock: .system)

    let store: RankTop100Store
    let clock: RankTop100Clock

    func run(
        requests: [RankTop100PageRequest],
        existingPages: [Int: AO3SearchPage],
        load: @escaping @Sendable (RankTop100PageRequest) async throws -> AO3SearchPage,
        onProgress: @escaping @MainActor @Sendable (Int, Int) -> Void = { _, _ in },
        onPage: @escaping @MainActor @Sendable ([Int: AO3SearchPage]) -> Void = { _ in }
    ) async -> RankTop100Outcome {
        // Page 1 is never a lookahead request. Pages 2–5 must still pass through
        // the timestamped store below; a page visible for over ten minutes is not
        // fresh merely because the view still has its parsed value.
        var pages = existingPages.filter { $0.key == 1 }
        let start = await clock.now()
        let initialAvailability = await store.availability(at: start)
        guard initialAvailability.allowsRun else {
            return RankTop100Outcome(pages: pages, stop: .unavailable(initialAvailability))
        }

        var lastRequestStart: Date?
        for request in requests.sorted(by: { $0.page < $1.page })
            where (2 ... RankTop100Feature.maximumPage).contains(request.page) {
            do {
                try Task.checkCancellation()
                await onProgress(request.page, RankTop100Pages.works(in: pages).count)

                let cacheTime = await clock.now()
                if let cached = await store.cachedPage(for: request, at: cacheTime) {
                    pages[request.page] = cached
                    await onPage(pages)
                    continue
                }

                if let lastRequestStart {
                    let deadline = lastRequestStart.addingTimeInterval(RankTop100Feature.requestSpacing)
                    if await clock.now() < deadline {
                        try await clock.sleepUntil(deadline)
                    }
                }
                try Task.checkCancellation()
                let requestStart = await clock.now()
                let reservation = await store.reserveRequest(at: requestStart)
                guard reservation.allowsRun else {
                    return RankTop100Outcome(pages: pages, stop: .unavailable(reservation))
                }
                lastRequestStart = requestStart

                let page = try await load(request)
                try Task.checkCancellation()
                pages[request.page] = page
                await store.remember(page, for: request, at: await clock.now())
                await onPage(pages)
            } catch is CancellationError {
                return RankTop100Outcome(pages: pages, stop: .cancelled)
            } catch let error as AO3Error {
                if let throttleAvailability = await store.recordThrottle(error, at: await clock.now()) {
                    let retryUntil: Date? = switch throttleAvailability {
                    case let .retryAfter(date), let .throttledUntil(date): date
                    default: nil
                    }
                    let status = switch error {
                    case .rateLimited: 429
                    case .forbidden: 403
                    case .server(status: 502): 502
                    case .server(status: 503): 503
                    case .server(status: 504): 504
                    default: 0
                    }
                    return RankTop100Outcome(
                        pages: pages,
                        stop: .throttled(status: status, retryAfterUntil: retryUntil)
                    )
                }
                return RankTop100Outcome(
                    pages: pages,
                    stop: .failed(error.errorDescription ?? "AO3 couldn't load that page.")
                )
            } catch {
                return RankTop100Outcome(pages: pages, stop: .failed(error.localizedDescription))
            }
        }
        return RankTop100Outcome(pages: pages, stop: .completed)
    }
}

enum RankTop100Pages {
    /// AO3 order across pages, with a defensive ID de-duplication in case the
    /// listing shifts while the reader-requested run is in progress.
    static func works(in pages: [Int: AO3SearchPage]) -> [AO3WorkSummary] {
        var seen: Set<Int> = []
        return pages.keys.sorted().flatMap { pages[$0]?.works ?? [] }.filter { seen.insert($0.id).inserted }
    }
}

struct RankTop100Progress: Equatable {
    let page: Int
    let loadedWorks: Int
}

@MainActor @Observable
final class RankTop100Controller {
    private(set) var progress: RankTop100Progress?
    private(set) var availability: RankTop100Availability = .available
    private(set) var message: String?

    @ObservationIgnored
    private let loader: RankTop100Loader
    @ObservationIgnored
    private var task: Task<Void, Never>?
    @ObservationIgnored
    private var availabilityTask: Task<Void, Never>?
    @ObservationIgnored
    private var generation = 0

    init(loader: RankTop100Loader = .shared) {
        self.loader = loader
    }

    var isRunning: Bool { progress != nil }
    var canStart: Bool { !isRunning && availability.allowsRun }

    func refreshAvailability() async {
        availability = await loader.store.availability(at: await loader.clock.now())
        scheduleAvailabilityRefresh()
    }

    func start(
        requests: [RankTop100PageRequest],
        existingPages: [Int: AO3SearchPage],
        load: @escaping @Sendable (RankTop100PageRequest) async throws -> AO3SearchPage,
        onPages: @escaping @MainActor @Sendable ([Int: AO3SearchPage]) -> Void
    ) {
        guard canStart else { return }
        cancel()
        generation += 1
        let runGeneration = generation
        message = nil
        progress = RankTop100Progress(
            page: requests.first?.page ?? 2,
            loadedWorks: RankTop100Pages.works(in: existingPages).count
        )
        task = Task { [weak self] in
            guard let self else { return }
            let outcome = await loader.run(
                requests: requests,
                existingPages: existingPages,
                load: load,
                onProgress: { [weak self] page, count in
                    guard let self, runGeneration == generation else { return }
                    progress = RankTop100Progress(page: page, loadedWorks: count)
                },
                onPage: { [weak self] pages in
                    guard let self, runGeneration == generation else { return }
                    progress = RankTop100Progress(
                        page: progress?.page ?? 2,
                        loadedWorks: RankTop100Pages.works(in: pages).count
                    )
                    onPages(pages)
                }
            )
            guard runGeneration == generation else { return }
            progress = nil
            availability = await loader.store.availability(at: await loader.clock.now())
            switch outcome.stop {
            case .completed, .cancelled:
                break
            case .unavailable:
                message = nil
            case .throttled:
                message = nil
            case let .failed(text):
                message = text
            }
            scheduleAvailabilityRefresh()
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        progress = nil
    }

    private func scheduleAvailabilityRefresh() {
        availabilityTask?.cancel()
        let deadline: Date?
        switch availability {
        case let .retryAfter(date), let .throttledUntil(date), let .budgetRenews(date):
            deadline = date
        case .available, .releaseDisabled:
            deadline = nil
        }
        guard let deadline else { return }
        availabilityTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await loader.clock.sleepUntil(deadline)
                try Task.checkCancellation()
                availability = await loader.store.availability(at: await loader.clock.now())
                if availability.allowsRun { message = nil }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    var availabilityText: String? {
        switch availability {
        case .available: nil
        case .releaseDisabled: "Rank Top 100 is disabled in this release."
        case let .retryAfter(date): "AO3 asked Kudos to wait until \(date.formatted(date: .omitted, time: .shortened))."
        case let .throttledUntil(date):
            "Rank Top 100 is off until \(date.formatted(date: .abbreviated, time: .shortened))."
        case let .budgetRenews(date):
            "The 10-page budget renews at \(date.formatted(date: .omitted, time: .shortened))."
        }
    }
}

/// Running state above the result rows, as Quality-RankDeeper draws it.
struct RankTop100ProgressCard: View {
    let controller: RankTop100Controller
    let totalPages: Int

    @ViewBuilder
    var body: some View {
        if RankTop100Feature.isEnabled, let progress = controller.progress {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    progressDetails(progress)
                    Button("Cancel", action: controller.cancel)
                        .buttonStyle(.bordered)
                }
                VStack(alignment: .leading, spacing: 10) {
                    progressDetails(progress)
                    Button("Cancel", action: controller.cancel)
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                "Ranking the top 100, page \(progress.page) of \(min(totalPages, 5)), "
                    + "\(progress.loadedWorks) works loaded"
            )
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func progressDetails(_ progress: RankTop100Progress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ranking the top 100 · page \(progress.page) of \(min(totalPages, 5))")
                .font(.subheadline.weight(.semibold))
            ProgressView(value: Double(progress.page), total: Double(min(totalPages, 5)))
            Text("One page every 3 seconds · \(progress.loadedWorks) works so far")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Idle controls and loaded-count footnote below the result rows.
struct RankTop100Controls: View {
    let controller: RankTop100Controller
    let currentPage: Int
    let totalPages: Int
    let loadedWorks: Int
    let totalWorks: Int
    let isPageLoading: Bool
    let loadNextPage: () -> Void
    let start: () -> Void

    @ViewBuilder
    var body: some View {
        if RankTop100Feature.isEnabled {
            VStack(alignment: .leading, spacing: 8) {
                if controller.progress == nil {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { actionButtons }
                        VStack(alignment: .leading, spacing: 8) { actionButtons }
                    }
                }
                if let message = controller.message ?? controller.availabilityText {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(loadedWorks.formatted()) of \(totalWorks.formatted()) loaded · "
                    + "ranking updates as each page arrives")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .task { await controller.refreshAvailability() }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Load Page \(min(currentPage + 1, totalPages))", action: loadNextPage)
            .buttonStyle(.bordered)
            .disabled(isPageLoading || currentPage >= totalPages)
        Button(action: start) {
            Label("Rank Top 100", systemImage: "arrow.up.arrow.down")
        }
        .buttonStyle(.bordered)
        .disabled(!controller.canStart || isPageLoading || totalPages < 2)
    }
}
