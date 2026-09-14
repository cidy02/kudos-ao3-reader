import Foundation

/// Which of the signed-in user's AO3 account lists a cached size belongs to.
nonisolated enum AO3AccountListKind: String, Hashable, Sendable {
    case myWorks
    case series
    case bookmarks
    case subscriptions
    case markedForLater
    case history
    case collections
}

/// A cached size for one account list: exact when the whole list fit on one page
/// (or AO3 printed a total), otherwise a lower bound derived from the pagination
/// the app already parsed (`firstPageCount × (totalPages − 1)`) — deliberately
/// approximate rather than spending an extra request on an exact heading scrape.
nonisolated struct AO3AccountListCount: Equatable, Sendable {
    var exact: Int?
    var lowerBound: Int?

    /// "12" for exact counts, "220+" for paginated lower bounds, nil when neither
    /// could be derived (callers hide the count entirely).
    var displayText: String? {
        if let exact { return exact.formatted() }
        if let lowerBound, lowerBound > 0 { return "\(lowerBound.formatted())+" }
        return nil
    }

    /// Derives a count from an already-fetched list page. One page → exact;
    /// several pages → a lower bound from the full pages before the last.
    init(itemsOnPage: Int, totalPages: Int) {
        if totalPages <= 1 {
            exact = itemsOnPage
        } else {
            lowerBound = itemsOnPage * (totalPages - 1)
        }
    }

    init(exact: Int) {
        self.exact = exact
    }

    /// True when this count is at least as informative as `other` — an exact
    /// count beats any lower bound, and among lower bounds a larger one is
    /// closer to the true size. Used to stop a later, weaker page (e.g. a short
    /// final page) from downgrading an already-cached stronger estimate.
    func isAtLeastAsStrong(as other: AO3AccountListCount) -> Bool {
        // Two exact counts are both totals, so the newer one wins — otherwise a
        // count cached before the user posted a work would outlive the truth for
        // the whole TTL. Only a lower bound loses to an exact.
        if exact != nil { return other.exact == nil }
        if other.exact != nil { return false }
        return (lowerBound ?? 0) >= (other.lowerBound ?? 0)
    }
}

/// In-session cache of account-list sizes, so the Account tab's Overview cards can
/// show a count **only when one is already locally available** — it is populated
/// as a side effect of lists the user actually opened (or Home/Library already
/// fetch) and never triggers an AO3 request of its own. Mirrors
/// `AO3AuthorPageCache`'s conventions: in-memory only (cleared on relaunch),
/// TTL-based, and keyed by authentication scope so one account's numbers can
/// never show for another (or for a signed-out session).
@MainActor
@Observable
final class AO3AccountListCountsCache {
    nonisolated struct Key: Hashable, Sendable {
        let kind: AO3AccountListKind
        let authenticationScope: String
    }

    private struct Entry {
        let count: AO3AccountListCount
        let expiresAt: Date
    }

    static let shared = AO3AccountListCountsCache()

    private let ttl: TimeInterval
    private var entries: [Key: Entry] = [:]

    init(ttl: TimeInterval = 30 * 60) {
        self.ttl = ttl
    }

    func count(
        for kind: AO3AccountListKind,
        authenticationScope: String,
        now: Date = Date()
    ) -> AO3AccountListCount? {
        let key = Key(kind: kind, authenticationScope: authenticationScope)
        guard let entry = entries[key], entry.expiresAt > now else { return nil }
        return entry.count
    }

    func record(
        _ count: AO3AccountListCount,
        kind: AO3AccountListKind,
        authenticationScope: String,
        now: Date = Date()
    ) {
        entries = entries.filter { $0.value.expiresAt > now }
        let key = Key(kind: kind, authenticationScope: authenticationScope)
        // A later fetch may land on a short/partial page (e.g. the last page of
        // results) and derive a weaker lower bound than one already cached —
        // keep whichever estimate is stronger, just refreshing its TTL.
        let toStore = entries[key].map { $0.count.isAtLeastAsStrong(as: count) ? $0.count : count }
            ?? count
        entries[key] = Entry(count: toStore, expiresAt: now.addingTimeInterval(ttl))
    }

    /// Seeds the lists whose exact size AO3 prints in the dashboard nav of the
    /// very page the profile header is parsed from — "Works (535)",
    /// "Bookmarks (22)", "Collections (33)".
    ///
    /// This is why an Overview shortcut can show a count before its list has ever
    /// been opened. It costs no request: the page is already fetched and these
    /// links are already parsed; the numbers in them were simply being discarded.
    ///
    /// Subscriptions, History and Marked for Later are not in that nav, so they
    /// still fill in only once their own list is loaded.
    ///
    /// Series is here because the nav prints it — "Series (40)" — even though no
    /// list load in the app produces a series count. It was being parsed and
    /// dropped for want of a kind to file it under.
    func record(
        dashboardActions actions: [AO3AuthorWebAction],
        username: String,
        authenticationScope: String,
        now: Date = Date()
    ) {
        let base = "/users/\(username.lowercased())/"
        for action in actions {
            let path = action.url.path.lowercased()
            guard path.hasPrefix(base) else { continue }
            // Exact tail only, so a pseud's own "/pseuds/<name>/works" — whose
            // counts are the pseud's, not the account's — can never land here.
            let kind: AO3AccountListKind
            switch String(path.dropFirst(base.count)) {
            case "works": kind = .myWorks
            case "series": kind = .series
            case "bookmarks": kind = .bookmarks
            case "collections": kind = .collections
            default: continue
            }
            guard let count = action.listCount else { continue }
            record(
                AO3AccountListCount(exact: count),
                kind: kind,
                authenticationScope: authenticationScope,
                now: now
            )
        }
    }

    /// Records a just-fetched works-list page (the common case).
    func record(
        page: AO3SearchPage,
        kind: AO3AccountListKind,
        authenticationScope: String,
        now: Date = Date()
    ) {
        record(
            AO3AccountListCount(itemsOnPage: page.works.count, totalPages: page.totalPages),
            kind: kind,
            authenticationScope: authenticationScope,
            now: now
        )
    }
}
