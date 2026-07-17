import Foundation
import Testing
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
        // Generic #main without logged-in/out body class is not enough — that
        // pattern appears on interstitials and must not wipe the session.
        #expect(!LiveAO3SessionValidator.looksLikeAO3Page(html: """
        <html><body><div id="main">Almost AO3</div></body></html>
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

/// A5-F4: `CascadingAO3SessionVault.delete()` must always attempt both underlying
/// stores, even when one throws, and must surface a failure rather than silently
/// dropping the second attempt. Uses throwing/spying doubles instead of the real
/// Keychain so a genuine (non-missing-entitlement) failure is reproducible at all.
struct CascadingAO3SessionVaultTests {
    private final class SpyingSessionVault: AO3SessionPersisting {
        private(set) var deleteCallCount = 0
        var deleteError: Error?

        func load() throws -> AO3Session? { nil }
        func save(_ session: AO3Session) throws {}
        func delete() throws {
            deleteCallCount += 1
            if let deleteError { throw deleteError }
        }
    }

    @Test func attemptsFileDeleteEvenWhenKeychainThrows() {
        let keychain = SpyingSessionVault()
        keychain.deleteError = AO3SessionVaultError.keychain(errSecInteractionNotAllowed)
        let file = SpyingSessionVault()
        let vault = CascadingAO3SessionVault(keychain: keychain, file: file)

        #expect(throws: AO3SessionVaultError.self) { try vault.delete() }
        #expect(keychain.deleteCallCount == 1)
        #expect(file.deleteCallCount == 1)
    }

    @Test func deleteSucceedsOnlyWhenBothStoresSucceed() throws {
        let keychain = SpyingSessionVault()
        let file = SpyingSessionVault()
        let vault = CascadingAO3SessionVault(keychain: keychain, file: file)

        try vault.delete()
        #expect(keychain.deleteCallCount == 1)
        #expect(file.deleteCallCount == 1)
    }

    @Test func missingEntitlementIsIgnoredButFileIsStillDeleted() throws {
        let keychain = SpyingSessionVault()
        keychain.deleteError = AO3SessionVaultError.keychain(errSecMissingEntitlement)
        let file = SpyingSessionVault()
        let vault = CascadingAO3SessionVault(keychain: keychain, file: file)

        try vault.delete() // missing entitlement is expected on Simulator/unsigned builds
        #expect(keychain.deleteCallCount == 1)
        #expect(file.deleteCallCount == 1)
    }

    @Test func fileFailureAloneIsStillSurfaced() {
        let keychain = SpyingSessionVault()
        let file = SpyingSessionVault()
        file.deleteError = AO3SessionVaultError.invalidData
        let vault = CascadingAO3SessionVault(keychain: keychain, file: file)

        #expect(throws: AO3SessionVaultError.self) { try vault.delete() }
        #expect(keychain.deleteCallCount == 1)
        #expect(file.deleteCallCount == 1)
    }
}

/// A5-F1: the cookie bridge must only ever mirror a session into WebKit's own cookie
/// store — never into `HTTPCookieStorage.shared`, which `AO3Client`'s "anonymous"
/// session used to read from automatically, silently authenticating requests that
/// were supposed to be anonymous.
@MainActor
struct AO3CookieBridgeTests {
    @Test func installNeverWritesToTheSharedHTTPCookieStorage() async {
        let marker = "kudos-test-marker-\(UUID().uuidString)"
        let session = AO3Session(
            username: "reader",
            cookies: [AO3StoredCookie(name: marker, value: "leak-check")]
        )

        await AO3CookieBridge.install(session)
        #expect(HTTPCookieStorage.shared.cookies?.contains { $0.name == marker } != true)
        await AO3CookieBridge.clearAO3Cookies()
    }

    /// A5-F1 upgrade gap: a pre-fix build wrote AO3 cookies into
    /// `HTTPCookieStorage.shared` and nothing ever deleted them once this bridge
    /// stopped touching that store. `purgeLegacySharedCookieJar()` must sweep any
    /// such leftover regardless of domain casing/leading-dot formatting, and must
    /// leave a non-AO3 cookie alone.
    @Test func purgeLegacySharedCookieJarRemovesOnlyAO3Cookies() throws {
        let marker = "kudos-test-legacy-\(UUID().uuidString)"
        let legacyAO3Cookie = try #require(HTTPCookie(properties: [
            .name: marker,
            .value: "leaked-before-the-fix",
            .domain: ".archiveofourown.org",
            .path: "/",
            .secure: "TRUE"
        ]))
        let unrelatedCookie = try #require(HTTPCookie(properties: [
            .name: marker,
            .value: "unrelated-site",
            .domain: "example.com",
            .path: "/",
            .secure: "TRUE"
        ]))
        HTTPCookieStorage.shared.setCookie(legacyAO3Cookie)
        HTTPCookieStorage.shared.setCookie(unrelatedCookie)
        #expect(HTTPCookieStorage.shared.cookies?.contains { $0.domain == ".archiveofourown.org" && $0.name == marker } == true)

        AO3CookieBridge.purgeLegacySharedCookieJar()

        #expect(HTTPCookieStorage.shared.cookies?.contains { $0.domain == ".archiveofourown.org" && $0.name == marker } != true)
        #expect(HTTPCookieStorage.shared.cookies?.contains { $0.domain == "example.com" && $0.name == marker } == true)
        HTTPCookieStorage.shared.deleteCookie(unrelatedCookie)
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
/// T-100: authenticated/write requests append `AO3Client`'s currently-held
/// Cloudflare cookies after the account's own explicit cookie pairs.
struct AO3AuthServiceCookieMergeTests {
    @Test func appendsAChallengeHeaderWhenOneIsPresent() {
        let merged = AO3AuthService.mergedCookieHeader(
            auth: "_otwarchive_session=secret", challenge: "cf_clearance=abc123; __cf_bm=def456"
        )
        #expect(merged == "_otwarchive_session=secret; cf_clearance=abc123; __cf_bm=def456")
    }

    @Test func returnsTheAuthHeaderUnchangedWhenThereIsNoChallengeCookieYet() {
        #expect(AO3AuthService.mergedCookieHeader(auth: "_otwarchive_session=secret", challenge: nil)
            == "_otwarchive_session=secret")
        #expect(AO3AuthService.mergedCookieHeader(auth: "_otwarchive_session=secret", challenge: "")
            == "_otwarchive_session=secret")
    }
}

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
            cookieManager: cookies,
            removalTracker: MemoryAO3SessionRemovalTracker()
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
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
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
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
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
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )

        let loginTask = Task { await service.login(username: "reader", password: "password") }
        for _ in 0..<50 where !performer.isSuspended {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(performer.isSuspended)
        #expect(service.status == .signingIn)
        let cancellationCallsBeforeUserCancel = performer.cancelCount

        service.cancelLogin()
        await loginTask.value

        #expect(service.status == .signedOut)
        #expect(performer.cancelCount == cancellationCallsBeforeUserCancel + 1)
        #expect(!service.isLoggedIn)
    }

    /// The login sheet's Cancel button calls `cancelLogin()` unconditionally,
    /// including right after a native attempt already failed back to
    /// `.signedOut` with `errorMessage` set (nothing left in flight to abort).
    /// That stale failure text must not resurface the next time the sheet
    /// opens, before any new attempt is submitted.
    @Test func cancelAfterAFailedAttemptClearsTheStaleErrorMessage() async {
        let performer = MockAO3LoginPerformer(
            result: .failure(.invalidCredentials("The password was incorrect."))
        )
        let service = AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: MockAO3SessionValidator(result: .expired),
            loginPerformer: performer,
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )

        await service.login(username: "reader", password: "bad")
        #expect(service.status == .signedOut)
        #expect(service.errorMessage == "The password was incorrect.")

        service.cancelLogin()

        #expect(service.errorMessage == nil)
        #expect(service.status == .signedOut)
    }

    /// A fallback coordinator can retain its callback after `cancel()`. The
    /// callback must be inert synchronously, before it can queue a new accept.
    @Test func staleManualCompletionAfterCancelDoesNotResurrectSession() async {
        let alice = AO3Session(
            username: "alice",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "alice-cookie")]
        )
        let vault = MemoryAO3SessionVault()
        let performer = MockAO3LoginPerformer(
            result: .failure(.fallbackRequired("Finish on AO3."))
        )
        let cookies = MockAO3CookieManager()
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .expired),
            loginPerformer: performer,
            cookieManager: cookies,
            removalTracker: MemoryAO3SessionRemovalTracker()
        )

        await service.login(username: "alice", password: "password")
        #expect(service.status == .usingFallback)

        service.cancelLogin()
        performer.completeManualLogin(with: alice) // non-cooperative old callback

        #expect(service.status == .signedOut)
        #expect(!service.isLoggedIn)
        #expect(vault.session == nil)
        #expect(cookies.installed == nil)
    }

    @Test func expiredRestoredSessionIsClearedGracefully() async {
        let vault = MemoryAO3SessionVault(session: testSession)
        let cookies = MockAO3CookieManager()
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .expired),
            loginPerformer: MockAO3LoginPerformer(result: .success(testSession)),
            cookieManager: cookies,
            removalTracker: MemoryAO3SessionRemovalTracker()
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
            cookieManager: cookies,
            removalTracker: MemoryAO3SessionRemovalTracker()
        )

        await service.restoreSession()
        #expect(service.status == .signedIn(username: "reader"))
        await service.sessionDidExpire(expectedGeneration: service.sessionGeneration)

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
        let tracker = MemoryAO3SessionRemovalTracker()
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(session)),
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: cookies,
            sessionHintStore: hints,
            removalTracker: tracker
        )

        await service.restoreSession()
        await service.logout()

        #expect(service.status == .signedOut)
        #expect(service.noticeMessage == "Logged out of AO3.")
        #expect(vault.session == nil)
        #expect(cookies.clearCount == 1)
        #expect(hints.username == nil)
        #expect(!tracker.isRemovalPending)
    }

    /// A clear that has already begun must finish before the next account's clear
    /// and install. Otherwise WebKit can delete B's replacement session cookie
    /// after the Swift auth state has already moved to B.
    @Test func delayedLogoutCookieClearCannotEraseANewerLogin() async {
        let alice = AO3Session(
            username: "alice",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "alice-cookie")]
        )
        let bob = AO3Session(
            username: "bob",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "bob-cookie")]
        )
        let vault = MemoryAO3SessionVault()
        let cookies = GatedClearAO3CookieManager()
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(alice)),
            loginPerformer: UsernameAO3LoginPerformer(sessions: ["alice": alice, "bob": bob]),
            cookieManager: cookies,
            removalTracker: MemoryAO3SessionRemovalTracker()
        )

        await service.login(username: "alice", password: "password")
        #expect(cookies.installed == alice)

        cookies.gateNextClear()
        let logout = Task { await service.logout() }
        await cookies.clearEntered.wait()

        let newerLogin = Task { await service.login(username: "bob", password: "password") }
        for _ in 0..<10 where service.status != .signingIn {
            await Task.yield()
        }
        #expect(service.status == .signingIn)

        await cookies.releaseClear.fire()
        await logout.value
        await newerLogin.value

        #expect(service.status == .signedIn(username: "bob"))
        #expect(vault.session == bob)
        #expect(cookies.installed == bob)
    }

    /// Durable logout must finish before awaiting WebKit. If the replacement
    /// login later fails, relaunch must not revive the old account from the vault.
    @Test func delayedLogoutWithFailedReplacementCannotRestoreTheOldSession() async {
        let alice = AO3Session(
            username: "alice",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "alice-cookie")]
        )
        let vault = MemoryAO3SessionVault()
        let hints = MemoryAO3SessionHintStore()
        let tracker = MemoryAO3SessionRemovalTracker()
        let cookies = GatedClearAO3CookieManager()
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(alice)),
            loginPerformer: UsernameAO3LoginPerformer(sessions: ["alice": alice]),
            cookieManager: cookies,
            sessionHintStore: hints,
            removalTracker: tracker
        )

        await service.login(username: "alice", password: "password")
        cookies.gateNextClear()
        let logout = Task { await service.logout() }
        await cookies.clearEntered.wait()

        let failedReplacement = Task {
            await service.login(username: "bob", password: "password")
        }
        for _ in 0..<10 where service.status != .signingIn {
            await Task.yield()
        }
        #expect(service.status == .signingIn)

        await cookies.releaseClear.fire()
        await logout.value
        await failedReplacement.value

        #expect(service.status == .signedOut)
        #expect(vault.session == nil)
        #expect(hints.username == nil)
        #expect(!tracker.isRemovalPending)

        let relaunched = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(alice)),
            loginPerformer: MockAO3LoginPerformer(result: .success(alice)),
            cookieManager: MockAO3CookieManager(),
            sessionHintStore: hints,
            removalTracker: tracker
        )
        await relaunched.restoreSession()
        #expect(relaunched.status == .signedOut)
    }

    /// A5-F4: a Keychain/file delete that throws must not be reported as a clean
    /// logout, and the failure must be tracked so a relaunch refuses to restore.
    @Test func logoutSurfacesRetryableFailureInsteadOfClaimingSuccess() async {
        let session = testSession
        let vault = MemoryAO3SessionVault(session: session, deleteError: .keychain(errSecInteractionNotAllowed))
        let cookies = MockAO3CookieManager()
        let hints = MemoryAO3SessionHintStore(username: session.username)
        let tracker = MemoryAO3SessionRemovalTracker()
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(session)),
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: cookies,
            sessionHintStore: hints,
            removalTracker: tracker
        )

        await service.restoreSession()
        await service.logout()

        #expect(service.status == .signedOut)
        #expect(service.noticeMessage != "Logged out of AO3.")
        #expect(service.noticeMessage?.isEmpty == false)
        #expect(tracker.isRemovalPending)
        // Soft/live state is still cleared even though the durable delete failed.
        #expect(cookies.clearCount == 1)
        #expect(hints.username == nil)
        #expect(!service.isLoggedIn)
    }

    /// A5-F4: while removal is pending, a relaunch must refuse to restore the
    /// still-present session, no matter what the vault holds.
    @Test func pendingRemovalRefusesToRestoreStaleSessionOnRelaunch() async {
        let session = testSession
        let vault = MemoryAO3SessionVault(session: session, deleteError: .keychain(errSecInteractionNotAllowed))
        let tracker = MemoryAO3SessionRemovalTracker()
        tracker.markRemovalPending() // simulates a prior failed logout

        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(session)),
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: MockAO3CookieManager(),
            removalTracker: tracker
        )

        await service.restoreSession()

        #expect(service.status == .signedOut)
        #expect(!service.isLoggedIn)
        #expect(tracker.isRemovalPending) // the relaunch retry also failed; still pending
    }

    /// A5-F4: once the durable store is actually clearable, the automatic relaunch
    /// retry succeeds and the pending marker clears.
    @Test func pendingRemovalRetrySucceedsAndClearsPendingState() async {
        let session = testSession
        let vault = MemoryAO3SessionVault(session: session) // no deleteError: this retry succeeds
        let tracker = MemoryAO3SessionRemovalTracker()
        tracker.markRemovalPending()

        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(session)),
            loginPerformer: MockAO3LoginPerformer(result: .success(session)),
            cookieManager: MockAO3CookieManager(),
            removalTracker: tracker
        )

        await service.restoreSession()

        #expect(service.status == .signedOut)
        #expect(!tracker.isRemovalPending)
        #expect(vault.deleteAttempts == 1)
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
            sessionHintStore: hints,
            removalTracker: MemoryAO3SessionRemovalTracker()
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
            sessionHintStore: hints,
            removalTracker: MemoryAO3SessionRemovalTracker()
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
            sessionHintStore: hints,
            removalTracker: MemoryAO3SessionRemovalTracker()
        )

        await service.restoreSession()

        #expect(service.status == .signedIn(username: "reader"))
        #expect(service.errorMessage == nil)
        #expect(cookies.installed == session)
    }

    /// Launch-time WebKit capture must not revive its old account after the user
    /// starts and completes a newer login while capture is suspended.
    @Test func staleWebKitRestoreCannotOverwriteANewerLogin() async {
        let alice = AO3Session(
            username: "alice",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "alice-cookie")]
        )
        let bob = AO3Session(
            username: "bob",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "bob-cookie")]
        )
        let vault = MemoryAO3SessionVault()
        let cookies = GatedCaptureAO3CookieManager(capturedCookies: alice.cookies)
        let service = AO3AuthService(
            vault: vault,
            validator: MockAO3SessionValidator(result: .valid(alice)),
            loginPerformer: UsernameAO3LoginPerformer(sessions: ["bob": bob]),
            cookieManager: cookies,
            sessionHintStore: MemoryAO3SessionHintStore(username: alice.username),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )

        let restoration = Task { await service.restoreSession() }
        await cookies.captureEntered.wait()

        await service.login(username: "bob", password: "password")
        let bobGeneration = service.sessionGeneration
        await cookies.releaseCapture.fire()
        await restoration.value

        #expect(service.status == .signedIn(username: "bob"))
        #expect(service.sessionGeneration == bobGeneration)
        #expect(vault.session == bob)
        #expect(cookies.installed == bob)
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
            sessionHintStore: hints,
            removalTracker: MemoryAO3SessionRemovalTracker()
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
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )

        await service.restoreSession()
        let generationBeforeVerify = service.sessionGeneration
        await service.verifySession()

        guard case .healthy = service.sessionHealth else {
            Issue.record("expected .healthy, got \(String(describing: service.sessionHealth))")
            return
        }
        #expect(service.isLoggedIn)
        #expect(vault.session == session)
        #expect(service.sessionGeneration == generationBeforeVerify + 1)
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
            cookieManager: cookies,
            removalTracker: MemoryAO3SessionRemovalTracker()
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
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
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
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )

        await service.verifySession()

        #expect(service.sessionHealth == .unknown)
    }

    @Test func staleVerificationCannotExpireANewerLogin() async {
        let alice = AO3Session(
            username: "alice",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "alice-cookie")]
        )
        let bob = AO3Session(
            username: "bob",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "bob-cookie")]
        )
        let vault = MemoryAO3SessionVault()
        let validator = GatedAO3SessionValidator(result: .expired)
        let cookies = MockAO3CookieManager()
        let service = AO3AuthService(
            vault: vault,
            validator: validator,
            loginPerformer: UsernameAO3LoginPerformer(sessions: ["alice": alice, "bob": bob]),
            cookieManager: cookies,
            removalTracker: MemoryAO3SessionRemovalTracker()
        )

        await service.login(username: "alice", password: "password")
        let verification = Task { await service.verifySession() }
        await validator.entered.wait()

        await service.logout()
        await service.login(username: "bob", password: "password")
        let bobGeneration = service.sessionGeneration

        await validator.release.fire()
        await verification.value

        #expect(service.status == .signedIn(username: "bob"))
        #expect(service.sessionGeneration == bobGeneration)
        #expect(vault.session == bob)
        #expect(cookies.installed == bob)
    }

    /// A5-F1 upgrade gap: the purge must happen at construction, not inside
    /// `restoreSession()` — that method only ever runs from the root view's
    /// `.task`, and SwiftUI gives no ordering guarantee between sibling `.task`s,
    /// so a sibling avatar view's own `AsyncImage` fetch (same default
    /// `URLSession.shared` cookie jar) could otherwise win the race and carry a
    /// pre-fix build's leftover AO3 cookie once, on the very first launch after
    /// upgrading. Construction (the owning view's `@State` initializer) always
    /// precedes every `.task` in the tree, so asserting the cookie is already gone
    /// immediately after `init` — before `restoreSession()` ever runs — is the
    /// actual regression this guards.
    @Test func initPurgesLegacyCookieFromTheSharedHTTPCookieStorageBeforeAnyTaskCanRace() async throws {
        let marker = "kudos-test-legacy-restore-\(UUID().uuidString)"
        let legacyCookie = try #require(HTTPCookie(properties: [
            .name: marker,
            .value: "leaked-before-the-fix",
            .domain: ".archiveofourown.org",
            .path: "/",
            .secure: "TRUE"
        ]))
        HTTPCookieStorage.shared.setCookie(legacyCookie)

        let service = AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: MockAO3SessionValidator(result: .expired),
            loginPerformer: MockAO3LoginPerformer(result: .success(testSession)),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )

        // Gone immediately — before `restoreSession()` (or any `.task`) has run.
        #expect(HTTPCookieStorage.shared.cookies?.contains { $0.name == marker } != true)

        await service.restoreSession()

        #expect(HTTPCookieStorage.shared.cookies?.contains { $0.name == marker } != true)
    }

    private var testSession: AO3Session {
        AO3Session(
            username: "reader",
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "session")]
        )
    }
}
