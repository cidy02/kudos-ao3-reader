import Foundation
import Testing
import WebKit
@testable import Kudos

struct AO3SessionTests {
    @Test func cookieHeadersAreScopedAndExpiredCookiesAreDropped() throws {
        let active = AO3StoredCookie(name: "_otwarchive_session", value: "session")
        let pathCookie = AO3StoredCookie(
            name: "work",
            value: "allowed",
            path: "/works"
        )
        let expired = AO3StoredCookie(
            name: "old",
            value: "expired",
            expiresDate: Date(timeIntervalSinceNow: -60)
        )
        let session = AO3Session(
            username: "reader",
            cookies: [active, pathCookie, expired]
        )

        let workURL = try #require(URL(string: "https://archiveofourown.org/works/123"))
        let homeURL = try #require(URL(string: "https://archiveofourown.org/"))
        let externalURL = try #require(URL(string: "https://example.com/works/123"))
        let similarPathURL = try #require(URL(string: "https://archiveofourown.org/workskins/123"))

        #expect(session.hasSessionCookie)
        #expect(session.cookieHeader(for: workURL) == "work=allowed; _otwarchive_session=session")
        #expect(session.cookieHeader(for: homeURL) == "_otwarchive_session=session")
        #expect(session.cookieHeader(for: externalURL) == nil)
        #expect(session.cookieHeader(for: similarPathURL) == "_otwarchive_session=session")
    }

    @Test func sessionRoundTripsThroughCodable() throws {
        let original = AO3Session(
            username: "ExampleUser",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "secret")],
            savedAt: Date(timeIntervalSince1970: 1_000)
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(AO3Session.self, from: data)
        #expect(restored == original)
    }

    @Test func loggedInHTMLAndUsernameAreRecognized() {
        let html = """
        <html><body class="logged-in">
          <div id="greeting">
            <a href="/users/Example%20User">Hi</a>
            <a href="/users/logout">Log Out</a>
          </div>
        </body></html>
        """
        #expect(LiveAO3SessionValidator.isLoggedIn(html: html))
        #expect(LiveAO3SessionValidator.username(in: html) == "Example User")
        #expect(!LiveAO3SessionValidator.isLoggedIn(html: "<body class='logged-out'></body>"))
    }

    @Test func pageObservationNormalizesBlankValues() {
        let observation = AO3LoginPageObservation(javaScriptValue: [
            "isLoggedIn": true,
            "username": " Reader ",
            "errorMessage": "   ",
            "hasLoginForm": false
        ])
        #expect(observation.isLoggedIn)
        #expect(observation.username == "Reader")
        #expect(observation.errorMessage == nil)
    }
}

@MainActor
struct AO3AuthServiceTests {
    @Test func hiddenSuccessPersistsSessionAndBuildsAuthenticatedRequest() async throws {
        let session = testSession
        let vault = MemoryAO3SessionVault()
        let performer = MockAO3LoginPerformer(result: .success(session))
        let cookies = MockAO3CookieManager()
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(session)),
            loginPerformer: performer,
            cookieManager: cookies
        )

        await service.login(username: "reader", password: "password")

        #expect(service.status == .signedIn(username: "reader"))
        #expect(vault.session == session)
        #expect(cookies.installed == session)
        #expect(cookies.clearCount == 1)

        let url = try #require(URL(string: "https://archiveofourown.org/users/reader/bookmarks"))
        let request = try service.authenticatedRequest(for: url)
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("_otwarchive_session=") == true)

        let insecureURL = try #require(URL(string: "http://archiveofourown.org/users/reader"))
        #expect(throws: AO3AuthenticatedRequestError.self) {
            try service.authenticatedRequest(for: insecureURL)
        }
    }

    @Test func mechanismFailureAutomaticallyStartsVisibleFallback() async {
        let session = testSession
        let vault = MemoryAO3SessionVault()
        let performer = MockAO3LoginPerformer(
            result: .failure(.fallbackRequired("Form changed."))
        )
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .expired),
            loginPerformer: performer,
            cookieManager: MockAO3CookieManager()
        )

        await service.login(username: "reader", password: "password")

        #expect(service.status == .usingFallback)
        #expect(service.fallbackMessage == "Form changed.")
        #expect(performer.didBeginManualLogin)

        performer.completeManualLogin(with: session)
        for _ in 0..<50 where !service.isLoggedIn {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(service.status == .signedIn(username: "reader"))
        #expect(vault.session == session)
    }

    @Test func rejectedCredentialsStayNativeInsteadOfOpeningFallback() async {
        let performer = MockAO3LoginPerformer(
            result: .failure(.invalidCredentials("The password was incorrect."))
        )
        let service = AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: MockAO3SessionValidator(result: .expired),
            loginPerformer: performer,
            cookieManager: MockAO3CookieManager()
        )

        await service.login(username: "reader", password: "bad")

        #expect(service.status == .signedOut)
        #expect(service.errorMessage == "The password was incorrect.")
        #expect(!performer.didBeginManualLogin)
    }

    @Test func expiredRestoredSessionIsClearedGracefully() async {
        let vault = MemoryAO3SessionVault(session: testSession)
        let cookies = MockAO3CookieManager()
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .expired),
            loginPerformer: MockAO3LoginPerformer(result: .success(testSession)),
            cookieManager: cookies
        )

        await service.restoreSession()

        #expect(service.status == .signedOut)
        #expect(service.noticeMessage?.contains("expired") == true)
        #expect(vault.session == nil)
        #expect(cookies.clearCount == 1)
    }

    @Test func featureResponseCanInvalidateAnExpiredSession() async {
        let vault = MemoryAO3SessionVault(session: testSession)
        let cookies = MockAO3CookieManager()
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(testSession)),
            loginPerformer: MockAO3LoginPerformer(result: .success(testSession)),
            cookieManager: cookies
        )

        await service.restoreSession()
        #expect(service.status == .signedIn(username: "reader"))
        await service.sessionDidExpire()

        #expect(service.status == .signedOut)
        #expect(service.noticeMessage?.contains("expired") == true)
        #expect(vault.session == nil)
        #expect(cookies.clearCount == 1)
    }

    @Test func logoutClearsPersistedAndWebSessions() async {
        let session = testSession
        let vault = MemoryAO3SessionVault(session: session)
        let cookies = MockAO3CookieManager()
        let hints = MemoryAO3SessionHintStore(username: session.username)
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(session)),
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: cookies,
            sessionHintStore: hints
        )

        await service.restoreSession()
        await service.logout()

        #expect(service.status == .signedOut)
        #expect(service.noticeMessage == "Logged out of AO3.")
        #expect(vault.session == nil)
        #expect(cookies.clearCount == 1)
        #expect(hints.username == nil)
    }

    @Test func loginSurvivesMissingKeychainEntitlement() async {
        let session = testSession
        let vault = MemoryAO3SessionVault(saveError: .keychain(errSecMissingEntitlement))
        let cookies = MockAO3CookieManager()
        let hints = MemoryAO3SessionHintStore()
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(session)),
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: cookies,
            sessionHintStore: hints
        )

        await service.login(username: "reader", password: "password")

        #expect(service.status == .signedIn(username: "reader"))
        #expect(service.errorMessage == nil)
        #expect(cookies.installed == session)
        #expect(cookies.clearCount == 1)
        #expect(hints.username == "reader")
    }

    @Test func restoreRecoversSessionFromPersistentWebCookies() async {
        let session = testSession
        let vault = MemoryAO3SessionVault(
            loadError: .keychain(errSecMissingEntitlement),
            saveError: .keychain(errSecMissingEntitlement)
        )
        let cookies = MockAO3CookieManager(capturedCookies: session.cookies)
        let hints = MemoryAO3SessionHintStore(username: session.username)
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(session)),
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: cookies,
            sessionHintStore: hints
        )

        await service.restoreSession()

        #expect(service.status == .signedIn(username: "reader"))
        #expect(service.errorMessage == nil)
        #expect(cookies.installed == session)
    }

    @Test func unrelatedSessionSaveFailureStillRejectsLogin() async {
        let session = testSession
        let vault = MemoryAO3SessionVault(saveError: .invalidData)
        let cookies = MockAO3CookieManager()
        let hints = MemoryAO3SessionHintStore(username: "stale-user")
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(session)),
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: cookies,
            sessionHintStore: hints
        )

        await service.login(username: "reader", password: "password")

        #expect(service.status == .signedOut)
        #expect(service.errorMessage?.contains("could not be saved securely") == true)
        #expect(cookies.clearCount == 2)
        #expect(hints.username == nil)
    }

    private var testSession: AO3Session {
        AO3Session(
            username: "reader",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "session")]
        )
    }
}

@MainActor
private final class MemoryAO3SessionVault: AO3SessionPersisting {
    var session: AO3Session?
    let loadError: AO3SessionVaultError?
    let saveError: AO3SessionVaultError?

    init(
        session: AO3Session? = nil,
        loadError: AO3SessionVaultError? = nil,
        saveError: AO3SessionVaultError? = nil
    ) {
        self.session = session
        self.loadError = loadError
        self.saveError = saveError
    }

    func load() throws -> AO3Session? {
        if let loadError { throw loadError }
        return session
    }

    func save(_ session: AO3Session) throws {
        if let saveError { throw saveError }
        self.session = session
    }

    func delete() throws { session = nil }
}

@MainActor
private final class MemoryAO3SessionHintStore: AO3SessionHintPersisting {
    var username: String?

    init(username: String? = nil) {
        self.username = username
    }

    func loadUsername() -> String? { username }
    func saveUsername(_ username: String) { self.username = username }
    func deleteUsername() { username = nil }
}

@MainActor
private struct MockAO3SessionValidator: AO3SessionValidating {
    let result: AO3SessionValidation
    func validate(_ session: AO3Session) async throws -> AO3SessionValidation { result }
}

@MainActor
private final class MockAO3CookieManager: AO3CookieManaging {
    var installed: AO3Session?
    var clearCount = 0
    var capturedCookies: [AO3StoredCookie]

    init(capturedCookies: [AO3StoredCookie] = []) {
        self.capturedCookies = capturedCookies
    }

    func install(_ session: AO3Session) async { installed = session }
    func clear() async { clearCount += 1 }
    func capture() async -> [AO3StoredCookie] { capturedCookies }
}

@MainActor
private final class MockAO3LoginPerformer: AO3LoginPerforming {
    lazy var webView = WKWebView()
    let result: Result<AO3Session, AO3WebLoginError>
    private(set) var didBeginManualLogin = false
    private var manualCompletion: ((AO3Session) -> Void)?

    init(result: Result<AO3Session, AO3WebLoginError>) {
        self.result = result
    }

    func login(username: String, password: String) async throws -> AO3Session {
        try result.get()
    }

    func beginManualLogin(
        expectedUsername: String,
        onAuthenticated: @escaping (AO3Session) -> Void,
        onError: @escaping (String) -> Void
    ) {
        didBeginManualLogin = true
        manualCompletion = onAuthenticated
    }

    func completeManualLogin(with session: AO3Session) {
        manualCompletion?(session)
    }

    func applyVisibleTheme(_ theme: ReaderTheme) {}
    func cancel() {}
}
