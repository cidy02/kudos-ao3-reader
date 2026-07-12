import Foundation

/// State for the signed-in user's AO3 Inbox feed — shared by the Account tab's
/// Overview "Recent Comments" preview and the Activity tab's full Inbox list,
/// so the two surfaces never fetch the same page twice. Read-only v1: no
/// mark-read/delete/reply-from-inbox writes. Fetches go through
/// `AO3AuthorProfileFetcher` for the same TTL cache, coordinator slot, pacing,
/// and stale-fallback discipline as author pages (the cache is keyed by full URL
/// + authentication scope, so inbox HTML can never leak across accounts).
@MainActor
@Observable
final class AO3InboxModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var items: [AO3InboxItem] = []
    private(set) var phase: Phase = .idle
    private(set) var currentPage = 1
    private(set) var totalPages = 1
    /// Exact totals from the inbox heading, when AO3 printed them.
    private(set) var totalComments: Int?
    private(set) var unreadCount: Int?
    private(set) var isShowingStaleCache = false

    private var authenticationScope = ""
    private var activeTask: Task<Void, Never>?

    /// Loads the first page if this scope hasn't loaded yet (also called when the
    /// signed-in account changes — content from another scope is discarded).
    func activate(auth: AO3AuthService) {
        let scope = AO3AuthorProfileFetcher.authenticationScope(for: auth)
        if authenticationScope != scope {
            authenticationScope = scope
            reset()
        }
        guard auth.isLoggedIn else {
            reset()
            return
        }
        guard phase == .idle else { return }
        launch { await self.load(auth: auth, page: 1) }
    }

    func goToPage(_ page: Int, auth: AO3AuthService) {
        launch { await self.load(auth: auth, page: page) }
    }

    func retry(auth: AO3AuthService) {
        launch { await self.load(auth: auth, page: self.currentPage, bypassCache: true) }
    }

    func refresh(auth: AO3AuthService) async {
        let task = launch { await self.load(auth: auth, page: self.currentPage, bypassCache: true) }
        await task.value
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
    }

    @discardableResult
    private func launch(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        activeTask?.cancel()
        let task = Task { await operation() }
        activeTask = task
        return task
    }

    private func load(auth: AO3AuthService, page: Int, bypassCache: Bool = false) async {
        guard let username = auth.username,
              let url = AO3Client.inboxURL(username: username, page: page)
        else {
            reset()
            return
        }
        phase = items.isEmpty ? .loading : .loaded
        do {
            let fetched = try await AO3AuthorProfileFetcher.page(
                at: url, auth: auth, bypassCache: bypassCache
            )
            try Task.checkCancellation()
            let parsed = try AO3Client.parseInboxPage(fetched.html, page: page)
            items = parsed.items
            currentPage = parsed.currentPage
            totalPages = parsed.totalPages
            totalComments = parsed.totalComments
            unreadCount = parsed.unreadCount
            isShowingStaleCache = fetched.isStale
            phase = .loaded
        } catch is CancellationError {
            return
        } catch AO3Error.authenticationRequired {
            await auth.sessionDidExpire()
            reset()
        } catch {
            let message: String
            if let ao3 = error as? AO3Error, let description = ao3.errorDescription {
                message = description
            } else {
                message = error.localizedDescription
            }
            phase = .failed(message)
        }
    }

    private func reset() {
        cancel()
        items = []
        phase = .idle
        currentPage = 1
        totalPages = 1
        totalComments = nil
        unreadCount = nil
        isShowingStaleCache = false
    }
}
