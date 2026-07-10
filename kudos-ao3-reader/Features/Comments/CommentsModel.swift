import Foundation
import SwiftUI

/// Screen state + fetch logic for the native AO3 comments UI.
///
/// Networking respect (see `docs/ai/COMMENTS_HANDOFF.md`): every request maps to
/// an explicit user action — opening the screen, switching chapter/page/order,
/// or pull-to-refresh. Pages are cached (TTL) so re-visits don't re-fetch, and
/// nothing loads eagerly, in the background, or per-chapter in bulk.
@MainActor
@Observable
final class CommentsModel {
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
    /// The work's author names, for the "Author" badge on their comments.
    let workAuthors: [String]

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
    private(set) var chaptersFailed = false
    var selectedChapter: AO3ChapterRef?
    /// A 1-based AO3 story-chapter to open on (from the reader's chapter-aware
    /// Comments button), applied once by `loadInitial`. nil = open on All.
    private var pendingInitialChapterPosition: Int?
    /// True only while `loadInitial` is programmatically setting scope/chapter, so
    /// the view's scope/selectedChapter `onChange` handlers skip the redundant loads
    /// they'd otherwise stack on the single load `loadInitial` already performs.
    private(set) var isApplyingInitialContext = false
    /// Local rendering order — AO3 itself has no comment sort; newest-first
    /// starts from the last page and reverses within each page.
    var newestFirst = false {
        didSet { rebuildDisplayThreads() }
    }

    // Composer
    var composerContext: AO3CommentContext?
    /// The comment being replied to (quoted in the composer), nil for top-level.
    var composerParent: AO3Comment?
    /// When set, the composer is editing this existing comment (PUT, not POST).
    var composerEditTarget: AO3Comment?
    var composerText = ""
    let submissionGuard = CommentSubmissionGuard()
    private let drafts = CommentDraftStore()

    /// Session-wide page cache; 5-minute TTL.
    private static let cache = CommentsPageCache()

    init(workID: Int, workAuthors: [String], initialChapterPosition: Int? = nil) {
        self.workID = workID
        self.workAuthors = workAuthors
        self.pendingInitialChapterPosition = initialChapterPosition
    }

    var chapterForRequests: Int? {
        scope == .byChapter ? selectedChapter?.id : nil
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
        guard let target = pendingInitialChapterPosition else {
            await load(auth: auth)
            return
        }
        pendingInitialChapterPosition = nil
        isApplyingInitialContext = true
        defer { isApplyingInitialContext = false }

        await loadChaptersIfNeeded(auth: auth)
        guard let ref = chapterRef(forStoryPosition: target) else {
            // Index failed or the work has no chapter list (e.g. single-chapter):
            // work-level All comments show the same thread anyway.
            await load(auth: auth)
            return
        }
        scope = .byChapter
        selectedChapter = ref
        await load(auth: auth)
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
    func load(auth: AO3AuthService, forceRefresh: Bool = false) async {
        // Newest-first starts at the last page; we may need one fetch of page 1
        // first to learn the page count (cached afterwards).
        var target = 1
        if newestFirst {
            if let known = knownTotalPages() {
                target = known
            } else if let first = await fetchPage(1, auth: auth, forceRefresh: forceRefresh) {
                target = first.totalPages
            } else {
                return // fetchPage set the failure phase
            }
        }
        await loadPage(target, auth: auth, forceRefresh: forceRefresh)
    }

    func loadPage(_ number: Int, auth: AO3AuthService, forceRefresh: Bool = false) async {
        guard let fetched = await fetchPage(number, auth: auth, forceRefresh: forceRefresh) else {
            return
        }
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
        displayThreads = newestFirst ? Array(page.comments.reversed()) : page.comments
    }

    /// One page, via cache unless stale/bypassed. Returns nil after setting a
    /// user-readable failure phase (keeping any cached page visible).
    private func fetchPage(
        _ number: Int, auth: AO3AuthService, forceRefresh: Bool
    ) async -> AO3CommentsPage? {
        let key = CommentsPageCache.Key(workID: workID, chapterID: chapterForRequests, page: number)
        if !forceRefresh, let cached = Self.cache.page(for: key) {
            isFromCache = true
            if phase != .loaded { phase = .loaded }
            return cached
        }

        phase = page == nil ? .loading : phase
        do {
            let request = try? auth.authenticatedRequest(
                for: AO3Client.commentsPageURL(workID: workID, chapterID: chapterForRequests, page: number)
            )
            let fetched = try await AO3Client.shared.commentsPage(
                workID: workID, chapterID: chapterForRequests, page: number, request: request
            )
            Self.cache.store(fetched, for: key)
            isOffline = false
            isFromCache = false
            return fetched
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            isOffline = Self.isOfflineError(error)
            // Keep showing a cached page if one exists (marked stale) — only a
            // cold miss surfaces the full-screen failure state.
            if let cached = Self.cache.page(for: key, ignoringTTL: true) {
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
        guard chapters.isEmpty else { return }
        if let cached = Self.cache.chapters(forWork: workID) {
            chapters = cached
            return
        }
        do {
            let request = try? auth.authenticatedRequest(for: AO3Client.chapterIndexURL(workID: workID))
            let fetched = try await AO3Client.shared.chapterIndex(workID: workID, request: request)
            Self.cache.storeChapters(fetched, forWork: workID)
            chapters = fetched
            chaptersFailed = false
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            chaptersFailed = true
        }
    }

    private func knownTotalPages() -> Int? {
        let key = CommentsPageCache.Key(workID: workID, chapterID: chapterForRequests, page: 1)
        return Self.cache.page(for: key, ignoringTTL: true)?.totalPages
    }

    // MARK: Composer

    func startComposer(replyingTo parent: AO3Comment? = nil) {
        let context = AO3CommentContext(
            workID: workID,
            chapterID: chapterForRequests,
            parentCommentID: parent?.id
        )
        composerParent = parent
        composerEditTarget = nil
        composerContext = context
        composerText = drafts.draft(for: context)
        submissionGuard.reset()
    }

    /// Opens the composer to edit an existing own comment. Prefills the rendered
    /// text — AO3 comments are usually plain text; heavy formatting is better
    /// edited on AO3 itself (documented limitation).
    func startEditing(_ comment: AO3Comment) {
        composerParent = nil
        composerEditTarget = comment
        composerContext = AO3CommentContext(workID: workID, chapterID: comment.chapterID)
        composerText = comment.bodyText
        submissionGuard.reset()
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
        drafts.save(composerText, for: composerContext)
    }

    /// The full defensive submit flow (see COMMENTS_HANDOFF.md):
    /// one POST at most per attempt; ambiguous outcomes verify before any retry
    /// becomes possible; the draft survives until verified success.
    func submit(auth: AO3AuthService) async {
        guard let context = composerContext else { return }
        let body = composerText
        // Edits carry the target id in the identity so re-editing the same text
        // into a different comment is never mistaken for a duplicate.
        let identity = composerEditTarget.map { "\(auth.username ?? "")#edit\($0.id)" }
            ?? (auth.username ?? "")
        let key = CommentSubmissionKey(context: context, body: body, identity: identity)
        guard submissionGuard.begin(key) else { return }

        do {
            if let editTarget = composerEditTarget {
                _ = try await auth.editComment(commentID: editTarget.id, content: body)
                submissionGuard.succeed()
            } else if let parentID = context.parentCommentID {
                _ = try await auth.postCommentReply(parentCommentID: parentID, content: body)
                submissionGuard.succeed()
                drafts.clear(for: context)
            } else {
                _ = try await auth.postComment(workID: context.workID, content: body)
                submissionGuard.succeed()
                drafts.clear(for: context)
            }
        } catch {
            if composerEditTarget == nil, Self.isAmbiguousSubmitError(error) {
                submissionGuard.markAmbiguous(
                    "The connection dropped while posting. Checking whether the comment went through…"
                )
                await runVerification(auth: auth, context: context, body: body)
            } else {
                // Edits are safe to retry explicitly (re-PUTting the same text is
                // idempotent), so an ambiguous edit surfaces as a plain failure.
                submissionGuard.fail(Self.message(for: error))
            }
        }

        await finishIfSucceeded(auth: auth)
    }

    /// Re-runs verification for an ambiguous submission ("Check Again").
    func reverify(auth: AO3AuthService) async {
        guard let context = composerContext, case .ambiguous = submissionGuard.phase else { return }
        await runVerification(auth: auth, context: context, body: composerText)
        await finishIfSucceeded(auth: auth)
    }

    private func runVerification(
        auth: AO3AuthService, context: AO3CommentContext, body: String
    ) async {
        submissionGuard.beginVerifying()
        let verification = await auth.verifyCommentPosted(context: context, body: body)
        submissionGuard.resolveAmbiguity(verification)
        if case .found = verification { drafts.clear(for: context) }
    }

    private func finishIfSucceeded(auth: AO3AuthService) async {
        guard submissionGuard.phase == .succeeded, composerContext != nil else { return }
        closeComposer()
        composerText = ""
        // One refresh so the new/updated comment is visible (bypasses cache).
        await load(auth: auth, forceRefresh: true)
    }

    // MARK: Error classification

    /// True when the POST may have reached AO3 even though the response never
    /// arrived — the only situations where a duplicate is possible and
    /// verification (not retry) must decide.
    static func isAmbiguousSubmitError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost:
            return true
        default:
            return false
        }
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

/// Session-scoped comment page cache with a short TTL: repeat visits inside the
/// window cost AO3 nothing; anything older re-fetches on demand. Intentionally
/// in-memory only — comments are live site state, not library content.
@MainActor
final class CommentsPageCache {
    struct Key: Hashable {
        let workID: Int
        let chapterID: Int?
        let page: Int
    }

    private var pages: [Key: AO3CommentsPage] = [:]
    private var chapterIndexes: [Int: (refs: [AO3ChapterRef], fetchedAt: Date)] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 300) {
        self.ttl = ttl
    }

    func page(for key: Key, ignoringTTL: Bool = false) -> AO3CommentsPage? {
        guard let cached = pages[key] else { return nil }
        if ignoringTTL || Date().timeIntervalSince(cached.fetchedAt) < ttl { return cached }
        return nil
    }

    func store(_ page: AO3CommentsPage, for key: Key) {
        pages[key] = page
    }

    /// Chapter lists barely change; keep them for the session.
    func chapters(forWork workID: Int) -> [AO3ChapterRef]? {
        chapterIndexes[workID]?.refs
    }

    func storeChapters(_ refs: [AO3ChapterRef], forWork workID: Int) {
        chapterIndexes[workID] = (refs, Date())
    }
}
