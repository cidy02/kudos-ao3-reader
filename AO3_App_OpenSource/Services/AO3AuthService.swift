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
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { return .expired }
            throw URLError(.badServerResponse)
        }

        let html = String(bytes: data, encoding: .utf8) ?? ""
        guard Self.isLoggedIn(html: html) else { return .expired }
        let username = Self.username(in: html) ?? storedSession.username
        let refreshed = Self.responseCookies(from: http, url: url)
        return .valid(Self.merging(refreshed, into: storedSession, username: username))
    }

    static func isLoggedIn(html: String) -> Bool {
        guard let document = try? SwiftSoup.parse(html) else { return false }
        if document.body()?.hasClass("logged-in") == true { return true }
        return (try? document.select("a[href='/users/logout']").first()) != nil
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

enum AO3RequestDefaults {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func isTrustedURL(_ url: URL?) -> Bool {
        guard url?.scheme?.lowercased() == "https",
              let host = url?.host()?.lowercased()
        else { return false }
        return host == "archiveofourown.org" || host.hasSuffix(".archiveofourown.org")
    }
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

    var isLoggedIn: Bool {
        if case .signedIn = status { true } else { false }
    }

    var username: String? {
        if case .signedIn(let username) = status { username } else { nil }
    }

    var isUsingFallback: Bool { status == .usingFallback }
    var loginWebView: WKWebView { loginPerformer.webView }

    private let vault: AO3SessionPersisting
    private let validator: AO3SessionValidating
    private let loginPerformer: AO3LoginPerforming
    private let cookieManager: AO3CookieManaging
    private let sessionHintStore: AO3SessionHintPersisting
    private var currentSession: AO3Session?
    private var didRestore = false

    init(
        vault: AO3SessionPersisting? = nil,
        validator: AO3SessionValidating? = nil,
        loginPerformer: AO3LoginPerforming? = nil,
        cookieManager: AO3CookieManaging? = nil,
        sessionHintStore: AO3SessionHintPersisting? = nil
    ) {
        self.vault = vault ?? KeychainAO3SessionVault()
        self.validator = validator ?? LiveAO3SessionValidator()
        self.loginPerformer = loginPerformer ?? AO3WebLoginCoordinator()
        self.cookieManager = cookieManager ?? LiveAO3CookieManager()
        self.sessionHintStore = sessionHintStore ?? UserDefaultsAO3SessionHintStore()
    }

    func restoreSession() async {
        guard !didRestore else { return }
        didRestore = true
        status = .restoring

        do {
            guard let saved = try vault.load(), saved.hasSessionCookie else {
                status = .signedOut
                return
            }
            await restore(saved, source: .keychain)
        } catch {
            if isMissingKeychainEntitlement(error) {
                Log.auth.notice("Keychain is unavailable; checking WebKit's persistent AO3 session")
                await restoreWebSession()
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

        errorMessage = nil
        noticeMessage = nil
        fallbackMessage = nil
        status = .signingIn
        // Avoid silently reusing a stale WebKit account when the user is trying
        // to authenticate with a different set of credentials.
        await cookieManager.clear()

        do {
            let session = try await loginPerformer.login(
                username: trimmedUsername,
                password: password
            )
            await accept(session)
        } catch AO3WebLoginError.invalidCredentials(let message) {
            status = .signedOut
            errorMessage = message
            Log.auth.notice("AO3 rejected the supplied login credentials")
        } catch AO3WebLoginError.fallbackRequired(let message) {
            beginFallback(expectedUsername: trimmedUsername, reason: message)
        } catch is CancellationError {
            status = .signedOut
        } catch {
            beginFallback(
                expectedUsername: trimmedUsername,
                reason: "The automatic AO3 login could not be completed."
            )
        }
    }

    func cancelLogin() {
        loginPerformer.cancel()
        fallbackMessage = nil
        errorMessage = nil
        if !isLoggedIn { status = .signedOut }
    }

    func logout() async {
        loginPerformer.cancel()
        currentSession = nil
        errorMessage = nil
        fallbackMessage = nil
        do {
            try vault.delete()
        } catch {
            Log.auth.error("Could not delete the saved AO3 session: \(error.localizedDescription, privacy: .public)")
        }
        sessionHintStore.deleteUsername()
        await cookieManager.clear()
        status = .signedOut
        noticeMessage = "Logged out of AO3."
        Log.auth.info("Cleared the local AO3 session")
    }

    /// Called by future authenticated feature clients when AO3 redirects to its
    /// login page or otherwise reports that the saved session is no longer valid.
    func sessionDidExpire() async {
        await clearStoredSession()
        noticeMessage = "Your AO3 session expired. Please log in again."
        Log.auth.notice("AO3 reported that the saved session expired")
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
        guard let currentSession,
              let cookieHeader = currentSession.cookieHeader(for: url)
        else {
            throw AO3AuthenticatedRequestError.notAuthenticated
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(AO3RequestDefaults.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    func applyFallbackTheme(_ theme: ReaderTheme) {
        loginPerformer.applyVisibleTheme(theme)
    }

    private func beginFallback(expectedUsername: String, reason: String) {
        status = .usingFallback
        fallbackMessage = reason
        errorMessage = nil
        loginPerformer.beginManualLogin(
            expectedUsername: expectedUsername,
            onAuthenticated: { [weak self] session in
                Task { @MainActor [weak self] in await self?.accept(session) }
            },
            onError: { [weak self] message in
                self?.errorMessage = message
            }
        )
        Log.auth.notice("Falling back to the visible AO3 login page")
    }

    private func accept(_ session: AO3Session) async {
        do {
            try vault.save(session)
        } catch {
            if isMissingKeychainEntitlement(error) {
                await finishAccepting(session)
                Log.auth.notice(
                    "Keychain is unavailable; retained the AO3 session in WebKit's persistent store"
                )
                return
            }
            currentSession = nil
            sessionHintStore.deleteUsername()
            await cookieManager.clear()
            status = .signedOut
            errorMessage = "AO3 logged in, but the session could not be saved securely."
            Log.auth.error("Could not save the AO3 session: \(error.localizedDescription, privacy: .public)")
            return
        }

        await finishAccepting(session)
        Log.auth.info("Captured and saved an AO3 session")
    }

    private func finishAccepting(_ session: AO3Session) async {
        currentSession = session
        sessionHintStore.saveUsername(session.username)
        await cookieManager.install(session)
        status = .signedIn(username: session.username)
        errorMessage = nil
        noticeMessage = nil
        fallbackMessage = nil
    }

    private enum RestoreSource {
        case keychain
        case webKit
    }

    private func restoreWebSession() async {
        let cookies = await cookieManager.capture()
        guard cookies.contains(where: { $0.name == "_otwarchive_session" && !$0.isExpired }) else {
            status = .signedOut
            return
        }

        let usernameHint = sessionHintStore.loadUsername() ?? ""
        let session = AO3Session(username: usernameHint, cookies: cookies)
        await restore(session, source: .webKit)
    }

    private func restore(_ saved: AO3Session, source: RestoreSource) async {
        currentSession = saved
        await cookieManager.install(saved)

        do {
            switch try await validator.validate(saved) {
            case .valid(let refreshed):
                do {
                    try vault.save(refreshed)
                } catch {
                    if !isMissingKeychainEntitlement(error) {
                        Log.auth.error(
                            "Could not refresh the saved AO3 session: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
                await finishAccepting(refreshed)
                Log.auth.info("Restored and validated an AO3 session")
            case .expired:
                await clearStoredSession()
                if source == .keychain || !saved.username.isEmpty {
                    noticeMessage = "Your AO3 session expired. Please log in again."
                }
            }
        } catch {
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

    private func clearStoredSession() async {
        currentSession = nil
        try? vault.delete()
        sessionHintStore.deleteUsername()
        await cookieManager.clear()
        status = .signedOut
    }
}
