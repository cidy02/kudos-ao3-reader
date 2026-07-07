import SwiftData
import SwiftUI

/// A login-gated list of AO3 works fetched from one of the user's account pages
/// (Marked for Later, bookmarks, …). Self-contained: signed-out prompt, loading,
/// empty, error + retry, and a paginated list reusing the search result card.
/// A work that's also saved locally renders as its richer local row instead of a
/// second, remote card. Navigates through the host's navigation stack, so the host
/// must register `AO3WorkSummary` and `SavedWork` destinations (all hosts do).
struct AO3AccountWorksList: View {
    /// Which account list to show. Holds the page's copy, URL, and fetch method so
    /// the view body is identical across lists.
    enum Kind: Hashable {
        case markedForLater
        case bookmarks
        case history
        case subscriptions
        case myWorks
        /// Works in a named collection (the user's own collections list links here).
        case collection(name: String, title: String)

        var emptyTitle: String {
            switch self {
            case .markedForLater: "Nothing marked for later"
            case .bookmarks: "No bookmarks yet"
            case .history: "No reading history"
            case .subscriptions: "No subscriptions"
            case .myWorks: "No works yet"
            case .collection: "No works in this collection"
            }
        }

        var emptyMessage: String {
            switch self {
            case .markedForLater: "Tap “Mark for Later” on a work on AO3 to queue it up here."
            case .bookmarks: "Bookmark a work on AO3 to see it here."
            case .history: "Works you read on AO3 show up here."
            case .subscriptions: "Works you subscribe to on AO3 show up here."
            case .myWorks: "Works you post on AO3 show up here."
            case .collection: "This collection has no works yet."
            }
        }

        var signedOutTitle: String {
            switch self {
            case .markedForLater: "Marked for Later"
            case .bookmarks: "AO3 Bookmarks"
            case .history: "AO3 History"
            case .subscriptions: "AO3 Subscriptions"
            case .myWorks: "My Works"
            case let .collection(_, title): title
            }
        }

        var signedOutMessage: String {
            switch self {
            case .markedForLater: "Log in to AO3 to see the works you've marked to read later."
            case .bookmarks: "Log in to AO3 to see the works you've bookmarked."
            case .history: "Log in to AO3 to see your reading history."
            case .subscriptions: "Log in to AO3 to see the works you subscribe to."
            case .myWorks: "Log in to AO3 to see the works you've posted."
            case .collection: "Log in to AO3 to see this collection's works."
            }
        }

        func url(username: String, page: Int) -> URL? {
            switch self {
            case .markedForLater: AO3Client.markedForLaterURL(username: username, page: page)
            case .bookmarks: AO3Client.bookmarksURL(username: username, page: page)
            case .history: AO3Client.historyURL(username: username, page: page)
            case .subscriptions: AO3Client.subscriptionsURL(username: username, page: page)
            case .myWorks: AO3Client.myWorksURL(username: username, page: page)
            case let .collection(name, _): AO3Client.collectionWorksURL(name: name, page: page)
            }
        }

        func fetch(for request: URLRequest, page: Int) async throws -> AO3SearchPage {
            switch self {
            // Standard work-blurb pages; bookmarks and subscriptions need their own
            // outer selector / parser.
            case .markedForLater, .history, .myWorks, .collection:
                try await AO3Client.shared.worksPage(for: request, page: page)
            case .bookmarks:
                try await AO3Client.shared.bookmarksPage(for: request, page: page)
            case .subscriptions:
                try await AO3Client.shared.subscriptionsPage(for: request, page: page)
            }
        }
    }

    let kind: Kind

    @Environment(AO3AuthService.self) private var auth
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var localWorks: [SavedWork]

    @State private var works: [AO3WorkSummary] = []
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var phase: Phase = .idle
    @State private var showLogin = false
    @State private var expandAll = false
    /// Client-side refine of the loaded page — narrows the works on screen in place,
    /// contextual to this account list rather than a fresh AO3 search.
    @State private var filters = AO3SearchFilters()
    @State private var showingFilters = false

    private enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    /// The loaded page narrowed by the active refine filters.
    private var visibleWorks: [AO3WorkSummary] {
        filters.apply(to: works)
    }

    /// The visible page with locally-saved matches paired in, so each renders as
    /// the richer local row. Matching only against privacy-visible works keeps a
    /// Hide-mode Mature work on its plain remote row instead of surfacing local
    /// state for it; in Blur mode the paired local row blurs itself.
    private var visibleEntries: [CanonicalWork] {
        CanonicalWorkMerge.remoteLed(
            remote: visibleWorks,
            localLibrary: localWorks.filter { !gate.isHidden($0, enabled: hideMature, mode: matureMode) }
        )
    }

    var body: some View {
        Group {
            if auth.isLoggedIn {
                signedInContent
            } else {
                signedOutPrompt
            }
        }
        .hidesFloatingTabBar()
        .toolbar {
            // One item holding a tight HStack — separate ToolbarItems get the
            // system's wide spacing, which reads as inconsistent between the privacy
            // toggle and the expand/filter cluster. Matches the pattern already
            // established in LibraryView.swift's dashboard toolbar.
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 2) {
                    if hideMature, visibleEntries.contains(where: { $0.local?.isAdult == true }) {
                        MatureRevealToggle()
                    }
                    if auth.isLoggedIn, phase == .loaded, !works.isEmpty {
                        WorkCardListControls(expandAll: $expandAll,
                                             filtersActive: filters.hasActiveFilters,
                                             showingFilters: $showingFilters,
                                             onClearFilters: { filters = AO3SearchFilters() })
                    }
                }
            }
        }
        .inspector(isPresented: $showingFilters) {
            AO3FilterPanel(
                filters: $filters,
                mode: .refine,
                canReset: filters.hasActiveFilters,
                onApply: { showingFilters = false },
                onReset: { filters = AO3SearchFilters() }
            )
            .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
            .navigationTitle("Filter Works")
        }
        .task(id: auth.isLoggedIn) {
            // Load on first appearance and again right after a sign-in; skip the
            // signed-out state so we don't fire an unauthenticated request.
            if auth.isLoggedIn, phase == .idle { await load(page: 1) }
        }
        .sheet(isPresented: $showLogin) { AO3LoginView() }
    }

    // MARK: Signed in

    @ViewBuilder
    private var signedInContent: some View {
        switch phase {
        case .loaded where works.isEmpty:
            ContentUnavailableView {
                Label(kind.emptyTitle, systemImage: "bookmark")
            } description: {
                Text(kind.emptyMessage)
            }

        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't load your list", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load(page: currentPage) } }
            }

        case .loading where works.isEmpty:
            // First page of this AO3 list — show the work-row shape (same skeleton as
            // Search/Browse) instead of a centered spinner.
            AO3WorkRowSkeletonList()

        default:
            worksList
        }
    }

    private var worksList: some View {
        List {
            if showPagination {
                Section { paginationRow }
            }
            Section {
                ForEach(visibleEntries) { entry in
                    if let work = entry.local {
                        SensitiveWorkRow(work: work, expandAll: expandAll)
                    } else if let remote = entry.remote {
                        AO3WorkRow(work: remote, expandAll: expandAll).cardNavigation(to: remote)
                    }
                }
                .cardRow()
            }
            if showPagination {
                Section { paginationRow }
            }
        }
        .cardList()
        .overlay {
            if phase == .loading {
                ProgressView().controlSize(.large)
            } else if visibleWorks.isEmpty, !works.isEmpty {
                // Everything on the page was filtered out by the refine facets.
                ContentUnavailableView {
                    Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No works on this page match the current filters.")
                } actions: {
                    Button("Clear Filters") { filters = AO3SearchFilters() }
                }
            }
        }
        .refreshable { await load(page: currentPage) }
    }

    private var showPagination: Bool {
        totalPages > 1 && !works.isEmpty
    }

    private var paginationRow: some View {
        SearchPaginationBar(currentPage: currentPage, totalPages: totalPages) { page in
            Task { await load(page: page) }
        }
        .cardRow()
    }

    // MARK: Signed out

    private var signedOutPrompt: some View {
        ContentUnavailableView {
            Label(kind.signedOutTitle, systemImage: "bookmark")
        } description: {
            Text(kind.signedOutMessage)
        } actions: {
            Button("Log In to AO3") { showLogin = true }
        }
    }

    // MARK: Loading

    private func load(page: Int) async {
        guard let username = auth.username,
              let url = kind.url(username: username, page: page)
        else {
            phase = .failed("You need to be logged in to AO3.")
            return
        }
        phase = .loading
        do {
            let request = try auth.authenticatedRequest(for: url)
            let result = try await kind.fetch(for: request, page: page)
            works = result.works
            currentPage = result.currentPage
            totalPages = result.totalPages
            phase = .loaded
        } catch AO3Error.authenticationRequired {
            await auth.sessionDidExpire()
            works = []
            phase = .idle // back to the signed-out prompt
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
