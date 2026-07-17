import Foundation
import SwiftUI

/// Screen state + fetch logic for the native AO3 comments UI.
///
/// Networking respect (see `docs/ai/COMMENTS_HANDOFF.md`): every request maps to
/// an explicit user action — opening the screen, switching chapter/page/order,
/// or pull-to-refresh. Pages are cached for this Comments session, under a short
/// TTL, so re-visits don't re-fetch, and nothing loads eagerly, in the background,
/// or per-chapter in bulk.
@MainActor
@Observable
final class CommentsModel {
    private struct AuthContext: Equatable {
        let identity: String
        let cacheScope: String
        let generation: Int

        static func current(_ auth: AO3AuthService) -> AuthContext {
            let username = auth.username?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let knownUsername = username.flatMap {
                !$0.isEmpty && $0.caseInsensitiveCompare("AO3 Account") != .orderedSame
                    ? $0 : nil
            }
            // Offline restore can know that a session exists without knowing
            // which account owns it. Keep those drafts session-local instead
            // of collapsing every unknown account into the empty identity.
            let identity = knownUsername
                ?? (auth.isLoggedIn ? "unknown-session:\(auth.sessionGeneration)" : "")
            return AuthContext(
                identity: identity,
                cacheScope: AO3AuthorProfileFetcher.authenticationScope(for: auth),
                generation: auth.sessionGeneration
            )
        }
    }

    typealias PageLoader = @MainActor (
        _ workID: Int, _ chapterID: Int?, _ page: Int, _ request: URLRequest?
    ) async throws -> AO3CommentsPage
    typealias ChapterLoader = @MainActor (
        _ workID: Int, _ request: URLRequest?
    ) async throws -> [AO3ChapterRef]
    typealias CommentSubmitter = @MainActor (
        _ context: AO3CommentContext, _ editTarget: AO3Comment?, _ body: String,
        _ expectedGeneration: Int, _ auth: AO3AuthService,
        _ onFormPrepared: @escaping @MainActor (Bool) -> Void
    ) async throws -> Void
    typealias CommentVerifier = @MainActor (
        _ context: AO3CommentContext, _ body: String, _ submittedAt: Date?,
        _ commentMayBeHidden: Bool, _ expectedGeneration: Int,
        _ auth: AO3AuthService
    ) async throws -> AO3AuthService.CommentVerification
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum Scope: String, CaseIterable, Identifiable {
        case all = "All"
        case byChapter = "By Chapter"
        var id: String { rawValue }
    }

    let workID: Int
    /// Inbox destinations contain private account-scoped context and must not
    /// survive the session that created them. Other entry points leave this nil.
    private let requiredSessionGeneration: Int?
    private let initialWorkContext: AO3CommentsWorkContext
    /// Mutable because Inbox starts with a sparse notification summary and then
    /// enriches it from the canonical work page. Keeping one value prevents the
    /// Author badges and the work-summary card from observing different caches.
    private(set) var workContext: AO3CommentsWorkContext

    var workAuthors: [String] { workContext.authors }
    var workAuthorIdentities: [AO3AuthorIdentity] { workContext.authorIdentities }

    private(set) var phase: Phase = .idle
    private(set) var page: AO3CommentsPage?
    private(set) var currentPageNumber = 1
    /// The last load failed because the device appears offline; posting is
    /// disabled and cached content is labeled stale.
    private(set) var isOffline = false
    /// Serving a cached page (shown with its fetch time when offline/stale).
    private(set) var isFromCache = false
    /// Root comment nodes in the current display order. Each node keeps its full
    /// direct-reply tree so the view can render replies recursively inside the
    /// specific comment they answer.
    private(set) var displayThreads: [AO3Comment] = []

    var scope: Scope = .all
    private(set) var chapters: [AO3ChapterRef] = []
    private(set) var chaptersFailureMessage: String?
    var chaptersFailed: Bool { chaptersFailureMessage != nil }
    var selectedChapter: AO3ChapterRef?
    /// A 1-based AO3 story-chapter to open on (from the reader's chapter-aware
    /// Comments button), applied once by `loadInitial`. nil = open on All.
    private var pendingInitialChapterPosition: Int?
    /// A notification comment whose standalone AO3 thread should be loaded on
    /// first open. This bounded lookup avoids scanning paginated work comments.
    private var pendingInitialCommentID: Int?
    private var pendingInitialFocusesChapter = false
    /// Inbox's Reply control uses the same focused-thread load, then opens the
    /// existing composer against this exact notification comment.
    private var pendingInitialReplyCommentID: Int?
    /// Consumed by `CommentsView` after the focused thread has materialized.
    private(set) var initialFocusCommentID: Int?
    /// True only while `loadInitial` is programmatically setting scope/chapter, so
    /// the view's scope/selectedChapter `onChange` handlers skip the redundant loads
    /// they'd otherwise stack on the single load `loadInitial` already performs.
    private(set) var isApplyingInitialContext = false
    /// Local rendering order — AO3 itself has no comment sort; newest-first
    /// starts from the last page and reverses within each page. Changing this
    /// always re-fetches the correct target page (the view's `onChange` resets
    /// and reloads) rather than reversing whatever page happens to be cached —
    /// on a multi-page thread, the current page usually isn't the target page.
    var newestFirst = false

    // Composer
    var composerContext: AO3CommentContext?
    /// The comment being replied to (quoted in the composer), nil for top-level.
    var composerParent: AO3Comment?
    /// When set, the composer is editing this existing comment (PUT, not POST).
    var composerEditTarget: AO3Comment?
    var composerText = ""
    // Shares the process-lifetime unresolved-submission store across every
    // CommentsModel instance (a fresh one is created whenever the Comments
    // screen or its Reply target changes), so an ambiguous submission stays
    // blocked across that recreation instead of resetting with it.
    let submissionGuard: CommentSubmissionGuard
    private let drafts: CommentDraftStore

    /// Scoped to this one Comments-viewing session — owned per instance (not a
    /// shared singleton) so it lives and dies with the screen, per `CommentsView`
    /// constructing a fresh `CommentsModel` via `@State` on every open. Injectable
    /// so tests can hand in their own instance.
    private let cache: CommentsPageCache
    private var authContext = AuthContext(identity: "", cacheScope: "", generation: -1)
    private let pageLoader: PageLoader
    private let chapterLoader: ChapterLoader
    private let commentSubmitter: CommentSubmitter
    private let commentVerifier: CommentVerifier

    init(
        workID: Int,
        workContext: AO3CommentsWorkContext,
        requiredSessionGeneration: Int? = nil,
        initialChapterPosition: Int? = nil,
        initialCommentID: Int? = nil,
        initialFocusesChapter: Bool = false,
        initialReplyCommentID: Int? = nil,
        pageLoader: @escaping PageLoader = { workID, chapterID, page, request in
            try await AO3Client.shared.commentsPage(
                workID: workID, chapterID: chapterID, page: page, request: request
            )
        },
        chapterLoader: @escaping ChapterLoader = { workID, request in
            try await AO3Client.shared.chapterIndex(workID: workID, request: request)
        },
        commentSubmitter: @escaping CommentSubmitter = CommentsModel.submitComment,
        commentVerifier: @escaping CommentVerifier = { context, body, submittedAt, hidden, expectedGeneration, auth in
            try await auth.verifyCommentPosted(
                context: context,
                body: body,
                submittedAt: submittedAt,
                commentMayBeHidden: hidden,
                expectedGeneration: expectedGeneration
            )
        },
        submissionGuard: CommentSubmissionGuard? = nil,
        draftStore: CommentDraftStore? = nil,
        pageCache: CommentsPageCache? = nil
    ) {
        self.workID = workID
        self.requiredSessionGeneration = requiredSessionGeneration
        self.initialWorkContext = workContext
        self.workContext = workContext
        self.pendingInitialChapterPosition = initialChapterPosition
        self.pendingInitialCommentID = initialCommentID
        self.pendingInitialFocusesChapter = initialFocusesChapter
        self.pendingInitialReplyCommentID = initialReplyCommentID
        self.pageLoader = pageLoader
        self.chapterLoader = chapterLoader
        self.commentSubmitter = commentSubmitter
        self.commentVerifier = commentVerifier
        self.submissionGuard = submissionGuard ?? CommentSubmissionGuard(store: .shared)
        self.drafts = draftStore ?? CommentDraftStore()
        self.cache = pageCache ?? CommentsPageCache()
    }

    var chapterForRequests: Int? {
        scope == .byChapter ? selectedChapter?.id : nil
    }

    func belongsToCurrentSession(auth: AO3AuthService) -> Bool {
        requiredSessionGeneration == nil || requiredSessionGeneration == auth.sessionGeneration
    }

    @discardableResult
    func syncAuthenticationContext(auth: AO3AuthService) -> Bool {
        guard belongsToCurrentSession(auth: auth) else { return false }
        let current = AuthContext.current(auth)
        guard current != authContext else { return false }
        let hadContext = authContext.generation >= 0
        if hadContext, let composerContext, composerEditTarget == nil {
            drafts.save(composerText, for: composerContext, identity: authContext.identity)
        }
        authContext = current
        guard hadContext else { return true }
        page = nil
        displayThreads = []
        chapters = []
        chaptersFailureMessage = nil
        scope = .all
        selectedChapter = nil
        currentPageNumber = 1
        initialFocusCommentID = nil
        pendingInitialChapterPosition = nil
        pendingInitialCommentID = nil
        pendingInitialFocusesChapter = false
        pendingInitialReplyCommentID = nil
        isApplyingInitialContext = false
        composerContext = nil
        composerParent = nil
        composerEditTarget = nil
        composerText = ""
        submissionGuard.resetForAuthenticationChange()
        workContext = initialWorkContext
        isOffline = false
        isFromCache = false
        phase = .idle
        return true
    }

    private func isCurrent(_ expected: AuthContext, _ auth: AO3AuthService) -> Bool {
        expected == authContext && expected == AuthContext.current(auth)
    }

    private func authenticatedRequest(for url: URL, auth: AO3AuthService) throws -> URLRequest? {
        guard auth.isLoggedIn else { return nil }
        do {
            return try auth.authenticatedRequest(for: url)
        } catch {
            throw AO3Error.authenticationRequired
        }
    }

    // MARK: Loading

    /// Clears the shown page when the scope/chapter changes, so the list shows
    /// the skeleton for the new context instead of the previous scope's comments.
    func resetForContextChange() {
        page = nil
        displayThreads = []
        phase = .idle
        currentPageNumber = 1
    }

    /// The screen's first load. With no preselected chapter it's a plain All load;
    /// with one (the reader's chapter-aware Comments button) it resolves that AO3
    /// story-chapter against the live `/navigate` index and opens By Chapter on it,
    /// falling back to All if the index is unavailable or empty. Runs one page fetch
    /// (plus the small chapter index) — the `isApplyingInitialContext` flag keeps the
    /// view's onChange handlers from firing extra loads while scope/chapter are set.
    func loadInitial(auth: AO3AuthService) async {
        guard belongsToCurrentSession(auth: auth) else { return }
        syncAuthenticationContext(auth: auth)
        let expected = authContext
        if let commentID = pendingInitialCommentID {
            await loadFocusedThread(commentID: commentID, auth: auth)
            guard isCurrent(expected, auth) else { return }
            if phase == .loaded { pendingInitialCommentID = nil }
            return
        }
        guard let target = pendingInitialChapterPosition else {
            await load(auth: auth, expected: expected)
            return
        }
        pendingInitialChapterPosition = nil
        isApplyingInitialContext = true
        defer {
            if isCurrent(expected, auth) { isApplyingInitialContext = false }
        }

        await loadChaptersIfNeeded(auth: auth, expected: expected)
        guard isCurrent(expected, auth) else { return }
        guard let ref = chapterRef(forStoryPosition: target) else {
            // Index failed or the work has no chapter list (e.g. single-chapter):
            // work-level All comments show the same thread anyway.
            await load(auth: auth, expected: expected)
            return
        }
        scope = .byChapter
        selectedChapter = ref
        await load(auth: auth, expected: expected)
    }

    /// Loads the exact Inbox notification thread. AO3's standalone comment page
    /// tells us whether this is a reply via its rendered Parent Thread action; a
    /// reply then costs one additional explicit GET for that root. This remains
    /// bounded at two comment requests and never crawls work/chapter pages.
    private func loadFocusedThread(commentID: Int, auth: AO3AuthService) async {
        let expected = AuthContext.current(auth)
        guard isCurrent(expected, auth) else { return }
        let requestedChapterPosition = pendingInitialChapterPosition
        pendingInitialChapterPosition = nil
        isApplyingInitialContext = true
        defer {
            if isCurrent(expected, auth) { isApplyingInitialContext = false }
        }

        phase = .loading
        do {
            let targetPage = try await fetchStandaloneThread(
                commentID: commentID, auth: auth, expected: expected
            )
            guard isCurrent(expected, auth) else { return }
            guard let rootID = Self.focusedRootID(
                notificationCommentID: commentID, in: targetPage
            ) else { throw AO3Error.parse }
            let focusedPage: AO3CommentsPage
            if rootID == commentID {
                focusedPage = targetPage
            } else {
                focusedPage = try await fetchStandaloneThread(
                    commentID: rootID, auth: auth, expected: expected
                )
                guard isCurrent(expected, auth) else { return }
            }
            guard focusedPage.comments.contains(where: { $0.contains(commentID: rootID) }) else {
                throw AO3Error.parse
            }

            var presentedPage = focusedPage
            if pendingInitialFocusesChapter {
                var chapter = Self.chapterRef(in: focusedPage)
                if chapter == nil, let requestedChapterPosition {
                    await loadChaptersIfNeeded(auth: auth, expected: expected)
                    guard isCurrent(expected, auth) else { return }
                    chapter = chapterRef(forStoryPosition: requestedChapterPosition)
                }
                guard let chapter else { throw AO3Error.parse }
                scope = .byChapter
                selectedChapter = chapter

                // The Chapter control promises the chapter's comments, not a
                // mislabeled isolated-thread screen. Fetch its real first page,
                // then include the explicitly requested root if it lives on a
                // later AO3 page so focus remains deterministic without crawling.
                guard let chapterPage = await fetchPage(
                    1, auth: auth, forceRefresh: false, expected: expected
                ) else { return }
                guard isCurrent(expected, auth) else { return }
                presentedPage = Self.chapterPage(
                    chapterPage,
                    including: focusedPage,
                    focusedRootID: rootID
                )
            }

            absorbWorkAuthors(from: presentedPage)
            // Standalone and chapter comment pages can supply creator identities,
            // but not rating/fandom/chapter totals. This explicit Inbox navigation
            // resolves any missing summary fields with at most one work request.
            if workContext.needsSummaryEnrichment {
                await enrichWorkContextIfNeeded(auth: auth, expected: expected)
                guard isCurrent(expected, auth) else { return }
            }
            if let replyID = pendingInitialReplyCommentID,
               !presentedPage.comments.contains(where: { $0.contains(commentID: replyID) }) {
                throw AO3Error.parse
            }

            page = presentedPage
            rebuildDisplayThreads()
            currentPageNumber = 1
            initialFocusCommentID = rootID
            isOffline = false
            isFromCache = false
            phase = .loaded
            if let replyID = pendingInitialReplyCommentID,
               let target = presentedPage.comments
                   .flatMap(\.flattened)
                   .first(where: { $0.id == replyID }) {
                pendingInitialReplyCommentID = nil
                startComposer(replyingTo: target, auth: auth)
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard isCurrent(expected, auth) else { return }
            isOffline = Self.isOfflineError(error)
            phase = .failed(Self.message(for: error))
        }
    }

    /// Retry the screen's original intent. A focused Inbox failure must not turn
    /// the Try Again button into an ordinary work-comments load.
    func retryInitialLoad(auth: AO3AuthService) async {
        guard belongsToCurrentSession(auth: auth) else { return }
        if pendingInitialCommentID != nil {
            await loadInitial(auth: auth)
        } else {
            await load(auth: auth, forceRefresh: true)
        }
    }

    private func fetchStandaloneThread(
        commentID: Int, auth: AO3AuthService, expected: AuthContext
    ) async throws -> AO3CommentsPage {
        guard isCurrent(expected, auth) else { throw CancellationError() }
        let url = AO3Client.commentThreadURL(commentID: commentID)
        let request = try authenticatedRequest(for: url, auth: auth)
        let page = try await AO3Client.shared.commentThreadPage(
            commentID: commentID, request: request
        )
        guard isCurrent(expected, auth) else { throw CancellationError() }
        return page
    }

    private func enrichWorkContextIfNeeded(
        auth: AO3AuthService, expected: AuthContext
    ) async {
        guard isCurrent(expected, auth),
              workContext.needsSummaryEnrichment,
              let url = URL(string: "https://archiveofourown.org/works/\(workID)?view_adult=true")
        else { return }
        do {
            let request = try authenticatedRequest(for: url, auth: auth)
            let metadata = try await AO3Client.shared.workMetadata(
                workID: workID, request: request
            )
            guard isCurrent(expected, auth) else { return }
            workContext = workContext.merging(AO3CommentsWorkContext(metadata: metadata))
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            // The comment thread itself is already loaded. Keep registered
            // commenters as User instead of turning optional badge enrichment
            // into a navigation failure.
        }
    }

    private func absorbWorkAuthors(from page: AO3CommentsPage) {
        guard !page.workAuthors.isEmpty else { return }
        workContext = workContext.merging(AO3CommentsWorkContext(
            title: "",
            authors: page.workAuthors,
            authorIdentities: page.workAuthorIdentities
        ))
    }

    /// A standalone root comment on a multichapter work carries the exact AO3
    /// chapter id in its byline, so the Chapter tap can enter By Chapter without
    /// a separate `/navigate` lookup in the normal case.
    nonisolated static func chapterRef(in page: AO3CommentsPage) -> AO3ChapterRef? {
        guard let comment = page.comments
            .flatMap(\.flattened)
            .first(where: { $0.chapterID != nil }),
              let chapterID = comment.chapterID
        else { return nil }
        let position = comment.chapterLabel?
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .first ?? 1
        return AO3ChapterRef(id: chapterID, position: position, title: "")
    }

    /// AO3's standalone reply renders a Parent Thread action pointing at the
    /// owning root; top-level comments omit it and focus themselves.
    nonisolated static func focusedRootID(
        notificationCommentID: Int, in page: AO3CommentsPage
    ) -> Int? {
        guard let comment = page.comments
            .flatMap(\.flattened)
            .first(where: { $0.id == notificationCommentID })
        else { return nil }
        return comment.parentCommentID ?? comment.id
    }

    /// Preserves AO3's real chapter-page pagination while making the explicitly
    /// requested thread visible. No insertion occurs when that root is already
    /// present, so page-one content never duplicates it.
    nonisolated static func chapterPage(
        _ chapterPage: AO3CommentsPage,
        including focusedPage: AO3CommentsPage,
        focusedRootID: Int
    ) -> AO3CommentsPage {
        guard !chapterPage.comments.contains(where: { $0.contains(commentID: focusedRootID) }),
              let root = focusedPage.comments.first(where: {
                  $0.contains(commentID: focusedRootID)
              })
        else { return chapterPage }
        var result = chapterPage
        result.comments.insert(root, at: 0)
        return result
    }

    /// Maps a 1-based AO3 story-chapter number (already normalized by the reader
    /// against Preface/Summary/Afterword) to an actual chapter ref from `/navigate`,
    /// clamped into range so an over-count (e.g. Afterword past the last real chapter)
    /// lands on the last chapter. nil when the index is empty/unavailable.
    func chapterRef(forStoryPosition position: Int) -> AO3ChapterRef? {
        guard let clamped = Self.clampedChapterPosition(position, chapterCount: chapters.count) else {
            return nil
        }
        return chapters.first { $0.position == clamped } ?? chapters.last
    }

    /// Clamps a target story-chapter number into `1...chapterCount`; nil when there
    /// are no chapters. Pure (nonisolated) so it's unit-testable off the main actor.
    nonisolated static func clampedChapterPosition(_ position: Int, chapterCount: Int) -> Int? {
        guard chapterCount > 0 else { return nil }
        return min(max(position, 1), chapterCount)
    }

    /// Initial load (or scope/chapter/order change). Serves fresh cache instantly;
    /// otherwise fetches exactly one page.
    func load(
        auth: AO3AuthService,
        forceRefresh: Bool = false,
        expectedGeneration: Int? = nil
    ) async {
        guard belongsToCurrentSession(auth: auth) else { return }
        guard expectedGeneration == nil || auth.sessionGeneration == expectedGeneration else {
            return
        }
        syncAuthenticationContext(auth: auth)
        let expected = authContext
        await load(auth: auth, forceRefresh: forceRefresh, expected: expected)
    }

    private func load(
        auth: AO3AuthService, forceRefresh: Bool = false,
        expected: AuthContext
    ) async {
        guard isCurrent(expected, auth) else { return }
        // Newest-first starts at the last page; we may need one fetch of page 1
        // first to learn the page count (cached afterwards).
        var target = 1
        if newestFirst {
            if let known = knownTotalPages() {
                target = known
            } else if let first = await fetchPage(
                1, auth: auth, forceRefresh: forceRefresh, expected: expected
            ) {
                guard isCurrent(expected, auth) else { return }
                target = first.totalPages
            } else {
                return // fetchPage set the failure phase
            }
        }
        guard isCurrent(expected, auth) else { return }
        await loadPage(
            target, auth: auth, forceRefresh: forceRefresh, expected: expected
        )
    }

    func loadPage(_ number: Int, auth: AO3AuthService, forceRefresh: Bool = false) async {
        guard belongsToCurrentSession(auth: auth) else { return }
        syncAuthenticationContext(auth: auth)
        let expected = authContext
        await loadPage(
            number, auth: auth, forceRefresh: forceRefresh, expected: expected
        )
    }

    private func loadPage(
        _ number: Int, auth: AO3AuthService, forceRefresh: Bool,
        expected: AuthContext
    ) async {
        guard isCurrent(expected, auth) else { return }
        guard let fetched = await fetchPage(
            number, auth: auth, forceRefresh: forceRefresh, expected: expected
        ), isCurrent(expected, auth) else {
            return
        }
        absorbWorkAuthors(from: fetched)
        page = fetched
        rebuildDisplayThreads()
        currentPageNumber = fetched.currentPage
        phase = .loaded
    }

    private func rebuildDisplayThreads() {
        guard let page else {
            displayThreads = []
            return
        }
        displayThreads = Self.orderedDisplayThreads(
            from: page.comments, newestFirst: newestFirst
        )
    }

    /// Root-thread display order for a fetched page. Newest-first reverses only
    /// the top-level roots; each root keeps its full reply tree intact so the
    /// view can nest cards under the immediate parent (T-86). Pure so tests can
    /// pin the contract without standing up a live model load.
    nonisolated static func orderedDisplayThreads(
        from comments: [AO3Comment], newestFirst: Bool
    ) -> [AO3Comment] {
        newestFirst ? Array(comments.reversed()) : comments
    }

    /// The top-level root that owns `commentID` (itself or a descendant), used
    /// to materialize the List row before scrolling to a nested `.id`.
    func rootID(containing commentID: Int) -> Int? {
        Self.rootID(containing: commentID, in: displayThreads)
    }

    /// Pure lookup over a display-thread list (testable without a live load).
    nonisolated static func rootID(containing commentID: Int, in threads: [AO3Comment]) -> Int? {
        threads.first { $0.contains(commentID: commentID) }?.id
    }

    /// One page, via cache unless stale/bypassed. Returns nil after setting a
    /// user-readable failure phase (keeping any cached page visible).
    private func fetchPage(
        _ number: Int, auth: AO3AuthService, forceRefresh: Bool,
        expected: AuthContext
    ) async -> AO3CommentsPage? {
        guard isCurrent(expected, auth) else { return nil }
        // Key includes session identity so a signed-out fetch (no Reply/Edit
        // actions) is never reused after login — that was hiding Reply in All
        // when By Chapter was loaded fresh under the same work id.
        let key = CommentsPageCache.Key(
            workID: workID,
            chapterID: chapterForRequests,
            page: number,
            authenticationScope: expected.cacheScope,
            sessionGeneration: expected.generation
        )
        if !forceRefresh, let cached = cache.freshPage(for: key) {
            isFromCache = true
            if phase != .loaded { phase = .loaded }
            return cached
        }

        phase = page == nil ? .loading : phase
        do {
            let request = try authenticatedRequest(
                for: AO3Client.commentsPageURL(workID: workID, chapterID: chapterForRequests, page: number), auth: auth
            )
            let fetched = try await pageLoader(workID, chapterForRequests, number, request)
            guard isCurrent(expected, auth) else { return nil }
            cache.store(fetched, for: key)
            isOffline = false
            isFromCache = false
            return fetched
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch AO3Error.authenticationRequired {
            guard isCurrent(expected, auth) else { return nil }
            phase = .failed(Self.message(for: AO3Error.authenticationRequired))
            return nil
        } catch {
            guard isCurrent(expected, auth) else { return nil }
            isOffline = Self.isOfflineError(error)
            // Keep showing a cached page if one exists (marked stale) — only a
            // cold miss surfaces the full-screen failure state.
            if let cached = cache.page(for: key) {
                isFromCache = true
                phase = .loaded
                return cached
            }
            phase = .failed(Self.message(for: error))
            return nil
        }
    }

    /// The chapter index, fetched once per work per session (small /navigate page).
    func loadChaptersIfNeeded(auth: AO3AuthService) async {
        guard belongsToCurrentSession(auth: auth) else { return }
        syncAuthenticationContext(auth: auth)
        let expected = authContext
        await loadChaptersIfNeeded(auth: auth, expected: expected)
    }

    private func loadChaptersIfNeeded(
        auth: AO3AuthService, expected: AuthContext
    ) async {
        guard isCurrent(expected, auth) else { return }
        guard chapters.isEmpty else { return }
        let context = authContext
        if let cached = cache.chapters(
            forWork: workID,
            authenticationScope: context.cacheScope,
            sessionGeneration: context.generation
        ) {
            chapters = cached
            chaptersFailureMessage = nil
            return
        }
        do {
            let request = try authenticatedRequest(
                for: AO3Client.chapterIndexURL(workID: workID), auth: auth
            )
            let fetched = try await chapterLoader(workID, request)
            guard isCurrent(expected, auth) else { return }
            cache.storeChapters(
                fetched, forWork: workID,
                authenticationScope: context.cacheScope,
                sessionGeneration: context.generation
            )
            chapters = fetched
            chaptersFailureMessage = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard isCurrent(expected, auth) else { return }
            chaptersFailureMessage = Self.message(for: error)
        }
    }

    private func knownTotalPages() -> Int? {
        // Keyed by the current auth scope/generation only — another authentication
        // context's cached page count can legitimately differ (AO3 hides some
        // comments from some viewers), so sizing "newest first" off it would jump
        // to the wrong last page. A miss just costs the one page-1 fetch `load`
        // already falls back to.
        let key = CommentsPageCache.Key(
            workID: workID, chapterID: chapterForRequests, page: 1,
            authenticationScope: authContext.cacheScope,
            sessionGeneration: authContext.generation
        )
        return cache.page(for: key)?.totalPages
    }

    private static func submitComment(
        context: AO3CommentContext,
        editTarget: AO3Comment?,
        body: String,
        expectedGeneration: Int,
        auth: AO3AuthService,
        onFormPrepared: @escaping @MainActor (Bool) -> Void
    ) async throws {
        if let editTarget {
            _ = try await auth.editComment(
                commentID: editTarget.id,
                content: body,
                expectedGeneration: expectedGeneration
            )
        } else if let parentID = context.parentCommentID {
            _ = try await auth.postCommentReply(
                parentCommentID: parentID,
                content: body,
                expectedGeneration: expectedGeneration,
                onFormPrepared: onFormPrepared
            )
        } else {
            _ = try await auth.postComment(
                workID: context.workID,
                content: body,
                expectedGeneration: expectedGeneration,
                onFormPrepared: onFormPrepared
            )
        }
    }

    // MARK: Composer

    func startComposer(replyingTo parent: AO3Comment? = nil, auth: AO3AuthService) {
        guard belongsToCurrentSession(auth: auth) else { return }
        syncAuthenticationContext(auth: auth)
        let resolvedParent: AO3Comment?
        if let requested = parent {
            guard let current = displayedComment(id: requested.id), current.canReply else { return }
            resolvedParent = current
        } else {
            resolvedParent = nil
        }
        let context = AO3CommentContext(
            workID: workID,
            chapterID: chapterForRequests,
            parentCommentID: resolvedParent?.id
        )
        composerParent = resolvedParent
        composerEditTarget = nil
        composerContext = context
        composerText = drafts.draft(for: context, identity: authContext.identity)
        // Unconditional: rehydrates an unresolved earlier attempt for this
        // exact draft (context + text + identity) as blocked again — even
        // from a brand-new guard — instead of resetting to idle.
        adoptSubmissionGuardToComposerState()
    }

    private func adoptSubmissionGuardToComposerState() {
        guard let composerContext, composerEditTarget == nil else { return }
        submissionGuard.adopt(CommentSubmissionKey(
            context: composerContext,
            body: composerText,
            identity: authContext.identity
        ))
    }

    /// Re-syncs the guard ONLY while it's currently showing `.ambiguous`, so
    /// editing away from a blocked submission's exact text immediately exits
    /// that display (Check Again disappears, Post becomes available for this
    /// now-distinct text) instead of staying stuck on a stale banner. Scoped
    /// to `.ambiguous` specifically — unlike `startComposer`'s unconditional
    /// adopt, this must never also reset an unrelated `.failed`/`.succeeded`
    /// display just because the user kept typing. The durable entry for the
    /// ORIGINAL text is untouched either way — reopening or retyping it still
    /// shows it blocked. Call on every composer text change.
    func syncSubmissionGuardToComposerText() {
        guard case .ambiguous = submissionGuard.phase else { return }
        adoptSubmissionGuardToComposerState()
    }

    /// Opens the composer to edit an existing own comment. Prefills the rendered
    /// text — AO3 comments are usually plain text; heavy formatting is better
    /// edited on AO3 itself (documented limitation). Edits never enter the
    /// `.ambiguous` phase (they're safe to retry explicitly, see `submit()`), so
    /// an unconditional reset here can't unblock a duplicate the way a reply's
    /// could — unlike `startComposer`, this doesn't need the same guard.
    func startEditing(_ comment: AO3Comment, auth: AO3AuthService) {
        guard belongsToCurrentSession(auth: auth) else { return }
        syncAuthenticationContext(auth: auth)
        guard let comment = displayedComment(id: comment.id), comment.editPath != nil else { return }
        composerParent = nil
        composerEditTarget = comment
        composerContext = AO3CommentContext(workID: workID, chapterID: comment.chapterID)
        composerText = comment.bodyText
        submissionGuard.reset()
    }

    func deletableComment(_ comment: AO3Comment, auth: AO3AuthService) -> AO3Comment? {
        guard belongsToCurrentSession(auth: auth) else { return nil }
        syncAuthenticationContext(auth: auth)
        guard let current = displayedComment(id: comment.id), current.deletePath != nil else {
            return nil
        }
        return current
    }

    private func displayedComment(id: Int) -> AO3Comment? {
        displayThreads.flatMap(\.flattened).first { $0.id == id }
    }

    func closeComposer() {
        composerContext = nil
        composerParent = nil
        composerEditTarget = nil
    }

    func saveDraft() {
        // Edits don't use the draft store — a stale edit draft could silently
        // overwrite a newer comment revision.
        guard let composerContext, composerEditTarget == nil else { return }
        // A's draft must never appear when B opens the same work/comment target.
        drafts.save(composerText, for: composerContext, identity: authContext.identity)
    }

    /// The full defensive submit flow (see COMMENTS_HANDOFF.md):
    /// one POST at most per attempt; ambiguous outcomes verify before any retry
    /// becomes possible; the draft survives until verified success.
    func submit(auth: AO3AuthService) async {
        guard belongsToCurrentSession(auth: auth) else { return }
        syncAuthenticationContext(auth: auth)
        let expected = authContext
        guard let context = composerContext else { return }
        let body = composerText
        let editTarget = composerEditTarget
        let key = CommentSubmissionKey(
            context: context, body: body,
            identity: editTarget.map { "\(expected.identity)#edit\($0.id)" } ?? expected.identity
        )
        guard submissionGuard.begin(key) else { return }
        var commentMayBeHidden = false

        do {
            guard isCurrent(expected, auth) else { return }
            try await commentSubmitter(
                context, editTarget, body, expected.generation, auth,
                { commentMayBeHidden = $0 }
            )
            guard isCurrent(expected, auth), submissionGuard.pendingKey == key else { return }
            submissionGuard.succeed()
            if editTarget == nil {
                drafts.clearVariants(for: context, identity: expected.identity)
            }
        } catch {
            guard isCurrent(expected, auth), submissionGuard.pendingKey == key else { return }
            if editTarget == nil, Self.isAmbiguousSubmitError(error) {
                submissionGuard.markAmbiguous(
                    Self.ambiguousSubmitMessage(for: error),
                    commentMayBeHidden: commentMayBeHidden
                )
                await runVerification(auth: auth, context: context, expected: expected)
            } else {
                // An ambiguous edit surfaces as an explicit couldn't-confirm
                // failure (`AO3WriteError.unconfirmed` message) rather than
                // entering the ambiguous store — re-PUTs are NOT idempotent
                // upstream (every update re-stamps `edited_at`, re-notifies, and
                // consumes rate limit), so the message tells the user to check
                // AO3 first; an unresolved-edit state is CAA-13 (Part E).
                submissionGuard.fail(Self.message(for: error))
            }
        }

        guard isCurrent(expected, auth) else { return }
        await finishIfSucceeded(auth: auth, expected: expected)
    }

    /// Re-runs verification for an ambiguous submission ("Check Again").
    func reverify(auth: AO3AuthService) async {
        guard belongsToCurrentSession(auth: auth) else { return }
        syncAuthenticationContext(auth: auth)
        let expected = authContext
        guard let context = composerContext, case .ambiguous = submissionGuard.phase else { return }
        await runVerification(auth: auth, context: context, expected: expected)
        guard isCurrent(expected, auth) else { return }
        await finishIfSucceeded(auth: auth, expected: expected)
    }

    /// What verification must check: `pendingKey`'s own body, never the
    /// composer's *current* text. "Check Again" can run after the user has
    /// typed something different from what was originally posted;
    /// authoritatively checking THAT edited text against AO3 would verify the
    /// wrong thing and, on `.absent`, release the block on the real
    /// unresolved submission — re-enabling a genuine duplicate POST for it.
    /// This function doesn't even take the composer's live text as an input,
    /// so that can't leak in by accident. `context` still comes from the live
    /// composer (not `pendingKey.context`, which is chapter-stripped for
    /// dedup) so draft clearing hits the exact key the draft was saved under.
    /// Pure and `nonisolated` so the "verify the pending key, not whatever's
    /// on screen" invariant is directly unit-testable.
    nonisolated static func verificationTarget(
        pendingKey: CommentSubmissionKey?, composerContext: AO3CommentContext
    ) -> (context: AO3CommentContext, body: String)? {
        guard let pendingKey else { return nil }
        return (composerContext, pendingKey.normalizedBody)
    }

    private func runVerification(
        auth: AO3AuthService, context: AO3CommentContext, expected: AuthContext
    ) async {
        guard isCurrent(expected, auth) else { return }
        guard let target = Self.verificationTarget(
            pendingKey: submissionGuard.pendingKey, composerContext: context
        ) else { return }
        guard let pendingKey = submissionGuard.pendingKey else { return }
        let submittedAt = submissionGuard.pendingSubmittedAt
        let commentMayBeHidden = submissionGuard.pendingCommentMayBeHidden
        submissionGuard.beginVerifying()
        // A reply verifies against its own parent thread (the exact
        // authoritative endpoint), not a page number, so no "which page was
        // showing" state is needed here — see `AO3AuthService.verifyCommentPosted`.
        let verification: AO3AuthService.CommentVerification
        do {
            verification = try await commentVerifier(
                target.context,
                target.body,
                submittedAt,
                commentMayBeHidden,
                expected.generation,
                auth
            )
        } catch {
            guard isCurrent(expected, auth), submissionGuard.pendingKey == pendingKey else { return }
            submissionGuard.markAmbiguous(Self.message(for: error))
            return
        }
        guard isCurrent(expected, auth), submissionGuard.pendingKey == pendingKey else { return }
        if case .found = verification {
            drafts.clearVariants(for: target.context, identity: pendingKey.identity)
        }
        submissionGuard.resolveAmbiguity(verification)
    }

    private func finishIfSucceeded(
        auth: AO3AuthService, expected: AuthContext
    ) async {
        guard isCurrent(expected, auth),
              submissionGuard.phase == .succeeded,
              composerContext != nil
        else { return }
        closeComposer()
        composerText = ""
        // One refresh so the new/updated comment is visible (bypasses cache).
        await load(auth: auth, forceRefresh: true, expected: expected)
    }

    // MARK: Error classification

    /// True when the POST may have reached AO3 even though no confirmation came
    /// back — the only situations where a duplicate is possible and verification
    /// (not retry) must decide. Two shapes: the response never arrived (timeout /
    /// dropped connection), or a final-200 page arrived carrying neither a
    /// recognized error flash nor a recognized success flash
    /// (`AO3WriteError.unconfirmed` — maintenance page, interstitial; CAA-2).
    static func isAmbiguousSubmitError(_ error: Error) -> Bool {
        if case AO3WriteError.unconfirmed = error { return true }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost:
            return true
        default:
            return false
        }
    }

    /// The banner text for an ambiguous submit, honest about which of the two
    /// ambiguity shapes happened.
    static func ambiguousSubmitMessage(for error: Error) -> String {
        if case AO3WriteError.unconfirmed = error {
            return "AO3 answered but didn't confirm the comment posted. "
                + "Checking whether it went through…"
        }
        return "The connection dropped while posting. Checking whether the comment went through…"
    }

    private static func isOfflineError(_ error: Error) -> Bool {
        (error as? URLError)?.code == .notConnectedToInternet
    }

    static func message(for error: Error) -> String {
        switch error {
        case AO3Error.rateLimited:
            return "AO3 is asking for a pause. Please try again in a moment."
        case AO3Error.authenticationRequired, AO3WriteError.notSignedIn:
            return "Log in to AO3 to do that."
        case let AO3WriteError.rejected(reason):
            return reason
        case AO3Error.notFound:
            return "AO3 couldn't find these comments — the work may be hidden or deleted."
        case AO3Error.forbidden:
            return "AO3 declined the request. The work may be restricted to logged-in users."
        case let error as URLError where error.code == .notConnectedToInternet:
            return "You're offline. Comments will load when you're back online."
        default:
            return (error as? LocalizedError)?.errorDescription
                ?? "Something went wrong talking to AO3."
        }
    }
}

/// Comment-page + chapter-index cache for one Comments-viewing session. Each
/// `CommentsModel` owns its own instance (never a shared singleton), so entries
/// live exactly as long as the screen does — cleared for free on dismiss when
/// SwiftUI deallocates the `@State` that owns it.
///
/// Owning the cache per screen bounds how *much* is retained, but not how *stale*
/// any one entry gets: a Comments screen left open would otherwise serve its first
/// fetch for the rest of its life, and the stale banner only appears when offline.
/// Hence the TTL on `freshPage`. Reads that would rather have something old than
/// nothing at all use `page` instead.
///
/// Intentionally in-memory only — comments are live site state, not library
/// content, and nothing here is meant to outlive the session that fetched it.
@MainActor
final class CommentsPageCache {
    struct Key: Hashable {
        let workID: Int
        let chapterID: Int?
        let page: Int
        let authenticationScope: String
        let sessionGeneration: Int
    }

    private var pages: [Key: AO3CommentsPage] = [:]
    private var chapterIndexes: [ChapterKey: [AO3ChapterRef]] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 300) {
        self.ttl = ttl
    }

    /// Any cached entry, however old — for reads where a stale page beats no page.
    func page(for key: Key) -> AO3CommentsPage? {
        pages[key]
    }

    /// A cached entry still inside the TTL, for the happy-path read: past it, the
    /// page re-fetches on the next visit rather than being served indefinitely.
    func freshPage(for key: Key) -> AO3CommentsPage? {
        guard let cached = pages[key],
              Date().timeIntervalSince(cached.fetchedAt) < ttl else { return nil }
        return cached
    }

    func store(_ page: AO3CommentsPage, for key: Key) {
        pages[key] = page
    }

    private struct ChapterKey: Hashable {
        let workID: Int
        let authenticationScope: String
        let sessionGeneration: Int
    }

    /// Chapter titles can include owner-only drafts, so they are scoped exactly
    /// like comment pages (including same-account re-login generations).
    func chapters(forWork workID: Int, authenticationScope: String, sessionGeneration: Int) -> [AO3ChapterRef]? {
        chapterIndexes[ChapterKey(
            workID: workID, authenticationScope: authenticationScope, sessionGeneration: sessionGeneration
        )]
    }

    func storeChapters(
        _ refs: [AO3ChapterRef], forWork workID: Int,
        authenticationScope: String, sessionGeneration: Int
    ) {
        chapterIndexes[ChapterKey(
            workID: workID, authenticationScope: authenticationScope, sessionGeneration: sessionGeneration
        )] = refs
    }
}
