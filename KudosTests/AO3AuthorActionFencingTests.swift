import Foundation
import Testing
@testable import Kudos

/// The three authenticated author actions (Subscribe, block/mute begin,
/// block/mute confirm) share one stale-response fence
/// (`performFencedAuthorAction`): route / authentication scope / session
/// generation are captured before the operation's await and re-checked after,
/// so a response that outlives an account switch (or a pseud-scope switch) can
/// never touch the replacement context's state. `beginModeration` drives the
/// fence end-to-end through the injectable page loader; the success-path route
/// fence is exercised on the shared helper directly.
@Suite(.serialized)
@MainActor
struct AO3AuthorActionFencingTests {
    private final class BundleAnchor {}

    private static func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func makeAuth() -> AO3AuthService {
        AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
    }

    private static let blockAction = AO3AuthorWebAction(
        label: "Block",
        url: URL(string: "https://archiveofourown.org/users/Avery_Archive/blocked/confirm")!,
        kind: .block
    )

    private static func makeModel(
        pageLoader: @escaping AO3AuthorProfileModel.PageLoader
    ) throws -> AO3AuthorProfileModel {
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        return AO3AuthorProfileModel(route: route, pageLoader: pageLoader)
    }

    // MARK: beginModeration end-to-end through the injectable page loader

    @Test func moderationFormStagesForTheContextThatRequestedIt() async throws {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "pw")
        let html = try Self.fixture("ao3_author_confirm_block")
        let model = try Self.makeModel { _, _, _ in
            AO3AuthorProfileFetcher.Page(html: html, isStale: false)
        }

        await model.beginModeration(action: Self.blockAction, auth: auth)

        #expect(model.pendingModerationForm?.kind == .block)
        #expect(model.actionMessage == nil)
        #expect(!model.isPerformingModeration)
    }

    @Test func staleGenerationSuppressesModerationFormStaging() async throws {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "pw")
        let html = try Self.fixture("ao3_author_confirm_block")
        let entered = Signal()
        let release = Signal()
        let model = try Self.makeModel { _, _, _ in
            await entered.fire()
            await release.wait()
            return AO3AuthorProfileFetcher.Page(html: html, isStale: false)
        }

        let action = Task { await model.beginModeration(action: Self.blockAction, auth: auth) }
        await entered.wait()
        await auth.logout()
        await auth.login(username: "bob", password: "pw")
        await release.fire()
        await action.value

        // The fetch succeeded and parsed, but for a superseded session — nothing staged.
        #expect(model.pendingModerationForm == nil)
        #expect(model.actionMessage == nil)
        #expect(!model.isPerformingModeration)
    }

    @Test func authenticationRequiredExpiresTheSessionThatWasCaptured() async throws {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "pw")
        let model = try Self.makeModel { _, _, _ in
            throw AO3Error.authenticationRequired
        }

        await model.beginModeration(action: Self.blockAction, auth: auth)

        #expect(!auth.isLoggedIn)
        #expect(auth.sessionHealth == .expired)
        #expect(model.pendingModerationForm == nil)
    }

    @Test func staleAuthenticationRequiredCannotLogOutTheReplacementAccount() async throws {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "pw")
        let entered = Signal()
        let release = Signal()
        let model = try Self.makeModel { _, _, _ in
            await entered.fire()
            await release.wait()
            throw AO3Error.authenticationRequired
        }

        let action = Task { await model.beginModeration(action: Self.blockAction, auth: auth) }
        await entered.wait()
        await auth.logout()
        await auth.login(username: "bob", password: "pw")
        await release.fire()
        await action.value

        #expect(auth.isLoggedIn)
        #expect(auth.username == "bob")
    }

    @Test func failureMessageBelongsOnlyToTheContextThatFailed() async throws {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "pw")

        // Current generation: the failure surfaces.
        let failing = try Self.makeModel { _, _, _ in throw URLError(.timedOut) }
        await failing.beginModeration(action: Self.blockAction, auth: auth)
        #expect(failing.actionMessage != nil)

        // Stale generation: the same failure is dropped silently.
        let entered = Signal()
        let release = Signal()
        let gated = try Self.makeModel { _, _, _ in
            await entered.fire()
            await release.wait()
            throw URLError(.timedOut)
        }
        let action = Task { await gated.beginModeration(action: Self.blockAction, auth: auth) }
        await entered.wait()
        await auth.logout()
        await auth.login(username: "bob", password: "pw")
        await release.fire()
        await action.value
        #expect(gated.actionMessage == nil)
    }

    // MARK: The shared fence itself (success-path route check)

    @MainActor
    private final class SuccessFlag {
        var value = false
    }

    @Test func successAfterARouteSwitchToAnotherAuthorIsDropped() async throws {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "pw")
        // Header loads triggered by selectScope just fail fast; only the fence matters.
        let model = try Self.makeModel { _, _, _ in throw URLError(.cannotConnectToHost) }
        let entered = Signal()
        let release = Signal()
        let flag = SuccessFlag()

        let action = Task {
            await model.performFencedAuthorAction(auth: auth) { _, _ in
                await entered.fire()
                await release.wait()
                return "done"
            } onSuccess: { (_: String) in
                flag.value = true
            }
        }
        await entered.wait()
        model.selectScope(try #require(AO3AuthorRoute(username: "Different_User")), auth: auth)
        await release.fire()
        await action.value

        #expect(!flag.value)
        model.cancel()
    }

    @Test func successForTheUnchangedContextRuns() async throws {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "pw")
        let model = try Self.makeModel { _, _, _ in throw URLError(.cannotConnectToHost) }
        var received: String?

        await model.performFencedAuthorAction(auth: auth) { actionRoute, _ in
            "hello-\(actionRoute.username)"
        } onSuccess: { value in
            received = value
        }

        #expect(received == "hello-Avery_Archive")
    }
}
