import Foundation

@MainActor
enum AO3AuthorProfileFetcher {
    struct Page {
        let html: String
        let isStale: Bool
    }

    static func authenticationScope(for auth: AO3AuthService) -> String {
        auth.isLoggedIn ? "signed-in:\(auth.username ?? "unknown")" : "anonymous"
    }

    static func page(
        at url: URL,
        auth: AO3AuthService,
        bypassCache: Bool = false
    ) async throws -> Page {
        let key = AO3AuthorPageCache.Key(
            url: url,
            authenticationScope: authenticationScope(for: auth)
        )
        if !bypassCache, let cached = await AO3AuthorPageCache.shared.value(for: key) {
            return Page(html: cached, isStale: false)
        }

        let request = auth.isLoggedIn ? try auth.authenticatedRequest(for: url) : nil
        do {
            let html = try await AO3RequestCoordinator.shared.withSlot {
                if let request {
                    try await AO3Client.shared.authenticatedPageHTML(for: request)
                } else {
                    try await AO3Client.shared.getHTML(url)
                }
            }
            await AO3AuthorPageCache.shared.insert(html, for: key)
            return Page(html: html, isStale: false)
        } catch AO3Error.authenticationRequired {
            // Never hide an expired session behind cached authenticated markup.
            throw AO3Error.authenticationRequired
        } catch {
            if let stale = await AO3AuthorPageCache.shared.staleValue(for: key) {
                return Page(html: stale, isStale: true)
            }
            throw error
        }
    }

    static func invalidate(_ url: URL, auth: AO3AuthService) async {
        let key = AO3AuthorPageCache.Key(
            url: url,
            authenticationScope: authenticationScope(for: auth)
        )
        await AO3AuthorPageCache.shared.removeValue(for: key)
    }

    static func invalidateAuthorDashboards(
        username: String,
        authenticationScope: String
    ) async {
        await AO3AuthorPageCache.shared.removeAuthorDashboards(
            username: username,
            authenticationScope: authenticationScope
        )
    }
}

@MainActor
@Observable
final class AO3AuthorProfileModel {
    typealias PageLoader = @MainActor (
        _ url: URL,
        _ auth: AO3AuthService,
        _ bypassCache: Bool
    ) async throws -> AO3AuthorProfileFetcher.Page

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
        case unavailable
    }

    private(set) var route: AO3AuthorRoute
    var selectedTab: AO3AuthorProfileTab = .works
    private(set) var selectedFandom: AO3AuthorFandom?
    private(set) var header: AO3AuthorHeader?
    private(set) var about: AO3AuthorAbout?
    private(set) var works: [AO3WorkSummary] = []
    private(set) var series: [AO3SeriesSummary] = []
    private(set) var bookmarks: [AO3AuthorBookmark] = []
    private(set) var headerPhase: Phase = .idle
    private(set) var contentPhase: Phase = .idle
    private(set) var isLoadingMore = false
    private(set) var loadMoreError: String?
    private(set) var isShowingStaleCache = false
    private(set) var isPerformingSubscription = false
    private(set) var isPerformingModeration = false
    /// Set after a successful confirm-page fetch; the UI presents a native dialog.
    private(set) var pendingModerationForm: AO3AuthorModerationForm?
    /// Snapshot for submit — SwiftUI alert dismiss can clear `pendingModerationForm`
    /// before the confirm button's `Task` runs, which previously no-op'd the POST.
    private var moderationFormForSubmit: AO3AuthorModerationForm?
    private(set) var actionMessage: String?

    private var worksPage = 0
    private var worksTotalPages = 1
    private var seriesPage = 0
    private var seriesTotalPages = 1
    private var bookmarksPage = 0
    private var bookmarksTotalPages = 1
    private var loadedTabs = Set<AO3AuthorProfileTab>()
    private var authenticationScope = ""
    private var activeTask: Task<Void, Never>?
    private let pageLoader: PageLoader

    init(
        route: AO3AuthorRoute,
        pageLoader: @escaping PageLoader = { url, auth, bypassCache in
            try await AO3AuthorProfileFetcher.page(
                at: url,
                auth: auth,
                bypassCache: bypassCache
            )
        }
    ) {
        self.route = route
        self.pageLoader = pageLoader
    }

    var hasMore: Bool {
        switch selectedTab {
        case .works: worksPage < worksTotalPages
        case .series: seriesPage < seriesTotalPages
        case .bookmarks: bookmarksPage < bookmarksTotalPages
        case .about: false
        }
    }

    var currentPage: Int {
        switch selectedTab {
        case .works: worksPage
        case .series: seriesPage
        case .bookmarks: bookmarksPage
        case .about: 1
        }
    }

    var totalPages: Int {
        switch selectedTab {
        case .works: worksTotalPages
        case .series: seriesTotalPages
        case .bookmarks: bookmarksTotalPages
        case .about: 1
        }
    }

    func activate(auth: AO3AuthService) {
        let scope = AO3AuthorProfileFetcher.authenticationScope(for: auth)
        if authenticationScope != scope {
            authenticationScope = scope
            resetForAuthenticationChange()
        }
        guard headerPhase != .loaded || !loadedTabs.contains(selectedTab) else { return }
        launch {
            await self.loadHeader(auth: auth)
            guard self.headerPhase == .loaded else { return }
            await self.loadSelectedTab(auth: auth)
        }
    }

    func selectTab(_ tab: AO3AuthorProfileTab, auth: AO3AuthService) {
        guard selectedTab != tab else { return }
        selectedTab = tab
        loadMoreError = nil
        if loadedTabs.contains(tab) {
            activeTask?.cancel()
            contentPhase = .loaded
            return
        }
        launch { await self.loadSelectedTab(auth: auth) }
    }

    func selectScope(_ route: AO3AuthorRoute, auth: AO3AuthService) {
        guard self.route != route else { return }
        let keepsAccountAbout = self.route.username.localizedCaseInsensitiveCompare(route.username)
            == .orderedSame
        self.route = route
        selectedFandom = nil
        if !keepsAccountAbout { about = nil }
        resetScopedContent(keepingAbout: keepsAccountAbout)
        launch {
            await self.loadHeader(auth: auth)
            guard self.headerPhase == .loaded else { return }
            await self.loadSelectedTab(auth: auth)
        }
    }

    func selectFandom(_ fandom: AO3AuthorFandom?, auth: AO3AuthService) {
        guard selectedTab == .works, selectedFandom != fandom else { return }
        selectedFandom = fandom
        works = []
        worksPage = 0
        worksTotalPages = 1
        loadedTabs.remove(.works)
        launch { await self.loadWorks(auth: auth, page: 1, replace: true) }
    }

    func loadMore(auth: AO3AuthService) {
        guard hasMore, !isLoadingMore else { return }
        let nextPage = currentPage + 1
        loadMoreError = nil
        isLoadingMore = true
        launch {
            defer { self.isLoadingMore = false }
            do {
                switch self.selectedTab {
                case .works:
                    try await self.fetchWorks(auth: auth, page: nextPage, replace: false)
                case .series:
                    try await self.fetchSeries(auth: auth, page: nextPage, replace: false)
                case .bookmarks:
                    try await self.fetchBookmarks(auth: auth, page: nextPage, replace: false)
                case .about:
                    break
                }
            } catch is CancellationError {
                return
            } catch {
                self.loadMoreError = Self.message(for: error)
            }
        }
    }

    func retry(auth: AO3AuthService) {
        launch {
            if self.headerPhase != .loaded {
                await self.loadHeader(auth: auth, bypassCache: true)
            }
            guard self.headerPhase == .loaded else { return }
            await self.loadSelectedTab(auth: auth, force: true, bypassCache: true)
        }
    }

    func refresh(auth: AO3AuthService) async {
        let task = launch {
            await self.loadHeader(auth: auth, bypassCache: true)
            guard self.headerPhase == .loaded else { return }
            await self.loadSelectedTab(auth: auth, force: true, bypassCache: true)
        }
        await task.value
    }

    func toggleSubscription(auth: AO3AuthService) async {
        guard let form = header?.subscriptionForm, !isPerformingSubscription else { return }
        let actionRoute = route
        let actionAuthenticationScope = AO3AuthorProfileFetcher.authenticationScope(for: auth)
        isPerformingSubscription = true
        actionMessage = nil
        defer { isPerformingSubscription = false }
        do {
            let message = try await auth.submitAuthorSubscription(form)
            await AO3AuthorProfileFetcher.invalidateAuthorDashboards(
                username: actionRoute.username,
                authenticationScope: actionAuthenticationScope
            )
            guard route.username.localizedCaseInsensitiveCompare(actionRoute.username)
                    == .orderedSame,
                  AO3AuthorProfileFetcher.authenticationScope(for: auth)
                    == actionAuthenticationScope else { return }
            actionMessage = message
            await reloadHeaderTracked(auth: auth)
        } catch AO3Error.authenticationRequired {
            guard AO3AuthorProfileFetcher.authenticationScope(for: auth)
                == actionAuthenticationScope else { return }
            await auth.sessionDidExpire()
        } catch {
            guard AO3AuthorProfileFetcher.authenticationScope(for: auth)
                == actionAuthenticationScope else { return }
            actionMessage = Self.message(for: error)
        }
    }

    /// Fetches AO3's block/mute confirm page, parses the form, and stages it for a
    /// native confirmation screen — never opens the in-app browser. Signed-out taps
    /// set `actionMessage` to "Log in to AO3 first." (same alert as Subscribe).
    func beginModeration(action: AO3AuthorWebAction, auth: AO3AuthService) async {
        guard action.kind == .block || action.kind == .mute,
              !isPerformingModeration else { return }
        guard auth.isLoggedIn else {
            actionMessage = AO3WriteError.notSignedIn.localizedDescription
            return
        }
        let actionRoute = route
        let actionAuthenticationScope = AO3AuthorProfileFetcher.authenticationScope(for: auth)
        isPerformingModeration = true
        actionMessage = nil
        pendingModerationForm = nil
        moderationFormForSubmit = nil
        defer { isPerformingModeration = false }
        do {
            let page = try await pageLoader(action.url, auth, true)
            let form = try AO3Client.parseAuthorModerationForm(
                page.html,
                referer: action.url,
                webKind: action.kind,
                targetUsername: actionRoute.username
            )
            guard route.username.localizedCaseInsensitiveCompare(actionRoute.username)
                    == .orderedSame,
                  AO3AuthorProfileFetcher.authenticationScope(for: auth)
                    == actionAuthenticationScope else { return }
            // Keep a submit snapshot; the alert binding may clear `pending` on dismiss.
            moderationFormForSubmit = form
            pendingModerationForm = form
        } catch AO3Error.authenticationRequired {
            guard AO3AuthorProfileFetcher.authenticationScope(for: auth)
                == actionAuthenticationScope else { return }
            await auth.sessionDidExpire()
        } catch {
            guard AO3AuthorProfileFetcher.authenticationScope(for: auth)
                == actionAuthenticationScope else { return }
            actionMessage = Self.message(for: error)
        }
    }

    func confirmPendingModeration(auth: AO3AuthService) async {
        // Prefer the snapshot — alert dismiss often nils `pendingModerationForm` first.
        guard let form = moderationFormForSubmit ?? pendingModerationForm,
              !isPerformingModeration else { return }
        let actionRoute = route
        let actionAuthenticationScope = AO3AuthorProfileFetcher.authenticationScope(for: auth)
        isPerformingModeration = true
        actionMessage = nil
        pendingModerationForm = nil
        moderationFormForSubmit = nil
        defer { isPerformingModeration = false }
        do {
            let message = try await auth.submitAuthorModeration(form)
            await AO3AuthorProfileFetcher.invalidateAuthorDashboards(
                username: actionRoute.username,
                authenticationScope: actionAuthenticationScope
            )
            guard route.username.localizedCaseInsensitiveCompare(actionRoute.username)
                    == .orderedSame,
                  AO3AuthorProfileFetcher.authenticationScope(for: auth)
                    == actionAuthenticationScope else { return }
            actionMessage = message
            await reloadHeaderTracked(auth: auth)
        } catch AO3Error.authenticationRequired {
            guard AO3AuthorProfileFetcher.authenticationScope(for: auth)
                == actionAuthenticationScope else { return }
            await auth.sessionDidExpire()
        } catch {
            guard AO3AuthorProfileFetcher.authenticationScope(for: auth)
                == actionAuthenticationScope else { return }
            actionMessage = Self.message(for: error)
        }
    }

    func cancelPendingModeration() {
        pendingModerationForm = nil
        moderationFormForSubmit = nil
    }

    func clearActionMessage() {
        actionMessage = nil
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
    }

    /// Lets deterministic tests await the model's current load without changing
    /// the view-facing fire-and-forget API used by tab and scope controls.
    func waitForActiveLoad() async {
        await activeTask?.value
    }

    @discardableResult
    private func launch(
        _ operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        activeTask?.cancel()
        let task = Task { await operation() }
        activeTask = task
        return task
    }

    /// Reloads the header through the same tracked `activeTask` every other load
    /// uses — a bare `await loadHeader(...)` here would run un-cancellable (survives
    /// `cancel()`/`onDisappear`) and could race a scope/tab change's own in-flight
    /// fetch of the same page instead of superseding it.
    private func reloadHeaderTracked(auth: AO3AuthService) async {
        await launch { await self.loadHeader(auth: auth, bypassCache: true) }.value
    }

    private func loadHeader(
        auth: AO3AuthService,
        bypassCache: Bool = false
    ) async {
        let expectedRoute = route
        headerPhase = header == nil ? .loading : .loaded
        do {
            let page = try await parsedPage(
                at: expectedRoute.dashboardURL,
                auth: auth,
                bypassCache: bypassCache
            ) {
                try AO3Client.parseAuthorDashboard($0, route: expectedRoute)
            }
            guard !Task.isCancelled, route == expectedRoute else { return }
            header = page.value
            // A fresh dashboard parse doesn't repeat pseud aliases the About tab
            // already found (e.g. ones only listed on the profile page, not the
            // dashboard) — reapply them so a reload doesn't quietly drop pseuds
            // the user could already see and select.
            mergeAboutPseudsIntoHeader(about?.pseuds ?? [])
            isShowingStaleCache = page.isStale
            headerPhase = .loaded
        } catch is CancellationError {
            return
        } catch AO3Error.authenticationRequired {
            await auth.sessionDidExpire()
            guard route == expectedRoute else { return }
            header = nil
            headerPhase = .idle
        } catch AO3Error.notFound {
            guard route == expectedRoute else { return }
            header = nil
            headerPhase = .unavailable
        } catch {
            guard route == expectedRoute else { return }
            headerPhase = .failed(Self.message(for: error))
        }
    }

    private func loadSelectedTab(
        auth: AO3AuthService,
        force: Bool = false,
        bypassCache: Bool = false
    ) async {
        let tab = selectedTab
        if !force, loadedTabs.contains(tab) {
            contentPhase = .loaded
            return
        }
        switch tab {
        case .works:
            await loadWorks(auth: auth, page: 1, replace: true, bypassCache: bypassCache)
        case .series:
            await loadSeries(auth: auth, page: 1, replace: true, bypassCache: bypassCache)
        case .bookmarks:
            await loadBookmarks(auth: auth, page: 1, replace: true, bypassCache: bypassCache)
        case .about:
            await loadAbout(auth: auth, bypassCache: bypassCache)
        }
    }

    private func loadWorks(
        auth: AO3AuthService,
        page: Int,
        replace: Bool,
        bypassCache: Bool = false
    ) async {
        contentPhase = works.isEmpty ? .loading : .loaded
        do {
            try await fetchWorks(
                auth: auth,
                page: page,
                replace: replace,
                bypassCache: bypassCache
            )
            loadedTabs.insert(.works)
            contentPhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            contentPhase = .failed(Self.message(for: error))
        }
    }

    private func fetchWorks(
        auth: AO3AuthService,
        page: Int,
        replace: Bool,
        bypassCache: Bool = false
    ) async throws {
        let baseURL = selectedFandom?.url ?? route.contentURL(.works)
        let url = Self.pageURL(baseURL, page: page)
        let cached = try await parsedPage(at: url, auth: auth, bypassCache: bypassCache) {
            try AO3Client.parseAuthorWorksPage($0, page: page)
        }
        try Task.checkCancellation()
        works = replace
            ? cached.value.works
            : Self.appendingUnique(works, cached.value.works, id: \.id)
        worksPage = cached.value.currentPage
        worksTotalPages = cached.value.totalPages
        isShowingStaleCache = isShowingStaleCache || cached.isStale
    }

    private func loadSeries(
        auth: AO3AuthService,
        page: Int,
        replace: Bool,
        bypassCache: Bool = false
    ) async {
        contentPhase = series.isEmpty ? .loading : .loaded
        do {
            try await fetchSeries(
                auth: auth,
                page: page,
                replace: replace,
                bypassCache: bypassCache
            )
            loadedTabs.insert(.series)
            contentPhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            contentPhase = .failed(Self.message(for: error))
        }
    }

    private func fetchSeries(
        auth: AO3AuthService,
        page: Int,
        replace: Bool,
        bypassCache: Bool = false
    ) async throws {
        let url = route.contentURL(.series, page: page)
        let cached = try await parsedPage(at: url, auth: auth, bypassCache: bypassCache) {
            try AO3Client.parseAuthorSeriesPage($0, page: page)
        }
        try Task.checkCancellation()
        series = replace
            ? cached.value.series
            : Self.appendingUnique(series, cached.value.series, id: \.id)
        seriesPage = cached.value.currentPage
        seriesTotalPages = cached.value.totalPages
        isShowingStaleCache = isShowingStaleCache || cached.isStale
    }

    private func loadBookmarks(
        auth: AO3AuthService,
        page: Int,
        replace: Bool,
        bypassCache: Bool = false
    ) async {
        contentPhase = bookmarks.isEmpty ? .loading : .loaded
        do {
            try await fetchBookmarks(
                auth: auth,
                page: page,
                replace: replace,
                bypassCache: bypassCache
            )
            loadedTabs.insert(.bookmarks)
            contentPhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            contentPhase = .failed(Self.message(for: error))
        }
    }

    private func fetchBookmarks(
        auth: AO3AuthService,
        page: Int,
        replace: Bool,
        bypassCache: Bool = false
    ) async throws {
        let url = route.contentURL(.bookmarks, page: page)
        let cached = try await parsedPage(at: url, auth: auth, bypassCache: bypassCache) {
            try AO3Client.parseAuthorBookmarksPage($0, page: page)
        }
        try Task.checkCancellation()
        bookmarks = replace
            ? cached.value.bookmarks
            : Self.appendingUnique(bookmarks, cached.value.bookmarks, id: \.id)
        bookmarksPage = cached.value.currentPage
        bookmarksTotalPages = cached.value.totalPages
        isShowingStaleCache = isShowingStaleCache || cached.isStale
    }

    private func loadAbout(
        auth: AO3AuthService,
        bypassCache: Bool = false
    ) async {
        contentPhase = about == nil ? .loading : .loaded
        do {
            let profileURL = route.profileURL
            let cached = try await parsedPage(
                at: profileURL,
                auth: auth,
                bypassCache: bypassCache
            ) {
                try AO3Client.parseAuthorAbout($0, route: route)
            }
            try Task.checkCancellation()
            about = cached.value
            mergeAboutPseudsIntoHeader(cached.value.pseuds)
            loadedTabs.insert(.about)
            isShowingStaleCache = isShowingStaleCache || cached.isStale
            contentPhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            contentPhase = .failed(Self.message(for: error))
        }
    }

    private func mergeAboutPseudsIntoHeader(_ pseuds: [AO3AuthorPseud]) {
        guard var header, !pseuds.isEmpty else { return }
        var known = Set(header.pseuds.map(\.route.id))
        header.pseuds += pseuds.filter { known.insert($0.route.id).inserted }
        header.pseuds.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.header = header
    }

    private func resetForAuthenticationChange() {
        header = nil
        about = nil
        selectedFandom = nil
        resetScopedContent(keepingAbout: false)
        isShowingStaleCache = false
        actionMessage = nil
    }

    private func resetScopedContent(keepingAbout: Bool) {
        header = nil
        headerPhase = .idle
        works = []
        series = []
        bookmarks = []
        worksPage = 0
        seriesPage = 0
        bookmarksPage = 0
        worksTotalPages = 1
        seriesTotalPages = 1
        bookmarksTotalPages = 1
        contentPhase = .idle
        loadMoreError = nil
        loadedTabs = keepingAbout && about != nil ? [.about] : []
    }

    private static func appendingUnique<Value, ID: Hashable>(
        _ current: [Value],
        _ incoming: [Value],
        id: KeyPath<Value, ID>
    ) -> [Value] {
        var seen = Set(current.map { $0[keyPath: id] })
        return current + incoming.filter { seen.insert($0[keyPath: id]).inserted }
    }

    private func parsedPage<Value>(
        at url: URL,
        auth: AO3AuthService,
        bypassCache: Bool,
        parse: (String) throws -> Value
    ) async throws -> (value: Value, isStale: Bool) {
        let page = try await pageLoader(url, auth, bypassCache)
        do {
            return (try parse(page.html), page.isStale)
        } catch {
            if let ao3Error = error as? AO3Error, case .parse = ao3Error {
                await AO3AuthorProfileFetcher.invalidate(url, auth: auth)
            }
            throw error
        }
    }

    private static func pageURL(_ url: URL, page: Int) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = (components.queryItems ?? []).filter { $0.name != "page" }
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url ?? url
    }

    private static func message(for error: Error) -> String {
        if let ao3 = error as? AO3Error, let description = ao3.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

extension AO3AuthService {
    /// Submits the exact user-subscription form AO3 exposed on this profile. The
    /// endpoint, hidden fields, method override, and CSRF token all come from that
    /// fetched page; no action is synthesized and the POST remains single-shot.
    func submitAuthorSubscription(_ form: AO3AuthorSubscriptionForm) async throws -> String {
        try await submitScrapedHTMLForm(
            actionURL: form.actionURL,
            fields: form.fields,
            csrfToken: form.csrfToken,
            referer: form.referer,
            successMessage: form.isSubscribed ? "Unsubscribed." : "Subscribed.",
            failureFallback: "AO3 didn't accept the subscription change."
        )
    }

    /// Submits the exact block/mute (or undo) form from AO3's confirm page —
    /// same `writeRequest` / `submitWrite` path as subscription.
    func submitAuthorModeration(_ form: AO3AuthorModerationForm) async throws -> String {
        try await submitScrapedHTMLForm(
            actionURL: form.actionURL,
            fields: form.fields,
            csrfToken: form.csrfToken,
            referer: form.referer,
            successMessage: form.kind.successMessage,
            failureFallback: "AO3 didn't accept the \(form.kind.rawValue) action."
        )
    }

    /// Shared single-shot POST for scraped AO3 forms (subscribe, block/mute, …).
    /// Reuses `writeRequest`, `formEncoded`, `submitWrite`, and `writeErrorMessage`.
    private func submitScrapedHTMLForm(
        actionURL: URL,
        fields: [AO3FormField],
        csrfToken: String,
        referer: URL,
        successMessage: String,
        failureFallback: String
    ) async throws -> String {
        guard isLoggedIn else { throw AO3WriteError.notSignedIn }
        var pairs = fields.map { ($0.name, $0.value) }
        if !pairs.contains(where: { $0.0 == "authenticity_token" }) {
            pairs.append(("authenticity_token", csrfToken))
        }
        // Rails may put ids only on the form action query string (block/mute).
        if let items = URLComponents(url: actionURL, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items {
                guard let value = item.value,
                      !pairs.contains(where: { $0.0 == item.name }) else { continue }
                pairs.append((item.name, value))
            }
        }
        let request = try writeRequest(
            to: actionURL,
            body: Self.formEncoded(pairs),
            csrf: csrfToken,
            referer: referer,
            ajax: false
        )
        let (status, body) = try await AO3Client.shared.submitWrite(request)
        if let error = AO3Client.writeErrorMessage(in: body) {
            throw AO3WriteError.rejected(error)
        }
        guard (200 ... 399).contains(status) else {
            throw AO3WriteError.rejected(failureFallback)
        }
        return successMessage
    }
}
