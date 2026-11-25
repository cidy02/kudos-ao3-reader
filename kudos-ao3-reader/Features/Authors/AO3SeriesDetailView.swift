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
    /// Optional anonymous page-1 HTML fetched by queue-source counts, reused
    /// once when signed out so Find More makes no second request.
    var preloadedPageOneHTML: String?
    var initialOrigin: ReadingQueueMembershipOrigin?
    var onPageOneLoaded: (() -> Void)?
    @State private var recordedSeriesView = false
    @State private var didConsumePreloaded = false
    @State private var didNotifyPageOneLoaded = false

    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    @AppStorage(WorkListKeys.seriesShowSummaries) private var showSummaries = true
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
    /// The title this series was last saved with from here, until the list behind is read again.
    @State private var savedTitle: String?
    /// "Preserve all N" — one run at a time; `preserveStatus` is its progress, then its result.
    @State private var preserveTask: Task<Void, Never>?
    @State private var preserveStatus: String?
    @State private var isConfirmingPreserve = false
    @State private var subscribeModel = AO3SeriesSubscribeModel()

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
                seriesHeader
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
            }

            if isShowingStaleCache {
                Section {
                    Label("Showing cached AO3 data", systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
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
        .subjectWash(seriesPalette)
        .navigationTitle("Series")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                if bulkSelection.isSelecting {
                    RemoteWorkSelectionToolbar(controller: bulkSelection, selectable: { works }) {
                        bulkSelection.selected(in: works)
                    }
                } else {
                    ToolbarItemGroup(placement: .primaryAction) {
                        ShareLink(item: series.url) {
                            Label("Share Series", systemImage: "square.and.arrow.up")
                        }
                        .labelStyle(.iconOnly)

                        // The app's one "…" order (pass2-1): Mature, Select, Reorder,
                        // Expand, then the page's own items.
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
                                ShowSummariesMenuItem(isOn: $showSummaries)
                                ExpandAllMenuItem(expandAll: $expandAll)
                                Divider()
                            }
                            if canEditSeries {
                                Button { isEditingSeries = true } label: {
                                    Label("Edit Series", systemImage: "square.and.pencil")
                                }
                            }
                            Button { router.open(series.url) } label: {
                                Label("Open on AO3", systemImage: "safari")
                            }
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
            .remoteWorkSelectionChrome(bulkSelection)
            .environment(\.queueMembershipOrigin, bulkSelection.origin ?? initialOrigin)
            .onAppear {
                if bulkSelection.origin == nil, let initialOrigin {
                    bulkSelection.origin = initialOrigin
                }
            }
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
                subscribeModel.reset()
                bulkSelection.exitSelectMode()
                works = []
                currentPage = 0
                totalPages = 1
                phase = .idle
                loadMoreError = nil
                isShowingStaleCache = false
                await load(page: 1, replace: true)
            }
            .onDisappear {
                loadTask?.cancel()
            }
            .sensoryFeedback(.success, trigger: subscribeModel.writeSuccesses)
            .sensoryFeedback(.error, trigger: subscribeModel.writeFailures)
            .alert("AO3", isPresented: subscribeBannerPresented) {
                Button("OK", role: .cancel) { subscribeModel.banner = nil }
            } message: {
                Text(subscribeModel.banner ?? "")
            }
            // A save, a new order or a removal in the edit screens: the works are read again past
            // the cache, and the header takes the saved title. It showed the old ones until pulled.
            .onChange(of: auth.lastSeriesWrite) { _, write in
                guard let write, write.seriesID == series.id else { return }
                if let title = write.title { savedTitle = title }
                Task {
                    // As a pull to refresh does: the HTTP cache under the page cache too.
                    await AO3Client.shared.invalidateCachedResponses()
                    startLoad(page: 1, replace: true, bypassCache: true)
                }
            }
    }

    // MARK: Header (board 24)

    /// Fandom eyebrow, title, author, facts, summary, then the two actions.
    private var seriesHeader: some View {
        let shown = shownSeries
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Self.eyebrow(for: shown))
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(seriesPalette.accent)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                Capsule()
                    .fill(seriesPalette.accent)
                    .frame(width: 22, height: 2.5)
            }
            Text(shown.title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            AO3AuthorBylineView(
                names: shown.creatorNames, identities: shown.creatorIdentities,
                includesBy: false, compact: !dynamicTypeSize.isAccessibilitySize
            )
            Text(Self.facts(for: shown))
                .font(.subheadline)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if !shown.summary.isEmpty {
                Text(shown.summary)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            seriesActions
            if let preserveStatus {
                Text(preserveStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var seriesActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if AO3SeriesSubscribeModel.showsSubscribe(isLoggedIn: auth.isLoggedIn) {
                Button {
                    subscribeModel.tapped(seriesID: series.id, auth: auth) {
                        SavedSeriesStore.series(for: series.id, in: context)?.isSubscribed = subscribeModel.isSubscribed
                        await invalidateSeriesPageCache()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if subscribeModel.isWorking {
                            ProgressView()
                                .controlSize(.small)
                                .tint(ThemeManager.label(on: theme.effectiveTint))
                        } else {
                            // The bell is Subscribe app-wide (owner, 2026-11-09).
                            Image(systemName: subscribeModel.isSubscribed ? "bell.slash" : "bell")
                        }
                        Text(subscribeModel.isSubscribed ? "Unsubscribe" : "Subscribe")
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.kudosPrimaryConfirm)
                .disabled(
                    subscribeModel.isWorking || !subscribeModel.hasSyncedSubscription
                )
                .accessibilityLabel(subscribeModel.isSubscribed ? "Unsubscribe" : "Subscribe")
                .accessibilityValue(subscribeModel.isWorking ? "In progress" : "")
                .accessibilityAddTraits(subscribeModel.isSubscribed ? [.isSelected] : [])
                .confirmationDialog(
                    "Unsubscribe from \(shownSeries.title)?",
                    isPresented: $subscribeModel.isConfirmingUnsubscribe,
                    titleVisibility: .visible
                ) {
                    Button("Unsubscribe", role: .destructive) {
                        subscribeModel.confirmUnsubscribe(seriesID: series.id, auth: auth) {
                            if let saved = SavedSeriesStore.series(for: series.id, in: context) {
                                saved.isSubscribed = false
                                // Mail from before the unsubscribe must not subscribe the series again.
                                saved.lastNotifiedAt = max(saved.lastNotifiedAt ?? .distantPast, Date())
                            }
                            await invalidateSeriesPageCache()
                        }
                    }
                    Button("Cancel", role: .cancel) { subscribeModel.cancelUnsubscribe() }
                } message: {
                    Text("You will stop receiving email updates for this series on AO3.")
                }
            }
            // One tap can download a whole series, so it asks first; while it runs it is Cancel.
            Button {
                if let preserveTask {
                    preserveTask.cancel()
                    preserveStatus = "Cancelling series preservation…"
                } else {
                    isConfirmingPreserve = true
                }
            } label: {
                Text(preserveTask == nil ? Self.preserveTitle(count: preserveCount) : "Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kudosSecondaryConfirm)
            .confirmationDialog(
                Self.preserveTitle(count: preserveCount) + "?",
                isPresented: $isConfirmingPreserve, titleVisibility: .visible
            ) {
                Button("Preserve", action: preserveAll)
            } message: {
                Text("Downloads every work in this series to Want to Read. Works you already have are skipped.")
            }
        }
    }

    private var preserveCount: Int? { shownSeries.workCount ?? (works.isEmpty ? nil : works.count) }

    /// The fandom line above the title; "Series" when AO3 printed none.
    static func eyebrow(for series: AO3SeriesSummary) -> String {
        let names = series.fandoms.map(FandomDisplayName.bareTitle)
        return (names.isEmpty ? "Series" : names.joined(separator: ", ")).uppercased()
    }

    /// Every fact the old card showed, in AO3's order: counts, restricted, status, date.
    static func facts(for series: AO3SeriesSummary) -> String {
        var parts: [String] = []
        if let count = series.workCount { parts.append(count == 1 ? "1 work" : "\(count) works") }
        if let words = series.words { parts.append("\(words.formatted()) words") }
        if let bookmarks = series.bookmarkCount {
            parts.append(bookmarks == 1 ? "1 bookmark" : "\(bookmarks.formatted()) bookmarks")
        }
        if series.isRestricted { parts.append("restricted") }
        if let complete = series.isComplete { parts.append(complete ? "complete" : "in progress") }
        if !series.dateUpdated.isEmpty { parts.append(WorkStat.displayDate(series.dateUpdated)) }
        return parts.joined(separator: " · ")
    }

    static func preserveTitle(count: Int?) -> String {
        count.map { "Preserve all \($0)" } ?? "Preserve all"
    }

    /// Downloads every work in the series into Want to Read through the same service Work
    /// Detail uses. The works already loaded are used when they are the whole series;
    /// otherwise the download queue's existing `seriesWorks` walk reads the other pages.
    private func preserveAll() {
        guard preserveTask == nil else { return }
        preserveStatus = "Preserving series…"
        preserveTask = Task { @MainActor in
            defer { preserveTask = nil }
            var summaries = works
            if currentPage < totalPages || works.isEmpty {
                do {
                    summaries = try await AO3Client.shared.seriesWorks(seriesURL: series.url)
                } catch {
                    preserveStatus = UserFacingError.message(for: error)
                    return
                }
            }
            let result = await ReadingQueueService.preserveSeries(
                summaries,
                state: .new,
                origin: ReadingQueueMembershipOrigin(kind: .manual),
                in: context,
                progress: { preserveStatus = "Preserving series \($0.completed) of \($0.total)…" }
            )
            let parts = result.summaryParts(verb: "preserved")
            preserveStatus = result.cancelled > 0
                ? "Series preservation cancelled. Preserved \(result.preserved)."
                : result.total == 0 ? "No series works were found."
                : parts.isEmpty ? "Series works are already preserved."
                : "Series preservation complete: " + parts.joined(separator: ", ") + "."
        }
    }

    private var shownSeries: AO3SeriesSummary {
        var shown = series
        if let savedTitle { shown.title = savedTitle }
        return shown
    }

    private var seriesPalette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: CoverArt.hue(for: shownSeries.title))
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
                    SelectableAO3WorkRow(
                        work: remote, expandAll: expandAll, controller: bulkSelection, showsSummary: showSummaries
                    )
                        .cardRow(isSelected: bulkSelection.selection.contains(remote.id), chrome: .plain)
                } else if let work = entry.local {
                    // No .cardNavigation here: SensitiveWorkRow already applies it
                    // internally (MatureContent.swift) for its non-blurred, non-selecting
                    // branch — re-wrapping it stacks a second, unhidden, real-titled
                    // NavigationLink behind the blurred branch's reveal gate.
                    SensitiveWorkRow(
                        work: work, expandAll: expandAll, showsSummary: showSummaries, twin: entry.remote
                    )
                        .cardRow(chrome: .plain)
                } else if let remote = entry.remote {
                    SensitiveWorkRow(work: remote, expandAll: expandAll, showsSummary: showSummaries)
                        .cardRow(chrome: .plain)
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
            localLibrary: localWorks
        ).filter { !gate.isHidden($0, enabled: hideMature, mode: matureMode) }
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

    /// Keeps what this page says about the series (T-519): the header from page 1, and the whole part list once
    /// every page is loaded. No request of its own: it reads the page the reader just opened.
    /// One view per screen, whether the page came fresh or from the offline cache.
    private func recordSeriesViewOnce() {
        guard !recordedSeriesView else { return }
        recordedSeriesView = true
        SavedSeriesWeeklyCheck.recordView(seriesID: series.id, in: context)
    }

    private func recordSavedSeries(pageOneHTML: String?) {
        let ids = works.map(\.id)
        let isWholeList = currentPage >= totalPages
        if let html = pageOneHTML,
           let parsed = AO3ParsedSeries.parse(
               html: html, ao3SeriesID: series.id, pageWorkIDs: ids, isWholeList: isWholeList
           ) {
            let saved = SavedSeriesStore.upsert(parsed, in: context)
            if auth.isLoggedIn { saved?.isSubscribed = subscribeModel.isSubscribed }
            recordSeriesViewOnce()
        } else if isWholeList, let saved = SavedSeriesStore.series(for: series.id, in: context),
                  saved.partCount == ids.count {
            saved.partWorkIDs = SavedSeries.normalizedPartWorkIDs(ids)
            saved.lastModifiedAt = Date()
        }
    }

    private func load(
        page: Int,
        replace: Bool,
        bypassCache: Bool = false
    ) async {
        let expectedAuthenticationScope = authenticationScope
        let expectedSessionGeneration = auth.sessionGeneration
        let expectedCacheScope = AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        if replace, works.isEmpty { phase = .loading }
        if !replace { isLoadingMore = true }
        loadMoreError = nil
        defer { isLoadingMore = false }
        do {
            guard let url = AO3Client.seriesPageURL(series.url, page: page) else {
                throw AO3Error.network("Bad series URL.")
            }
            let cached: AO3AuthorProfileFetcher.Page
            if page == 1, replace, !bypassCache, !didConsumePreloaded, !auth.isLoggedIn,
               let html = preloadedPageOneHTML {
                didConsumePreloaded = true
                cached = AO3AuthorProfileFetcher.Page(html: html, isStale: false)
            } else {
                didConsumePreloaded = true
                cached = try await AO3AuthorProfileFetcher.page(
                    at: url,
                    auth: auth,
                    cacheScope: expectedCacheScope,
                    isCurrent: {
                        authenticationScope == expectedAuthenticationScope
                            && auth.sessionGeneration == expectedSessionGeneration
                    },
                    bypassCache: bypassCache
                )
            }
            let result: AO3SearchPage
            do {
                result = try AO3Client.parseAuthorWorksPage(cached.html, page: page)
            } catch {
                if let ao3Error = error as? AO3Error, case .parse = ao3Error {
                    await AO3AuthorProfileFetcher.invalidate(
                        url,
                        auth: auth,
                        cacheScope: expectedCacheScope
                    )
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
            if page == 1 {
                subscribeModel.syncFromSeriesPage(html: cached.html, isLoggedIn: auth.isLoggedIn)
            }
            if !cached.isStale { recordSavedSeries(pageOneHTML: page == 1 ? cached.html : nil) }
            if page == 1 { recordSeriesViewOnce() }
            isShowingStaleCache = replace
                ? cached.isStale
                : isShowingStaleCache || cached.isStale
            phase = .loaded
            if page == 1, !didNotifyPageOneLoaded {
                didNotifyPageOneLoaded = true
                onPageOneLoaded?()
            }
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

    private var subscribeBannerPresented: Binding<Bool> {
        Binding(get: { subscribeModel.banner != nil }, set: { if !$0 { subscribeModel.banner = nil } })
    }

    private func invalidateSeriesPageCache() async {
        if let url = AO3Client.seriesPageURL(series.url, page: 1) {
            await AO3AuthorProfileFetcher.invalidate(
                url,
                auth: auth,
                cacheScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
            )
        }
        await AO3Client.shared.invalidateCachedResponses()
    }
}

/// UI state and action driver for native series Subscribe / Unsubscribe (`T-549`).
@MainActor
@Observable
final class AO3SeriesSubscribeModel {
    /// Series ID, the state the reader asked for, the session.
    typealias ToggleHandler = @MainActor (Int, Bool, AO3AuthService) async throws -> String

    private(set) var isSubscribed = false
    private(set) var hasSyncedSubscription = false
    private(set) var isWorking = false
    var isConfirmingUnsubscribe = false
    var banner: String?
    private(set) var writeSuccesses = 0
    private(set) var writeFailures = 0

    private var activeTask: Task<Void, Never>?
    private var isHandlingSessionExpiry = false
    private let toggleHandler: ToggleHandler

    init(
        toggleHandler: @escaping ToggleHandler = { seriesID, want, auth in
            try await auth.toggleSubscribe(seriesID: seriesID, to: want)
        }
    ) {
        self.toggleHandler = toggleHandler
    }

    func syncFromSeriesPage(html: String, isLoggedIn: Bool) {
        guard !isWorking else { return }
        guard isLoggedIn else {
            isSubscribed = false
            hasSyncedSubscription = false
            return
        }
        isSubscribed = AO3Client.parseSubscription(from: html).isSubscribed
        hasSyncedSubscription = true
    }

    func reset() {
        // Don't abort or clear the alert when `.task(id: authenticationScope)` fires
        // because `sessionDidExpire` just moved the session to `.signedOut`.
        if !isHandlingSessionExpiry {
            activeTask?.cancel()
            activeTask = nil
        }
        isSubscribed = false
        hasSyncedSubscription = false
        isWorking = false
        isConfirmingUnsubscribe = false
        if !isHandlingSessionExpiry,
           banner != AO3Error.authenticationRequired.errorDescription {
            banner = nil
        }
    }

    static func showsSubscribe(isLoggedIn: Bool) -> Bool {
        isLoggedIn
    }

    func tapped(
        seriesID: Int,
        auth: AO3AuthService,
        onSuccess: (@MainActor () async -> Void)? = nil
    ) {
        guard !isWorking, auth.isLoggedIn else { return }
        if isSubscribed {
            isConfirmingUnsubscribe = true
            return
        }
        performToggle(seriesID: seriesID, want: true, auth: auth, onSuccess: onSuccess)
    }

    func confirmUnsubscribe(
        seriesID: Int,
        auth: AO3AuthService,
        onSuccess: (@MainActor () async -> Void)? = nil
    ) {
        guard !isWorking, auth.isLoggedIn else { return }
        // The dialog asked to unsubscribe; a page refresh while it was open must not turn that around.
        performToggle(seriesID: seriesID, want: false, auth: auth, onSuccess: onSuccess)
    }

    func cancelUnsubscribe() {
        isConfirmingUnsubscribe = false
    }

    func waitForCurrentTask() async {
        await activeTask?.value
    }

    private func performToggle(
        seriesID: Int,
        want: Bool,
        auth: AO3AuthService,
        onSuccess: (@MainActor () async -> Void)?
    ) {
        let expectedGeneration = auth.sessionGeneration
        isWorking = true
        activeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isWorking = false
                self.activeTask = nil
            }
            do {
                let message = try await self.toggleHandler(seriesID, want, auth)
                guard auth.sessionGeneration == expectedGeneration else { return }
                self.isSubscribed = want
                self.banner = message
                self.writeSuccesses += 1
                await onSuccess?()
            } catch is CancellationError {
                return
            } catch AO3Error.authenticationRequired {
                guard auth.sessionGeneration == expectedGeneration else { return }
                isHandlingSessionExpiry = true
                let expired = await auth.sessionDidExpire(expectedGeneration: expectedGeneration)
                isHandlingSessionExpiry = false
                guard !Task.isCancelled else { return }
                if expired {
                    self.banner = AO3Error.authenticationRequired.errorDescription
                    self.writeFailures += 1
                }
            } catch {
                guard auth.sessionGeneration == expectedGeneration else { return }
                self.banner = (error as? LocalizedError)?.errorDescription
                    ?? UserFacingError.message(for: error)
                self.writeFailures += 1
            }
        }
    }
}
