import Foundation
import Testing
import WebKit
@testable import Kudos

/// T91-RF3: an Inbox write/reload must never outlive an account switch and
/// overwrite the newly-active account's model with the previous account's
/// private data. Every scenario here deterministically controls *when* a
/// gated async dependency (`pageLoader`/`bulkActionSubmitter`) resumes, so the
/// account switch is guaranteed to happen strictly before that resumption —
/// no sleeps racing real timing.
@MainActor
struct AO3InboxAccountTransitionTests {
    // MARK: Fixtures

    private final class BundleAnchor {}

    private static func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// AO3's recognized-but-empty inbox markup (no items), distinguished by the
    /// heading's total so a test can tell which load actually landed.
    private static func inboxHTML(total: Int) -> String {
        """
        <html><body>
        <h2 class="heading">My Inbox (\(total) comments, \(total) unread)</h2>
        <form class="narrow-hidden filters" id="inbox-filters" action="/users/tester/inbox"></form>
        </body></html>
        """
    }

    private static func page(_ html: String) -> AO3AuthorProfileFetcher.Page {
        AO3AuthorProfileFetcher.Page(html: html, isStale: false)
    }

    // MARK: Auth helper

    private static func makeAuthService() -> AO3AuthService {
        AO3AuthService(
            vault: MemoryInboxTestSessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: NoOpInboxTestCookieManager(),
            removalTracker: MemoryInboxTestRemovalTracker()
        )
    }

    // MARK: 1. Suspend A reload, switch to B, resume A → B unchanged.

    @Test func suspendedReloadResumingAfterSwitchNeverReachesTheNewAccount() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")

        let aliceEntered = Signal()
        let aliceRelease = Signal()
        let model = AO3InboxModel(pageLoader: { _, authArg, _, _, _ in
            let username = authArg.username
            if username == "alice" {
                await aliceEntered.fire()
                await aliceRelease.wait()
                return Self.page(Self.inboxHTML(total: 5))
            }
            return Self.page(Self.inboxHTML(total: 9))
        })

        model.syncAuthenticationContext(auth: auth)
        let aliceReload = Task { await model.refresh(auth: auth) }
        await aliceEntered.wait()

        await auth.logout()
        await auth.login(username: "bob", password: "password")
        // AccountView's generation observer resets stale private state before
        // B fetches. Load B *before* A is allowed to finish, then prove the
        // resumed A continuation cannot alter the already-visible B screen.
        model.syncAuthenticationContext(auth: auth)
        let bobReload = Task { await model.refresh(auth: auth) }
        await bobReload.value
        #expect(model.totalComments == 9)
        #expect(model.phase == .loaded)
        await aliceRelease.fire()
        await aliceReload.value

        #expect(model.totalComments == 9)
        #expect(model.phase == .loaded)
    }

    // MARK: 2. A POST succeeds, switch to B before invalidation → no A mutation reaches B.

    @Test func writeSucceedsButLocalEffectsAreSuppressedAfterAccountSwitch() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")

        let manageHTML = try Self.fixture("ao3_inbox_manage")
        let submitEntered = Signal()
        let submitRelease = Signal()
        let model = AO3InboxModel(
            pageLoader: { _, authArg, _, _, _ in
                if authArg.username == "alice" {
                    return Self.page(manageHTML)
                }
                return Self.page(Self.inboxHTML(total: 0))
            },
            bulkActionSubmitter: { action, _, _, _, _ in
                await submitEntered.fire()
                await submitRelease.wait()
                return action.successMessage
            }
        )

        model.syncAuthenticationContext(auth: auth)
        let initialLoad = Task { await model.refresh(auth: auth) }
        await initialLoad.value
        #expect(model.items.map(\.id) == [9001, 9002, 9003])
        let item = try #require(model.items.first)

        let writeTask = try #require(model.startItemAction(.markRead, item: item, auth: auth))
        await submitEntered.wait()
        #expect(model.isPerformingBulkAction)

        await auth.logout()
        await auth.login(username: "bob", password: "password")
        model.syncAuthenticationContext(auth: auth)
        let bobReload = Task { await model.refresh(auth: auth) }
        await bobReload.value
        // Bob's own fresh load landed and the switch already reset selection —
        // confirmed *before* Alice's write is even allowed to finish.
        #expect(model.items.isEmpty)
        #expect(!model.isPerformingBulkAction)

        // The write itself is single-shot and must still be allowed to reach
        // "AO3" — only its local follow-up (invalidate/reload) is suppressed.
        await submitRelease.fire()
        await writeTask.value

        #expect(model.items.isEmpty)
        #expect(model.actionError == nil)
        #expect(!model.isPerformingBulkAction)
        #expect(auth.isLoggedIn)
        #expect(auth.username == "bob")
    }

    // MARK: 3. Switch during forced reload → old completion ignored.

    @Test func forcedReloadSupersededByASwitchToAThirdAccountIsIgnored() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "bob", password: "password")

        // Bob's first (`activate()`) load resolves immediately; only his
        // *second* call — the forced reload below — is gated.
        var bobCallCount = 0
        var forcedReloadBypassedCache = false
        let retryEntered = Signal()
        let retryRelease = Signal()
        let model = AO3InboxModel(pageLoader: { _, authArg, _, _, bypassCache in
            guard authArg.username == "bob" else { return Self.page(Self.inboxHTML(total: 42)) }
            bobCallCount += 1
            guard bobCallCount == 2 else { return Self.page(Self.inboxHTML(total: 1)) }
            forcedReloadBypassedCache = bypassCache
            await retryEntered.fire()
            await retryRelease.wait()
            return Self.page(Self.inboxHTML(total: 77))
        })

        model.syncAuthenticationContext(auth: auth)
        let initialLoad = Task { await model.refresh(auth: auth) }
        await initialLoad.value
        #expect(model.totalComments == 1)

        // Bob taps "Try Again" — a forced, bypass-cache reload — and it suspends.
        let forcedReload = Task { await model.refresh(auth: auth) }
        await retryEntered.wait()
        #expect(forcedReloadBypassedCache)

        // Keep the stale model token in place until the completion returns. A
        // model-only guard would accept Bob's result here; only the fresh auth
        // generation knows the operation is now obsolete.
        await auth.logout()
        await auth.login(username: "carol", password: "password")
        model.syncAuthenticationContext(auth: auth)
        let carolReload = Task { await model.refresh(auth: auth) }
        await carolReload.value
        await retryRelease.fire()
        await forcedReload.value

        #expect(model.totalComments == 42)
        #expect(model.phase == .loaded)
    }

    // MARK: 4. Same username/new generation does not reuse stale cache.

    @Test func sameUsernameNewGenerationForcesAFreshFetch() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")

        var calls: [(scope: String, bypassCache: Bool)] = []
        let firstFetch = Signal()
        let secondFetch = Signal()
        let model = AO3InboxModel(pageLoader: { _, _, scope, generation, bypassCache in
            calls.append((scope: "\(scope)#session-\(generation)", bypassCache: bypassCache))
            if calls.count == 1 {
                await firstFetch.fire()
            } else {
                await secondFetch.fire()
            }
            return Self.page(Self.inboxHTML(total: calls.count))
        })

        model.activate(auth: auth)
        await firstFetch.wait()
        #expect(calls[0].bypassCache)

        // Re-establish a session for the *same* username without the model
        // ever observing an intermediate "anonymous" `activate()` call — this
        // isolates that the bypass below comes from `sessionGeneration`
        // changing, not from `authenticationScope`'s string happening to
        // differ in between.
        await auth.logout()
        await auth.login(username: "alice", password: "password")

        model.activate(auth: auth)
        await secondFetch.wait()
        #expect(calls[1].bypassCache)
        #expect(calls[0].scope != calls[1].scope)
    }

    // MARK: 5. Logout invalidates pending continuations.

    @Test func logoutInvalidatesAPendingReload() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")

        let entered = Signal()
        let release = Signal()
        let model = AO3InboxModel(pageLoader: { _, _, _, _, _ in
            await entered.fire()
            await release.wait()
            return Self.page(Self.inboxHTML(total: 3))
        })

        model.syncAuthenticationContext(auth: auth)
        let pendingReload = Task { await model.refresh(auth: auth) }
        await entered.wait()

        await auth.logout()
        await release.fire()
        await pendingReload.value

        #expect(model.items.isEmpty)
        #expect(model.totalComments == nil)
        #expect(!auth.isLoggedIn)

        // AccountView performs this transition-only reset without prefetching.
        model.syncAuthenticationContext(auth: auth)
        #expect(model.phase == .idle)
    }

    // MARK: 6. Current-scope operation still completes.

    @Test func currentScopeOperationStillCompletesWithoutAnySwitch() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")

        let entered = Signal()
        let release = Signal()
        let model = AO3InboxModel(pageLoader: { _, _, _, _, _ in
            await entered.fire()
            await release.wait()
            return Self.page(Self.inboxHTML(total: 6))
        })

        model.syncAuthenticationContext(auth: auth)
        let reload = Task { await model.refresh(auth: auth) }
        await entered.wait()
        await release.fire()
        await reload.value
        #expect(model.totalComments == 6)
        #expect(model.phase == .loaded)
    }

    // MARK: 7. Old-scope failure cannot replace B's screen with an error.

    @Test func oldScopeFailureNeitherCorruptsBsScreenNorExpiresBsSession() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")

        let aliceEntered = Signal()
        let aliceRelease = Signal()
        let model = AO3InboxModel(pageLoader: { _, authArg, _, _, _ in
            if authArg.username == "alice" {
                await aliceEntered.fire()
                await aliceRelease.wait()
                // Alice's session was independently kicked out server-side —
                // a completely unrelated failure that must never touch Bob.
                throw AO3Error.authenticationRequired
            }
            return Self.page(Self.inboxHTML(total: 4))
        })

        model.syncAuthenticationContext(auth: auth)
        let aliceReload = Task { await model.refresh(auth: auth) }
        await aliceEntered.wait()

        await auth.logout()
        await auth.login(username: "bob", password: "password")
        await aliceRelease.fire()
        await aliceReload.value

        // Alice's stale authenticationRequired must not have forced Bob's own
        // live session to sign out.
        #expect(auth.isLoggedIn)
        #expect(auth.username == "bob")

        model.syncAuthenticationContext(auth: auth)
        let bobReload = Task { await model.refresh(auth: auth) }
        await bobReload.value
        #expect(model.phase == .loaded)
        #expect(model.totalComments == 4)
    }

    // MARK: Non-cancellable post-write reload

    @Test func postWriteReloadFromOldAccountCannotOverwriteTheNewInbox() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")

        let manageHTML = try Self.fixture("ao3_inbox_manage")
        let reloadEntered = Signal()
        let reloadRelease = Signal()
        var aliceLoadCount = 0
        let model = AO3InboxModel(
            pageLoader: { _, authArg, _, _, _ in
                let username = authArg.username
                if username == "alice" {
                    aliceLoadCount += 1
                    if aliceLoadCount == 1 { return Self.page(manageHTML) }
                    await reloadEntered.fire()
                    await reloadRelease.wait()
                    return Self.page(Self.inboxHTML(total: 99))
                }
                return Self.page(Self.inboxHTML(total: 8))
            },
            bulkActionSubmitter: { action, _, _, _, _ in action.successMessage }
        )

        model.syncAuthenticationContext(auth: auth)
        let initialLoad = Task { await model.refresh(auth: auth) }
        await initialLoad.value
        let item = try #require(model.items.first)

        // `performAction` calls its forced reload directly, outside `activeTask`.
        // This gate therefore covers the original RF3 path rather than a read
        // that `activate()` happens to cancel during the account switch.
        let write = try #require(model.startItemAction(.markRead, item: item, auth: auth))
        await reloadEntered.wait()

        await auth.logout()
        await auth.login(username: "bob", password: "password")
        model.syncAuthenticationContext(auth: auth)
        let bobReload = Task { await model.refresh(auth: auth) }
        await bobReload.value

        await reloadRelease.fire()
        await write.value

        #expect(model.totalComments == 8)
        #expect(model.phase == .loaded)
        #expect(auth.username == "bob")
    }

    // MARK: Queued write start

    @Test func queuedATapCannotSubmitTheEquivalentBRow() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")

        let manageHTML = try Self.fixture("ao3_inbox_manage")
        let writeEntered = Signal()
        let writeRelease = Signal()
        var submittedAs: [String?] = []
        let model = AO3InboxModel(
            pageLoader: { _, _, _, _, _ in Self.page(manageHTML) },
            bulkActionSubmitter: { action, _, _, _, authArg in
                submittedAs.append(authArg.username)
                return action.successMessage
            },
            beforeWriteSubmission: {
                await writeEntered.fire()
                await writeRelease.wait()
            }
        )

        model.syncAuthenticationContext(auth: auth)
        let aliceLoad = Task { await model.refresh(auth: auth) }
        await aliceLoad.value
        let aliceItem = try #require(model.items.first)

        // The synchronous button boundary captures A's form/items/context, then
        // the test parks the task before its first write guard. B deliberately
        // has the same item id and form shape, which is what made a late,
        // task-started item action capable of submitting against B before RF3.
        let queuedWrite = try #require(
            model.startItemAction(.markRead, item: aliceItem, auth: auth)
        )
        await writeEntered.wait()

        await auth.logout()
        await auth.login(username: "bob", password: "password")
        model.syncAuthenticationContext(auth: auth)
        let bobLoad = Task { await model.refresh(auth: auth) }
        await bobLoad.value
        #expect(model.items.map(\.id) == [9001, 9002, 9003])

        await writeRelease.fire()
        await queuedWrite.value

        #expect(submittedAs.isEmpty)
        #expect(auth.username == "bob")
        #expect(!model.isPerformingBulkAction)
    }

    // MARK: Metadata and destination-cache continuations

    @Test func oldScopeMetadataEnrichmentCannotReachANewSession() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")

        let entered = Signal()
        let release = Signal()
        let oldContext = AO3CommentsWorkContext(title: "Alice private", authors: ["Alice"])
        let model = AO3InboxModel(workContextLoader: { _, _ in
            await entered.fire()
            await release.wait()
            return oldContext
        })

        model.syncAuthenticationContext(auth: auth)
        let enrichment = Task {
            await model.enrichVisibleWorkContexts(
                workIDs: [7],
                seededContexts: [:],
                auth: auth
            )
        }
        await entered.wait()

        await auth.logout()
        await auth.login(username: "bob", password: "password")
        await release.fire()
        await enrichment.value

        #expect(model.workContext(for: 7) == nil)
    }

    @Test func oldInboxDestinationCannotCacheContextForANewSession() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")
        let model = AO3InboxModel()
        model.syncAuthenticationContext(auth: auth)
        let aliceGeneration = auth.sessionGeneration

        await auth.logout()
        await auth.login(username: "bob", password: "password")
        model.syncAuthenticationContext(auth: auth)
        model.cacheWorkContext(
            AO3CommentsWorkContext(title: "Alice private", authors: ["Alice"]),
            for: 7,
            sessionGeneration: aliceGeneration,
            auth: auth
        )

        #expect(model.workContext(for: 7) == nil)
    }

    // MARK: Fetcher-level wiring (production default `pageLoader`)
    //
    // Every scenario above injects a custom `pageLoader`, which exercises the
    // model's own `AuthContext` guards but not the production default closure
    // (the wiring that passes `cacheScope`/`isCurrent` into
    // `AO3AuthorProfileFetcher.page`) or that fetcher's own suspension gates.
    // These two close that gap directly, without any live network: a valid
    // `AO3AuthorPageCache.shared` entry is pre-seeded under the exact key the
    // real wiring computes, so the fetcher's cache-hit path — not a network
    // fetch — is what's actually exercised.

    /// `AO3InboxModel()`'s default `pageLoader` must build
    /// `"<scope>#session-<generation>"` and pass it as `AO3AuthorProfileFetcher.page`'s
    /// `cacheScope`, matching the key `AO3AuthorPageCache` tests separately
    /// (`AO3AuthorProfileTests.cacheSeparatesRoutesPagesAndAuthenticationScopes`).
    /// `syncAuthenticationContext` + `goToPage` (rather than `activate`, which
    /// always forces `bypassCache: true` on a first load) reaches the
    /// cache-preferring branch, so a matching seed proves the wiring without
    /// ever needing a real network call.
    @Test func defaultPageLoaderWiresAGenerationQualifiedCacheScopeIntoTheSharedFetcher() async throws {
        let auth = Self.makeAuthService()
        let username = "fetcher-wiring-\(UUID().uuidString.prefix(8))"
        await auth.login(username: username, password: "password")

        let url = try #require(AO3Client.inboxURL(username: username, page: 1))
        let cacheScope = "\(AO3AuthorProfileFetcher.authenticationScope(for: auth))"
            + "#session-\(auth.sessionGeneration)"
        let key = AO3AuthorPageCache.Key(url: url, authenticationScope: cacheScope)
        await AO3AuthorPageCache.shared.insert(Self.inboxHTML(total: 17), for: key)

        let model = AO3InboxModel() // production default pageLoader, not injected
        model.syncAuthenticationContext(auth: auth)
        model.goToPage(1, auth: auth) // bypassCache defaults to false

        let deadline = ContinuousClock.now + Duration.seconds(2)
        while model.phase != .loaded, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(model.phase == .loaded)
        #expect(model.totalComments == 17)
    }

    /// Calls the real `AO3AuthorProfileFetcher.page` directly (bypassing the
    /// model entirely) with an `isCurrent` that reports true for the gate
    /// before the cache lookup's own suspension point, then false for every
    /// gate after — simulating an account switch landing in that exact
    /// window. Even though a valid, matching cache entry is found, the
    /// fetcher's own gate immediately after that await must still reject it
    /// rather than returning the (now-stale) cached HTML.
    @Test func fetcherOwnIsCurrentGateRejectsAStaleCacheHitBeforeReturningIt() async throws {
        let auth = Self.makeAuthService()
        let username = "fetcher-gate-\(UUID().uuidString.prefix(8))"
        await auth.login(username: username, password: "password")

        let url = try #require(AO3Client.inboxURL(username: username, page: 1))
        let cacheScope = "\(AO3AuthorProfileFetcher.authenticationScope(for: auth))"
            + "#session-\(auth.sessionGeneration)"
        let key = AO3AuthorPageCache.Key(url: url, authenticationScope: cacheScope)
        await AO3AuthorPageCache.shared.insert(Self.inboxHTML(total: 3), for: key)

        var isCurrentCallCount = 0
        await #expect(throws: CancellationError.self) {
            _ = try await AO3AuthorProfileFetcher.page(
                at: url,
                auth: auth,
                cacheScope: cacheScope,
                isCurrent: {
                    isCurrentCallCount += 1
                    return isCurrentCallCount <= 1
                },
                bypassCache: false
            )
        }
        #expect(isCurrentCallCount >= 2)

        // The cache entry itself is untouched — only the in-flight read to
        // *this* caller was rejected; a fresh, current-scope read still hits it.
        #expect(await AO3AuthorPageCache.shared.value(for: key) == Self.inboxHTML(total: 3))
    }

    // MARK: T91-RF3/RF5 parity for the other account-list caches
    //
    // `AccountWorksInlineSection`/`AO3AccountListCountsCache`/`AO3AuthService.
    // accountWorks(from:)`/`accountSubscriptions()` all key their private,
    // per-session data through `AO3AuthorProfileFetcher.sessionScopedCacheScope(for:)`
    // now, the same helper the Inbox-specific `AuthContext.cacheScope` above
    // is built on. `AO3AccountListCountsTests.
    // sameUsernameDifferentSessionGenerationDoesNotReuseAStaleCount` covers
    // the cache class itself; this covers the shared helper those call sites
    // actually depend on for correctness.

    @Test func sessionScopedCacheScopeChangesOnASameUsernameRelogin() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")
        let first = AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        #expect(first == "signed-in:alice#session-\(auth.sessionGeneration)")

        // No intermediate `syncAuthenticationContext`/`activate` observes the
        // transient signed-out state in between — isolates that the change
        // below comes from `sessionGeneration`, not from any model-level
        // bookkeeping noticing an "anonymous" scope in passing.
        await auth.logout()
        await auth.login(username: "alice", password: "password")
        let second = AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)

        #expect(first != second)
        #expect(second == "signed-in:alice#session-\(auth.sessionGeneration)")
    }

    @Test func sessionScopedCacheScopeDiffersFromTheBareAuthenticationScope() async throws {
        let auth = Self.makeAuthService()
        await auth.login(username: "alice", password: "password")

        let bare = AO3AuthorProfileFetcher.authenticationScope(for: auth)
        let scoped = AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)

        #expect(bare == "signed-in:alice")
        #expect(scoped == "signed-in:alice#session-\(auth.sessionGeneration)")
        #expect(scoped != bare)
    }
}

/// A one-shot async gate used to deterministically sequence a gated async
/// dependency (`pageLoader`/`bulkActionSubmitter`) against a concurrent
/// account switch — mirrors `AO3RequestCoordinatorTests.Signal`.
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

@MainActor
final class MemoryInboxTestSessionVault: AO3SessionPersisting {
    private var session: AO3Session?
    func load() throws -> AO3Session? { session }
    func save(_ session: AO3Session) throws { self.session = session }
    func delete() throws { session = nil }
}

@MainActor
final class MemoryInboxTestRemovalTracker: AO3SessionRemovalTracking {
    private(set) var isRemovalPending = false
    func markRemovalPending() { isRemovalPending = true }
    func clearRemovalPending() { isRemovalPending = false }
}

@MainActor
struct InboxTestSessionValidator: AO3SessionValidating {
    func validate(_ session: AO3Session) async throws -> AO3SessionValidation { .valid(session) }
}

@MainActor
final class NoOpInboxTestCookieManager: AO3CookieManaging {
    func install(_ session: AO3Session) async {}
    func clear() async {}
    func capture() async -> [AO3StoredCookie] { [] }
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

    func beginManualLogin(
        expectedUsername: String,
        onAuthenticated: @escaping (AO3Session) -> Void,
        onError: @escaping (String) -> Void
    ) {}

    func applyVisibleTheme(_ theme: ReaderTheme) {}
    func cancel() {}
}
