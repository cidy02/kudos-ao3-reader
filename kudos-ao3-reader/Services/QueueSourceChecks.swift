import Foundation

/// Pure scheduling and count rules; the queue page supplies the fetcher and clock.
enum QueueSourceChecks {
    static let cooldown: TimeInterval = 6 * 60 * 60
    static let spacing: TimeInterval = 3

    /// Baseline filters for a tag's works listing (newest first by Date Updated),
    /// shared with `TagWorksView` so count fetches and Find More hit the same URL.
    nonisolated static var tagBaselineFilters: AO3SearchFilters {
        var filters = AO3SearchFilters()
        filters.sort = .dateUpdated
        filters.sortDirection = AO3SearchFilters.Sort.dateUpdated.naturalDirection
        return filters
    }

    /// Counts only run when the reader has visibly opened a non-smart queue page
    /// with at least one visible source on the active tab while the app is active.
    static func shouldCheckOnOpen(
        isPageVisible: Bool,
        isAppActive: Bool,
        isSelectedTab: Bool,
        isSmartQueue: Bool,
        hasVisibleSources: Bool
    ) -> Bool {
        isPageVisible && isAppActive && isSelectedTab && !isSmartQueue && hasVisibleSources
    }

    static func eligible<T>(
        _ sources: [T], checkedAt: (T) -> Date?, now: Date
    ) -> [T] {
        sources.filter { source in
            checkedAt(source).map { now.timeIntervalSince($0) >= cooldown } ?? true
        }
        .sorted { (checkedAt($0) ?? .distantPast) < (checkedAt($1) ?? .distantPast) }
        .prefix(5).map { $0 }
    }

    /// AO3 search blurbs carry a calendar day, not a time. A work is new when
    /// that day is on or after the UTC day of `lastOpenedAt`. A source that has
    /// never been opened or baselined counts 0 — never the whole first page.
    static func count(_ page: AO3SearchPage, since opened: Date?) -> Int {
        guard let opened else { return 0 }
        let cutoff = utcDay(of: opened)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd", "dd MMM yyyy", "d MMM yyyy"] {
            formatter.dateFormat = format
            let dates = page.works.map { formatter.date(from: $0.dateUpdated) }
            if dates.contains(where: { $0 != nil }) {
                return dates.filter { $0.map { $0 >= cutoff } ?? false }.count
            }
        }
        return 0
    }

    /// New-result counts for saved searches are only meaningful when page 1 is newest-first.
    static func countsNewResults(_ filters: AO3SearchFilters) -> Bool {
        (filters.sort == .dateUpdated || filters.sort == .datePosted)
            && filters.sortDirection == .descending
    }

    /// Whether a source of `kind` counts new results. Unknown kinds (`nil`) never fetch or count.
    static func countsNewResults(kind: QueueSourceKind?, filters: AO3SearchFilters? = nil) -> Bool {
        guard let kind else { return false }
        switch kind {
        case .savedSearch:
            return filters.map(countsNewResults) ?? false
        case .author, .series, .tag:
            return true
        }
    }

    static func displayedCount(_ count: Int?, filters: AO3SearchFilters) -> Int? {
        guard countsNewResults(filters), let count, count > 0 else { return nil }
        return count
    }

    static func displayedCount(
        _ count: Int?,
        kind: QueueSourceKind?,
        filters: AO3SearchFilters? = nil
    ) -> Int? {
        guard countsNewResults(kind: kind, filters: filters), let count, count > 0 else { return nil }
        return count
    }

    static func badge(_ count: Int) -> String {
        count >= 20 ? "20+ new" : "\(count) new"
    }

    /// Unlinked searches, zero counts, and non-date sorts have no count phrase.
    static func savedSearchAccessibilityLabel(
        name: String, count: Int?, isLinked: Bool, filters: AO3SearchFilters
    ) -> String {
        let base = "Open saved search \(name)"
        guard isLinked, let shown = displayedCount(count, filters: filters) else { return base }
        return "\(base), \(badge(shown))"
    }

    static func findMoreAccessibilityLabel(
        name: String, count: Int?, filters: AO3SearchFilters
    ) -> String {
        let base = "Find more works: \(name)"
        guard let shown = displayedCount(count, filters: filters) else {
            return "\(base) on AO3"
        }
        return "\(base), \(badge(shown)) on AO3"
    }

    static func sourceAccessibilityLabel(
        name: String,
        kind: QueueSourceKind,
        count: Int?,
        filters: AO3SearchFilters? = nil
    ) -> String {
        if kind == .savedSearch {
            return findMoreAccessibilityLabel(
                name: name, count: count, filters: filters ?? AO3SearchFilters()
            )
        }
        let prefix = switch kind {
        case .savedSearch: "Find more works"
        case .author: "Open author \(name)"
        case .series: "Open series \(name)"
        case .tag: "Open tag \(name)"
        }
        guard let shown = displayedCount(count, kind: kind, filters: filters) else {
            return "\(prefix) on AO3"
        }
        return "\(prefix), \(badge(shown)) on AO3"
    }

    /// Queue counts stay anonymous. A signed-in Find More must load its own page.
    static func cachedPageForFindMore(_ page: AO3SearchPage?, isLoggedIn: Bool) -> AO3SearchPage? {
        isLoggedIn ? nil : page
    }

    /// Queue counts stay anonymous. A signed-in Find More must load its own page.
    static func cachedFetchForFindMore(
        _ fetched: QueueSourceFetchedPage?,
        isLoggedIn: Bool
    ) -> QueueSourceFetchedPage? {
        isLoggedIn ? nil : fetched
    }

    static func recordsOpenImmediately(hasCachedPage: Bool) -> Bool {
        hasCachedPage
    }

    static func shouldRecordOpen(page: Int, loadToken: Int, expectedToken: Int) -> Bool {
        page == 1 && loadToken == expectedToken
    }

    /// Offline and unreachable errors mean the request never got an answer.
    static func isUnreachable(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .timedOut, .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    @MainActor
    // swiftlint:disable:next function_parameter_count
    static func run<Source>(
        sources: [Source],
        checkedAt: (Source) -> Date?,
        now: () -> Date,
        sleep: (TimeInterval) async throws -> Void,
        attempt: (Source, Date) -> Bool,
        fetch: (Source) async throws -> AO3SearchPage,
        received: (Source, AO3SearchPage) -> Void
    ) async {
        await runPass(
            sources: sources,
            checkedAt: checkedAt,
            now: now,
            sleep: sleep,
            attempt: attempt,
            fetch: fetch,
            received: received
        )
    }

    @MainActor
    // swiftlint:disable:next function_parameter_count
    static func runFetched<Source>(
        sources: [Source],
        checkedAt: (Source) -> Date?,
        now: () -> Date,
        sleep: (TimeInterval) async throws -> Void,
        attempt: (Source, Date) -> Bool,
        fetch: (Source) async throws -> QueueSourceFetchedPage,
        received: (Source, QueueSourceFetchedPage) -> Void
    ) async {
        await runPass(
            sources: sources,
            checkedAt: checkedAt,
            now: now,
            sleep: sleep,
            attempt: attempt,
            fetch: fetch,
            received: received
        )
    }

    @MainActor
    // swiftlint:disable:next function_parameter_count
    private static func runPass<Source, Payload>(
        sources: [Source],
        checkedAt: (Source) -> Date?,
        now: () -> Date,
        sleep: (TimeInterval) async throws -> Void,
        attempt: (Source, Date) -> Bool,
        fetch: (Source) async throws -> Payload,
        received: (Source, Payload) -> Void
    ) async {
        let selected = eligible(sources, checkedAt: checkedAt, now: now())
        var previousStart: Date?
        for source in selected {
            var started: Date?
            do {
                try Task.checkCancellation()
                if let previousStart {
                    let remaining = spacing - now().timeIntervalSince(previousStart)
                    if remaining > 0 { try await sleep(remaining) }
                }
                try Task.checkCancellation()
                started = now()
                previousStart = started
                let page = try await fetch(source)
                try Task.checkCancellation()
                guard let started, attempt(source, started) else { return }
                received(source, page)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch let error where isUnreachable(error) {
                // No answer: leave lastCheckedAt alone and stop the pass.
                return
            } catch AO3Error.rateLimited {
                // The 429 hold is the cooldown; do not stamp a source we may not
                // have actually requested (a hold can throw before URLSession).
                return
            } catch AO3Error.forbidden {
                if let started { _ = attempt(source, started) }
                return
            } catch AO3Error.maintenance {
                if let started { _ = attempt(source, started) }
                return
            } catch {
                // The attempt is stamped; another eligible source may run.
                if let started { _ = attempt(source, started) }
            }
        }
    }

    private static func utcDay(of date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.startOfDay(for: date)
    }
}
