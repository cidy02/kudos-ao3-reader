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
    /// Failures cache nothing: a 525 or a dropped connection is not evidence that
    /// an author has no works, and caching it as such would hide the line for the
    /// rest of the session.
    static func newestWork(
        username: String,
        auth: AO3AuthService,
        isCurrent: @escaping @MainActor () -> Bool = { true }
    ) async -> AO3WorkSummary? {
        let scope = AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        if let cached = cached(username: username, scope: scope) {
            return cached
        }
        guard let url = newestWorkURL(username: username) else { return nil }
        do {
            let page = try await AO3AuthorProfileFetcher.page(
                at: url,
                auth: auth,
                cacheScope: scope,
                isCurrent: isCurrent
            )
            let parsed = try AO3Client.parseAuthorWorksPage(page.html, page: 1)
            guard isCurrent() else { return nil }
            let newest = parsed.works.first
            store(newest, username: username, scope: scope)
            return newest
        } catch {
            return nil
        }
    }

    /// Fetches every distinct author in the order presented by Favorites' Authors
    /// scope. Sequential requests preserve AO3 pacing; callers enable a filter only
    /// once every account has a cached answer, never from a partially loaded list.
    /// Returns false when an answer is still missing (for example, after a request
    /// failure or cancellation).
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
            _ = await newestWork(username: username, auth: auth, isCurrent: isCurrent)
        }
        guard !Task.isCancelled, isCurrent() else { return false }
        return distinctUsernames.allSatisfy { cached(username: $0, scope: scope) != nil }
    }
}
