import Foundation
import OSLog
import SwiftSoup

// A small native AO3 client: it fetches AO3's normal HTML pages over the network
// and reads the data out of them with SwiftSoup. The page structure (which CSS
// classes hold the title, stats, etc.) and the search parameters are ported from
// the open-source ao3_api project (github.com/ArmindoFlores/ao3_api) and verified
// against live AO3 HTML. AO3 has no official API, so this is HTML scraping — kept
// polite and personal.

// Lint: the existing client keeps scraping/parsing behavior centralized.
// swiftlint:disable file_length
/// Central AO3 network access: every request is paced (see `pace()`), retried with
/// backoff only when transient, coalesced when identical, and status-checked into
/// typed errors — one place owns the politeness rules.
actor AO3Client { // swiftlint:disable:this type_body_length
    static let shared = AO3Client()

    private let base = "https://archiveofourown.org"
    private let session: URLSession
    private let redirectCookieRelay = AO3RedirectCookieRelay()

    init() {
        session = URLSession(configuration: Self.makeAnonymousSessionConfiguration())
    }

    /// The configuration for this client's one session (T-100). Cookie handling is
    /// enabled into a **private, in-memory, per-process** jar (`.ephemeral` —
    /// never `HTTPCookieStorage.shared`, never touched by another app or by
    /// WebKit's own store) so AO3's Cloudflare front door recognizes repeat
    /// requests instead of challenging every single one as a brand-new client
    /// (T-93 disabled cookie handling outright, which fixed A5-F1's identity leak
    /// but also discarded Cloudflare's own `cf_clearance`/`__cf_bm` — the regression
    /// that started serving a CAPTCHA/managed challenge).
    ///
    /// This must not reopen A5-F1: the AO3 **auth** session cookie
    /// (`AO3RequestDefaults.sessionCookieName`) is the only cookie capable of
    /// carrying account identity, so it is explicitly purged from this jar after
    /// every anonymous fetch (`purgeSessionCookie`, called from `performFetch`) —
    /// it can only ever appear here transiently if AO3 sets one on a *signed-out*
    /// response (a guest Rails session, never an authenticated one, since
    /// anonymous requests never send a Cookie header in the first place).
    /// Authenticated/write requests still build their `Cookie` header explicitly
    /// from `AO3AuthService`'s own persisted, per-account `AO3Session` — never
    /// from this ambient jar — so two accounts' authenticated requests can never
    /// race over a single shared cookie value; they only ever *read* this jar's
    /// Cloudflare cookies (`challengeCookieHeader`), a lookup that carries no
    /// identity and is safe under any concurrency. Internal (not private) so the
    /// isolation guarantee is unit-testable without a network call.
    static func makeAnonymousSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        // The shared app identity (browser-like base + product token + contact URL) —
        // single-sourced in AO3RequestDefaults because authenticated requests set the
        // same header per-request, which would silently override a diverging default.
        config.httpAdditionalHeaders = ["User-Agent": AO3RequestDefaults.userAgent]
        config.timeoutIntervalForRequest = 30
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        return config
    }

    /// Cloudflare's own bot-management cookies currently held for `url`, joined
    /// as a `Cookie` header fragment — never the AO3 auth cookie, filtered out
    /// defensively even though it cannot legitimately end up here (see
    /// `makeAnonymousSessionConfiguration`). `session` is an immutable `Sendable`
    /// value once constructed and `HTTPCookieStorage.cookies(for:)` is
    /// thread-safe, so this reads off-actor without an `await` — callers building
    /// an authenticated/write request (`AO3AuthService.authenticatedRequest`)
    /// merge this into their own explicit `Cookie` header so those requests also
    /// present a warm `cf_clearance`/`__cf_bm`, not just anonymous reads.
    nonisolated func challengeCookieHeader(for url: URL) -> String? {
        Self.challengeCookieHeader(from: session.configuration.httpCookieStorage?.cookies(for: url) ?? [])
    }

    /// Pure (unit-tested): joins every cookie except the AO3 auth cookie into a
    /// `Cookie` header fragment. nil when nothing remains — either the jar is
    /// empty, or (defensively; this must never legitimately happen — see
    /// `makeAnonymousSessionConfiguration`) it holds only the auth cookie.
    static func challengeCookieHeader(from cookies: [HTTPCookie]) -> String? {
        let pairs = cookies
            .filter { $0.name != AO3RequestDefaults.sessionCookieName }
            .map { "\($0.name)=\($0.value)" }
        return pairs.isEmpty ? nil : pairs.joined(separator: "; ")
    }

    /// Deletes any cookie named `AO3RequestDefaults.sessionCookieName` from
    /// `storage`. Called after every anonymous fetch as a structural invariant —
    /// the jar exists only to keep Cloudflare's own cookies warm, and must never
    /// be able to carry AO3 account identity, even transiently. Internal (not
    /// private) so the deletion itself is unit-testable against a real, isolated
    /// `HTTPCookieStorage` instance.
    static func purgeSessionCookie(from storage: HTTPCookieStorage?, url: URL) {
        guard let storage else { return }
        for cookie in storage.cookies(for: url) ?? []
            where cookie.name == AO3RequestDefaults.sessionCookieName {
            storage.deleteCookie(cookie)
        }
    }

    // MARK: Pacing

    /// Next instant a request may start. Actors are reentrant — several fetches can
    /// interleave across `await`s despite the actor — so the old "one request at a
    /// time" assumption didn't actually hold. This slot-claiming pacer makes the
    /// politeness real: every network call (GETs, POSTs, EPUB downloads, retries)
    /// claims the next slot synchronously, then sleeps out its own wait, so request
    /// *starts* are always at least `minRequestInterval` apart no matter how many
    /// callers are in flight.
    private var nextAllowedRequestAt = Date.distantPast
    private let minRequestInterval: TimeInterval = 0.6

    private func pace() async throws {
        let step = Self.paceStep(now: Date(), nextAllowed: nextAllowedRequestAt, minInterval: minRequestInterval)
        nextAllowedRequestAt = step.nextAllowed
        if step.wait > 0 {
            try await Task.sleep(nanoseconds: UInt64(step.wait * 1_000_000_000))
        }
    }

    /// The slot-claiming computation behind `pace()`, pure so the politeness math
    /// is unit-testable (the actor state + sleep around it are not).
    static func paceStep(
        now: Date,
        nextAllowed: Date,
        minInterval: TimeInterval
    ) -> (wait: TimeInterval, nextAllowed: Date) {
        (
            wait: nextAllowed.timeIntervalSince(now),
            nextAllowed: max(now, nextAllowed).addingTimeInterval(minInterval)
        )
    }

    // MARK: Requests

    /// Internal (not private) so feature extensions in other files (e.g.
    /// `AO3Client+Comments`) fetch through the same coalesced/retried/paced GET
    /// pipeline instead of growing a second one.
    func getHTML(_ url: URL) async throws -> String {
        let data = try await fetchData(from: url)
        return Self.htmlString(from: data)
    }

    /// Fetches an AO3-hosted image through the same paced, coalesced GET pipeline
    /// as HTML. Comment avatars use this rather than creating unpaced `AsyncImage`
    /// requests outside the app's AO3 networking policy.
    func imageData(at url: URL) async throws -> Data {
        try await fetchData(from: url)
    }

    private static func htmlString(from data: Data) -> String {
        // Preserve the existing lossy UTF-8 behavior for AO3 HTML with bad bytes.
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: data, as: UTF8.self)
    }

    /// Coalesces concurrent identical GETs so two callers requesting the same page
    /// at once share one network round-trip (politeness: no duplicate requests).
    private let coalescer = RequestCoalescer<URL, Data>()

    /// Same, for authenticated GETs. Keyed by URL *and* Cookie header so a mid-flight
    /// account switch can never hand one session's response to another. The value
    /// carries the response URL's path instead of the URLResponse (not Sendable) for
    /// the login-redirect check.
    private let authCoalescer = RequestCoalescer<String, (Data, String?)>()

    /// Fetches a URL's body, validating the HTTP status and retrying transient
    /// failures with backoff (see `withRetry`). Concurrent requests for the same URL
    /// are coalesced into a single fetch.
    private func fetchData(from url: URL) async throws -> Data {
        try await coalescer.shared(url) { [self] in
            try await performFetch(from: url)
        }
    }

    private func performFetch(from url: URL) async throws -> Data {
        Log.network.debug("GET \(url.absoluteString, privacy: .public)")
        return try await withRetry {
            try await pace()
            let (data, response) = try await session.data(from: url)
            // `defer`, not after `check`: a non-2xx response still completed a
            // round-trip and may have set a cookie, so the purge must run
            // regardless of whether the status throws.
            defer { Self.purgeSessionCookie(from: session.configuration.httpCookieStorage, url: url) }
            try Self.check(response)
            return data
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AO3Error.network("No response from AO3.")
        }
        switch http.statusCode {
        case 200 ... 299: return
        case 429: throw AO3Error.rateLimited(retryAfter: retryAfter(from: http))
        case 403: throw AO3Error.forbidden
        case 404: throw AO3Error.notFound
        case 500 ... 599: throw AO3Error.server(status: http.statusCode)
        default: throw AO3Error.http(status: http.statusCode)
        }
    }

    /// Parses a `Retry-After` header (seconds, or an HTTP-date) into a delay.
    private static func retryAfter(from http: HTTPURLResponse) -> TimeInterval? {
        guard let value = http.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) { return max(0, date.timeIntervalSinceNow) }
        return nil
    }

    // MARK: Retry

    /// Runs `operation`, retrying up to `maxRetries` times on *transient* failures
    /// with exponential backoff (~0.5s, then 1s). Network drop-outs/timeouts,
    /// HTTP 5xx, and 429 (honouring Retry-After) are retried; 404 / other 4xx and
    /// parse errors are not. Cancellation propagates immediately.
    private func withRetry<T>(maxRetries: Int = 2, _ operation: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                attempt += 1
                guard attempt <= maxRetries,
                      let delay = Self.retryDelay(for: error, attempt: attempt)
                else { throw error }
                Log.network.warning(
                    "Request failed (\(error.localizedDescription, privacy: .public)); retry \(attempt) in \(delay)s"
                )
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    /// Backoff (seconds) before retrying a transient error, or nil if it should
    /// not be retried. Base 0.5s, doubled per attempt; 429 respects Retry-After.
    /// Internal (not private) so the retry policy itself is unit-testable.
    static func retryDelay(for error: Error, attempt: Int) -> TimeInterval? {
        let backoff = 0.5 * pow(2, Double(attempt - 1)) // 0.5, 1.0, 2.0…
        switch error {
        case let AO3Error.rateLimited(retryAfter):
            return max(retryAfter ?? 0, backoff)
        case AO3Error.server:
            return backoff
        case let urlError as URLError where transientURLErrorCodes.contains(urlError.code):
            return backoff
        default:
            return nil
        }
    }

    /// URLSession transport failures worth retrying (transient connectivity).
    private static let transientURLErrorCodes: Set<URLError.Code> = [
        .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
        .notConnectedToInternet, .dnsLookupFailed, .secureConnectionFailed, .badServerResponse
    ]

    /// Runs a works search for the given filters. `page` is 1-based.
    func search(filters: AO3SearchFilters, page: Int = 1) async throws -> AO3SearchPage {
        var components = URLComponents(string: "\(base)/works/search")!
        var items: [URLQueryItem] = []

        func add(_ name: String, _ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            items.append(URLQueryItem(name: name, value: value))
        }

        // AO3's structured search has no multi-rating or exclusion fields.
        // `searchQuery` folds those into AO3's documented text-search syntax.
        add("work_search[query]", filters.searchQuery)

        add("work_search[fandom_names]", filters.fandom)
        add("work_search[character_names]", filters.characters)
        add("work_search[relationship_names]", filters.relationships)
        add("work_search[freeform_names]", filters.additionalTags)

        add("work_search[rating_ids]", filters.structuredRatingID)
        for warning in filters.warnings {
            items.append(URLQueryItem(name: "work_search[archive_warning_ids][]", value: warning.ao3ID))
        }
        for category in filters.categories {
            items.append(URLQueryItem(name: "work_search[category_ids][]", value: category.ao3ID))
        }
        add("work_search[crossover]", filters.crossover.value)
        add("work_search[complete]", filters.completion.value)
        add("work_search[word_count]", wordCountExpression(filters))
        add("work_search[revised_at]", filters.updated.value)
        add("work_search[language_id]", filters.language.code)
        add("work_search[sort_column]", filters.sort.column)

        items.append(URLQueryItem(name: "page", value: String(page)))
        components.queryItems = items

        guard let url = components.url else { throw AO3Error.network("Bad search URL.") }
        let html = try await getHTML(url)
        return try Self.parseSearchPage(html, page: page)
    }

    /// The URL of a user's "Marked for Later" reading list. AO3 renders it at
    /// `/users/<name>/readings?show=to-read`, paginated, using the same work-blurb
    /// markup as search results — so `parseSearchPage` reads it directly.
    static func markedForLaterURL(username: String, page: Int) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/users/\(name)/readings"
        var items = [URLQueryItem(name: "show", value: "to-read")]
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        components?.queryItems = items
        return components?.url
    }

    /// The URL of a user's AO3 reading history — the readings page with no filter.
    /// Same `li.work.blurb` markup as search, so `worksPage` / `parseSearchPage`
    /// read it directly.
    static func historyURL(username: String, page: Int) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/users/\(name)/readings"
        if page > 1 { components?.queryItems = [URLQueryItem(name: "page", value: String(page))] }
        return components?.url
    }

    /// The URL of a user's AO3 *work* subscriptions. The subscriptions page is a
    /// `<dl>` of work/series/user subscriptions — not work-blurb markup — so it needs
    /// `parseSubscriptionsPage`, not `parseSearchPage`. `?type=works` narrows it to
    /// work subscriptions server-side (so pagination counts works too).
    static func subscriptionsURL(username: String, page: Int) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/users/\(name)/subscriptions"
        var items = [URLQueryItem(name: "type", value: "works")]
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        components?.queryItems = items
        return components?.url
    }

    /// The URL of a user's AO3 bookmarks page (their bookmarked works), paginated.
    static func bookmarksURL(username: String, page: Int) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/users/\(name)/bookmarks"
        if page > 1 { components?.queryItems = [URLQueryItem(name: "page", value: String(page))] }
        return components?.url
    }

    /// The URL of a user's own posted works (`/users/<name>/works`). Standard
    /// `li.work.blurb` markup, so `worksPage` / `parseSearchPage` read it directly.
    static func myWorksURL(username: String, page: Int) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/users/\(name)/works"
        if page > 1 { components?.queryItems = [URLQueryItem(name: "page", value: String(page))] }
        return components?.url
    }

    /// The URL of a user's collections index (`/users/<name>/collections`).
    static func collectionsURL(username: String, page: Int) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/users/\(name)/collections"
        if page > 1 { components?.queryItems = [URLQueryItem(name: "page", value: String(page))] }
        return components?.url
    }

    /// The works in a collection (`/collections/<name>/works`). Standard work-blurb
    /// markup, so `worksPage` reads it directly.
    static func collectionWorksURL(name: String, page: Int) -> URL? {
        let slug = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/collections/\(slug)/works"
        if page > 1 { components?.queryItems = [URLQueryItem(name: "page", value: String(page))] }
        return components?.url
    }

    /// An authenticated collections-index page parsed into `AO3Collection`s.
    func collectionsPage(for request: URLRequest) async throws -> [AO3Collection] {
        try await Self.parseCollections(from: authenticatedHTML(for: request))
    }

    /// Parses a collections index (`li.collection.blurb`) into name/title/byline.
    static func parseCollections(from html: String) throws -> [AO3Collection] {
        let doc = try SwiftSoup.parse(html)
        var result: [AO3Collection] = []
        for li in try doc.select("li.collection.blurb").array() {
            guard let link = try li.select("h4.heading a[href*=/collections/]").first() else { continue }
            let href = (try? link.attr("href")) ?? ""
            // /collections/<name>[/...] → slug
            guard let range = href.range(of: "/collections/") else { continue }
            let slug = String(href[range.upperBound...]).split(separator: "/").first.map(String.init) ?? ""
            guard !slug.isEmpty else { continue }
            let title = (try? link.text()) ?? slug
            let maintainerLinks = try li.select("h4.heading a[href*='/users/']").array()
            let maintainerNames = try maintainerLinks.map { try $0.text() }
            let maintainerIdentities = try maintainerLinks.compactMap { link in
                try AO3AuthorIdentity(displayName: link.text(), href: link.attr("href"))
            }
            let fallbackByline = (try? li.select(".byline, .heading .byline").first()?.text()) ?? ""
            result.append(AO3Collection(
                name: slug,
                title: title,
                byline: maintainerNames.isEmpty ? fallbackByline : maintainerNames.joined(separator: ", "),
                maintainerNames: maintainerNames,
                maintainerIdentities: maintainerIdentities
            ))
        }
        return result
    }

    /// Fetches an authenticated AO3 page and returns its HTML. The `request` must
    /// already carry the user's session cookies — build it with
    /// `AO3AuthService.authenticatedRequest(for:)`. A bounce to AO3's login page is
    /// surfaced as `AO3Error.authenticationRequired` so the caller can re-auth.
    private func authenticatedHTML(for request: URLRequest) async throws -> String {
        var request = request
        // The session cookies are attached explicitly by the auth service; don't let
        // URLSession's shared cookie storage add a second, possibly stale, set.
        request.httpShouldHandleCookies = false
        Log.network.debug("GET (auth) \(request.url?.absoluteString ?? "?", privacy: .public)")

        let key = Self.authCoalescingKey(
            url: request.url,
            cookieHeader: request.value(forHTTPHeaderField: "Cookie")
        )
        // Capture a let so the coalescer closure does not close over the mutable `var request`.
        let fetchRequest = request
        let (data, responsePath) = try await authCoalescer.shared(key) { [self] in
            try await performAuthenticatedFetch(for: fetchRequest)
        }
        if Self.isLoginRedirect(path: responsePath) {
            throw AO3Error.authenticationRequired
        }
        return Self.htmlString(from: data)
    }

    /// Whether AO3 bounced an authenticated request to its login page — the
    /// signal that the session cookies are no longer valid.
    private static func isLoginRedirect(path: String?) -> Bool {
        path?.contains("/users/login") == true
    }

    /// The `authCoalescer` key: URL *and* Cookie header, so a mid-flight account
    /// switch can never share an in-flight result with another account (A5-F1) — two
    /// different sessions requesting the same URL always produce different keys, and
    /// this coalescer is never touched by the anonymous `coalescer` pipeline at all.
    /// Internal + static so the scoping rule is unit-testable without a network call.
    static func authCoalescingKey(url: URL?, cookieHeader: String?) -> String {
        (url?.absoluteString ?? "") + "|" + (cookieHeader ?? "")
    }

    private func performAuthenticatedFetch(for request: URLRequest) async throws -> (Data, String?) {
        try await withRetry {
            try await pace()
            let (data, response) = try await session.data(for: request, delegate: redirectCookieRelay)
            try Self.check(response)
            return (data, response.url?.path)
        }
    }

    // MARK: - Write actions (authenticated, single-shot POSTs)

    /// HTML of an authenticated page for a write flow that first needs the page's CSRF
    /// token (a polite GET — retried/coalesced like other reads).
    func authenticatedPageHTML(for request: URLRequest) async throws -> String {
        try await authenticatedHTML(for: request)
    }

    /// Submits a single authenticated POST and returns its status + body. **Never
    /// retried or coalesced** — replaying a write would double-post (kudos/comments).
    /// 429s are surfaced (not auto-retried) so the UI can ask the user to try later.
    func submitWrite(_ request: URLRequest) async throws -> (status: Int, body: String) {
        var request = request
        request.httpShouldHandleCookies = false
        Log.network.debug("POST (auth) \(request.url?.absoluteString ?? "?", privacy: .public)")
        try await pace()
        let (data, response) = try await session.data(for: request, delegate: redirectCookieRelay)
        guard let http = response as? HTTPURLResponse else {
            throw AO3Error.network("No response from AO3.")
        }
        if Self.isLoginRedirect(path: http.url?.path) {
            throw AO3Error.authenticationRequired
        }
        if http.statusCode == 429 {
            throw AO3Error.rateLimited(retryAfter: Self.retryAfter(from: http))
        }
        return (http.statusCode, Self.htmlString(from: data))
    }

    /// The Rails CSRF authenticity token from a page's `<meta name="csrf-token">`.
    static func parseCSRFToken(from html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html),
              let token = try? doc.select("meta[name=csrf-token]").first()?.attr("content")
        else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The pseud id the fetched form would submit (e.g. `comment[pseud_id]` for
    /// comments, `bookmark[pseud_id]` for bookmarks). Single-pseud accounts get a
    /// **hidden input** (otwarchive `_comment_form.html.erb` renders
    /// `f.hidden_field :pseud_id` unless `current_user.pseuds.count > 1`), whose
    /// value must still be POSTed — the server never defaults a missing pseud, it
    /// applies guest validations and rejects the write. Precedence mirrors
    /// `ao3_api`'s `get_pseud_id`: hidden input first, then the `<select>`
    /// (explicitly-selected option, else the first). nil when the page renders no
    /// pseud control at all — an interstitial/login/formless page, never a
    /// postable form.
    static func parseDefaultPseudID(from html: String, field: String = "comment[pseud_id]") -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let hidden = try? doc.select("input[name=\"\(field)\"]").first()?.attr("value")
        if let hidden, !hidden.isEmpty { return hidden }
        let select = try? doc.select("select[name=\"\(field)\"]").first()
        let selected = try? select?.select("option[selected]").first()?.attr("value")
        if let selected, !selected.isEmpty { return selected }
        let first = try? select?.select("option").first()?.attr("value")
        return (first?.isEmpty == false) ? first : nil
    }

    /// Every pseud AO3 rendered as an authorized choice in a form's pseud
    /// `<select>`. The default flag: the explicitly-selected option, else the
    /// first. Empty when the form has no pseud select — single-pseud accounts get
    /// a hidden input instead, which `parseDefaultPseudID` reads (its value must
    /// still be POSTed; the server rejects a pseud-less signed-in comment rather
    /// than defaulting it — otwarchive `comment.rb` guest validations).
    static func parsePostingPseudOptions(
        from html: String,
        field: String = "comment[pseud_id]"
    ) -> [AO3PostingPseudOption] {
        guard let doc = try? SwiftSoup.parse(html),
              let select = try? doc.select("select[name=\"\(field)\"]").first(),
              let options = try? select.select("option").array()
        else { return [] }
        var results: [AO3PostingPseudOption] = []
        var sawSelected = false
        for option in options {
            let id = (try? option.attr("value")) ?? ""
            let name = ((try? option.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !name.isEmpty else { continue }
            let isSelected = option.hasAttr("selected")
            results.append(AO3PostingPseudOption(id: id, name: name, isDefault: isSelected))
            if isSelected { sawSelected = true }
        }
        if !sawSelected, let first = results.first {
            results[0] = AO3PostingPseudOption(id: first.id, name: first.name, isDefault: true)
        }
        return results
    }

    /// Whether the user is currently subscribed to the work, read from the work page's
    /// subscribe/unsubscribe form. When subscribed, AO3 renders a delete form whose
    /// action is the unsubscribe path (`/users/X/subscriptions/<id>`); that path is
    /// returned so the caller can unsubscribe.
    static func parseSubscription(from html: String) -> (isSubscribed: Bool, unsubscribePath: String?) {
        guard let doc = try? SwiftSoup.parse(html),
              let form = try? doc.select("form[action*=/subscriptions]").first()
        else { return (false, nil) }
        let action = (try? form.attr("action")) ?? ""
        let method = (try? form.select("input[name=_method]").first()?.attr("value"))?
            .lowercased() ?? ""
        if method == "delete" {
            return (true, action.isEmpty ? nil : action)
        }
        return (false, nil)
    }

    /// The signed-in user's existing bookmark of this work, read from the work
    /// page's embedded bookmark form. When already bookmarked, AO3 renders that
    /// form as an *edit*: `action="/bookmarks/<id>"` carrying `_method=put`,
    /// prefilled with the bookmark's current values (verified live 2026-07-16).
    /// A not-yet-bookmarked work renders a create form
    /// (`action="/works/<id>/bookmarks"`, no method override) → nil.
    static func parseExistingBookmark(from html: String) -> AO3ExistingBookmark? {
        guard let doc = try? SwiftSoup.parse(html),
              let form = try? doc.select("form[action*=/bookmarks]").first(),
              let action = try? form.attr("action"),
              action.contains("/bookmarks/"),
              let method = try? form.select("input[name=_method]").first()?.attr("value"),
              method.lowercased() == "put"
        else { return nil }

        var input = AO3AuthService.BookmarkInput()
        if let notes = try? form.select("textarea[name='bookmark[bookmarker_notes]']").first()?.text() {
            input.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        input.tags = (try? form.select("input[name='bookmark[tag_string]']").first()?
            .attr("value")) ?? ""
        input.isPrivate = (try? form.select("input[type=checkbox][name='bookmark[private]']").first()?
            .hasAttr("checked")) ?? false
        input.isRec = (try? form.select("input[type=checkbox][name='bookmark[rec]']").first()?
            .hasAttr("checked")) ?? false
        let collections = (try? form.select("input[name='bookmark[collection_names]']").first()?
            .attr("value")) ?? ""
        return AO3ExistingBookmark(editPath: action, collectionNames: collections, input: input)
    }

    /// The first error AO3 renders after a rejected write (so the UI can show the
    /// real reason), or nil when the page carries no recognized error. Covers the
    /// validation error list plus every flash class otwarchive uses for failed
    /// writes: `flash[:error]` (`.flash.error`), `flash[:comment_error]`
    /// (`.flash.comment_error` — blocked comments and failed deletes;
    /// `comments_controller.rb`), and `flash[:caution]` (`.flash.caution` — the
    /// Inbox mass-edit failure branch, `inbox_controller.rb`). The CSS classes
    /// don't overlap (`flash_div` emits `class="flash <key>"`), so `.flash.error`
    /// alone never matched the latter two.
    static func writeErrorMessage(in html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let text = try? doc.select(
            ".errorlist li, .error p, .flash.error, .flash.comment_error, .flash.caution"
        ).first()?.text()
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    /// The success flash otwarchive renders after a completed comment or Inbox
    /// write: `flash[:comment_notice]` on comment create/update and most deletes,
    /// `flash[:notice]` on the unreviewed-delete branch and Inbox mass-edits.
    /// Rendered by the comment region (`_commentable.html.erb`,
    /// `comments/show.html.erb`) and the application layout respectively — this is
    /// the positive evidence a final-200 write actually landed. Deliberately
    /// requires both classes (`div.flash.notice`): the moderated-work note inside
    /// the comment form is a bare `p.notice` and must not read as success.
    static func writeSuccessMessage(in html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let text = try? doc.select(".flash.comment_notice, .flash.notice").first()?.text()
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    /// Honest reading of a comment/Inbox write response (CAA-2). A final 2xx/3xx
    /// page is only `success` with positive evidence (`writeSuccessMessage`);
    /// a recognized error flash/list is `rejected` (with AO3's own reason when one
    /// parsed); anything else that returned 2xx/3xx — maintenance pages, blank
    /// bodies, interstitials that render neither flash — is `unconfirmed`: the
    /// write may or may not have been recorded, so callers must treat it as
    /// ambiguous (verification for posts/replies, a visible "couldn't confirm"
    /// for edit/delete/Inbox), never as success. Pure and static so the
    /// classification is unit-testable without a network call.
    enum CommentWriteVerdict: Equatable {
        case success
        /// AO3's parsed reason, or nil when only the status code condemned it
        /// (callers supply their own action-specific fallback message).
        case rejected(String?)
        case unconfirmed
    }

    static func commentWriteVerdict(status: Int, body: String) -> CommentWriteVerdict {
        if let message = writeErrorMessage(in: body) { return .rejected(message) }
        guard (200 ... 399).contains(status) else { return .rejected(nil) }
        if writeSuccessMessage(in: body) != nil { return .success }
        return .unconfirmed
    }

    /// An authenticated reading-list / search-style page (work blurbs + pagination),
    /// e.g. the Marked-for-Later list.
    func worksPage(for request: URLRequest, page: Int) async throws -> AO3SearchPage {
        try await Self.parseSearchPage(authenticatedHTML(for: request), page: page)
    }

    /// Loads an arbitrary AO3 works listing URL (e.g. a tag's `/tags/<name>/works`
    /// page, tapped in a work's preface) and parses its work blurbs. Adds the page
    /// number + `view_adult=true` so paging and adult works resolve like search.
    func worksPage(at url: URL, page: Int) async throws -> AO3SearchPage {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = (components?.queryItems ?? []).filter { $0.name != "page" && $0.name != "view_adult" }
        items.append(URLQueryItem(name: "view_adult", value: "true"))
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        components?.queryItems = items
        let resolved = components?.url ?? url
        return try await Self.parseSearchPage(getHTML(resolved), page: page)
    }

    /// An authenticated AO3 bookmarks page (the user's bookmarked works).
    func bookmarksPage(for request: URLRequest, page: Int) async throws -> AO3SearchPage {
        try await Self.parseBookmarksPage(authenticatedHTML(for: request), page: page)
    }

    /// An authenticated AO3 subscriptions page (the user's *work* subscriptions).
    func subscriptionsPage(for request: URLRequest, page: Int) async throws -> AO3SearchPage {
        try await Self.parseSubscriptionsPage(authenticatedHTML(for: request), page: page)
    }

    /// Builds AO3's `word_count` expression from the from/to fields.
    private func wordCountExpression(_ filters: AO3SearchFilters) -> String? {
        let from = filters.wordsFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = filters.wordsTo.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (from.isEmpty, to.isEmpty) {
        case (false, false): return "\(from)-\(to)"
        case (false, true): return "> \(from)"
        case (true, false): return "< \(to)"
        case (true, true): return nil
        }
    }

    /// Downloads a work's EPUB to a temp file. AO3 accepts any filename slug, so
    /// we don't need to scrape the exact link — the work id is enough.
    /// A series page URL with the given page number. Strips any existing `page`
    /// query item and adds it back only for pages past the first.
    static func seriesPageURL(_ seriesURL: URL, page: Int) -> URL? {
        guard var components = URLComponents(url: seriesURL, resolvingAgainstBaseURL: false) else { return nil }
        var items = (components.queryItems ?? []).filter { $0.name != "page" }
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    /// Every work in a series, across all of the series page's pages. The series
    /// page lists works with the same `li.work.blurb` markup as search, so it reuses
    /// `parseSearchPage`. Used by the download queue to fetch a whole series.
    func seriesWorks(seriesURL: URL) async throws -> [AO3WorkSummary] {
        var all: [AO3WorkSummary] = []
        var page = 1
        while let pageURL = Self.seriesPageURL(seriesURL, page: page) {
            let result = try await Self.parseSearchPage(getHTML(pageURL), page: page)
            all.append(contentsOf: result.works)
            if result.works.isEmpty || page >= result.totalPages { break }
            page += 1
        }
        return all
    }

    /// The first page of a series, including AO3's parsed total page count. This is
    /// intentionally bounded to one request so callers can decide whether an
    /// automatic small-series action is safe before crawling every page.
    func seriesPreview(seriesURL: URL) async throws -> AO3SeriesPreview {
        guard let pageURL = Self.seriesPageURL(seriesURL, page: 1) else {
            throw AO3Error.network("Bad series URL.")
        }
        let result = try await Self.parseSearchPage(getHTML(pageURL), page: 1)
        return AO3SeriesPreview(
            works: result.works,
            currentPage: result.currentPage,
            totalPages: result.totalPages
        )
    }

    func downloadEPUB(workID: Int) async throws -> URL {
        Log.network.info("Downloading EPUB for work \(workID)")
        guard let url = URL(string: "\(base)/downloads/\(workID)/work.epub") else {
            throw AO3Error.network("Bad download URL.")
        }
        let tempURL = try await withRetry { () -> URL in
            try await pace()
            let (tempURL, response) = try await session.download(from: url)
            defer { Self.purgeSessionCookie(from: session.configuration.httpCookieStorage, url: url) }
            try Self.check(response)
            return tempURL
        }
        let destination = Storage.tempDownloadURL(suggestedName: "\(workID).epub")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    /// Fetches a work's canonical tags from its AO3 page (fandoms, relationships,
    /// characters, freeform, warnings, categories — the rating is stored separately).
    /// `view_adult=true` clears the adult interstitial; works locked to registered
    /// users return no tags, which the caller treats as "leave the EPUB tags".
    func workTags(workID: Int) async throws -> AO3WorkTagGroups {
        guard let url = URL(string: "\(base)/works/\(workID)?view_adult=true") else {
            throw AO3Error.network("Bad work URL.")
        }
        let html = try await getHTML(url)
        return try Self.parseWorkTags(from: html)
    }

    /// Fetches a work's refreshable metadata from its AO3 page. Callers must treat
    /// any thrown error as a non-destructive refresh failure; only this successful,
    /// fully parsed value should be merged into local `SavedWork` records.
    func workMetadata(
        workID: Int, request: URLRequest? = nil
    ) async throws -> AO3WorkMetadata {
        guard let url = URL(string: "\(base)/works/\(workID)?view_adult=true") else {
            throw AO3Error.network("Bad work URL.")
        }
        let html: String
        if var request {
            request.url = url
            html = try await authenticatedPageHTML(for: request)
        } else {
            html = try await getHTML(url)
        }
        return try Self.parseWorkMetadata(from: html, workID: workID)
    }

    /// Parses a work page's canonical tag groups + stats from its HTML. Split out
    /// from `workTags(workID:)` so it can be unit-tested against fixture HTML
    /// without a network round-trip.
    static func parseWorkTags(from html: String) throws -> AO3WorkTagGroups {
        try parseWorkMetadata(from: html).tagGroups
    }

    // Lint: parser stays cohesive to avoid changing scraping behavior.
    /// Parses a work page's refreshable metadata from its HTML. This intentionally
    /// returns a value type, leaving merge/safety decisions to the refresh service.
    static func parseWorkMetadata( // swiftlint:disable:this function_body_length
        from html: String,
        workID: Int = 0
    ) throws -> AO3WorkMetadata {
        let doc = try SwiftSoup.parse(html)

        func clean(_ text: String?) -> String {
            (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func firstText(_ selectors: [String]) -> String {
            for selector in selectors {
                let value = clean(try? doc.select(selector).first()?.text())
                if !value.isEmpty { return value }
            }
            return ""
        }

        func unique(_ values: [String]) -> [String] {
            var seen = Set<String>()
            var result: [String] = []
            for raw in values {
                let value = clean(raw)
                guard !value.isEmpty, seen.insert(value.lowercased()).inserted else { continue }
                result.append(value)
            }
            return result
        }

        func tags(_ kind: String) throws -> [String] {
            var seen = Set<String>()
            var result: [String] = []
            for element in try doc.select("dd.\(kind).tags a.tag").array() {
                let tag = try clean(element.text())
                if !tag.isEmpty, seen.insert(tag.lowercased()).inserted { result.append(tag) }
            }
            return result
        }

        func stat(_ cls: String) -> String {
            firstText(["dl.stats dd.\(cls)", "dd.\(cls)"])
        }

        func statInt(_ cls: String) -> Int? {
            Int(stat(cls).filter(\.isNumber))
        }

        func authorByline() throws -> (names: [String], identities: [AO3AuthorIdentity]) {
            let selectors = [
                "h3.byline.heading a[rel=author]",
                "h3.byline a[rel=author]",
                "h3.byline.heading a",
                "h3.byline a"
            ]
            for selector in selectors {
                let links = try doc.select(selector).array()
                let names = try unique(links.map { try $0.text() })
                if !names.isEmpty {
                    let identities = try links.compactMap { link -> AO3AuthorIdentity? in
                        try AO3AuthorIdentity(
                            displayName: clean(link.text()),
                            href: link.attr("href")
                        )
                    }
                    return (names, identities)
                }
            }
            let anonymousName = firstText(["h3.byline.heading", "h3.byline"])
            if !anonymousName.isEmpty {
                return ([], [.nonNavigable(anonymousName, kind: .anonymous)])
            }
            return ([], [])
        }

        func absoluteAO3URL(_ href: String) -> String? {
            let trimmed = clean(href)
            guard !trimmed.isEmpty else { return nil }
            return trimmed.hasPrefix("http") ? trimmed : "https://archiveofourown.org\(trimmed)"
        }

        func firstNumber(in text: String) -> Int? {
            let parts = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
            return parts.lazy.compactMap { Int($0) }.first
        }

        func completionStatus(chapters: String, statusLabel: String) -> Bool? {
            let label = statusLabel.lowercased()
            if label.contains("completed") { return true }
            if label.contains("updated") { return false }
            let parts = chapters.split(separator: "/")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else { return nil }
            if let posted = Int(parts[0]), let total = Int(parts[1]), total > 0 {
                return posted >= total
            }
            if parts[1] == "?" { return false }
            return nil
        }

        /// AO3 doesn't class the "Completed:"/"Updated:" <dt> label itself — only its
        /// sibling <dd class="status"> carries a class. Read the label from that dt's
        /// text instead of a (nonexistent) `dt.status` selector.
        func statusDTLabel() -> String {
            guard let statusDD = try? doc.select("dd.status").first() else { return "" }
            return clean(try? statusDD.previousElementSibling()?.text())
        }

        let title = firstText(["h2.title.heading", "h2.title"])
        let byline = try authorByline()
        let authors = byline.names
        let fandoms = try tags("fandom")
        let relationships = try tags("relationship")
        let characters = try tags("character")
        let freeforms = try tags("freeform")
        let warnings = try tags("warning")
        let categories = try tags("category")
        let rating = try tags("rating").first ?? firstText(["dd.rating.tags"])
        let language = firstText(["dd.language"])
        let chapters = stat("chapters")
        let seriesLink = try doc.select("dd.series a[href*=\"/series/\"]").first()
        let seriesTitle = try clean(seriesLink?.text())
        let rawSeriesURL = try seriesLink?.attr("href")
        let seriesPositionText = firstText(["dd.series span.position", "dd.series"])

        let metadata = AO3WorkMetadata(
            id: workID,
            title: title,
            authors: authors,
            authorIdentities: byline.identities,
            summary: firstText(["div.summary blockquote.userstuff", "blockquote.userstuff.summary"]),
            rating: rating,
            fandoms: fandoms,
            relationships: relationships,
            characters: characters,
            freeforms: freeforms,
            warnings: warnings,
            categories: categories,
            language: language,
            words: statInt("words"),
            chapters: chapters,
            kudos: statInt("kudos"),
            comments: statInt("comments"),
            hits: statInt("hits"),
            datePublished: firstText(["dd.published"]),
            dateUpdated: firstText(["dd.status", "dd.updated"]),
            isComplete: completionStatus(chapters: chapters, statusLabel: statusDTLabel()),
            seriesTitle: seriesTitle.isEmpty ? nil : seriesTitle,
            seriesURL: rawSeriesURL.flatMap(absoluteAO3URL),
            seriesPosition: firstNumber(in: seriesPositionText)
        )

        guard !metadata.title.isEmpty
            || !metadata.tagGroups.isEmpty
            || metadata.words != nil
            || !metadata.chapters.isEmpty
        else { throw AO3Error.parse }
        return metadata
    }

    /// Live tag search via AO3's autocomplete endpoints (returns canonical tag
    /// names for the given kind). Used by the filter tag pickers.
    func autocompleteTags(kind: AO3TagKind, term: String) async throws -> [String] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var components = URLComponents(string: "\(base)/autocomplete/\(kind.rawValue)")!
        components.queryItems = [URLQueryItem(name: "term", value: trimmed)]
        guard let url = components.url else { return [] }
        let data = try await fetchData(from: url)
        return try (JSONDecoder().decode([AutocompleteItem].self, from: data)).map(\.name)
    }

    private struct AutocompleteItem: Decodable { let id: String; let name: String }

    /// The most-used tags of a kind for a fandom, read from that fandom's works-page
    /// filter sidebar (AO3 lists the top ~10 with work counts). Used to seed the tag
    /// pickers with fandom-relevant suggestions before the user searches. Returns an
    /// empty list (rather than throwing) when the fandom page can't be loaded.
    func popularTags(forFandom fandom: String, kind: AO3TagKind) async throws -> [String] {
        let field: String
        switch kind {
        case .character: field = "character_ids"
        case .relationship: field = "relationship_ids"
        case .freeform, .tag: field = "freeform_ids"
        case .fandom: return [] // no parent-fandom context for the fandom field
        }
        guard let url = fandomWorksURL(fandom) else { return [] }
        let html = try await getHTML(url)
        let doc = try SwiftSoup.parse(html)

        let target = "include_work_search[\(field)][]"
        var seen = Set<String>()
        var result: [String] = []
        for input in try doc.select("input[type=checkbox]").array() {
            guard (try? input.attr("name")) == target, let label = input.parent() else { continue }
            // The label reads "Tag Name (12345)" — strip only a trailing numeric count
            // (tag names can themselves contain parentheses, e.g. "Naruto (Anime...)").
            let name = try Self.strippingTrailingCount(label.text().trimmingCharacters(in: .whitespacesAndNewlines))
            if !name.isEmpty, seen.insert(name).inserted { result.append(name) }
        }
        return result
    }

    /// Builds a fandom's `/tags/<escaped>/works` URL, applying AO3's tag escaping
    /// (`&`→`*a*`, `/`→`*s*`, `.`→`*d*`, `?`→`*q*`, `#`→`*h*`) before percent-encoding.
    private func fandomWorksURL(_ fandom: String) -> URL? {
        var escaped = fandom
        for (from, to) in [("/", "*s*"), ("&", "*a*"), (".", "*d*"), ("?", "*q*"), ("#", "*h*")] {
            escaped = escaped.replacingOccurrences(of: from, with: to)
        }
        guard let encoded = escaped.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "\(base)/tags/\(encoded)/works")
    }

    private static func strippingTrailingCount(_ text: String) -> String {
        guard let range = text.range(of: #"\s*\(\d[\d,]*\)\s*$"#, options: .regularExpression) else { return text }
        return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fetches AO3's `/media` page: each media category with its featured fandoms.
    /// The fandom link text is the canonical tag name, ready for a fandom search.
    func mediaCategories() async throws -> [AO3MediaCategory] {
        guard let url = URL(string: "\(base)/media") else {
            throw AO3Error.network("Bad media URL.")
        }
        let html = try await getHTML(url)
        let doc = try SwiftSoup.parse(html)
        var categories: [AO3MediaCategory] = []
        for li in try doc.select("ul.media.fandom.index.group li.medium.listbox.group").array() {
            let heading = try li.select("h3.heading a").first()
            let name = try heading?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // The heading link points at the category's full fandom index page.
            let fandomsURL = try (heading?.attr("href")) ?? ""
            // The category-name link in the heading isn't an `a.tag`, so this picks
            // up only the featured fandom links.
            let fandoms = try li.select("a.tag").array().compactMap { element -> AO3Fandom? in
                let fandom = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                return fandom.isEmpty ? nil : AO3Fandom(name: fandom)
            }
            if !name.isEmpty, !fandoms.isEmpty {
                categories.append(AO3MediaCategory(name: name, fandoms: fandoms, fandomsURL: fandomsURL))
            }
        }
        guard !categories.isEmpty else { throw AO3Error.parse }
        return categories
    }

    /// Fetches the full fandom index for a media category (every fandom plus its
    /// work count), from the category's `/media/<name>/fandoms` page. `path` is the
    /// relative href captured in `mediaCategories()`.
    func fandoms(atPath path: String) async throws -> [AO3Fandom] {
        let absolute = path.hasPrefix("http") ? path : base + path
        guard let url = URL(string: absolute) else { throw AO3Error.network("Bad fandoms URL.") }
        let html = try await getHTML(url)
        let result = Self.parseFandomIndex(html)
        guard !result.isEmpty else { throw AO3Error.parse }
        return result
    }

    /// Extracts every fandom (+work count) from a `/media/<name>/fandoms` index page
    /// with a single linear string scan — deliberately **not** SwiftSoup.
    ///
    /// These pages are enormous (the big categories list 10k+ fandoms; multiple MB of
    /// HTML). Building a full DOM for them, then running a `select` per `<li>`, cost
    /// seconds of pegged CPU and a transient memory balloon well past 1GB (SwiftSoup's
    /// per-select query-index rebuilds over a several-hundred-thousand-node tree) —
    /// enough for iOS to jetsam the app on device the moment Browse opened (BUG-5's
    /// second, deeper root cause; the first was the per-render stats storm).
    ///
    /// The page's relevant markup is flat and regular — one `<ol class="fandom index
    /// group">` per letter, each `<li>` holding `<a class="tag" href="…">Name</a>
    /// (1,234)` — so a cursor scan is exact, order-of-attributes tolerant, and runs in
    /// O(page) time with O(result) memory. Static + internal for fixture tests,
    /// matching `parseSearchPage`'s convention.
    static func parseFandomIndex(_ html: String) -> [AO3Fandom] {
        var result: [AO3Fandom] = []
        var seen = Set<String>()
        var cursor = html.startIndex

        // Each letter section is its own <ol class="fandom index group">.
        while let olOpen = html.range(of: "<ol", range: cursor..<html.endIndex) {
            guard let olTagEnd = html.range(of: ">", range: olOpen.upperBound..<html.endIndex) else { break }
            cursor = olTagEnd.upperBound
            let olClasses = Self.classList(in: html[olOpen.upperBound..<olTagEnd.lowerBound])
            guard olClasses.contains("fandom"), olClasses.contains("index") else { continue }
            let blockEnd = html.range(of: "</ol>", range: cursor..<html.endIndex)?.lowerBound ?? html.endIndex

            // Every fandom link inside the block: <a … class="tag" …>Name</a> (count)
            var linkCursor = cursor
            while let aOpen = html.range(of: "<a ", range: linkCursor..<blockEnd) {
                guard let aTagEnd = html.range(of: ">", range: aOpen.upperBound..<blockEnd) else { break }
                linkCursor = aTagEnd.upperBound
                let aAttrs = html[aOpen.upperBound..<aTagEnd.lowerBound]
                guard Self.classList(in: aAttrs).contains("tag") else { continue }
                guard let aClose = html.range(of: "</a>", range: aTagEnd.upperBound..<blockEnd) else { break }

                let rawName = String(html[aTagEnd.upperBound..<aClose.lowerBound])
                let name = rawName.decodingHTMLEntities()
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // The text between </a> and the next tag is the work count, e.g.
                // " (1,234)" (same digits-only read the old DOM parse used).
                let tailEnd = html.range(of: "<", range: aClose.upperBound..<blockEnd)?.lowerBound ?? blockEnd
                let digits = html[aClose.upperBound..<tailEnd].filter(\.isNumber)
                let count = Int(digits)

                if !name.isEmpty, seen.insert(name).inserted {
                    result.append(AO3Fandom(name: name, workCount: count))
                }
                linkCursor = aClose.upperBound
            }
            cursor = blockEnd
        }
        return result
    }

    /// The space-separated class names from a tag's attribute text — so matching
    /// `class="tag"` keeps CSS `a.tag` semantics (word membership, any order,
    /// tolerant of extra classes), not an exact-string comparison.
    private static func classList(in attributes: Substring) -> [Substring] {
        guard let attrStart = attributes.range(of: "class=\"") else { return [] }
        let valueStart = attrStart.upperBound
        guard let valueEnd = attributes[valueStart...].firstIndex(of: "\"") else { return [] }
        return attributes[valueStart..<valueEnd].split(separator: " ")
    }

    // MARK: Parsing (ported selectors)

    /// Parses a works-search results page (works list + pagination). `static` and
    /// internal so it can be unit-tested against fixture HTML without a network call.
    static func parseSearchPage(_ html: String, page: Int) throws -> AO3SearchPage {
        try parseWorksList(html, page: page, blurbSelector: "li.work.blurb")
    }

    /// Parses a user's AO3 bookmarks page. Bookmark blurbs are `li.bookmark.blurb`
    /// (id `bookmark_<n>`, not the work id), so `parseBlurb` reads the work id from
    /// the `/works/<id>` title link. Series and external-work bookmarks have no such
    /// link and are skipped — only bookmarked works are surfaced.
    static func parseBookmarksPage(_ html: String, page: Int) throws -> AO3SearchPage {
        try parseWorksList(html, page: page, blurbSelector: "li.bookmark.blurb")
    }

    /// Parses a user's AO3 subscriptions page. Unlike search/readings, it's a
    /// `<dl class="subscription index group">` of `<dt>` items mixing work, series, and
    /// user subscriptions — not `li.work.blurb` markup. Each `<dt>` holds a link to the
    /// subscribed item plus a byline; we keep the ones linking to `/works/<id>` and
    /// build a sparse summary (title + author only — the page carries no stats).
    static func parseSubscriptionsPage(_ html: String, page: Int) throws -> AO3SearchPage {
        let doc = try SwiftSoup.parse(html)
        var works: [AO3WorkSummary] = []
        for dt in try doc.select("dl.subscription dt").array() {
            // The work link points at /works/<id>; series/user subscriptions have no
            // such link and are skipped.
            guard let workLink = try dt.select("a[href*=\"/works/\"]").first(),
                  let id = try Self.workID(fromPath: workLink.attr("href")) else { continue }
            let title = try workLink.text()
            // The remaining links are the byline pseuds (/users/...) — the author(s).
            let authorLinks = try dt.select("a[href*=\"/users/\"]").array()
            let authors = try authorLinks.map { try $0.text() }
            let identities = try authorLinks.compactMap { link in
                try AO3AuthorIdentity(displayName: link.text(), href: link.attr("href"))
            }
            works.append(.subscription(
                id: id,
                title: title,
                authors: authors,
                authorIdentities: identities
            ))
        }
        let totalPages = try Self.paginationTotal(in: doc, currentPage: page)
        return AO3SearchPage(works: works, currentPage: page, totalPages: totalPages)
    }

    private static func parseWorksList(
        _ html: String, page: Int, blurbSelector: String
    ) throws -> AO3SearchPage {
        let doc = try SwiftSoup.parse(html)
        let blurbs = try doc.select(blurbSelector).array()
        // Skip any single malformed / non-work blurb rather than failing the page.
        let works = blurbs.compactMap { try? Self.parseBlurb($0) }
        let totalPages = try Self.paginationTotal(in: doc, currentPage: page)
        return AO3SearchPage(works: works, currentPage: page, totalPages: totalPages)
    }

    /// Extracts the numeric work id from a `/works/<id>[/...]` path.
    private static func workID(fromPath path: String) -> Int? {
        guard let range = path.range(of: "/works/") else { return nil }
        return Int(path[range.upperBound...].prefix { $0.isNumber })
    }

    static func parseBlurb(_ el: Element) throws -> AO3WorkSummary {
        // Search/readings blurbs are `li id="work_<id>"`; bookmark blurbs are
        // `li id="bookmark_<id>"`, so fall back to the work's `/works/<id>` link.
        let id: Int
        if let workID = Int(el.id().replacingOccurrences(of: "work_", with: "")) {
            id = workID
        } else if let href = try el.select("h4.heading a[href^=\"/works/\"]").first()?.attr("href"),
                  let workID = Self.workID(fromPath: href) {
            id = workID
        } else {
            throw AO3Error.parse
        }

        let title = try el.select("h4.heading a").first()?.text() ?? "Untitled"
        let authorLinks = try el.select("h4.heading a[rel=author]").array()
        let authors = try authorLinks.map { try $0.text() }
        var authorIdentities = try authorLinks.compactMap { link in
            try AO3AuthorIdentity(displayName: link.text(), href: link.attr("href"))
        }
        if authorLinks.isEmpty, try isAnonymousBlurb(el) {
            authorIdentities = [.nonNavigable("Anonymous", kind: .anonymous)]
        }
        let fandoms = try el.select("h5.fandoms a.tag").array().map { try $0.text() }

        let rating = try el.select("ul.required-tags .rating .text").first()?.text() ?? ""
        let warnings = try el.select("ul.required-tags .warnings .text").array().map { try $0.text() }
        let categories = try el.select("ul.required-tags .category .text").array().map { try $0.text() }
        let wipText = try el.select("ul.required-tags .iswip .text").first()?.text() ?? ""
        let isComplete: Bool? = wipText.isEmpty ? nil : wipText.lowercased().contains("complete")

        let date = try el.select("p.datetime").first()?.text() ?? ""
        // The blurb groups tags by class inside `ul.tags`. Pull out relationships and
        // characters; "Additional Tags" is the catch-all — every remaining tag in the
        // list (freeforms, plus anything that doesn't fit a category) so none drop out.
        let allTagTexts = try el.select("ul.tags li a.tag").array().map { try $0.text() }
        let relationships = try el.select("ul.tags li.relationships a.tag").array().map { try $0.text() }
        let characters = try el.select("ul.tags li.characters a.tag").array().map { try $0.text() }
        let warningTags = try el.select("ul.tags li.warnings a.tag").array().map { try $0.text() }
        let categorized = Set(relationships + characters + warningTags)
        let freeforms = allTagTexts.filter { !categorized.contains($0) }
        let summary = try el.select("blockquote.userstuff.summary").first()?.text() ?? ""

        func stat(_ cls: String) -> String {
            (try? el.select("dl.stats dd.\(cls)").first()?.text() ?? "") ?? ""
        }
        func statInt(_ cls: String) -> Int? {
            Self.statInt(cls, in: el)
        }

        // Series block: "Part <strong>N</strong> of <a href="/series/ID">Title</a>".
        let seriesLink = try el.select("ul.series li a").first()
        let seriesTitle = try seriesLink?.text()
        let seriesURL = try (seriesLink?.attr("href")).map { "https://archiveofourown.org\($0)" }
        let seriesPosition = Int((try? el.select("ul.series li strong").first()?.text() ?? "") ?? "")

        return AO3WorkSummary(
            id: id,
            title: title,
            authors: authors,
            authorIdentities: authorIdentities,
            fandoms: fandoms,
            rating: rating,
            warnings: warnings,
            categories: categories,
            relationships: relationships,
            characters: characters,
            isComplete: isComplete,
            dateUpdated: date,
            tags: freeforms,
            summary: summary,
            language: stat("language"),
            words: statInt("words"),
            chapters: stat("chapters"),
            comments: statInt("comments"),
            kudos: statInt("kudos"),
            hits: statInt("hits"),
            seriesTitle: seriesTitle?.isEmpty == false ? seriesTitle : nil,
            seriesURL: seriesURL,
            seriesPosition: seriesPosition
        )
    }

    /// AO3 marks a blurb as anonymous two ways depending on listing type: a class
    /// on the blurb `<li>` itself, or on its inner `div.header.module`. Shared by
    /// every blurb-shaped parser (works, series, bookmarks) so the detection can't
    /// drift between them.
    static func isAnonymousBlurb(_ element: Element) throws -> Bool {
        if element.hasClass("anonymous") { return true }
        return try element.select("div.header.module.anonymous").first() != nil
    }
}
