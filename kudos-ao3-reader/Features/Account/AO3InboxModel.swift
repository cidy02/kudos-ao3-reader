import Foundation

/// State for the signed-in user's AO3 Inbox feed (Account › Activity › Inbox).
/// Fetches go through `AO3AuthorProfileFetcher` for the same TTL cache,
/// coordinator slot, pacing, and stale-fallback discipline as author pages (the
/// cache is keyed by full URL + authentication/session scope, so Inbox HTML and
/// forms cannot leak across accounts or same-user sessions). Bulk writes use the
/// exact parsed Inbox form once only.
@MainActor
@Observable
final class AO3InboxModel {
    typealias WorkContextLoader = (Int, AO3AuthService) async throws -> AO3CommentsWorkContext
    typealias PageLoader = @MainActor (
        _ url: URL,
        _ auth: AO3AuthService,
        _ authenticationScope: String,
        _ sessionGeneration: Int,
        _ bypassCache: Bool
    ) async throws -> AO3AuthorProfileFetcher.Page
    typealias BulkActionSubmitter = @MainActor (
        _ action: AO3InboxBulkAction,
        _ form: AO3InboxBulkForm,
        _ items: [AO3InboxItem],
        _ referer: URL,
        _ auth: AO3AuthService
    ) async throws -> String

    /// Identifies which signed-in (or anonymous) session an async Inbox
    /// operation belongs to. Captured once at the start of every operation and
    /// re-checked after each suspension point that could outlive an account
    /// switch, reset, or logout — a mismatch makes that continuation's local
    /// effects (cache writes, row/form/page assignment, error assignment, a
    /// post-write reload, or any other user-visible state) permanently inert
    /// (T91-RF3). `scope` alone can't tell two logins of the *same* username
    /// apart, which is what `generation` is for.
    private struct AuthContext: Equatable {
        let scope: String
        let generation: Int

        static func current(_ auth: AO3AuthService) -> AuthContext {
            AuthContext(
                scope: AO3AuthorProfileFetcher.authenticationScope(for: auth),
                generation: auth.sessionGeneration
            )
        }

        /// The shared author-page cache normally scopes private markup by
        /// username. Inbox HTML additionally contains session-bound forms, so
        /// its cache identity must split same-user sessions as well (T91-RF3).
        var cacheScope: String { "\(scope)#session-\(generation)" }
    }

    /// Everything a submitted Inbox write needs after its first suspension.
    /// Capturing this before starting its task prevents a queued A tap from
    /// borrowing B's form, selection, URL, or authentication context.
    private struct WriteOperation {
        let id: UUID
        let action: AO3InboxBulkAction
        let form: AO3InboxBulkForm
        let items: [AO3InboxItem]
        let referer: URL
        let username: String?
        let page: Int
        let expected: AuthContext
    }

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
    private(set) var bulkForm: AO3InboxBulkForm?
    private(set) var filterForm: AO3InboxFilterForm?
    private(set) var filterValues: [String: String] = [:]
    private(set) var isSelecting = false
    private(set) var selectedItemIDs = Set<Int>()
    private var activeWriteID: UUID?
    var isPerformingBulkAction: Bool { activeWriteID != nil }
    private(set) var actionError: String?
    /// Auth-scoped, bounded cache shared by every row for the same work. Values
    /// arrive progressively while the visible Inbox page is hydrated.
    private(set) var workContextsByID: [Int: AO3CommentsWorkContext] = [:]
    private(set) var isEnrichingWorkContexts = false
    /// Changes after every successful Inbox page parse so a pull-to-refresh can
    /// retry supplemental metadata that failed without coupling it to feed state.
    private(set) var metadataRevision = 0

    /// Sentinel that matches no real `AuthContext.current(_:)` (whose `scope` is
    /// always `"anonymous"` or `"signed-in:…"`), so the very first `activate()`
    /// always resets and bypasses the cache regardless of whether the app opens
    /// signed in or signed out.
    private var authContext = AuthContext(scope: "", generation: -1)
    private var activeTask: Task<Void, Never>?
    private var lastLoadedURL: URL?
    private var workContextCacheOrder: [Int] = []
    private var attemptedMetadataRevisionByWorkID: [Int: Int] = [:]
    private var stoppedMetadataRevision: Int?
    private let workContextLoader: WorkContextLoader
    private let pageLoader: PageLoader
    private let bulkActionSubmitter: BulkActionSubmitter
    private let beforeWriteSubmission: @MainActor () async -> Void

    init(
        workContextLoader: @escaping WorkContextLoader = AO3InboxModel.loadWorkContext,
        pageLoader: @escaping PageLoader = { url, auth, scope, generation, bypassCache in
            try await AO3AuthorProfileFetcher.page(
                at: url,
                auth: auth,
                cacheScope: "\(scope)#session-\(generation)",
                isCurrent: {
                    AO3AuthorProfileFetcher.authenticationScope(for: auth) == scope
                        && auth.sessionGeneration == generation
                },
                bypassCache: bypassCache
            )
        },
        bulkActionSubmitter: @escaping BulkActionSubmitter = { action, form, items, referer, auth in
            try await auth.performInboxBulkAction(action, form: form, items: items, referer: referer)
        },
        beforeWriteSubmission: @escaping @MainActor () async -> Void = {}
    ) {
        self.workContextLoader = workContextLoader
        self.pageLoader = pageLoader
        self.bulkActionSubmitter = bulkActionSubmitter
        self.beforeWriteSubmission = beforeWriteSubmission
    }

    /// Current-page only: AO3's displayed mass-edit form only supplies these
    /// checkbox values, so selections cannot silently cross pagination.
    var selectableItemIDs: Set<Int> {
        Set(items.compactMap { $0.bulkSelectionField == nil ? nil : $0.id })
    }

    var selectedItems: [AO3InboxItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    var allCurrentPageSelected: Bool {
        !selectableItemIDs.isEmpty && selectableItemIDs.isSubset(of: selectedItemIDs)
    }

    var canSelectItems: Bool { bulkForm != nil && !selectableItemIDs.isEmpty }
    var canFilter: Bool { filterForm != nil }

    func workContext(for workID: Int) -> AO3CommentsWorkContext? {
        workContextsByID[workID]
    }

    /// Retains richer context learned by an explicitly opened Comments screen.
    /// The destination carries the generation active when it was opened, so a
    /// still-finishing Comments screen from account A cannot enrich account B's
    /// Inbox after an account transition.
    func cacheWorkContext(
        _ context: AO3CommentsWorkContext,
        for workID: Int,
        sessionGeneration: Int,
        auth: AO3AuthService
    ) {
        guard authContext.generation == sessionGeneration,
              auth.sessionGeneration == sessionGeneration,
              isCurrent(authContext, auth)
        else { return }
        storeWorkContext(context, for: workID)
    }

    func cacheWorkContext(
        _ context: AO3CommentsWorkContext,
        for destination: AccountInboxThreadDestination,
        auth: AO3AuthService
    ) {
        cacheWorkContext(
            context,
            for: destination.workID,
            sessionGeneration: destination.sessionGeneration,
            auth: auth
        )
    }

    /// Synchronizes only the private auth token. AccountView calls this for
    /// every session-generation change, including while Inbox is hidden, so a
    /// logout clears old rows without issuing a background Inbox request.
    @discardableResult
    func syncAuthenticationContext(auth: AO3AuthService) -> Bool {
        let context = AuthContext.current(auth)
        guard context != authContext else { return false }
        authContext = context
        reset()
        return true
    }

    private func isCurrent(_ expected: AuthContext, _ auth: AO3AuthService) -> Bool {
        expected == authContext && expected == AuthContext.current(auth)
    }

    /// Enriches only the distinct work ids rendered by the current Inbox view.
    /// The calling view owns this async task, so leaving Inbox or changing page
    /// cancels the loop. Requests are sequential even though each also claims the
    /// app-wide metadata coordinator slot.
    func enrichVisibleWorkContexts(
        workIDs: [Int], seededContexts: [Int: AO3CommentsWorkContext],
        auth: AO3AuthService
    ) async {
        let expected = AuthContext.current(auth)
        guard auth.isLoggedIn, isCurrent(expected, auth) else { return }
        seedWorkContexts(seededContexts)

        let ids = Self.uniqueWorkIDs(workIDs)
        guard !ids.isEmpty, stoppedMetadataRevision != metadataRevision else { return }
        isEnrichingWorkContexts = true
        defer {
            if isCurrent(expected, auth) { isEnrichingWorkContexts = false }
        }

        for workID in ids {
            do {
                try Task.checkCancellation()
                guard isCurrent(expected, auth) else { return }
                if let context = workContextsByID[workID], !context.needsSummaryEnrichment {
                    continue
                }
                guard attemptedMetadataRevisionByWorkID[workID] != metadataRevision else {
                    continue
                }
                attemptedMetadataRevisionByWorkID[workID] = metadataRevision

                let context = try await workContextLoader(workID, auth)
                try Task.checkCancellation()
                guard isCurrent(expected, auth) else { return }
                storeWorkContext(context, for: workID)
            } catch is CancellationError {
                guard isCurrent(expected, auth) else { return }
                if attemptedMetadataRevisionByWorkID[workID] == metadataRevision {
                    attemptedMetadataRevisionByWorkID[workID] = nil
                }
                return
            } catch let error as URLError where error.code == .cancelled {
                guard isCurrent(expected, auth) else { return }
                if attemptedMetadataRevisionByWorkID[workID] == metadataRevision {
                    attemptedMetadataRevisionByWorkID[workID] = nil
                }
                return
            } catch AO3Error.authenticationRequired {
                guard isCurrent(expected, auth) else { return }
                reset()
                await auth.sessionDidExpire(expectedGeneration: expected.generation)
                return
            } catch AO3Error.notFound {
                // One deleted/restricted work must not prevent later visible
                // notifications from receiving their metadata.
                continue
            } catch {
                // Offline, rate-limit, CDN, and parser failures are likely to
                // affect the whole batch. Stop instead of multiplying retries.
                guard isCurrent(expected, auth) else { return }
                stoppedMetadataRevision = metadataRevision
                return
            }
        }
    }

    nonisolated static func uniqueWorkIDs(_ workIDs: [Int]) -> [Int] {
        var seen = Set<Int>()
        return workIDs.filter { seen.insert($0).inserted }
    }

    /// Loads the first page if this scope hasn't loaded yet (also called when the
    /// signed-in account changes — content from another scope is discarded). A
    /// detected transition — a different account, or the same account under a
    /// new session generation (logged out and back in) — always bypasses the
    /// page cache in addition to using a generation-qualified cache key, so a
    /// still-fresh response can never hand this session a prior snapshot (T91-RF3).
    func activate(auth: AO3AuthService) {
        let didTransition = syncAuthenticationContext(auth: auth)
        guard auth.isLoggedIn else {
            reset()
            return
        }
        guard phase == .idle else { return }
        let expected = authContext
        launch {
            await self.load(
                auth: auth, expected: expected, page: 1, bypassCache: didTransition
            )
        }
    }

    func goToPage(_ page: Int, auth: AO3AuthService) {
        guard isCurrent(authContext, auth), !isPerformingBulkAction else { return }
        let expected = authContext
        launch { await self.load(auth: auth, expected: expected, page: page) }
    }

    func retry(auth: AO3AuthService) {
        guard isCurrent(authContext, auth), !isPerformingBulkAction else { return }
        let expected = authContext
        let page = currentPage
        launch { await self.load(auth: auth, expected: expected, page: page, bypassCache: true) }
    }

    func refresh(auth: AO3AuthService) async {
        guard isCurrent(authContext, auth), !isPerformingBulkAction else { return }
        let expected = authContext
        let page = currentPage
        let task = launch {
            await self.load(auth: auth, expected: expected, page: page, bypassCache: true)
        }
        await task.value
    }

    func beginSelection() {
        guard canSelectItems, !isPerformingBulkAction else { return }
        isSelecting = true
    }

    func endSelection() {
        isSelecting = false
        selectedItemIDs = []
    }

    func toggleSelection(for item: AO3InboxItem) {
        guard !isPerformingBulkAction, selectableItemIDs.contains(item.id) else { return }
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    func toggleSelectAllCurrentPage() {
        guard !isPerformingBulkAction else { return }
        selectedItemIDs = allCurrentPageSelected ? [] : selectableItemIDs
    }

    func applyFilter(fieldName: String, value: String, auth: AO3AuthService) {
        guard isCurrent(authContext, auth),
              !isPerformingBulkAction,
              let field = filterForm?.fields.first(where: { $0.name == fieldName }),
              field.options.contains(where: { $0.value == value })
        else { return }
        filterValues[fieldName] = value
        endSelection()
        let expected = authContext
        launch {
            await self.load(auth: auth, expected: expected, page: 1, bypassCache: true)
        }
    }

    func clearActionError() {
        actionError = nil
    }

    /// Starts one mass-edit POST from the synchronous button event. This never
    /// shares `activeTask`: a new read must not cancel an in-flight write, and a
    /// second action stays disabled until the first response arrives.
    @discardableResult
    func startBulkAction(_ action: AO3InboxBulkAction, auth: AO3AuthService) -> Task<Void, Never>? {
        startAction(action, items: selectedItems, auth: auth)
    }

    func canPerformItemAction(_ action: AO3InboxBulkAction, item: AO3InboxItem) -> Bool {
        guard let bulkForm, selectableItemIDs.contains(item.id) else { return false }
        return bulkForm.parameters(for: [item], action: action) != nil
    }

    @discardableResult
    func startItemAction(
        _ action: AO3InboxBulkAction, item: AO3InboxItem, auth: AO3AuthService
    ) -> Task<Void, Never>? {
        startAction(action, items: [item], auth: auth)
    }

    /// Once `bulkActionSubmitter` returns success the POST has already reached
    /// AO3 and is single-shot by construction — an account switch afterward can
    /// only suppress *local* follow-up effects (cache invalidation, the reload,
    /// this account's `actionError`/selection state), never retry or duplicate
    /// the write itself.
    private func startAction(
        _ action: AO3InboxBulkAction, items: [AO3InboxItem], auth: AO3AuthService
    ) -> Task<Void, Never>? {
        let expected = AuthContext.current(auth)
        guard isCurrent(expected, auth),
              !isPerformingBulkAction,
              let bulkForm,
              let lastLoadedURL,
              !items.isEmpty,
              items.allSatisfy({ selectableItemIDs.contains($0.id) })
        else { return nil }

        let writeID = UUID()
        activeWriteID = writeID
        actionError = nil
        let operation = WriteOperation(
            id: writeID,
            action: action,
            form: bulkForm,
            items: items,
            referer: lastLoadedURL,
            username: auth.username,
            page: currentPage,
            expected: expected
        )
        return Task { [weak self] in
            guard let self else { return }
            await self.beforeWriteSubmission()
            await self.performAction(operation, auth: auth)
        }
    }

    private func performAction(_ operation: WriteOperation, auth: AO3AuthService) async {
        defer {
            if activeWriteID == operation.id { activeWriteID = nil }
        }
        // `startAction` captured this snapshot synchronously at the button tap,
        // but its task can begin only after a logout/login has already run. Do
        // not turn that queued A tap into a B POST.
        guard isCurrent(operation.expected, auth) else { return }

        do {
            _ = try await bulkActionSubmitter(
                operation.action, operation.form, operation.items, operation.referer, auth
            )
            guard isCurrent(operation.expected, auth) else { return }
            // The page cache's stale fallback must not resurrect the pre-write
            // unread state after a confirmed AO3 update.
            if let username = operation.username {
                await AO3AuthorProfileFetcher.invalidateInbox(
                    username: username,
                    cacheScope: operation.expected.cacheScope,
                    isCurrent: { self.isCurrent(operation.expected, auth) }
                )
            }
            guard isCurrent(operation.expected, auth) else { return }
            if operation.form.actionURL != operation.referer {
                await AO3AuthorProfileFetcher.invalidate(
                    operation.form.actionURL,
                    auth: auth,
                    cacheScope: operation.expected.cacheScope,
                    isCurrent: { self.isCurrent(operation.expected, auth) }
                )
            }
            guard isCurrent(operation.expected, auth) else { return }
            endSelection()
            await load(
                auth: auth,
                expected: operation.expected,
                page: operation.page,
                bypassCache: true
            )
        } catch is CancellationError {
            guard isCurrent(operation.expected, auth) else { return }
            // Never retry a write after cancellation — the request may have reached AO3.
            actionError = "The Inbox update was interrupted. Reload to check AO3's current state."
        } catch AO3Error.authenticationRequired {
            guard isCurrent(operation.expected, auth) else { return }
            reset()
            await auth.sessionDidExpire(expectedGeneration: operation.expected.generation)
        } catch {
            guard isCurrent(operation.expected, auth) else { return }
            if let ao3 = error as? AO3Error, let description = ao3.errorDescription {
                actionError = description
            } else {
                actionError = error.localizedDescription
            }
        }
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

    /// Each public read entry point captures `expected` synchronously before it
    /// creates its task. That makes a queued A refresh inert if B takes over
    /// before the task gets a chance to start. The post-write reload retains the
    /// write's original snapshot for the same reason.
    private func load(
        auth: AO3AuthService,
        expected: AuthContext,
        page: Int,
        bypassCache: Bool = false
    ) async {
        guard !Task.isCancelled, isCurrent(expected, auth) else { return }
        guard let url = inboxURL(auth: auth, page: page)
        else {
            reset()
            return
        }
        phase = items.isEmpty ? .loading : .loaded
        do {
            let fetched = try await pageLoader(
                url,
                auth,
                expected.scope,
                expected.generation,
                bypassCache
            )
            try Task.checkCancellation()
            guard isCurrent(expected, auth) else { return }
            let parsed = try AO3Client.parseInboxPage(fetched.html, page: page)
            items = parsed.items
            currentPage = parsed.currentPage
            totalPages = parsed.totalPages
            totalComments = parsed.totalComments
            unreadCount = parsed.unreadCount
            isShowingStaleCache = fetched.isStale
            bulkForm = parsed.bulkForm
            filterForm = parsed.filterForm
            filterValues = parsed.filterForm?.selectedValues ?? [:]
            lastLoadedURL = url
            metadataRevision &+= 1
            endSelection()
            phase = .loaded
        } catch is CancellationError {
            return
        } catch AO3Error.authenticationRequired {
            guard isCurrent(expected, auth) else { return }
            reset()
            await auth.sessionDidExpire(expectedGeneration: expected.generation)
        } catch {
            guard isCurrent(expected, auth) else { return }
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
        bulkForm = nil
        filterForm = nil
        filterValues = [:]
        lastLoadedURL = nil
        isSelecting = false
        selectedItemIDs = []
        actionError = nil
        // A write started under a previous account keeps running to completion
        // (single-shot; never cancelled — see `performAction`), but this
        // account never asked for it, so it must not read as "performing a
        // bulk action" and stay UI-locked until that background write's own
        // `defer` eventually clears it.
        activeWriteID = nil
        workContextsByID = [:]
        workContextCacheOrder = []
        attemptedMetadataRevisionByWorkID = [:]
        stoppedMetadataRevision = nil
        isEnrichingWorkContexts = false
        metadataRevision = 0
    }

    private func inboxURL(auth: AO3AuthService, page: Int) -> URL? {
        guard let username = auth.username else { return nil }
        if let filterForm,
           let filteredURL = filterForm.url(values: filterValues, page: page) {
            return filteredURL
        }
        return AO3Client.inboxURL(username: username, page: page)
    }

    private func seedWorkContexts(_ contexts: [Int: AO3CommentsWorkContext]) {
        for (workID, seed) in contexts {
            if let existing = workContextsByID[workID] {
                // Existing network/navigation data wins; the local/profile seed
                // only fills fields that are still absent.
                storeWorkContext(seed.merging(existing), for: workID)
            } else {
                storeWorkContext(seed, for: workID)
            }
        }
    }

    private func storeWorkContext(_ context: AO3CommentsWorkContext, for workID: Int) {
        if let existing = workContextsByID[workID] {
            workContextsByID[workID] = existing.merging(context)
            workContextCacheOrder.removeAll(where: { $0 == workID })
        } else {
            workContextsByID[workID] = context
        }
        workContextCacheOrder.append(workID)
        while workContextCacheOrder.count > 128 {
            let evicted = workContextCacheOrder.removeFirst()
            workContextsByID[evicted] = nil
            attemptedMetadataRevisionByWorkID[evicted] = nil
        }
    }

    private static func loadWorkContext(
        workID: Int, auth: AO3AuthService
    ) async throws -> AO3CommentsWorkContext {
        guard let url = URL(
            string: "https://archiveofourown.org/works/\(workID)?view_adult=true"
        ) else { throw AO3Error.network("Bad work URL.") }
        let request = try auth.authenticatedRequest(for: url)
        let metadata = try await AO3RequestCoordinator.shared.withSlot {
            try await AO3Client.shared.workMetadata(workID: workID, request: request)
        }
        return AO3CommentsWorkContext(metadata: metadata)
    }
}
