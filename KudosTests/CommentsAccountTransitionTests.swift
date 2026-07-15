import Foundation
import Testing
import WebKit
@testable import Kudos

/// Part C: every Comments read, draft, write, and verification result stays
/// owned by the authentication generation that started it.
@Suite(.serialized)
@MainActor
struct CommentsAccountTransitionTests {
    private static let workContext = AO3CommentsWorkContext(
        title: "Test Work", authors: ["Creator"]
    )

    private static func makeAuth(
        loginPerformer: AO3LoginPerforming? = nil
    ) -> AO3AuthService {
        AO3AuthService(
            vault: MemoryInboxTestSessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: loginPerformer ?? DynamicInboxTestLoginPerformer(),
            cookieManager: NoOpInboxTestCookieManager(),
            removalTracker: MemoryInboxTestRemovalTracker()
        )
    }

    private static func page(id: Int, author: String) -> AO3CommentsPage {
        AO3CommentsPage(comments: [AO3Comment(id: id, author: author, isGuest: false)])
    }

    private static func isolatedDraftStore() -> (
        store: CommentDraftStore, defaults: UserDefaults, suiteName: String
    ) {
        let suiteName = "CommentsAccountTransitionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (CommentDraftStore(defaults: defaults), defaults, suiteName)
    }

    @Test func stalePageCompletionCannotReplaceTheNewAccountsPage() async {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "password")
        let aliceEntered = Signal()
        let aliceRelease = Signal()
        let model = CommentsModel(
            workID: 93_001,
            workContext: Self.workContext,
            pageLoader: { _, _, _, request in
                let cookie = request?.value(forHTTPHeaderField: "Cookie") ?? ""
                if cookie.contains("session-alice") {
                    await aliceEntered.fire()
                    await aliceRelease.wait()
                    return Self.page(id: 1, author: "Alice page")
                }
                return Self.page(id: 2, author: "Bob page")
            },
            pageCache: CommentsPageCache()
        )

        let aliceLoad = Task { await model.load(auth: auth, forceRefresh: true) }
        await aliceEntered.wait()
        await auth.logout()
        await auth.login(username: "bob", password: "password")
        model.syncAuthenticationContext(auth: auth)
        await model.load(auth: auth, forceRefresh: true)
        #expect(model.page?.comments.map(\.id) == [2])

        await aliceRelease.fire()
        await aliceLoad.value
        #expect(model.page?.comments.map(\.id) == [2])
        #expect(model.displayThreads.map(\.author) == ["Bob page"])
    }

    @Test func staleInboxDestinationNeverLoadsUnderTheReplacementAccount() async {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "password")
        let aliceGeneration = auth.sessionGeneration
        var pageLoadCount = 0
        var chapterLoadCount = 0
        let model = CommentsModel(
            workID: 93_010,
            workContext: AO3CommentsWorkContext(
                title: "Alice private title", authors: ["Alice"]
            ),
            requiredSessionGeneration: aliceGeneration,
            initialChapterPosition: 1,
            pageLoader: { _, _, _, _ in
                pageLoadCount += 1
                return AO3CommentsPage()
            },
            chapterLoader: { _, _ in
                chapterLoadCount += 1
                return []
            },
            pageCache: CommentsPageCache()
        )

        await auth.logout()
        await auth.login(username: "bob", password: "password")
        #expect(!model.belongsToCurrentSession(auth: auth))
        await model.loadInitial(auth: auth)
        await model.load(auth: auth, forceRefresh: true)
        await model.loadPage(2, auth: auth, forceRefresh: true)
        await model.loadChaptersIfNeeded(auth: auth)
        model.startComposer(auth: auth)

        #expect(pageLoadCount == 0)
        #expect(chapterLoadCount == 0)
        #expect(model.phase == .idle)
        #expect(model.page == nil)
        #expect(model.composerContext == nil)
    }

    @Test func chapterStateAndCacheAreIsolatedAcrossAccounts() async {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "password")
        let aliceEntered = Signal()
        let aliceRelease = Signal()
        var bobLoadCount = 0
        let aliceChapter = AO3ChapterRef(id: 11, position: 1, title: "Alice private draft")
        let bobChapter = AO3ChapterRef(id: 22, position: 1, title: "Bob chapter")
        let model = CommentsModel(
            workID: 93_002,
            workContext: Self.workContext,
            chapterLoader: { _, request in
                let cookie = request?.value(forHTTPHeaderField: "Cookie") ?? ""
                if cookie.contains("session-alice") {
                    await aliceEntered.fire()
                    await aliceRelease.wait()
                    return [aliceChapter]
                }
                bobLoadCount += 1
                return [bobChapter]
            },
            pageCache: CommentsPageCache()
        )
        model.syncAuthenticationContext(auth: auth)
        model.scope = .byChapter
        model.selectedChapter = aliceChapter

        let aliceLoad = Task { await model.loadChaptersIfNeeded(auth: auth) }
        await aliceEntered.wait()
        await auth.logout()
        await auth.login(username: "bob", password: "password")
        model.syncAuthenticationContext(auth: auth)
        #expect(model.scope == .all)
        #expect(model.selectedChapter == nil)
        #expect(model.chapters.isEmpty)

        await model.loadChaptersIfNeeded(auth: auth)
        #expect(bobLoadCount == 1)
        #expect(model.chapters == [bobChapter])
        await aliceRelease.fire()
        await aliceLoad.value
        #expect(model.chapters == [bobChapter])
    }

    @Test func sameUsernameReloginPerformsAColdPageLoad() async {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "password")
        var loadCount = 0
        let model = CommentsModel(
            workID: 93_003,
            workContext: Self.workContext,
            pageLoader: { _, _, _, _ in
                loadCount += 1
                return Self.page(id: loadCount, author: "Alice")
            },
            pageCache: CommentsPageCache()
        )

        await model.load(auth: auth)
        #expect(model.page?.comments.map(\.id) == [1])
        await auth.logout()
        await auth.login(username: "alice", password: "password")
        model.syncAuthenticationContext(auth: auth)
        await model.load(auth: auth)

        #expect(loadCount == 2)
        #expect(model.page?.comments.map(\.id) == [2])
    }

    @Test func missingApplicableAuthCookieNeverFallsBackToAnonymousReads() async {
        let auth = Self.makeAuth(loginPerformer: WrongPathCommentsLoginPerformer())
        await auth.login(username: "alice", password: "password")
        #expect(auth.isLoggedIn)
        var pageLoadCount = 0
        var chapterLoadCount = 0
        let model = CommentsModel(
            workID: 93_004,
            workContext: Self.workContext,
            pageLoader: { _, _, _, _ in
                pageLoadCount += 1
                return AO3CommentsPage()
            },
            chapterLoader: { _, _ in
                chapterLoadCount += 1
                return []
            },
            pageCache: CommentsPageCache()
        )

        await model.load(auth: auth, forceRefresh: true)
        #expect(pageLoadCount == 0)
        #expect(model.phase == .failed("Log in to AO3 to do that."))
        await model.loadChaptersIfNeeded(auth: auth)
        #expect(chapterLoadCount == 0)
        #expect(model.chaptersFailureMessage == "Log in to AO3 to do that.")

        do {
            _ = try await auth.verifyCommentPosted(
                context: AO3CommentContext(workID: 93_004),
                body: "hello",
                expectedGeneration: auth.sessionGeneration
            )
            Issue.record("expected verification to require authentication")
        } catch AO3Error.authenticationRequired {
            // Expected: never make an anonymous verification request.
        } catch {
            Issue.record("expected authenticationRequired, got \(error)")
        }
    }

    @Test func draftsFollowTheUsernameAcrossAccountSwitchesAndRelogin() async {
        let auth = Self.makeAuth()
        let isolated = Self.isolatedDraftStore()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }
        let model = CommentsModel(
            workID: 93_005,
            workContext: Self.workContext,
            draftStore: isolated.store,
            pageCache: CommentsPageCache()
        )

        await auth.login(username: "alice", password: "password")
        model.startComposer(auth: auth)
        model.composerText = "Alice draft"
        model.saveDraft()

        await auth.logout()
        await auth.login(username: "bob", password: "password")
        model.syncAuthenticationContext(auth: auth)
        model.startComposer(auth: auth)
        #expect(model.composerText.isEmpty)
        model.composerText = "Bob draft"
        model.saveDraft()

        await auth.logout()
        await auth.login(username: "alice", password: "password")
        model.syncAuthenticationContext(auth: auth)
        model.startComposer(auth: auth)
        #expect(model.composerText == "Alice draft")
        #expect(isolated.store.draft(
            for: AO3CommentContext(workID: 93_005), identity: "bob"
        ) == "Bob draft")
    }

    @Test func unknownSignedInUsernamesKeepDraftsGenerationLocal() async {
        let auth = Self.makeAuth(loginPerformer: UnknownUsernameCommentsLoginPerformer())
        let isolated = Self.isolatedDraftStore()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }
        let model = CommentsModel(
            workID: 93_011,
            workContext: Self.workContext,
            draftStore: isolated.store,
            pageCache: CommentsPageCache()
        )

        await auth.login(username: "alice", password: "password")
        #expect(auth.isLoggedIn)
        #expect(auth.username == "")
        model.startComposer(auth: auth)
        model.composerText = "Unknown Alice draft"
        model.saveDraft()

        await auth.logout()
        await auth.login(username: "bob", password: "password")
        #expect(auth.isLoggedIn)
        #expect(auth.username == "")
        model.syncAuthenticationContext(auth: auth)
        model.startComposer(auth: auth)

        #expect(model.composerText.isEmpty)
    }

    @Test func staleSuccessfulSubmitCannotClearOrCloseTheNewAccountsComposer() async {
        let auth = Self.makeAuth()
        let isolated = Self.isolatedDraftStore()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }
        let submitEntered = Signal()
        let submitRelease = Signal()
        var capturedGeneration = -1
        var pageLoadCount = 0
        let model = CommentsModel(
            workID: 93_006,
            workContext: Self.workContext,
            pageLoader: { _, _, _, _ in
                pageLoadCount += 1
                return AO3CommentsPage()
            },
            commentSubmitter: { _, _, _, generation, _, onFormPrepared in
                capturedGeneration = generation
                onFormPrepared(true)
                await submitEntered.fire()
                await submitRelease.wait()
            },
            submissionGuard: CommentSubmissionGuard(),
            draftStore: isolated.store,
            pageCache: CommentsPageCache()
        )

        await auth.login(username: "alice", password: "password")
        model.startComposer(auth: auth)
        model.composerText = "Alice draft"
        model.saveDraft()
        let submit = Task { await model.submit(auth: auth) }
        await submitEntered.wait()

        await auth.logout()
        await auth.login(username: "bob", password: "password")
        model.syncAuthenticationContext(auth: auth)
        model.startComposer(auth: auth)
        model.composerText = "Bob draft"
        model.saveDraft()
        #expect(throws: CancellationError.self) {
            try auth.requireSessionGeneration(capturedGeneration)
        }

        await submitRelease.fire()
        await submit.value
        #expect(model.composerText == "Bob draft")
        #expect(model.composerContext != nil)
        #expect(model.submissionGuard.phase == .idle)
        #expect(pageLoadCount == 0)
        #expect(isolated.store.draft(
            for: AO3CommentContext(workID: 93_006), identity: "alice"
        ) == "Alice draft")
        #expect(isolated.store.draft(
            for: AO3CommentContext(workID: 93_006), identity: "bob"
        ) == "Bob draft")
    }

    @Test func staleOwnerActionsCannotOpenUnderTheReplacementAccount() async {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "password")
        var aliceComment = AO3Comment(id: 61, author: "Alice", isGuest: false)
        aliceComment.canReply = true
        aliceComment.editPath = "/comments/61/edit"
        aliceComment.deletePath = "/comments/61"
        let model = CommentsModel(
            workID: 93_009,
            workContext: Self.workContext,
            pageLoader: { _, _, _, _ in AO3CommentsPage(comments: [aliceComment]) },
            pageCache: CommentsPageCache()
        )
        await model.load(auth: auth, forceRefresh: true)

        await auth.logout()
        await auth.login(username: "bob", password: "password")
        model.startEditing(aliceComment, auth: auth)
        #expect(model.composerContext == nil)
        model.startComposer(replyingTo: aliceComment, auth: auth)
        #expect(model.composerContext == nil)
        #expect(model.deletableComment(aliceComment, auth: auth) == nil)
    }

    @Test func staleVerificationCannotResolveTheNewAccountsGuard() async {
        let auth = Self.makeAuth()
        let isolated = Self.isolatedDraftStore()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }
        let verifyEntered = Signal()
        let verifyRelease = Signal()
        var verifierGeneration = -1
        let model = CommentsModel(
            workID: 93_007,
            workContext: Self.workContext,
            commentSubmitter: { _, _, _, _, _, onFormPrepared in
                onFormPrepared(true)
                throw AO3WriteError.unconfirmed
            },
            commentVerifier: { _, _, _, _, generation, _ in
                verifierGeneration = generation
                await verifyEntered.fire()
                await verifyRelease.wait()
                return .found
            },
            submissionGuard: CommentSubmissionGuard(),
            draftStore: isolated.store,
            pageCache: CommentsPageCache()
        )

        await auth.login(username: "alice", password: "password")
        model.startComposer(auth: auth)
        model.composerText = "Alice draft"
        model.saveDraft()
        let submit = Task { await model.submit(auth: auth) }
        await verifyEntered.wait()

        await auth.logout()
        await auth.login(username: "bob", password: "password")
        model.syncAuthenticationContext(auth: auth)
        model.startComposer(auth: auth)
        model.composerText = "Bob draft"
        model.saveDraft()
        #expect(verifierGeneration != auth.sessionGeneration)

        await verifyRelease.fire()
        await submit.value
        #expect(model.composerText == "Bob draft")
        #expect(model.composerContext != nil)
        #expect(model.submissionGuard.phase == .idle)
        #expect(isolated.store.draft(
            for: AO3CommentContext(workID: 93_007), identity: "alice"
        ) == "Alice draft")
        #expect(isolated.store.draft(
            for: AO3CommentContext(workID: 93_007), identity: "bob"
        ) == "Bob draft")
    }

    @Test func verifiedWorkScopeSuccessClearsTheOriginChapterDraft() async {
        let auth = Self.makeAuth()
        await auth.login(username: "alice", password: "password")
        let isolated = Self.isolatedDraftStore()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }
        let unresolved = UnresolvedCommentSubmissionStore()
        let chapter = AO3CommentContext(workID: 93_008, chapterID: 77)
        let all = AO3CommentContext(workID: 93_008)
        isolated.store.save("same draft", for: chapter, identity: "alice")
        isolated.store.save("same draft", for: all, identity: "alice")

        let chapterModel = CommentsModel(
            workID: 93_008,
            workContext: Self.workContext,
            commentSubmitter: { _, _, _, _, _, _ in
                throw AO3WriteError.unconfirmed
            },
            commentVerifier: { _, _, _, _, _, _ in .unknown },
            submissionGuard: CommentSubmissionGuard(store: unresolved),
            draftStore: isolated.store,
            pageCache: CommentsPageCache()
        )
        chapterModel.syncAuthenticationContext(auth: auth)
        chapterModel.scope = .byChapter
        chapterModel.selectedChapter = AO3ChapterRef(
            id: 77, position: 1, title: "Chapter"
        )
        chapterModel.startComposer(auth: auth)
        await chapterModel.submit(auth: auth)
        guard case .ambiguous = chapterModel.submissionGuard.phase else {
            Issue.record("expected the chapter attempt to stay ambiguous")
            return
        }

        let workModel = CommentsModel(
            workID: 93_008,
            workContext: Self.workContext,
            pageLoader: { _, _, _, _ in AO3CommentsPage() },
            commentVerifier: { _, _, _, _, _, _ in .found },
            submissionGuard: CommentSubmissionGuard(store: unresolved),
            draftStore: isolated.store,
            pageCache: CommentsPageCache()
        )
        workModel.startComposer(auth: auth)
        guard case .ambiguous = workModel.submissionGuard.phase else {
            Issue.record("expected work scope to adopt the chapter attempt")
            return
        }
        await workModel.reverify(auth: auth)

        #expect(isolated.store.draft(for: chapter, identity: "alice").isEmpty)
        #expect(isolated.store.draft(for: all, identity: "alice").isEmpty)
        #expect(workModel.submissionGuard.phase == .succeeded)
    }
}

@MainActor
private final class WrongPathCommentsLoginPerformer: AO3LoginPerforming {
    lazy var webView = WKWebView()

    func login(username: String, password: String) async throws -> AO3Session {
        AO3Session(
            username: username,
            cookies: [AO3StoredCookie(
                name: "_otwarchive_session",
                value: "wrong-path",
                path: "/users/not-comments"
            )]
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

@MainActor
private final class UnknownUsernameCommentsLoginPerformer: AO3LoginPerforming {
    lazy var webView = WKWebView()

    func login(username: String, password: String) async throws -> AO3Session {
        AO3Session(
            username: "",
            cookies: [AO3StoredCookie(
                name: "_otwarchive_session", value: "session-\(username)"
            )]
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
