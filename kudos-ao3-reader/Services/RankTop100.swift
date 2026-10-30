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
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func availability(at now: Date) -> RankTop100Availability {
        guard RankTop100Feature.isEnabled else { return .releaseDisabled }
        if let until = storedDate(forKey: Keys.throttledUntil), until > now {
            return .throttledUntil(until)
        }
        if let until = storedDate(forKey: Keys.retryAfter), until > now {
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
        cache[RankTop100CacheKey(url: request.url, scope: request.scope)] = RankTop100CachedPage(
            value: page,
            fetchedAt: now
        )
    }

    /// Reserves one of the ten rolling-window starts immediately before the
    /// loader hands the request to AO3Client.
    func reserveRequest(at now: Date) -> Bool {
        requestStarts.removeAll { now.timeIntervalSince($0) >= RankTop100Feature.cacheLifetime }
        guard requestStarts.count < RankTop100Feature.requestBudget else { return false }
        requestStarts.append(now)
        return true
    }

    @discardableResult
    func recordThrottle(_ error: AO3Error, at now: Date) -> RankTop100Availability? {
        let status: Int
        switch error {
        case let .rateLimited(retryAfter):
            status = 429
            if let retryAfter, retryAfter > 0 {
                defaults.set(now.addingTimeInterval(retryAfter).timeIntervalSince1970, forKey: Keys.retryAfter)
            }
        case .forbidden:
            status = 403
        case .server(status: 503):
            status = 503
        default:
            return nil
        }

        var runs = (defaults.array(forKey: Keys.throttleRuns) as? [Double] ?? [])
            .map { Date(timeIntervalSince1970: $0) }
            .filter { calendar.isDate($0, inSameDayAs: now) }
        runs.append(now)
        defaults.set(runs.map(\.timeIntervalSince1970), forKey: Keys.throttleRuns)
        if runs.count >= 2 {
            let until = now.addingTimeInterval(RankTop100Feature.throttleCooldown)
            defaults.set(until.timeIntervalSince1970, forKey: Keys.throttledUntil)
            return .throttledUntil(until)
        }
        if status == 429, let until = storedDate(forKey: Keys.retryAfter), until > now {
            return .retryAfter(until)
        }
        return .available
    }

    private func storedDate(forKey key: String) -> Date? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
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
                guard await store.reserveRequest(at: requestStart) else {
                    let availability = await store.availability(at: requestStart)
                    return RankTop100Outcome(pages: pages, stop: .unavailable(availability))
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
                if await store.recordThrottle(error, at: await clock.now()) != nil {
                    let retryUntil: Date?
                    if case let .rateLimited(seconds) = error, let seconds {
                        retryUntil = (await clock.now()).addingTimeInterval(seconds)
                    } else {
                        retryUntil = nil
                    }
                    let status = switch error {
                    case .rateLimited: 429
                    case .forbidden: 403
                    case .server(status: 503): 503
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
    private var generation = 0

    init(loader: RankTop100Loader = .shared) {
        self.loader = loader
    }

    var isRunning: Bool { progress != nil }
    var canStart: Bool { !isRunning && availability.allowsRun }

    func refreshAvailability() async {
        availability = await loader.store.availability(at: await loader.clock.now())
    }

    func start(
        requests: [RankTop100PageRequest],
        existingPages: [Int: AO3SearchPage],
        load: @escaping @Sendable (RankTop100PageRequest) async throws -> AO3SearchPage,
        onPages: @escaping @MainActor @Sendable ([Int: AO3SearchPage]) -> Void
    ) {
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
                message = availabilityText
            case let .throttled(status, _):
                message = "AO3 returned HTTP \(status). Ranking stopped."
            case let .failed(text):
                message = text
            }
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        progress = nil
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

/// Compact control and running state from Quality-RankDeeper.
struct RankTop100Controls: View {
    let controller: RankTop100Controller
    let totalPages: Int
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = controller.progress {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ranking the top 100 · page \(progress.page) of \(min(totalPages, 5))")
                            .font(.subheadline.weight(.semibold))
                        ProgressView(value: Double(progress.page), total: Double(min(totalPages, 5)))
                        Text("One page every 3 seconds · \(progress.loadedWorks) works so far")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Cancel", action: controller.cancel)
                        .buttonStyle(.bordered)
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(
                    "Ranking the top 100, page \(progress.page) of \(min(totalPages, 5)), "
                        + "\(progress.loadedWorks) works loaded"
                )
            } else {
                Button(action: start) {
                    Label("Rank Top 100", systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(.bordered)
                .disabled(!controller.canStart || totalPages < 2)
                if let message = controller.message ?? controller.availabilityText {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { await controller.refreshAvailability() }
    }
}
