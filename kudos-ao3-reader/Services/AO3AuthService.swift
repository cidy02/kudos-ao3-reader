import Foundation
import OSLog
import SwiftSoup
import WebKit

enum AO3AuthStatus: Equatable {
    case restoring
    case signedOut
    case signingIn
    case usingFallback
    case signedIn(username: String)
}

/// The result of the most recent on-demand session check, for the account UI's
/// health indicator. Orthogonal to `AO3AuthStatus` (which says whether we hold a
/// session at all); this says how confident we are that the held session is live.
enum AO3SessionHealth: Equatable {
    /// Signed out, or signed in but never re-checked this session.
    case unknown
    /// A check is in flight.
    case verifying
    /// Confirmed valid against AO3 at the given time.
    case healthy(Date)
    /// AO3 reported the session is no longer valid (the user was signed out).
    case expired
    /// Couldn't reach AO3 to check (offline / transient). The session is kept.
    case unreachable

    var isChecking: Bool { self == .verifying }
}

enum AO3AuthenticatedRequestError: LocalizedError {
    case notAuthenticated
    case nonAO3URL

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Log in to AO3 before using this feature."
        case .nonAO3URL:
            "Authenticated AO3 cookies cannot be attached to another website."
        }
    }
}

enum AO3SessionValidation: Equatable {
    case valid(AO3Session)
    case expired
}

protocol AO3SessionValidating {
    func validate(_ session: AO3Session) async throws -> AO3SessionValidation
}

@MainActor
protocol AO3CookieManaging {
    func install(_ session: AO3Session) async
    func clear() async
    func capture() async -> [AO3StoredCookie]
}

struct LiveAO3CookieManager: AO3CookieManaging {
    func install(_ session: AO3Session) async {
        await AO3CookieBridge.install(session)
    }

    func clear() async {
        await AO3CookieBridge.clearAO3Cookies()
    }

    func capture() async -> [AO3StoredCookie] {
        await AO3CookieBridge.captureAO3Cookies()
    }
}

/// Validates a restored cookie without involving the visible UI. A connectivity
/// failure is intentionally thrown rather than treated as expiration; being
/// offline must not log the user out.
struct LiveAO3SessionValidator: AO3SessionValidating {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpAdditionalHeaders = ["User-Agent": AO3RequestDefaults.userAgent]
        session = URLSession(configuration: configuration)
    }

    func validate(_ storedSession: AO3Session) async throws -> AO3SessionValidation {
        let url = URL(string: "https://archiveofourown.org")!
        guard let cookieHeader = storedSession.cookieHeader(for: url) else {
            return .expired
        }
        var request = URLRequest(url: url)
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            // Only an explicit 401 is treated as expiry. Every other non-2xx is
            // thrown, which the caller treats as "couldn't verify" and keeps the
            // session — deliberately erring toward not logging the user out on a
            // transient server hiccup. (Trade-off: a persistent hard 403/5xx also
            // keeps a stale session until a clean logged-out 200 or a 401 arrives.)
            if http.statusCode == 401 { return .expired }
            throw URLError(.badServerResponse)
        }

        let html = String(bytes: data, encoding: .utf8) ?? ""
        // Cloudflare / empty / non-AO3 responses must not be treated as "session
        // expired" — that path wipes the stored cookies and forces a re-login.
        // Only `body.logged-in` / `body.logged-out` count as a real AO3 page;
        // generic `#main` shells are too common on interstitials.
        guard Self.looksLikeAO3Page(html: html) else {
            throw URLError(.cannotParseResponse)
        }
        // Logged-out AO3 markup is the only definitive expiry signal here.
        guard Self.isLoggedIn(html: html) else { return .expired }
        let username = Self.username(in: html) ?? storedSession.username
        let refreshed = Self.responseCookies(from: http, url: url)
        return .valid(Self.merging(refreshed, into: storedSession, username: username))
    }

    /// True when the HTML is a real AO3 document (logged-in or logged-out body).
    /// Challenge walls, empty error pages, and pages that merely share `#main`
    /// return false so callers keep the session instead of wiping it.
    static func looksLikeAO3Page(html: String) -> Bool {
        guard let document = try? SwiftSoup.parse(html),
              let body = document.body()
        else { return false }
        return body.hasClass("logged-in") || body.hasClass("logged-out")
    }

    /// NOTE: This logged-in / username detection mirrors the JavaScript in
    /// `AO3WebLoginCoordinator.inspectPage()`. One runs here over URLSession-fetched
    /// HTML (SwiftSoup); the other runs inside the live WKWebView page. Keep the
    /// selectors in sync when AO3's markup changes.
    static func isLoggedIn(html: String) -> Bool {
        guard let document = try? SwiftSoup.parse(html) else { return false }
        if document.body()?.hasClass("logged-in") == true { return true }
        return (try? document.select("a[href='/users/logout'], form[action='/users/logout']").first()) != nil
    }

    static func username(in html: String) -> String? {
        guard let document = try? SwiftSoup.parse(html),
              let links = try? document.select("#greeting a[href^='/users/']").array()
        else { return nil }
        for link in links {
            guard let href = try? link.attr("href"),
                  href.hasPrefix("/users/"),
                  !href.hasSuffix("/login"),
                  !href.hasSuffix("/logout")
            else { continue }
            let username = String(href.dropFirst("/users/".count))
                .removingPercentEncoding?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let username, !username.isEmpty { return username }
        }
        return nil
    }

    private static func responseCookies(from response: HTTPURLResponse, url: URL) -> [HTTPCookie] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        return HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            .filter { AO3StoredCookie.isAO3Domain($0.domain) }
    }

    private static func merging(
        _ refreshed: [HTTPCookie],
        into session: AO3Session,
        username: String
    ) -> AO3Session {
        var cookies: [String: AO3StoredCookie] = [:]
        for cookie in session.validCookies {
            cookies[cookieKey(cookie)] = cookie
        }
        for cookie in refreshed {
            let stored = AO3StoredCookie(cookie)
            cookies[cookieKey(stored)] = stored
        }
        return AO3Session(username: username, cookies: Array(cookies.values))
    }

    private static func cookieKey(_ cookie: AO3StoredCookie) -> String {
        "\(cookie.domain.lowercased())|\(cookie.path)|\(cookie.name)"
    }
}

nonisolated enum AO3RequestDefaults {
    /// The one User-Agent every AO3-facing request sends (AO3Client's session default,
    /// authenticated per-request headers, and the session validator all use this):
    /// browser-like base + an honest product token with a contact URL, so AO3 admins
    /// can identify the app and reach its repository. Keep single-sourced — a
    /// per-request header silently overrides any session-level default, so a second
    /// definition would fork the app's identity.
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 "
            + "KudosReader/\(version) (+https://github.com/cidy02/kudos-ao3-reader)"
    }()

    static func isTrustedURL(_ url: URL?) -> Bool {
        guard url?.scheme?.lowercased() == "https",
              let host = url?.host()?.lowercased()
        else { return false }
        return host == "archiveofourown.org" || host.hasSuffix(".archiveofourown.org")
    }

    /// otwarchive's Rails session cookie name (`config/initializers/session_store.rb`
    /// — `session_store :force_signed_cookie_store, key: '_otwarchive_session'`), the
    /// one cookie that ever carries account identity. Single-sourced so every place
    /// that must recognize or, just as importantly, deliberately exclude it (T-100's
    /// Cloudflare-cookie jar) references the same literal.
    static let sessionCookieName = "_otwarchive_session"
}

/// The sole authentication API exposed to the rest of the app. UI and future AO3
/// feature clients interact with this service; only the service knows that login
/// is implemented through WebKit.
@MainActor
@Observable
final class AO3AuthService {
    private(set) var status: AO3AuthStatus = .restoring
    private(set) var errorMessage: String?
    private(set) var noticeMessage: String?
    private(set) var fallbackMessage: String?
    /// Confidence in the currently-held session, driven by `verifySession()` and by
    /// the launch restore/login/expiry paths. Purely informational for the account UI.
    private(set) var sessionHealth: AO3SessionHealth = .unknown

    /// Bumped when a login/restore/logout/expiry transition begins and when
    /// verification accepts refreshed cookies (T91-RF3). Lets a long-lived
    /// feature model (e.g. the Inbox) tell apart two sessions that share the
    /// same `authenticationScope` string — same username, logged out and back
    /// in, or a same-user cookie rotation — so it never reuses private cache or
    /// async results from an earlier credential set.
    private(set) var sessionGeneration = 0

    var isLoggedIn: Bool {
        if case .signedIn = status { true } else { false }
    }

    var username: String? {
        if case let .signedIn(username) = status { username } else { nil }
    }

    var isUsingFallback: Bool {
        status == .usingFallback
    }

    var loginWebView: WKWebView {
        loginPerformer.webView
    }

    private let vault: AO3SessionPersisting
    private let validator: AO3SessionValidating
    private let loginPerformer: AO3LoginPerforming
    private let cookieManager: AO3CookieManaging
    private let sessionHintStore: AO3SessionHintPersisting
    private let postingPseudStore: AO3PostingPseudPersisting
    private let removalTracker: AO3SessionRemovalTracking
    private var currentSession: AO3Session?
    private var didRestore = false
    /// WebKit's cookie store is global and its set/delete callbacks suspend. All
    /// service instances therefore share one FIFO so an older clear/install cannot
    /// finish after a newer account has reconciled its cookies.
    private static var cookieMutationTail: Task<Void, Never>?

    init(
        vault: AO3SessionPersisting? = nil,
        validator: AO3SessionValidating? = nil,
        loginPerformer: AO3LoginPerforming? = nil,
        cookieManager: AO3CookieManaging? = nil,
        sessionHintStore: AO3SessionHintPersisting? = nil,
        postingPseudStore: AO3PostingPseudPersisting? = nil,
        removalTracker: AO3SessionRemovalTracking? = nil
    ) {
        // Cascading vault: Keychain when available, plus an app-container file so
        // Simulator / unsigned builds still restore after relaunch (WebKit cookie
        // capture alone is not reliable enough across process death).
        self.vault = vault ?? CascadingAO3SessionVault()
        self.validator = validator ?? LiveAO3SessionValidator()
        self.loginPerformer = loginPerformer ?? AO3WebLoginCoordinator()
        self.cookieManager = cookieManager ?? LiveAO3CookieManager()
        self.sessionHintStore = sessionHintStore ?? UserDefaultsAO3SessionHintStore()
        self.postingPseudStore = postingPseudStore ?? UserDefaultsAO3PostingPseudStore()
        self.removalTracker = removalTracker ?? UserDefaultsAO3SessionRemovalTracker()

        // Legacy-jar cleanup (A5-F1 upgrade gap), deliberately here and not in
        // `restoreSession()`: that method only runs from the root view's `.task`,
        // and SwiftUI gives no ordering guarantee between sibling `.task`s — an
        // avatar view's own `AsyncImage` fetch (same default `URLSession.shared`
        // cookie jar) could otherwise win the race and carry a pre-fix build's
        // leftover AO3 cookie once, on the very first launch after upgrading. This
        // service is constructed as the owning view's `@State` initializer, which
        // SwiftUI always evaluates before that view's `body` — and therefore before
        // any `.task` anywhere in the tree — can run, so purging here is strictly
        // earlier than any request that could use the leak.
        AO3CookieBridge.purgeLegacySharedCookieJar()
    }

    // MARK: Posting pseud ("Posting As")

    /// The pseud name the signed-in user chose to post comments as, persisted
    /// per-account (non-secret). nil means AO3's own default pseud.
    var preferredPostingPseudName: String? {
        username.flatMap { postingPseudStore.pseudName(for: $0) }
    }

    /// Sets (or, with nil, clears back to AO3's default) the posting pseud for
    /// the signed-in account. No-op when signed out.
    func setPreferredPostingPseudName(_ name: String?) {
        guard let username else { return }
        postingPseudStore.setPseudName(name, for: username)
    }

    /// The pseud id a comment form should submit, resolved from that exact form's
    /// pseud `<select>`: the stored preference when one of the form's own options
    /// matches it by name, else the form's pre-selected default. The id is always
    /// scraped from the fetched form, never synthesized, so AO3 authorizes it.
    func resolvedPostingPseudID(
        from html: String,
        field: String = "comment[pseud_id]"
    ) -> String? {
        Self.resolvePostingPseudID(
            in: html,
            preferredName: preferredPostingPseudName,
            field: field
        )
    }

    /// Pure resolution (unit-tested): preferred-name match wins, else the form's
    /// own pre-selected/first default.
    static func resolvePostingPseudID(
        in html: String,
        preferredName: String?,
        field: String = "comment[pseud_id]"
    ) -> String? {
        if let preferredName {
            let options = AO3Client.parsePostingPseudOptions(from: html, field: field)
            if let match = options.first(where: {
                $0.name.localizedCaseInsensitiveCompare(preferredName) == .orderedSame
            }) {
                return match.id
            }
        }
        return AO3Client.parseDefaultPseudID(from: html, field: field)
    }

    func restoreSession() async {
        // Single-shot by design: this runs once from the root view's `.task` at
        // launch. Later sign-in/out flows drive `status` directly, so restore is
        // never meant to run again in a session.
        guard !didRestore, status == .restoring else { return }
        didRestore = true
        let restorationGeneration = advanceSessionGeneration()
        currentSession = nil
        status = .restoring

        if removalTracker.isRemovalPending {
            // A previous logout/expiry couldn't fully clear the durable store (A5-F4).
            // Retry it now, but refuse to restore anything this launch either way —
            // the saved session must never come back from the dead just because it's
            // still readable. Cookies/hint were already cleared when this was marked.
            await retryPendingRemoval(expectedGeneration: restorationGeneration)
            guard sessionGeneration == restorationGeneration else { return }
            status = .signedOut
            return
        }

        do {
            if let saved = try vault.load(), saved.hasSessionCookie {
                await restore(
                    saved,
                    source: .keychain,
                    expectedGeneration: restorationGeneration
                )
                return
            }
            // Unsigned/simulator builds often can't *write* Keychain
            // (`errSecMissingEntitlement` on save) while `load` still returns nil
            // cleanly. Login then lives only in WebKit + the username hint — so
            // an empty Keychain must fall through to that store, not force
            // signed-out. Same path when Keychain is missing the entitlement on
            // load (handled in `catch` below).
            Log.auth.notice("No Keychain AO3 session; checking WebKit's persistent store")
            await restoreWebSession(expectedGeneration: restorationGeneration)
        } catch {
            guard sessionGeneration == restorationGeneration else { return }
            if isMissingKeychainEntitlement(error) {
                Log.auth.notice("Keychain is unavailable; checking WebKit's persistent AO3 session")
                await restoreWebSession(expectedGeneration: restorationGeneration)
                return
            }
            status = .signedOut
            errorMessage = "The saved AO3 session could not be restored."
            Log.auth.error("Could not restore the AO3 session: \(error.localizedDescription, privacy: .public)")
        }
    }

    func login(username: String, password: String) async {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your AO3 username or email and password."
            return
        }

        let loginGeneration = advanceSessionGeneration()
        // Stop an old hidden/manual WebKit flow before its response can set
        // cookies after this replacement login's queued clear.
        loginPerformer.cancel()
        currentSession = nil
        errorMessage = nil
        noticeMessage = nil
        fallbackMessage = nil
        status = .signingIn
        // Avoid silently reusing a stale WebKit account when the user is trying
        // to authenticate with a different set of credentials.
        let cookieClear = enqueueCookieClear(expectedGeneration: loginGeneration)
        await cookieClear.value
        guard sessionGeneration == loginGeneration else { return }

        do {
            let session = try await loginPerformer.login(
                username: trimmedUsername,
                password: password
            )
            guard sessionGeneration == loginGeneration else { return }
            await accept(session, expectedGeneration: loginGeneration)
        } catch let AO3WebLoginError.invalidCredentials(message) {
            guard sessionGeneration == loginGeneration else { return }
            status = .signedOut
            errorMessage = message
            Log.auth.notice("AO3 rejected the supplied login credentials")
        } catch let AO3WebLoginError.fallbackRequired(message) {
            beginFallback(
                expectedUsername: trimmedUsername,
                reason: message,
                expectedGeneration: loginGeneration
            )
        } catch is CancellationError {
            guard sessionGeneration == loginGeneration else { return }
            status = .signedOut
        } catch {
            guard sessionGeneration == loginGeneration else { return }
            beginFallback(
                expectedUsername: trimmedUsername,
                reason: "Let's finish logging in on AO3's page below.",
                expectedGeneration: loginGeneration
            )
        }
    }

    func cancelLogin() {
        guard status == .signingIn || status == .usingFallback else {
            // Nothing in flight to cancel (e.g. a native attempt already
            // failed back to `.signedOut` and left `errorMessage` set) — the
            // login sheet's Cancel button still calls this unconditionally,
            // so the stale failure text must not resurface the next time the
            // sheet opens, before any new attempt.
            errorMessage = nil
            return
        }
        let cancellationGeneration = advanceSessionGeneration()
        currentSession = nil
        loginPerformer.cancel()
        fallbackMessage = nil
        errorMessage = nil
        status = .signedOut
        sessionHealth = .unknown
        _ = enqueueCookieClear(expectedGeneration: cancellationGeneration)
    }

    func logout() async {
        let logoutGeneration = advanceSessionGeneration()
        loginPerformer.cancel()
        let loggedOutUsername = currentSession?.username
        currentSession = nil
        errorMessage = nil
        fallbackMessage = nil
        // Soft/live state is always cleared, regardless of whether the durable delete
        // below succeeds: no in-memory session, no WebKit cookie, no username hint
        // survives a logout tap, so nothing in this running instance can act
        // authenticated even if the Keychain/file blob itself proves undeletable.
        sessionHintStore.deleteUsername()
        status = .signedOut
        sessionHealth = .unknown
        // This account's unresolved comment-submission guards must not survive
        // the account they were made under (T91-RF2): they'd otherwise either
        // leak into whoever logs in next or resurface confusingly if the same
        // user logs back in.
        if let loggedOutUsername {
            UnresolvedCommentSubmissionStore.shared.clear(identity: loggedOutUsername)
        }

        do {
            try vault.delete()
            removalTracker.clearRemovalPending()
            noticeMessage = "Logged out of AO3."
            Log.auth.info("Cleared the local AO3 session")
        } catch {
            // A5-F4: never report success while a durable store might still hold a
            // reusable session. Mark it pending so a relaunch refuses to restore it
            // instead of silently signing the user back in.
            removalTracker.markRemovalPending()
            noticeMessage = "Signed out here, but this device couldn't fully remove the saved AO3 " +
                "session. It won't be restored automatically — we'll keep retrying."
            Log.auth.error("Could not delete the saved AO3 session: \(error.localizedDescription, privacy: .public)")
        }
        let cookieClear = enqueueCookieClear(expectedGeneration: logoutGeneration)
        await cookieClear.value
        // A new login can begin while WebKit finishes clearing the old account's
        // cookies. The durable state above is already terminal for the outgoing
        // account; this late continuation must not mutate the incoming session.
        guard sessionGeneration == logoutGeneration else { return }
    }

    /// Called by authenticated feature clients when AO3 redirects to its login
    /// page or otherwise reports that *their captured* session is no longer
    /// valid. A later login must never be cleared by an old response.
    @discardableResult
    func sessionDidExpire(expectedGeneration: Int) async -> Bool {
        guard sessionGeneration == expectedGeneration,
              await clearStoredSession(expectedGeneration: expectedGeneration)
        else { return false }
        sessionHealth = .expired
        noticeMessage = "Your AO3 session expired. Please log in again."
        Log.auth.notice("AO3 reported that the saved session expired")
        return true
    }

    /// On-demand re-validation of the stored session, driven by the account UI's
    /// "Verify Session" control. Unlike `restoreSession()` (single-shot at launch),
    /// this can run whenever the user asks. Mirrors `restore()`'s valid/expired/
    /// transient handling: a transient failure (offline / server hiccup) keeps the
    /// session and reports `.unreachable` rather than logging the user out.
    func verifySession() async {
        guard isLoggedIn, let session = currentSession else {
            sessionHealth = .unknown
            return
        }
        let expectedGeneration = sessionGeneration
        sessionHealth = .verifying
        do {
            switch try await validator.validate(session) {
            case let .valid(refreshed):
                // Validation may merge Set-Cookie values into `refreshed`. Even
                // for the same username, parsed Inbox forms are private to those
                // credentials, so revoke old private continuations/cache first.
                guard sessionGeneration == expectedGeneration,
                      currentSession == session
                else { return }
                sessionGeneration += 1
                let refreshedGeneration = sessionGeneration
                do {
                    try vault.save(refreshed)
                } catch {
                    if !isMissingKeychainEntitlement(error) {
                        Log.auth.error(
                            "Could not refresh the saved AO3 session: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
                guard await finishAccepting(
                    refreshed, expectedGeneration: refreshedGeneration
                ) else { return }
                Log.auth.info("AO3 session re-verified on request")
            case .expired:
                guard await sessionDidExpire(expectedGeneration: expectedGeneration) else { return }
                Log.auth.notice("On-demand check found the AO3 session expired")
            }
        } catch {
            // Transient (offline / server hiccup): keep the session, flag unverified.
            guard sessionGeneration == expectedGeneration,
                  currentSession == session
            else { return }
            sessionHealth = .unreachable
            Log.auth.notice("Could not reach AO3 to verify the session; keeping it")
        }
    }

    /// Creates a request carrying the current AO3 cookies. Future feature clients
    /// can use this for authenticated reads and for fetching CSRF tokens before
    /// mutating actions such as kudos, comments, bookmarks, and subscriptions.
    func authenticatedRequest(
        for url: URL,
        method: String = "GET"
    ) throws -> URLRequest {
        guard AO3RequestDefaults.isTrustedURL(url) else {
            throw AO3AuthenticatedRequestError.nonAO3URL
        }
        guard isLoggedIn,
              let currentSession,
              let cookieHeader = currentSession.cookieHeader(for: url)
        else {
            throw AO3AuthenticatedRequestError.notAuthenticated
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(
            Self.mergedCookieHeader(auth: cookieHeader, for: url),
            forHTTPHeaderField: "Cookie"
        )
        request.setValue(AO3RequestDefaults.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Appends `AO3Client`'s currently-held Cloudflare cookies (T-100) after the
    /// account's own explicit cookie pairs, so an authenticated/write request
    /// presents a warm `cf_clearance`/`__cf_bm` too — not just anonymous reads.
    /// Pure string concatenation (unit-tested); the read of `AO3Client`'s jar is
    /// the only impure step, isolated to the one call site below.
    static func mergedCookieHeader(auth: String, challenge: String?) -> String {
        guard let challenge, !challenge.isEmpty else { return auth }
        return "\(auth); \(challenge)"
    }

    private static func mergedCookieHeader(auth: String, for url: URL) -> String {
        mergedCookieHeader(auth: auth, challenge: AO3Client.shared.challengeCookieHeader(for: url))
    }

    /// Fetches one page of the signed-in user's works from an account-list URL built
    /// from their username (e.g. Subscriptions, Marked for Later). Returns `[]` only
    /// when signed out (not an error — the caller's empty state should show
    /// immediately); throws on any fetch/parse failure so a caller refreshing a list
    /// that already has content can keep it instead of wiping it with an empty
    /// result. `makeURL` is a `AO3Client` URL builder such as `AO3Client.subscriptionsURL`.
    func accountWorks(
        from makeURL: (_ username: String, _ page: Int) -> URL?,
        page: Int = 1,
        recordAs countsKind: AO3AccountListKind? = nil
    ) async throws -> [AO3WorkSummary] {
        guard isLoggedIn, let username, let url = makeURL(username, page) else { return [] }
        let request = try authenticatedRequest(for: url)
        let result = try await AO3Client.shared.worksPage(for: request, page: page)
        if let countsKind {
            AO3AccountListCountsCache.shared.record(
                page: result,
                kind: countsKind,
                authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: self)
            )
        }
        return result.works
    }

    /// One page of the signed-in user's *work* subscriptions. Separate from
    /// `accountWorks` because the subscriptions page isn't work-blurb markup and needs
    /// `subscriptionsPage`. Returns `[]` only when signed out; throws on any
    /// fetch/parse failure (see `accountWorks`).
    func accountSubscriptions(page: Int = 1) async throws -> [AO3WorkSummary] {
        guard isLoggedIn, let username,
              let url = AO3Client.subscriptionsURL(username: username, page: page) else { return [] }
        let request = try authenticatedRequest(for: url)
        let result = try await AO3Client.shared.subscriptionsPage(for: request, page: page)
        AO3AccountListCountsCache.shared.record(
            page: result,
            kind: .subscriptions,
            authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: self)
        )
        return result.works
    }

    func applyFallbackTheme(_ theme: ReaderTheme) {
        loginPerformer.applyVisibleTheme(theme)
    }

    private func beginFallback(
        expectedUsername: String,
        reason: String,
        expectedGeneration: Int
    ) {
        guard sessionGeneration == expectedGeneration else { return }
        status = .usingFallback
        fallbackMessage = reason
        errorMessage = nil
        loginPerformer.beginManualLogin(
            expectedUsername: expectedUsername,
            onAuthenticated: { [weak self] session in
                self?.acceptManualLogin(session, expectedGeneration: expectedGeneration)
            },
            onError: { [weak self] message in
                guard self?.sessionGeneration == expectedGeneration else { return }
                self?.errorMessage = message
            }
        )
        Log.auth.notice("Falling back to the visible AO3 login page")
    }

    private func acceptManualLogin(_ session: AO3Session, expectedGeneration: Int) {
        guard sessionGeneration == expectedGeneration else { return }
        Task { @MainActor [weak self] in
            guard let self, self.sessionGeneration == expectedGeneration else { return }
            await self.accept(session, expectedGeneration: expectedGeneration)
        }
    }

    private func accept(_ session: AO3Session, expectedGeneration: Int) async {
        guard sessionGeneration == expectedGeneration else { return }
        // A new generation regardless of outcome below: this is always an
        // attempt to establish a (possibly different) identity, so any pending
        // continuation captured under the previous one must stop trusting it.
        let acceptingGeneration = advanceSessionGeneration()
        do {
            try vault.save(session)
            // A fresh, successful save is the durable store's new source of truth —
            // any removal that had been left pending from an earlier failed
            // logout/expiry no longer describes what's on disk.
            removalTracker.clearRemovalPending()
        } catch {
            if isMissingKeychainEntitlement(error) {
                // Production uses CascadingAO3SessionVault (file fallback), so
                // this path is mainly for tests that inject a Keychain-only vault.
                removalTracker.clearRemovalPending()
                guard await finishAccepting(
                    session, expectedGeneration: acceptingGeneration
                ) else { return }
                Log.auth.notice(
                    "Keychain is unavailable; retained the AO3 session without Keychain"
                )
                return
            }
            guard sessionGeneration == acceptingGeneration else { return }
            currentSession = nil
            sessionHintStore.deleteUsername()
            let cookieClear = enqueueCookieClear(expectedGeneration: acceptingGeneration)
            await cookieClear.value
            guard sessionGeneration == acceptingGeneration else { return }
            status = .signedOut
            errorMessage = "AO3 logged in, but the session could not be saved securely."
            Log.auth.error("Could not save the AO3 session: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard await finishAccepting(session, expectedGeneration: acceptingGeneration) else { return }
        Log.auth.info("Captured and saved an AO3 session")
    }

    @discardableResult
    private func finishAccepting(
        _ session: AO3Session,
        expectedGeneration: Int
    ) async -> Bool {
        guard sessionGeneration == expectedGeneration else { return false }
        // Updating the in-memory request gate before awaiting WebKit means a
        // generation-observing feature cannot start another request using a
        // session AO3 has already rejected.
        currentSession = session
        sessionHintStore.saveUsername(session.username)
        let cookieInstall = enqueueCookieInstall(
            session,
            expectedGeneration: expectedGeneration
        )
        await cookieInstall.value
        guard sessionGeneration == expectedGeneration else { return false }
        status = .signedIn(username: session.username)
        errorMessage = nil
        noticeMessage = nil
        fallbackMessage = nil
        // Reached only after a successful validate() (launch restore, login, or an
        // on-demand verify), so the session is confirmed live as of now.
        sessionHealth = .healthy(Date())
        return true
    }

    private enum RestoreSource {
        case keychain
        case webKit
    }

    private func restoreWebSession(expectedGeneration: Int) async {
        guard sessionGeneration == expectedGeneration else { return }
        let cookies = await cookieManager.capture()
        guard sessionGeneration == expectedGeneration else { return }
        guard cookies.contains(where: { $0.name == AO3RequestDefaults.sessionCookieName && !$0.isExpired }) else {
            status = .signedOut
            return
        }

        let usernameHint = sessionHintStore.loadUsername() ?? ""
        let session = AO3Session(username: usernameHint, cookies: cookies)
        await restore(session, source: .webKit, expectedGeneration: expectedGeneration)
    }

    private func restore(
        _ saved: AO3Session,
        source: RestoreSource,
        expectedGeneration: Int
    ) async {
        guard sessionGeneration == expectedGeneration else { return }
        let restoringGeneration = expectedGeneration
        currentSession = saved
        let cookieInstall = enqueueCookieInstall(
            saved,
            expectedGeneration: restoringGeneration
        )
        await cookieInstall.value
        guard sessionGeneration == restoringGeneration else { return }

        do {
            switch try await validator.validate(saved) {
            case let .valid(refreshed):
                guard sessionGeneration == restoringGeneration,
                      currentSession == saved
                else { return }
                do {
                    try vault.save(refreshed)
                } catch {
                    if !isMissingKeychainEntitlement(error) {
                        Log.auth.error(
                            "Could not refresh the saved AO3 session: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
                guard await finishAccepting(
                    refreshed, expectedGeneration: restoringGeneration
                ) else { return }
                Log.auth.info("Restored and validated an AO3 session")
            case .expired:
                guard await clearStoredSession(expectedGeneration: restoringGeneration) else { return }
                if source == .keychain || !saved.username.isEmpty {
                    noticeMessage = "Your AO3 session expired. Please log in again."
                }
            }
        } catch {
            guard sessionGeneration == restoringGeneration,
                  currentSession == saved
            else { return }
            // A Keychain session is already known to be authenticated. A WebKit
            // session is preserved offline only when a prior successful login
            // left the non-secret username hint.
            if source == .keychain || !saved.username.isEmpty {
                let username = saved.username.isEmpty ? "AO3 Account" : saved.username
                status = .signedIn(username: username)
                Log.auth.notice(
                    "AO3 session validation was unavailable; keeping the saved session"
                )
            } else {
                currentSession = nil
                status = .signedOut
                Log.auth.notice(
                    "Could not validate WebKit's AO3 cookies without a saved login hint"
                )
            }
        }
    }

    private func isMissingKeychainEntitlement(_ error: Error) -> Bool {
        (error as? AO3SessionVaultError)?.isMissingEntitlement == true
    }

    @discardableResult
    private func clearStoredSession(expectedGeneration: Int? = nil) async -> Bool {
        if let expectedGeneration, sessionGeneration != expectedGeneration { return false }
        let clearingGeneration = advanceSessionGeneration()
        let clearedUsername = currentSession?.username
        currentSession = nil
        do {
            try vault.delete()
            removalTracker.clearRemovalPending()
        } catch {
            // Same truthful-removal semantics as logout() (A5-F4): a failed delete
            // here must not be silently swallowed either, or the expired session's
            // durable copy could restore itself on the next launch.
            removalTracker.markRemovalPending()
            Log.auth.error(
                "Could not delete the expired AO3 session: \(error.localizedDescription, privacy: .public)"
            )
        }
        sessionHintStore.deleteUsername()
        status = .signedOut
        // Bare cleared state is "signed out / unknown"; callers meaning
        // "expired" set that explicitly after this returns.
        sessionHealth = .unknown
        let cookieClear = enqueueCookieClear(expectedGeneration: clearingGeneration)
        await cookieClear.value
        guard sessionGeneration == clearingGeneration else { return false }
        // Same isolation reasoning as logout() (T91-RF2): a lost/expired
        // session ends that identity's unresolved comment-submission guards too.
        if let clearedUsername, !clearedUsername.isEmpty {
            UnresolvedCommentSubmissionStore.shared.clear(identity: clearedUsername)
        }
        return true
    }

    /// Retries a durable-store deletion that a previous logout/expiry couldn't
    /// complete. Called once at the top of `restoreSession()` (A5-F4): while pending,
    /// the saved session must never be loaded, no matter what it contains — even if
    /// this retry fails again, the vault is left untouched for the rest of this
    /// launch and normal restore is skipped rather than risking a stale sign-in.
    @discardableResult
    private func retryPendingRemoval(expectedGeneration: Int) async -> Bool {
        guard sessionGeneration == expectedGeneration else { return false }
        do {
            try vault.delete()
            guard sessionGeneration == expectedGeneration else { return false }
            removalTracker.clearRemovalPending()
            Log.auth.info("Retried and cleared a pending AO3 session removal")
            return true
        } catch {
            guard sessionGeneration == expectedGeneration else { return false }
            Log.auth.error(
                "AO3 session removal is still pending: \(error.localizedDescription, privacy: .public)"
            )
            noticeMessage = "Couldn't finish removing a previous AO3 session from this device. " +
                "We'll keep retrying; you are not signed in."
            return false
        }
    }

    @discardableResult
    private func advanceSessionGeneration() -> Int {
        sessionGeneration += 1
        return sessionGeneration
    }

    /// Serializes all mutations of WebKit's process-wide AO3 cookie store. The
    /// generation check runs only after prior mutations have settled, immediately
    /// before the next mutation begins, so a stale continuation cannot enqueue a
    /// delete or install that lands after a newer account's cookies.
    private func enqueueCookieMutation(
        expectedGeneration: Int,
        _ mutation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let previous = Self.cookieMutationTail
        let task = Task { @MainActor [weak self] in
            if let previous { await previous.value }
            guard let self, self.sessionGeneration == expectedGeneration else { return }
            await mutation()
        }
        Self.cookieMutationTail = task
        return task
    }

    private func enqueueCookieClear(expectedGeneration: Int) -> Task<Void, Never> {
        enqueueCookieMutation(expectedGeneration: expectedGeneration) { [weak self] in
            await self?.cookieManager.clear()
        }
    }

    private func enqueueCookieInstall(
        _ session: AO3Session,
        expectedGeneration: Int
    ) -> Task<Void, Never> {
        enqueueCookieMutation(expectedGeneration: expectedGeneration) { [weak self] in
            await self?.cookieManager.install(session)
        }
    }
}
