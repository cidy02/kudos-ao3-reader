import Foundation
import WebKit
@testable import Kudos

/// Shared test doubles for AO3AuthService's 5 DI protocols
/// (`AO3SessionPersisting`, `AO3SessionRemovalTracking`,
/// `AO3SessionHintPersisting`, `AO3SessionValidating`, `AO3CookieManaging`,
/// `AO3LoginPerforming`), previously redefined per test file. Each type here is
/// the fullest-featured version found across the suite (error injection,
/// attempt counting, gating) — a test that doesn't need that extra capability
/// simply doesn't exercise it, so this is safe to use everywhere a simpler
/// local mock used to be.

/// A one-shot async gate used to deterministically sequence a gated async
/// dependency against a concurrent account switch/action.
actor Signal {
    private var fired = false
    private var continuation: CheckedContinuation<Void, Never>?

    func fire() {
        fired = true
        continuation?.resume()
        continuation = nil
    }

    func wait() async {
        if fired { return }
        await withCheckedContinuation { continuation = $0 }
    }
}

/// Every AO3LoginPerforming test double implements `login(username:password:)`
/// itself; the rest of the protocol is boilerplate no test double customizes
/// except `CancellableMockAO3LoginPerformer`'s own meaningful `cancel()`.
extension AO3LoginPerforming {
    func beginManualLogin(
        expectedUsername: String,
        onAuthenticated: @escaping (AO3Session) -> Void,
        onError: @escaping (String) -> Void
    ) {}
    func applyVisibleTheme(_ theme: ReaderTheme) {}
    func cancel() {}
}

final class MemoryAO3SessionVault: AO3SessionPersisting {
    var session: AO3Session?
    let loadError: AO3SessionVaultError?
    let saveError: AO3SessionVaultError?
    /// Mutable (not `let`) so a test can simulate "fails once, then a later retry
    /// succeeds" by clearing this between calls — mirrors `ConfigurableAO3SessionValidator`.
    var deleteError: AO3SessionVaultError?
    private(set) var deleteAttempts = 0

    init(
        session: AO3Session? = nil,
        loadError: AO3SessionVaultError? = nil,
        saveError: AO3SessionVaultError? = nil,
        deleteError: AO3SessionVaultError? = nil
    ) {
        self.session = session
        self.loadError = loadError
        self.saveError = saveError
        self.deleteError = deleteError
    }

    func load() throws -> AO3Session? {
        if let loadError { throw loadError }
        return session
    }

    func save(_ session: AO3Session) throws {
        if let saveError { throw saveError }
        self.session = session
    }

    func delete() throws {
        deleteAttempts += 1
        if let deleteError { throw deleteError }
        session = nil
    }
}

/// Fresh, isolated stand-in for the real UserDefaults-backed removal tracker — every
/// test that constructs `AO3AuthService` injects its own instance so pending state
/// from one test can never leak into another via `UserDefaults.standard`.
@MainActor
final class MemoryAO3SessionRemovalTracker: AO3SessionRemovalTracking {
    private(set) var isRemovalPending = false
    private(set) var markCount = 0
    private(set) var clearCount = 0

    func markRemovalPending() {
        isRemovalPending = true
        markCount += 1
    }

    func clearRemovalPending() {
        isRemovalPending = false
        clearCount += 1
    }
}

@MainActor
final class MemoryAO3SessionHintStore: AO3SessionHintPersisting {
    var username: String?

    init(username: String? = nil) {
        self.username = username
    }

    func loadUsername() -> String? { username }
    func saveUsername(_ username: String) { self.username = username }
    func deleteUsername() { username = nil }
}

@MainActor
struct MockAO3SessionValidator: AO3SessionValidating {
    let result: AO3SessionValidation
    func validate(_ session: AO3Session) async throws -> AO3SessionValidation { result }
}

/// A validator whose outcome can change between calls and which can be made to
/// throw — needed to drive `verifySession()` through healthy → expired →
/// unreachable within a single logged-in service instance.
@MainActor
final class ConfigurableAO3SessionValidator: AO3SessionValidating {
    var result: AO3SessionValidation
    var error: (any Error)?

    init(result: AO3SessionValidation) { self.result = result }

    func validate(_ session: AO3Session) async throws -> AO3SessionValidation {
        if let error { throw error }
        return result
    }
}

@MainActor
final class GatedAO3SessionValidator: AO3SessionValidating {
    let entered = Signal()
    let release = Signal()
    let result: AO3SessionValidation

    init(result: AO3SessionValidation) { self.result = result }

    func validate(_ session: AO3Session) async throws -> AO3SessionValidation {
        await entered.fire()
        await release.wait()
        return result
    }
}

@MainActor
final class MockAO3CookieManager: AO3CookieManaging {
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
final class GatedCaptureAO3CookieManager: AO3CookieManaging {
    var installed: AO3Session?
    private let capturedCookies: [AO3StoredCookie]
    let captureEntered = Signal()
    let releaseCapture = Signal()

    init(capturedCookies: [AO3StoredCookie]) {
        self.capturedCookies = capturedCookies
    }

    func install(_ session: AO3Session) async { installed = session }
    func clear() async { installed = nil }

    func capture() async -> [AO3StoredCookie] {
        await captureEntered.fire()
        await releaseCapture.wait()
        return capturedCookies
    }
}

@MainActor
final class GatedClearAO3CookieManager: AO3CookieManaging {
    var installed: AO3Session?
    private var shouldGateNextClear = false
    let clearEntered = Signal()
    let releaseClear = Signal()

    func gateNextClear() { shouldGateNextClear = true }

    func install(_ session: AO3Session) async { installed = session }

    func clear() async {
        if shouldGateNextClear {
            shouldGateNextClear = false
            await clearEntered.fire()
            await releaseClear.wait()
        }
        installed = nil
    }

    func capture() async -> [AO3StoredCookie] { [] }
}

@MainActor
final class MockAO3LoginPerformer: AO3LoginPerforming {
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
}

/// Stays suspended in `login` until `cancel()` resumes with `CancellationError`,
/// mirroring the real coordinator's continuation + cancel path.
@MainActor
final class CancellableMockAO3LoginPerformer: AO3LoginPerforming {
    lazy var webView = WKWebView()
    private(set) var cancelCount = 0
    private var continuation: CheckedContinuation<AO3Session, Error>?
    var isSuspended: Bool { continuation != nil }

    func login(username: String, password: String) async throws -> AO3Session {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() {
        cancelCount += 1
        if let continuation {
            self.continuation = nil
            continuation.resume(throwing: CancellationError())
        }
    }
}

@MainActor
final class UsernameAO3LoginPerformer: AO3LoginPerforming {
    lazy var webView = WKWebView()
    private let sessions: [String: AO3Session]

    init(sessions: [String: AO3Session]) { self.sessions = sessions }

    func login(username: String, password: String) async throws -> AO3Session {
        guard let session = sessions[username] else {
            throw AO3WebLoginError.invalidCredentials("Unknown test user.")
        }
        return session
    }
}

/// Unlike `MockAO3SessionValidator`'s fixed result, this echoes back whatever
/// session it's asked to validate — needed by the account-transition suites
/// (Inbox, Comments), which validate a *different* real session per account
/// (alice, then bob) within the same test and need each to come back `.valid`
/// as itself, not a stale fixed session from test setup.
@MainActor
struct InboxTestSessionValidator: AO3SessionValidating {
    func validate(_ session: AO3Session) async throws -> AO3SessionValidation { .valid(session) }
}

/// Unlike a fixed-result login double, this builds a session from whatever
/// username is actually requested — tests drive the same `AO3AuthService`
/// through alice → bob (and back to alice) without needing a new performer.
@MainActor
final class DynamicInboxTestLoginPerformer: AO3LoginPerforming {
    lazy var webView = WKWebView()

    func login(username: String, password: String) async throws -> AO3Session {
        AO3Session(
            username: username,
            cookies: [AO3StoredCookie(name: "_otwarchive_session", value: "session-\(username)")]
        )
    }
}
