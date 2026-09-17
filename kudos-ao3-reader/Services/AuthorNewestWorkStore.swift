import Foundation

/// The newest work by one author, for artboard **1ak**'s "Newest work" line.
///
/// **Sorted by Date Posted, explicitly.** A user's works page defaults to
/// `revised_at` (Date Updated), so its first row is the most recently *edited*
/// work — a 2019 WIP touched yesterday outranks something posted last week. 1ak
/// asks for the newest work, so the request pins `work_search[sort_column]` to
/// `created_at`. Both the parameter and the default were probed against a live
/// page on 2026-09-15: the page returns 200 and reports "Date Posted" selected.
///
/// **What the line can say.** A works-page blurb carries one date, and the parser
/// stores it as `AO3WorkSummary.dateUpdated` — because that is what AO3 shows
/// there. The artboard's line reads "posted 2 Sep 2026"; the app writes "updated",
/// because it does not have the posted date and a wrong label is worse than a
/// plainer one.
///
/// Results are cached in memory for the session with a TTL, keyed by the author
/// and the session scope. The underlying HTML fetch is already cached and
/// concurrency-limited by `AO3AuthorProfileFetcher` / `AO3RequestCoordinator`;
/// this caches the *parsed* answer so redrawing a row does not re-parse ~180KB of
/// markup.
@MainActor
enum AuthorNewestWorkStore {
    /// Long enough that scrolling a list back and forth costs nothing, short
    /// enough that a newly posted work shows up in the same sitting.
    static let ttl: TimeInterval = 30 * 60

    /// `nil` work is a real answer — this author has no visible works — and is
    /// cached like any other, so an author with none is not refetched on every
    /// appearance.
    private struct Entry {
        let work: AO3WorkSummary?
        let fetchedAt: Date
    }

    private static var cache: [String: Entry] = [:]

    private static func key(_ username: String, scope: String) -> String {
        "\(scope)|\(username.lowercased())"
    }

    /// The cached answer, if one is still fresh. Returns `.some(nil)` for "fetched,
    /// and there is nothing", `nil` for "not fetched".
    static func cached(username: String, scope: String, now: Date = Date()) -> AO3WorkSummary?? {
        guard let entry = cache[key(username, scope: scope)],
              now.timeIntervalSince(entry.fetchedAt) < ttl
        else { return nil }
        return .some(entry.work)
    }

    static func store(_ work: AO3WorkSummary?, username: String, scope: String, now: Date = Date()) {
        cache[key(username, scope: scope)] = Entry(work: work, fetchedAt: now)
    }

    /// Clears everything — call when the session changes, so one account's cached
    /// answers cannot outlive it.
    static func removeAll() {
        cache.removeAll()
    }

    /// The URL 1ak's line reads: the author's works, newest-posted first.
    static func newestWorkURL(username: String) -> URL? {
        guard let route = AO3AuthorRoute(username: username) else { return nil }
        var components = URLComponents(url: route.contentURL(.works), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "work_search[sort_column]", value: "created_at")]
        return components?.url
    }

    /// Fetches and caches this author's newest work. Returns the cached answer
    /// without a request when one is fresh.
    ///
    /// Transient failures cache nothing: a 525 or a dropped connection is not
    /// evidence that an author has no works, and caching it as such would hide the
    /// line for the rest of the session. A byline with no readable works page at
    /// all is the one exception — see `FetchOutcome.unresolvable`.
    static func newestWork(
        username: String,
        auth: AO3AuthService,
        isCurrent: @escaping @MainActor () -> Bool = { true }
    ) async -> AO3WorkSummary? {
        let scope = AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        if let cached = cached(username: username, scope: scope) {
            return cached
        }
        _ = await fetchAndStore(username: username, auth: auth, isCurrent: isCurrent)
        return cached(username: username, scope: scope) ?? nil
    }

    /// Why one author's fetch ended. A batch needs the difference, and it is the
    /// same line `AO3InboxModel` draws for Inbox metadata hydration: a byline that
    /// has no readable page is gone for good and must not stall every author queued
    /// behind it, while offline / rate-limited / CDN / parser trouble is likely to
    /// hit the rest too, so carrying on would only multiply retries.
    private enum FetchOutcome {
        case answered
        /// No page to read — an unroutable byline or a 404. Cached as "no visible
        /// works", because for a byline with no works page that *is* the honest
        /// answer, unlike a 525, which is evidence of nothing either way.
        case unresolvable
        /// Includes cancellation: both mean stop, and neither caches anything.
        case systemicFailure
    }

    private static func fetchAndStore(
        username: String,
        auth: AO3AuthService,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> FetchOutcome {
        let scope = AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        guard let url = newestWorkURL(username: username) else {
            store(nil, username: username, scope: scope)
            return .unresolvable
        }
        do {
            let page = try await AO3AuthorProfileFetcher.page(
                at: url,
                auth: auth,
                cacheScope: scope,
                isCurrent: isCurrent
            )
            let parsed = try AO3Client.parseAuthorWorksPage(page.html, page: 1)
            guard isCurrent() else { return .systemicFailure }
            store(parsed.works.first, username: username, scope: scope)
            return .answered
        } catch AO3Error.notFound {
            guard isCurrent() else { return .systemicFailure }
            store(nil, username: username, scope: scope)
            return .unresolvable
        } catch {
            return .systemicFailure
        }
    }

    /// Fetches every distinct author in the order presented by Favorites' Authors
    /// scope. Sequential requests preserve AO3 pacing; callers enable a filter only
    /// once every account has a cached answer, never from a partially loaded list.
    ///
    /// **A dead byline no longer stalls the batch.** Stopping at the first *missing*
    /// answer meant one deleted or renamed account disabled the whole filter for the
    /// session — and deterministically, because leaving the scope and returning
    /// re-ran the same batch into the same dead account. It now skips an
    /// unresolvable byline (already cached as "no visible works", so it cannot match
    /// "With new work") and stops only on a systemic failure, where continuing would
    /// just multiply retries against an unwell AO3.
    ///
    /// Returns false after a systemic failure or cancellation.
    static func prefetch(
        usernames: [String],
        auth: AO3AuthService,
        isCurrent: @escaping @MainActor () -> Bool = { true }
    ) async -> Bool {
        let scope = AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        var distinctUsernames: [String] = []
        var seen = Set<String>()
        for username in usernames where seen.insert(username.lowercased()).inserted {
            distinctUsernames.append(username)
        }

        for username in distinctUsernames {
            guard !Task.isCancelled, isCurrent() else { return false }
            // A fresh answer costs no request, so a re-run after a stop walks the
            // cached prefix and resumes where the batch actually left off.
            if cached(username: username, scope: scope) != nil { continue }
            switch await fetchAndStore(username: username, auth: auth, isCurrent: isCurrent) {
            case .answered, .unresolvable:
                continue
            case .systemicFailure:
                return false
            }
        }
        return !Task.isCancelled
            && isCurrent()
            && distinctUsernames.allSatisfy { cached(username: $0, scope: scope) != nil }
    }
}
