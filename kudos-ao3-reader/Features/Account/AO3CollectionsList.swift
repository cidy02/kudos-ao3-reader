import SwiftUI

/// The signed-in user's AO3 collections — artboards **1r** (the list) and **1bm**
/// (its sort-and-filter sheet). Tapping a collection pushes its works, reusing
/// `AO3AccountWorksList` via the `.collection` kind.
///
/// Cards route to native details, item management, and the collection form.
/// Owner-only deletion lives in that form behind its destructive confirmation.
struct AO3CollectionsList: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @ScaledMetric(relativeTo: .headline) private var stateTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var bodySize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .footnote) private var actionSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 11.5

    @State private var collections: [AO3Collection] = []
    @State private var phase: Phase = .idle
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var showLogin = false
    @State private var filters = AO3CollectionsFilter()
    @State private var showingFilters = false
    @State private var editingCollection: AO3CollectionFormDestination?
    @State private var yourItems: AO3CollectionItemsDestination?
    @State private var loadGeneration = 0
    /// Generation whose rows are stored. Nil until the load task has bound
    /// one. A later run with the same generation is a reappearance.
    @State private var loadedSessionGeneration: Int?
    @State private var wholeIndex: [AO3Collection] = []
    @State private var wholeIndexSessionGeneration: Int?
    @State private var wholeIndexPhase: Phase = .idle
    @State private var wholeIndexRetry = 0
    @State private var wholeIndexLoadGeneration = 0
    @State private var wholeIndexPartialNote: String?

    private enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    private struct WholeIndexLoadID: Equatable {
        var sessionGeneration: Int
        var isLoggedIn: Bool
        var needsWholeIndex: Bool
        var listIsSettled: Bool
        var retry: Int
    }

    /// Stored rows are drawn only for the generation that loaded them. A new
    /// generation renders empty in the same body pass that observes it,
    /// before the load task has cleared the arrays.
    private var sessionOwnsScreen: Bool {
        AO3CollectionSessionReload.ownsScreen(
            boundGeneration: loadedSessionGeneration,
            sessionGeneration: auth.sessionGeneration
        )
    }

    private var hasCurrentWholeIndex: Bool {
        wholeIndexSessionGeneration == auth.sessionGeneration
    }

    private var displayedCollections: [AO3Collection] {
        guard sessionOwnsScreen else { return [] }
        if filters.needsWholeIndex {
            return hasCurrentWholeIndex ? wholeIndex : []
        }
        return collections
    }

    /// What the list draws: AO3's rows, sorted and narrowed in memory. Any
    /// non-default client rule switches to the generation-owned whole index.
    private var visibleCollections: [AO3Collection] {
        filters.apply(to: displayedCollections)
    }

    private var showPagination: Bool {
        !filters.needsWholeIndex && totalPages > 1
    }

    var body: some View {
        Group {
            if auth.isLoggedIn { signedInContent } else { signedOutPrompt }
        }
        .hidesFloatingTabBar()
        .toolbar {
            if auth.isLoggedIn {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: AO3CollectionFormDestination(slug: nil)) {
                        Label("New Collection", systemImage: "plus")
                    }
                }
            }
            if phase == .loaded, !collections.isEmpty || hasCurrentWholeIndex {
                ToolbarItem(placement: .primaryAction) {
                    FilterButton(
                        filtersActive: filters.hasActiveFilters,
                        showingFilters: $showingFilters,
                        onClearFilters: { filters = AO3CollectionsFilter() }
                    )
                }
            }
        }
        .filterPanelPresentation(isPresented: $showingFilters) {
            AO3CollectionsFilterPanel(
                initial: filters,
                onFinish: {
                    filters = $0
                    showingFilters = false
                }
            )
            .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
        }
        .navigationDestination(item: $editingCollection) { destination in
            AO3CollectionFormView(
                slug: destination.slug,
                onDeleted: { editingCollection = nil }
            )
        }
        .navigationDestination(item: $yourItems) { destination in
            AO3CollectionItemsView(slug: destination.slug, title: destination.title)
        }
        .task(id: AO3AccountWorksLoadID(
            sessionGeneration: auth.sessionGeneration,
            isLoggedIn: auth.isLoggedIn
        )) {
            let decision = AO3CollectionSessionReload.listTask(
                boundGeneration: loadedSessionGeneration,
                phase: listPhase,
                sessionGeneration: auth.sessionGeneration,
                isLoggedIn: auth.isLoggedIn
            )
            if decision.clearAccountState {
                clearLoadedAccount()
                loadedSessionGeneration = auth.sessionGeneration
            }
            if decision.loadPageOne {
                await load(page: 1)
            }
        }
        .task(id: WholeIndexLoadID(
            sessionGeneration: auth.sessionGeneration,
            isLoggedIn: auth.isLoggedIn,
            needsWholeIndex: filters.needsWholeIndex,
            listIsSettled: phase == .loaded,
            retry: wholeIndexRetry
        )) {
            guard auth.isLoggedIn, filters.needsWholeIndex, phase == .loaded else { return }
            await loadWholeIndexIfNeeded()
        }
        .sheet(isPresented: $showLogin) { AO3LoginView() }
        .onReceive(NotificationCenter.default.publisher(for: .ao3CollectionDeleted)) { notification in
            guard let slug = notification.object as? String,
                  notification.deletesCollection(slug: slug) else { return }
            refreshAfterDelete(slug: slug)
        }
        // A failed page change (page 2+, say) while `collections` still holds
        // the prior page falls through to the ordinary list below — nothing
        // else in `signedInContent` ever surfaces it, so a tap that silently
        // failed read as a tap that did nothing. This is the only place that
        // failure becomes visible.
        .alert(
            "Couldn't load that page",
            isPresented: Binding(
                get: {
                    if case .failed = phase, !displayedCollections.isEmpty { return true }
                    return false
                },
                set: { if !$0, case .failed = phase { phase = .loaded } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if case let .failed(message) = phase { Text(message) }
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        if !sessionOwnsScreen {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case let .failed(message) = phase, displayedCollections.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load collections", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load(page: currentPage) } }
            }
        } else if phase == .loading, displayedCollections.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filters.needsWholeIndex, !hasCurrentWholeIndex {
            switch wholeIndexPhase {
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn't load all collections", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { wholeIndexRetry += 1 }
                }
            case .idle, .loading, .loaded:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            collectionsList
        }
    }

    private var collectionsList: some View {
        List {
            Section {
                header.pageBodyRow(top: 20, gutter: 0)
                scopeRail.pageBodyRow(top: 12, gutter: 0)
                if !filters.summaryLabels.isEmpty {
                    filterRail.pageBodyRow(top: 12, gutter: 0)
                }
                if showPagination {
                    paginationBar.pageBodyRow(top: 12, gutter: SubjectMetrics.accountGutter)
                }
            }

            if visibleCollections.isEmpty {
                Section {
                    emptyCard.pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
                }
            } else {
                Section {
                    ForEach(visibleCollections) { collection in
                        collectionRow(collection)
                    }
                }
            }

            if showPagination {
                Section {
                    paginationBar.pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
                }
            }

            Section {
                sourceFooter.pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
            }
        }
        .cardList()
        .subjectScreenWash(palette: palette)
        .refreshable {
            if filters.needsWholeIndex {
                wholeIndexLoadGeneration = AO3CollectionSessionReload.nextLoadGeneration(
                    wholeIndexLoadGeneration
                )
                wholeIndexSessionGeneration = nil
                wholeIndexPhase = .idle
                await load(page: AO3CollectionsWholeIndex.refreshPage(
                    currentPage: currentPage, needsWholeIndex: true
                ))
                wholeIndexRetry += 1
            } else {
                await load(page: currentPage)
            }
        }
    }

    private func collectionRow(_ collection: AO3Collection) -> some View {
        AO3CollectionCard(collection: collection)
            .cardNavigation(
                to: AO3CollectionDestination(
                    slug: collection.name,
                    title: collection.title
                ),
                accessibilityLabel: collection.title
            )
            .contextMenu {
                NavigationLink(value: editDestination(for: collection)) {
                    Label("Edit Collection", systemImage: "pencil")
                }
                NavigationLink(value: itemsDestination(for: collection)) {
                    Label("Manage Items", systemImage: "tray.full")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    editingCollection = editDestination(for: collection)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.gray)
            }
            .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
    }

    private func editDestination(for collection: AO3Collection) -> AO3CollectionFormDestination {
        AO3CollectionFormDestination(slug: collection.name)
    }

    private func itemsDestination(for collection: AO3Collection) -> AO3CollectionItemsDestination {
        AO3CollectionItemsDestination(slug: collection.name, title: collection.title)
    }

    private var header: some View {
        SubjectHeaderBlock(
            kicker: "AO3 Account",
            title: "Collections",
            subtitle: tallyLine,
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    /// 1r's two scopes. "Collections" is this list. "Your items" is AO3's
    /// account-wide collection-items page, not a sum the app builds itself.
    /// Nothing caches a pending-item count, so the pill has no badge.
    private var scopeRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SubjectChip(text: "Collections", style: .pill(isSelected: true), palette: palette)
                Button {
                    yourItems = AO3CollectionItemsDestination(slug: nil, title: "Your items")
                } label: {
                    SubjectChip(
                        text: "Your items",
                        style: .pill(isSelected: false),
                        palette: palette
                    )
                }
                .buttonStyle(.plain)
                .minimumHitTarget(28)
            }
            .padding(.horizontal, 16)
        }
    }

    private var filterRail: some View {
        SubjectFilterRail {
            ForEach(filters.summaryLabels, id: \.self) { label in
                SubjectChip(text: label, style: .tinted, palette: palette)
            }
        }
    }

    private var paginationBar: some View {
        SearchPaginationBar(
            currentPage: currentPage,
            totalPages: totalPages,
            isLoading: phase == .loading,
            palette: palette
        ) { page in
            Task { await load(page: page) }
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayedCollections.isEmpty ? "No collections" : "No collections match")
                .font(.system(size: stateTitleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(emptyDetail)
                .font(.system(size: bodySize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !displayedCollections.isEmpty {
                Button("Clear Filters") { filters = AO3CollectionsFilter() }
                    .buttonStyle(.borderless)
                    .font(.system(size: actionSize, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectPanel()
    }

    private var emptyDetail: String {
        if displayedCollections.isEmpty {
            return "Collections you create or maintain on AO3 show up here."
        }
        let count = displayedCollections.count
        return "\(count) collection\(count == 1 ? "" : "s") are hidden by the current filters."
    }

    private var sourceFooter: some View {
        Text("AO3 collections. Local collections live in Library.")
            .font(.system(size: captionSize))
            .foregroundStyle(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
    }

    private var palette: SubjectPalette {
        theme.scopePalette
    }

    private var signedOutPrompt: some View {
        ContentUnavailableView {
            Label("My Collections", systemImage: "square.stack")
        } description: {
            Text("Log in to AO3 to see your collections.")
        } actions: {
            Button("Log In to AO3…") { showLogin = true }
        }
    }

    /// Drops the previous session's rows and retires its in-flight load.
    /// Filters stay: they are this device's view of the page, not the account's.
    private func clearLoadedAccount() {
        loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
        let cleared = AO3CollectionSessionReload.clearedList
        collections = cleared.collections
        currentPage = cleared.currentPage
        totalPages = cleared.totalPages
        phase = .idle
        wholeIndex = []
        wholeIndexSessionGeneration = nil
        wholeIndexPhase = .idle
        wholeIndexLoadGeneration = AO3CollectionSessionReload.nextLoadGeneration(
            wholeIndexLoadGeneration
        )
    }

    /// The delete form can be reached from this list or through collection
    /// details. Remove the stale row immediately, then refresh the server page
    /// (or the generation-owned whole index) that backs the visible list.
    private func refreshAfterDelete(slug: String) {
        collections.removeAll { $0.name == slug }
        wholeIndex.removeAll { $0.name == slug }
        guard auth.isLoggedIn else { return }
        if filters.needsWholeIndex {
            wholeIndexLoadGeneration = AO3CollectionSessionReload.nextLoadGeneration(
                wholeIndexLoadGeneration
            )
            wholeIndexSessionGeneration = nil
            wholeIndexPhase = .idle
            wholeIndexRetry += 1
        } else {
            let page = collections.isEmpty && currentPage > 1 ? currentPage - 1 : currentPage
            Task { await load(page: page) }
        }
    }

    /// `phase` in the reload rule's terms: loaded and failed are both settled.
    private var listPhase: AO3CollectionSessionReload.ItemsPhase {
        switch phase {
        case .idle: .idle
        case .loading: .loading
        case .loaded, .failed: .settled
        }
    }

    private func load(page: Int) async {
        let expectedSessionGeneration = auth.sessionGeneration
        guard auth.isLoggedIn, let username = auth.username,
              let url = AO3Client.collectionsURL(username: username, page: page) else { return }
        loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
        let generation = loadGeneration
        phase = .loading
        do {
            let request = try auth.authenticatedRequest(for: url)
            let result = try await AO3Client.shared.collectionsIndex(for: request, page: page)
            guard AO3CollectionSessionReload.shouldApplyLoad(
                capturedLoadGeneration: generation,
                loadGeneration: loadGeneration,
                capturedSessionGeneration: expectedSessionGeneration,
                sessionGeneration: auth.sessionGeneration
            ) else { return }
            collections = result.collections
            currentPage = result.currentPage
            totalPages = max(result.totalPages, 1)
            phase = .loaded
            AO3AccountListCountsCache.shared.record(
                AO3AccountListCount(
                    itemsOnPage: result.collections.count,
                    totalPages: result.totalPages
                ),
                kind: .collections,
                authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
            )
        } catch AO3Error.authenticationRequired {
            guard generation == loadGeneration else { return }
            guard await auth.sessionDidExpire(expectedGeneration: expectedSessionGeneration) else { return }
            collections = []
            phase = .idle
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch let error as AO3Error {
            guard AO3CollectionSessionReload.shouldApplyLoad(
                capturedLoadGeneration: generation,
                loadGeneration: loadGeneration,
                capturedSessionGeneration: expectedSessionGeneration,
                sessionGeneration: auth.sessionGeneration
            ) else { return }
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            guard AO3CollectionSessionReload.shouldApplyLoad(
                capturedLoadGeneration: generation,
                loadGeneration: loadGeneration,
                capturedSessionGeneration: expectedSessionGeneration,
                sessionGeneration: auth.sessionGeneration
            ) else { return }
            phase = .failed(UserFacingError.message(for: error))
        }
    }

}

// Out of the struct body only for its length; `private` state is file-scoped.
extension AO3CollectionsList {
    /// Counts what is on screen, not what was fetched — a tally that ignored the
    /// filters would contradict the rows under it.
    private var tallyLine: String {
        let shown = visibleCollections.count
        var line = "\(shown) collection\(shown == 1 ? "" : "s")"
        if shown != displayedCollections.count {
            line += " · \(displayedCollections.count) in all"
        }
        if showPagination {
            line += " · page \(currentPage) of \(totalPages)"
        }
        if filters.needsWholeIndex, hasCurrentWholeIndex, let note = wholeIndexPartialNote {
            line += " · \(note)"
        }
        return line
    }

    /// Loads every collections-index page strictly in sequence. The surrounding
    /// SwiftUI task owns cancellation; each landed page also passes the existing
    /// list load/session fence before it can join the accumulator.
    private func loadWholeIndexIfNeeded() async {
        let expectedSessionGeneration = auth.sessionGeneration
        guard filters.needsWholeIndex,
              auth.isLoggedIn,
              wholeIndexSessionGeneration != expectedSessionGeneration,
              let username = auth.username
        else { return }

        wholeIndexLoadGeneration = AO3CollectionSessionReload.nextLoadGeneration(
            wholeIndexLoadGeneration
        )
        let generation = wholeIndexLoadGeneration
        wholeIndexPhase = .loading
        defer {
            if generation == wholeIndexLoadGeneration, wholeIndexPhase == .loading {
                wholeIndexPhase = .idle
            }
        }
        let canReusePageOne = AO3CollectionsWholeIndex.canReusePageOne(
            currentPage: currentPage,
            ownsScreen: sessionOwnsScreen,
            listIsLoaded: phase == .loaded
        )
        var accumulated = canReusePageOne ? collections : []
        var page = canReusePageOne ? 2 : 1
        var reportedTotalPages = canReusePageOne ? totalPages : 1
        var lastPageWasEmpty = false

        do {
            while page <= min(
                max(reportedTotalPages, 1), AO3CollectionsWholeIndex.maximumPages
            ) {
                try Task.checkCancellation()
                guard let url = AO3Client.collectionsURL(username: username, page: page) else {
                    throw AO3Error.network("Couldn't build the collections page address.")
                }
                let request = try auth.authenticatedRequest(for: url)
                let result = try await AO3Client.shared.collectionsIndex(for: request, page: page)
                try Task.checkCancellation()
                guard AO3CollectionsWholeIndex.append(
                    result,
                    to: &accumulated,
                    capturedLoadGeneration: generation,
                    loadGeneration: wholeIndexLoadGeneration,
                    capturedSessionGeneration: expectedSessionGeneration,
                    sessionGeneration: auth.sessionGeneration
                ) else { return }
                reportedTotalPages = max(reportedTotalPages, result.currentPage, result.totalPages)
                lastPageWasEmpty = result.collections.isEmpty
                guard let next = AO3CollectionsWholeIndex.nextPage(
                    after: page,
                    reportedTotalPages: reportedTotalPages,
                    pageWasEmpty: result.collections.isEmpty
                ) else { break }
                page = next
            }

            guard filters.needsWholeIndex,
                  AO3CollectionSessionReload.shouldApplyLoad(
                      capturedLoadGeneration: generation,
                      loadGeneration: wholeIndexLoadGeneration,
                      capturedSessionGeneration: expectedSessionGeneration,
                      sessionGeneration: auth.sessionGeneration
                  )
            else { return }
            wholeIndex = accumulated
            wholeIndexPartialNote = AO3CollectionsWholeIndex.partialNote(
                reportedTotalPages: reportedTotalPages, lastPageWasEmpty: lastPageWasEmpty
            )
            wholeIndexSessionGeneration = expectedSessionGeneration
            wholeIndexPhase = .loaded
        } catch AO3Error.authenticationRequired {
            guard generation == wholeIndexLoadGeneration else { return }
            guard await auth.sessionDidExpire(expectedGeneration: expectedSessionGeneration) else {
                return
            }
            wholeIndexPhase = .idle
        } catch let error where error is CancellationError || (error as? URLError)?.code == .cancelled {
            if AO3CollectionSessionReload.shouldApplyLoad(
                capturedLoadGeneration: generation,
                loadGeneration: wholeIndexLoadGeneration,
                capturedSessionGeneration: expectedSessionGeneration,
                sessionGeneration: auth.sessionGeneration
            ) {
                wholeIndexPhase = .idle
            }
        } catch let error as AO3Error {
            guard AO3CollectionSessionReload.shouldApplyLoad(
                capturedLoadGeneration: generation,
                loadGeneration: wholeIndexLoadGeneration,
                capturedSessionGeneration: expectedSessionGeneration,
                sessionGeneration: auth.sessionGeneration
            ) else { return }
            wholeIndexPhase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            guard AO3CollectionSessionReload.shouldApplyLoad(
                capturedLoadGeneration: generation,
                loadGeneration: wholeIndexLoadGeneration,
                capturedSessionGeneration: expectedSessionGeneration,
                sessionGeneration: auth.sessionGeneration
            ) else { return }
            wholeIndexPhase = .failed(UserFacingError.message(for: error))
        }
    }
}

/// One collection on the list. The hue is the collection's own, from its title,
/// the way a queue carries a colour. Approval queues and "works of yours" are
/// not on AO3's collection blurb, so they are not drawn.
struct AO3CollectionCard: View {
    let collection: AO3Collection

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 19
    @ScaledMetric(relativeTo: .footnote) private var summarySize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .caption) private var metaSize: CGFloat = 11.5

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: [], title: collection.title)
        )
    }

    private var eyebrow: String {
        AO3CollectionCardCopy.eyebrow(
            viewerIsOwner: collection.viewerIsOwner,
            maintainerNames: collection.maintainerNames,
            byline: collection.byline
        )
    }

    private var metaFacts: [String] {
        AO3CollectionCardCopy.metaFacts(
            worksCount: collection.worksCount,
            bookmarksCount: collection.bookmarksCount,
            isModerated: collection.isModerated,
            isClosed: collection.isClosed,
            challengeName: collection.challengeKind?.displayName
        )
    }

    private var statusLabels: [String] {
        AO3CollectionCardCopy.statusLabels(
            isUnrevealed: collection.isUnrevealed,
            isAnonymous: collection.isAnonymous
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if showsByline {
                AO3AuthorBylineView(
                    names: collection.maintainerNames,
                    identities: collection.maintainerIdentities,
                    fallbackText: collection.byline,
                    includesBy: !collection.maintainerNames.isEmpty,
                    font: .caption,
                    compact: true
                )
            }
            if !collection.summary.isEmpty {
                Text(collection.summary)
                    .font(.system(size: summarySize))
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !metaFacts.isEmpty || !collection.updatedAtText.isEmpty {
                metaRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectCard(palette: palette)
    }

    /// The eyebrow already names a single maintainer. The byline stays when it
    /// adds someone — you own it, so the maintainers are a second fact, or
    /// there is more than one name.
    private var showsByline: Bool {
        guard !collection.byline.isEmpty || !collection.maintainerNames.isEmpty else { return false }
        if collection.viewerIsOwner { return true }
        return collection.maintainerNames.count > 1
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            tile
            VStack(alignment: .leading, spacing: 4) {
                eyebrowRow
                Text(collection.title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var eyebrowRow: some View {
        if !eyebrow.isEmpty || !statusLabels.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                if !eyebrow.isEmpty {
                    SubjectKicker(
                        text: eyebrow,
                        palette: palette,
                        ruleWidth: 22,
                        ruleSpacing: 5
                    )
                }
                ForEach(statusLabels, id: \.self) { label in
                    SubjectChip(text: label, style: .neutral, palette: palette)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var tile: some View {
        Image(systemName: "archivebox")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(palette.accent)
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.chipFill)
            )
            .accessibilityHidden(true)
    }

    private var metaRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !metaFacts.isEmpty {
                Text(metaFacts.joined(separator: " · "))
                    .font(.system(size: metaSize))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !collection.updatedAtText.isEmpty {
                Text(collection.updatedAtText)
                    .font(.system(size: metaSize))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
