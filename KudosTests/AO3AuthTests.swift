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

    @Test func looksLikeAO3PageRejectsChallengeWalls() {
        #expect(LiveAO3SessionValidator.looksLikeAO3Page(html: """
        <html><body class="logged-in"><div id="header"></div></body></html>
        """))
        #expect(LiveAO3SessionValidator.looksLikeAO3Page(html: """
        <html><body class="logged-out"><div id="main"></div></body></html>
        """))
        #expect(!LiveAO3SessionValidator.looksLikeAO3Page(html: """
        <html><body>Just a moment... Cloudflare</body></html>
        """))
        #expect(!LiveAO3SessionValidator.looksLikeAO3Page(html: ""))
    }

    @Test func fileSessionVaultRoundTripsAndDeletes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kudos-ao3-session-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let vault = FileAO3SessionVault(fileURL: url)
        let session = AO3Session(
            username: "reader",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "session")]
        )
        #expect(try vault.load() == nil)
        try vault.save(session)
        #expect(try vault.load() == session)
        try vault.delete()
        #expect(try vault.load() == nil)
    }

    @Test func cascadingVaultFallsBackToFileWhenKeychainEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kudos-ao3-cascade-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        // Use a unique Keychain service so we never collide with a real app item;
        // empty load → file. On Simulator, Keychain often throws
        // errSecMissingEntitlement (-34018); the cascade must still round-trip
        // via the file vault.
        let vault = CascadingAO3SessionVault(
            keychain: KeychainAO3SessionVault(service: "KudosTests.cascade.\(UUID().uuidString)"),
            file: FileAO3SessionVault(fileURL: url)
        )
        let session = AO3Session(
            username: "reader",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "session")]
        )
        try vault.save(session)
        let restored = try vault.load()
        #expect(restored?.username == "reader")
        #expect(restored?.hasSessionCookie == true)
        try vault.delete()
        #expect(try vault.load() == nil)
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

/// Guards the Swift session parser against AO3 markup drift using representative
/// page fixtures. The hidden-login JS in `AO3WebLoginCoordinator` reads the same
/// structure, so a failure here is an early warning that the live-page checks need
/// updating too.
struct AO3AuthHTMLFixtureTests {
    final class BundleAnchor {}

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func recognizesLoggedInHeaderFixture() throws {
        let html = try fixture("ao3_logged_in")
        #expect(LiveAO3SessionValidator.isLoggedIn(html: html))
        #expect(LiveAO3SessionValidator.username(in: html) == "AO3_Reader")
    }

    @Test func treatsLoginPageFixtureAsLoggedOut() throws {
        let html = try fixture("ao3_logged_out")
        #expect(!LiveAO3SessionValidator.isLoggedIn(html: html))
        #expect(LiveAO3SessionValidator.username(in: html) == nil)
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

    /// Explicit Cancel must abort an in-flight automatic login. Sheet teardown
    /// without Cancel must *not* call this (see AO3LoginView) — covered here by
    /// proving cancelLogin is the path that flips status back to signedOut.
    @Test func cancelLoginAbortsInFlightAutomaticLogin() async {
        let performer = CancellableMockAO3LoginPerformer()
        let service = AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: MockAO3SessionValidator(result: .expired),
            loginPerformer: performer,
            cookieManager: MockAO3CookieManager()
        )

        let loginTask = Task { await service.login(username: "reader", password: "password") }
        for _ in 0..<50 where !performer.isSuspended {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(performer.isSuspended)
        #expect(service.status == .signingIn)

        service.cancelLogin()
        await loginTask.value

        #expect(service.status == .signedOut)
        #expect(performer.cancelCount == 1)
        #expect(!service.isLoggedIn)
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

    /// Simulator/unsigned: Keychain `load` returns nil (not found) while login
    /// cookies still live in WebKit — must not treat empty Keychain as signed-out.
    @Test func restoreFallsThroughToWebKitWhenKeychainIsEmpty() async {
        let session = testSession
        let vault = MemoryAO3SessionVault(session: nil)
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

    // MARK: On-demand session health (verifySession)

    @Test func verifySessionReportsHealthyAndKeepsSession() async {
        // Capture one session value — `testSession` mints a fresh instance (new
        // `savedAt`) on each access, so reuse the same one everywhere it's compared.
        let session = testSession
        let vault = MemoryAO3SessionVault(session: session)
        let validator = ConfigurableAO3SessionValidator(result: .valid(session))
        let service = AO3AuthService(
            vault: vault,
            validator: validator,
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: MockAO3CookieManager()
        )

        await service.restoreSession()
        await service.verifySession()

        guard case .healthy = service.sessionHealth else {
            Issue.record("expected .healthy, got \(String(describing: service.sessionHealth))")
            return
        }
        #expect(service.isLoggedIn)
        #expect(vault.session == session)
    }

    @Test func verifySessionExpiresAndClearsWhenAO3RejectsIt() async {
        let session = testSession
        let vault = MemoryAO3SessionVault(session: session)
        let validator = ConfigurableAO3SessionValidator(result: .valid(session))
        let cookies = MockAO3CookieManager()
        let service = AO3AuthService(
            vault: vault,
            validator: validator,
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: cookies
        )

        await service.restoreSession()
        validator.result = .expired          // AO3 now says the session is gone
        await service.verifySession()

        #expect(service.sessionHealth == .expired)
        #expect(service.status == .signedOut)
        #expect(vault.session == nil)
    }

    @Test func verifySessionKeepsSessionWhenAO3IsUnreachable() async {
        let session = testSession
        let vault = MemoryAO3SessionVault(session: session)
        let validator = ConfigurableAO3SessionValidator(result: .valid(session))
        let service = AO3AuthService(
            vault: vault,
            validator: validator,
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: MockAO3CookieManager()
        )

        await service.restoreSession()
        validator.error = URLError(.notConnectedToInternet)   // transient failure
        await service.verifySession()

        #expect(service.sessionHealth == .unreachable)
        #expect(service.isLoggedIn)               // session kept, not logged out
        #expect(vault.session == session)
    }

    @Test func verifySessionIsANoOpWhileSignedOut() async {
        let session = testSession
        let service = AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: ConfigurableAO3SessionValidator(result: .valid(session)),
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: MockAO3CookieManager()
        )

        await service.verifySession()

        #expect(service.sessionHealth == .unknown)
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

/// A validator whose outcome can change between calls and which can be made to
/// throw — needed to drive `verifySession()` through healthy → expired →
/// unreachable within a single logged-in service instance.
@MainActor
private final class ConfigurableAO3SessionValidator: AO3SessionValidating {
    var result: AO3SessionValidation
    var error: (any Error)?

    init(result: AO3SessionValidation) { self.result = result }

    func validate(_ session: AO3Session) async throws -> AO3SessionValidation {
        if let error { throw error }
        return result
    }
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

/// Stays suspended in `login` until `cancel()` resumes with `CancellationError`,
/// mirroring the real coordinator's continuation + cancel path.
@MainActor
private final class CancellableMockAO3LoginPerformer: AO3LoginPerforming {
    lazy var webView = WKWebView()
    private(set) var cancelCount = 0
    private var continuation: CheckedContinuation<AO3Session, Error>?
    var isSuspended: Bool { continuation != nil }

    func login(username: String, password: String) async throws -> AO3Session {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func beginManualLogin(
        expectedUsername: String,
        onAuthenticated: @escaping (AO3Session) -> Void,
        onError: @escaping (String) -> Void
    ) {}

    func applyVisibleTheme(_ theme: ReaderTheme) {}

    func cancel() {
        cancelCount += 1
        if let continuation {
            self.continuation = nil
            continuation.resume(throwing: CancellationError())
        }
    }
}
