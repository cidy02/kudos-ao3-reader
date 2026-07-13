import Foundation

/// State for the signed-in user's AO3 Inbox feed (Account › Activity › Inbox).
/// Fetches go through `AO3AuthorProfileFetcher` for the same TTL cache,
/// coordinator slot, pacing, and stale-fallback discipline as author pages (the
/// cache is keyed by full URL + authentication scope, so inbox HTML can never
/// leak across accounts). Bulk writes use the exact parsed Inbox form once only.
@MainActor
@Observable
final class AO3InboxModel {
    typealias WorkContextLoader = (Int, AO3AuthService) async throws -> AO3CommentsWorkContext

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

    private var authenticationScope = ""
    private var activeTask: Task<Void, Never>?
    private var lastLoadedURL: URL?
    private var workContextCacheOrder: [Int] = []
    private var attemptedMetadataRevisionByWorkID: [Int: Int] = [:]
    private var stoppedMetadataRevision: Int?
    private let workContextLoader: WorkContextLoader

    init() {
        workContextLoader = Self.loadWorkContext
    }

    init(workContextLoader: @escaping WorkContextLoader) {
        self.workContextLoader = workContextLoader
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
    func cacheWorkContext(_ context: AO3CommentsWorkContext, for workID: Int) {
        storeWorkContext(context, for: workID)
    }

    /// Enriches only the distinct work ids rendered by the current Inbox view.
    /// The calling view owns this async task, so leaving Inbox or changing page
    /// cancels the loop. Requests are sequential even though each also claims the
    /// app-wide metadata coordinator slot.
    func enrichVisibleWorkContexts(
        workIDs: [Int], seededContexts: [Int: AO3CommentsWorkContext],
        auth: AO3AuthService
    ) async {
        let startingScope = AO3AuthorProfileFetcher.authenticationScope(for: auth)
        guard !startingScope.isEmpty, startingScope == authenticationScope else { return }
        seedWorkContexts(seededContexts)

        let ids = Self.uniqueWorkIDs(workIDs)
        guard !ids.isEmpty, stoppedMetadataRevision != metadataRevision else { return }
        isEnrichingWorkContexts = true
        defer {
            if authenticationScope == startingScope { isEnrichingWorkContexts = false }
        }

        for workID in ids {
            do {
                try Task.checkCancellation()
                guard authenticationScope == startingScope else { return }
                if let context = workContextsByID[workID], !context.needsSummaryEnrichment {
                    continue
                }
                guard attemptedMetadataRevisionByWorkID[workID] != metadataRevision else {
                    continue
                }
                attemptedMetadataRevisionByWorkID[workID] = metadataRevision

                let context = try await workContextLoader(workID, auth)
                try Task.checkCancellation()
                guard authenticationScope == startingScope else { return }
                storeWorkContext(context, for: workID)
            } catch is CancellationError {
                if attemptedMetadataRevisionByWorkID[workID] == metadataRevision {
                    attemptedMetadataRevisionByWorkID[workID] = nil
                }
                return
            } catch let error as URLError where error.code == .cancelled {
                if attemptedMetadataRevisionByWorkID[workID] == metadataRevision {
                    attemptedMetadataRevisionByWorkID[workID] = nil
                }
                return
            } catch AO3Error.authenticationRequired {
                guard authenticationScope == startingScope else { return }
                await auth.sessionDidExpire()
                return
            } catch AO3Error.notFound {
                // One deleted/restricted work must not prevent later visible
                // notifications from receiving their metadata.
                continue
            } catch {
                // Offline, rate-limit, CDN, and parser failures are likely to
                // affect the whole batch. Stop instead of multiplying retries.
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
        guard !isPerformingBulkAction else { return }
        launch { await self.load(auth: auth, page: page) }
    }

    func retry(auth: AO3AuthService) {
        guard !isPerformingBulkAction else { return }
        launch { await self.load(auth: auth, page: self.currentPage, bypassCache: true) }
    }

    func refresh(auth: AO3AuthService) async {
        guard !isPerformingBulkAction else { return }
        let task = launch { await self.load(auth: auth, page: self.currentPage, bypassCache: true) }
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
        guard !isPerformingBulkAction,
              let field = filterForm?.fields.first(where: { $0.name == fieldName }),
              field.options.contains(where: { $0.value == value })
        else { return }
        filterValues[fieldName] = value
        endSelection()
        launch { await self.load(auth: auth, page: 1, bypassCache: true) }
    }

    func clearActionError() {
        actionError = nil
    }

    /// Executes one mass-edit POST. This never shares `activeTask`: a new read
    /// must not cancel an in-flight write, and a second action stays disabled until
    /// the first response arrives.
    func performBulkAction(_ action: AO3InboxBulkAction, auth: AO3AuthService) async {
        await performAction(action, items: selectedItems, auth: auth)
    }

    func canPerformItemAction(_ action: AO3InboxBulkAction, item: AO3InboxItem) -> Bool {
        guard let bulkForm, selectableItemIDs.contains(item.id) else { return false }
        return bulkForm.parameters(for: [item], action: action) != nil
    }

    func performItemAction(
        _ action: AO3InboxBulkAction, item: AO3InboxItem, auth: AO3AuthService
    ) async {
        await performAction(action, items: [item], auth: auth)
    }

    private func performAction(
        _ action: AO3InboxBulkAction, items: [AO3InboxItem], auth: AO3AuthService
    ) async {
        let startingScope = AO3AuthorProfileFetcher.authenticationScope(for: auth)
        let startingUsername = auth.username
        guard startingScope == authenticationScope,
              !isPerformingBulkAction,
              let bulkForm,
              let lastLoadedURL,
              !items.isEmpty,
              items.allSatisfy({ selectableItemIDs.contains($0.id) })
        else { return }

        let writeID = UUID()
        activeWriteID = writeID
        actionError = nil
        defer {
            if activeWriteID == writeID { activeWriteID = nil }
        }

        do {
            _ = try await auth.performInboxBulkAction(
                action,
                form: bulkForm,
                items: items,
                referer: lastLoadedURL
            )
            guard startingScope == authenticationScope,
                  startingScope == AO3AuthorProfileFetcher.authenticationScope(for: auth)
            else { return }
            // The page cache's stale fallback must not resurrect the pre-write
            // unread state after a confirmed AO3 update.
            if let startingUsername {
                await AO3AuthorProfileFetcher.invalidateInbox(
                    username: startingUsername,
                    authenticationScope: startingScope
                )
            }
            if bulkForm.actionURL != lastLoadedURL {
                await AO3AuthorProfileFetcher.invalidate(bulkForm.actionURL, auth: auth)
            }
            endSelection()
            await load(auth: auth, page: currentPage, bypassCache: true)
        } catch is CancellationError {
            guard startingScope == authenticationScope else { return }
            // Never retry a write after cancellation — the request may have reached AO3.
            actionError = "The Inbox update was interrupted. Reload to check AO3's current state."
        } catch AO3Error.authenticationRequired {
            guard startingScope == authenticationScope else { return }
            await auth.sessionDidExpire()
            reset()
        } catch {
            guard startingScope == authenticationScope else { return }
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

    private func load(auth: AO3AuthService, page: Int, bypassCache: Bool = false) async {
        guard let url = inboxURL(auth: auth, page: page)
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
        bulkForm = nil
        filterForm = nil
        filterValues = [:]
        lastLoadedURL = nil
        isSelecting = false
        selectedItemIDs = []
        actionError = nil
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
