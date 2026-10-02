import SwiftData
import SwiftUI

struct AO3SeriesDetailView: View {
    private enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let series: AO3SeriesSummary

    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(PrivacyGate.self) private var gate
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var localWorks: [SavedWork]
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @State private var works: [AO3WorkSummary] = []
    @State private var currentPage = 0
    @State private var totalPages = 1
    @State private var phase: Phase = .idle
    @State private var isLoadingMore = false
    @State private var loadMoreError: String?
    @State private var isShowingStaleCache = false
    @State private var expandAll = false
    /// Select over the series' works — Browse's remote selection shell and
    /// bulk bar (T-339).
    @State private var bulkSelection = RemoteWorkSelectionController()
    @State private var loadTask: Task<Void, Never>?
    /// 1br's Edit series, pushed rather than presented — a `NavigationLink` inside
    /// a `Menu` does not reliably push.
    @State private var isEditingSeries = false
    /// Reorder lives in "…" like every other ordered list (pass2-14); AO3's
    /// save step keeps it a pushed screen rather than an in-place mode.
    @State private var isReorderingSeries = false

    /// Whether the signed-in account is one of this series' creators — the gate on
    /// 1br's Edit series.
    ///
    /// Matched on the *registered identity's username*, not on the displayed
    /// byline: a byline is a pseud, and comparing it to `auth.username` would both
    /// miss a creator posting under a pseud and match a stranger whose pseud
    /// happens to equal your account name.
    private var canEditSeries: Bool {
        auth.isLoggedIn && series.isCreator(username: auth.username)
    }

    var body: some View {
        List {
            Section {
                AO3SeriesRow(series: series)
                    .cardRow()
            }

            if isShowingStaleCache {
                Section {
                    Label("Showing cached AO3 data", systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .cardRow()
                }
            }

            Section {
                worksContent
            } header: {
                SectionRuleHeader(title: "Works", count: works.isEmpty ? nil : works.count)
                    .textCase(nil)
                    .listRowInsets(EdgeInsets())
            }
        }
        .cardList()
        .navigationTitle("Series")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .hidesFloatingTabBar()
            .toolbar {
                if bulkSelection.isSelecting {
                    RemoteWorkSelectionToolbar(controller: bulkSelection) {
                        bulkSelection.selected(in: works)
                    }
                } else {
                    ActionToolbar(items: [
                        // The app's one "…" order (pass2-1): Mature, Select, Reorder,
                        // Expand, then the page's own items.
                        AnyView(
                            WorkListMoreMenu {
                                if hideMature {
                                    MatureRevealToggle()
                                }
                                if !works.isEmpty {
                                    Button { bulkSelection.isSelecting = true } label: {
                                        Label("Select", systemImage: "checklist")
                                    }
                                }
                                if canEditSeries, works.count > 1 {
                                    Button { isReorderingSeries = true } label: {
                                        Label("Reorder", systemImage: "arrow.up.arrow.down")
                                    }
                                }
                                if !works.isEmpty {
                                    ExpandAllMenuItem(expandAll: $expandAll)
                                    Divider()
                                }
                                if canEditSeries {
                                    Button { isEditingSeries = true } label: {
                                        Label("Edit series", systemImage: "square.and.pencil")
                                    }
                                }
                                Button { router.open(series.url) } label: {
                                    Label("Open on AO3", systemImage: "safari")
                                }
                                ShareLink(item: series.url) {
                                    Label("Share Series", systemImage: "square.and.arrow.up")
                                }
                            }
                        )
                    ])
                }
            }
            .remoteWorkSelectionChrome(bulkSelection)
            .navigationDestination(isPresented: $isEditingSeries) {
                SeriesEditDestination(series: series, works: works)
            }
            .navigationDestination(isPresented: $isReorderingSeries) {
                SeriesReorderDestination(seriesID: series.id, seriesTitle: series.title)
            }
            .refreshable {
                // bypassCache clears the app-level AO3AuthorPageCache; this clears the
                // HTTP one underneath it, which would otherwise serve the same page back.
                await AO3Client.shared.invalidateCachedResponses()
                await load(page: 1, replace: true, bypassCache: true)
            }
            .task(id: authenticationScope) {
                loadTask?.cancel()
                loadTask = nil
                bulkSelection.exitSelectMode()
                works = []
                currentPage = 0
                totalPages = 1
                phase = .idle
                loadMoreError = nil
                isShowingStaleCache = false
                await load(page: 1, replace: true)
            }
            .onDisappear { loadTask?.cancel() }
    }

    @ViewBuilder
    private var worksContent: some View {
        if phase == .loading, works.isEmpty {
            AO3AuthorLoadingRows()
        } else if case let .failed(message) = phase, works.isEmpty {
            AO3ProfileMessageRow(
                title: "Couldn't load series",
                systemImage: "exclamationmark.triangle",
                message: message,
                actionTitle: "Try Again",
                action: { startLoad(page: 1, replace: true, bypassCache: true) }
            )
            .cardRow()
        } else if phase == .loaded, works.isEmpty {
            AO3ProfileMessageRow(
                title: "No visible works",
                systemImage: "books.vertical",
                message: "No works in this series are visible to you on AO3."
            )
            .cardRow()
        } else {
            if case let .failed(message) = phase {
                AO3AuthorInlineErrorRow(message: message)
            }
            ForEach(workEntries) { entry in
                if bulkSelection.isSelecting, let remote = entry.remote {
                    // Every entry is remote-led, so selection runs over the AO3
                    // summaries — the list the bulk bar acts on.
                    SelectableAO3WorkRow(work: remote, expandAll: expandAll, controller: bulkSelection)
                        .cardRow(isSelected: bulkSelection.selection.contains(remote.id))
                } else if let work = entry.local {
                    // No .cardNavigation here: SensitiveWorkRow already applies it
                    // internally (MatureContent.swift) for its non-blurred, non-selecting
                    // branch — re-wrapping it stacks a second, unhidden, real-titled
                    // NavigationLink behind the blurred branch's reveal gate.
                    SensitiveWorkRow(work: work, expandAll: expandAll)
                        .cardRow()
                } else if let remote = entry.remote {
                    AO3WorkRow(work: remote, expandAll: expandAll)
                        .cardNavigation(to: remote, accessibilityLabel: remote.title)
                        .cardRow()
                }
            }
            AO3AuthorPaginationRows(
                loadMoreError: loadMoreError,
                hasMore: currentPage < totalPages,
                isLoadingMore: isLoadingMore,
                currentPage: currentPage,
                totalPages: totalPages,
                loadMore: { startLoad(page: currentPage + 1, replace: false) }
            )
        }
    }

    private var workEntries: [CanonicalWork] {
        CanonicalWorkMerge.remoteLed(
            remote: works,
            localLibrary: localWorks.filter {
                !gate.isHidden($0, enabled: hideMature, mode: matureMode)
            }
        )
    }

    private var authenticationScope: String {
        AO3AuthorProfileFetcher.authenticationScope(for: auth)
    }

    private func startLoad(page: Int, replace: Bool, bypassCache: Bool = false) {
        loadTask?.cancel()
        loadTask = Task {
            await load(page: page, replace: replace, bypassCache: bypassCache)
        }
    }

    private func load(
        page: Int,
        replace: Bool,
        bypassCache: Bool = false
    ) async {
        let expectedAuthenticationScope = authenticationScope
        let expectedSessionGeneration = auth.sessionGeneration
        if replace, works.isEmpty { phase = .loading }
        if !replace { isLoadingMore = true }
        loadMoreError = nil
        defer { isLoadingMore = false }
        do {
            guard let url = AO3Client.seriesPageURL(series.url, page: page) else {
                throw AO3Error.network("Bad series URL.")
            }
            let cached = try await AO3AuthorProfileFetcher.page(
                at: url,
                auth: auth,
                bypassCache: bypassCache
            )
            let result: AO3SearchPage
            do {
                result = try AO3Client.parseAuthorWorksPage(cached.html, page: page)
            } catch {
                if let ao3Error = error as? AO3Error, case .parse = ao3Error {
                    await AO3AuthorProfileFetcher.invalidate(url, auth: auth)
                }
                throw error
            }
            try Task.checkCancellation()
            guard authenticationScope == expectedAuthenticationScope,
                  auth.sessionGeneration == expectedSessionGeneration
            else { return }
            if replace {
                works = result.works
            } else {
                var ids = Set(works.map(\.id))
                works += result.works.filter { ids.insert($0.id).inserted }
            }
            currentPage = result.currentPage
            totalPages = result.totalPages
            isShowingStaleCache = replace
                ? cached.isStale
                : isShowingStaleCache || cached.isStale
            phase = .loaded
        } catch is CancellationError {
            return
        } catch AO3Error.authenticationRequired {
            guard authenticationScope == expectedAuthenticationScope,
                  auth.sessionGeneration == expectedSessionGeneration
            else { return }
            await auth.sessionDidExpire(expectedGeneration: expectedSessionGeneration)
        } catch {
            guard authenticationScope == expectedAuthenticationScope,
                  auth.sessionGeneration == expectedSessionGeneration
            else { return }
            let message = (error as? AO3Error)?.errorDescription ?? UserFacingError.message(for: error)
            if replace, works.isEmpty {
                phase = .failed(message)
            } else {
                loadMoreError = message
            }
        }
    }
}
