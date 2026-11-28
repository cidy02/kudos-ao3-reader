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
        .navigationTitle(ChallengesBoardCopy.collectionsTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if phase == .loaded, !collections.isEmpty || hasCurrentWholeIndex {
                ToolbarItem(placement: .primaryAction) {
                    FilterButton(
                        filtersActive: filters.hasActiveFilters,
                        showingFilters: $showingFilters,
                        filterHelp: ChallengesBoardCopy.collectionsFilterHelp,
                        onClearFilters: { filters = AO3CollectionsFilter() }
                    )
                }
            }
            if auth.isLoggedIn {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: AO3CollectionFormDestination(slug: nil)) {
                        Label("New Collection", systemImage: "plus")
                    }
                    .accessibilityLabel("New Collection")
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
        #if DEBUG
        .task {
            if DebugLaunchRoute.takeSheet("colsfilter") { showingFilters = true }
            if DebugLaunchRoute.takeSheet("colitems") {
                yourItems = AO3CollectionItemsDestination(
                    slug: nil, title: ChallengesBoardCopy.collectionsYourItemsPillTitle
                )
            }
        }
        #endif
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
        // A collection created or saved in the form: its row here was the old one, or missing.
        .onReceive(NotificationCenter.default.publisher(for: .ao3CollectionChanged)) { _ in reloadAfterChange() }
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
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accentFill()
        } else if case let .failed(message) = phase, displayedCollections.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load collections", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load(page: currentPage) } }
            }
        } else if phase == .loading, displayedCollections.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accentFill()
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
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accentFill()
            }
        } else {
            collectionsList
        }
    }

    private var collectionsList: some View {
        List {
            Section {
                Text(headerSubtitleLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .pageBodyRow(top: 12, gutter: SubjectMetrics.accountGutter)
                scopeRail.pageBodyRow(top: 10, gutter: 0)
                if !filters.summaryLabels.isEmpty {
                    filterRail.pageBodyRow(top: 10, gutter: 0)
                }
                if showPagination, SearchPaginationBar.showsTopPager(rowCount: visibleCollections.count) {
                    paginationBar.pageBodyRow(top: 12, gutter: SubjectMetrics.accountGutter)
                }
            }

            if visibleCollections.isEmpty {
                Section {
                    emptyCard.pageBodyRow(top: 16, gutter: SubjectMetrics.accountGutter)
                }
            } else {
                groupedCollectionSections
            }

            if showPagination {
                Section {
                    paginationBar.pageBodyRow(top: 16, gutter: SubjectMetrics.accountGutter)
                }
            }

            Section {
                sourceFooter.pageBodyRow(top: 16, gutter: SubjectMetrics.accountGutter)
            }
        }
        .cardList()
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(palette: palette, role: .grouped)
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

    @ViewBuilder
    private var groupedCollectionSections: some View {
        if filters.sort == .asReturned {
            let maintained = visibleCollections.filter(\.viewerIsOwner)
            let member = visibleCollections.filter { !$0.viewerIsOwner }
            if !maintained.isEmpty {
                collectionGroupSection(
                    title: ChallengesBoardCopy.collectionsMaintainSectionTitle,
                    collections: maintained
                )
            }
            if !member.isEmpty {
                collectionGroupSection(
                    title: ChallengesBoardCopy.collectionsMemberSectionTitle,
                    collections: member
                )
            }
        } else {
            collectionGroupSection(
                title: ChallengesBoardCopy.collectionsTitle,
                collections: visibleCollections
            )
        }
    }

    @ViewBuilder
    private func collectionGroupSection(title: String, collections groupRows: [AO3Collection]) -> some View {
        let keyed = PanelSegment.keyed(groupRows, id: \.id)
        Section {
            ChallengeBoardSectionHeader(title: title)
                .padding(.bottom, 6)
                .pageBodyRow(top: 16, gutter: 0)
            ForEach(keyed, id: \.key) { row in
                collectionRow(row.element, offset: row.offset, count: keyed.count)
            }
        }
    }

    private func collectionRow(_ collection: AO3Collection, offset: Int, count: Int) -> some View {
        let detail = ChallengesBoardCopy.collectionsRowDetail(for: collection)
        return AO3CollectionCard(collection: collection)
            .subjectRowNavigation(
                to: AO3CollectionDestination(
                    slug: collection.name,
                    title: collection.title
                ),
                accessibilityLabel: "\(collection.title), \(detail)"
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
            .panelSegment(offset, of: count, gutter: SubjectMetrics.accountGutter)
    }

    private func editDestination(for collection: AO3Collection) -> AO3CollectionFormDestination {
        AO3CollectionFormDestination(slug: collection.name)
    }

    private func itemsDestination(for collection: AO3Collection) -> AO3CollectionItemsDestination {
        AO3CollectionItemsDestination(slug: collection.name, title: collection.title)
    }

    /// Two scopes: "Collections" is this list; "Your Items" is AO3's
    /// account-wide collection-items page.
    private var scopeRail: some View {
        // One line cut "Your Items" at AX5.
        AccessibilityChipRail(horizontalPadding: SubjectMetrics.accountGutter) {
            ChallengeBoardChipLabel(
                text: ChallengesBoardCopy.collectionsTitle,
                isSelected: true
            )
            .accessibilityAddTraits(.isSelected)
            Button {
                yourItems = AO3CollectionItemsDestination(
                    slug: nil, title: ChallengesBoardCopy.collectionsYourItemsPillTitle
                )
            } label: {
                ChallengeBoardChipLabel(
                    text: ChallengesBoardCopy.collectionsYourItemsPillTitle,
                    isSelected: false
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ChallengesBoardCopy.collectionsYourItemsPillTitle)
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
            Text(ChallengesBoardCopy.collectionsEmptyTitle(hasLoadedCollections: !displayedCollections.isEmpty))
                .font(.system(size: stateTitleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(ChallengesBoardCopy.collectionsEmptyDetail(totalLoadedCount: displayedCollections.count))
                .font(.system(size: bodySize))
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if !displayedCollections.isEmpty {
                Button("Clear Filters") { filters = AO3CollectionsFilter() }
                    .buttonStyle(.borderless)
                    .font(.system(size: actionSize, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .challengeBoardCard()
    }

    private var sourceFooter: some View {
        ChallengeBoardSectionFooter(
            text: "These are your AO3 collections. Collections you make in Kudos are in Library.",
            horizontalInset: 16
        )
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
        reloadAfterChange()
    }
    private func reloadAfterChange() {
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
    private var headerSubtitleLine: String {
        ChallengesBoardCopy.collectionsHeaderLine(
            shown: visibleCollections.count,
            total: displayedCollections.count,
            isFiltered: filters.hasActiveFilters,
            currentPage: currentPage,
            totalPages: showPagination ? totalPages : 1,
            partialNote: filters.needsWholeIndex && hasCurrentWholeIndex ? wholeIndexPartialNote : nil
        )
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

/// One collection row matching `AO3-Collections.dc.html`: 40×40 rounded-10 colored
/// monogram tile, 16 pt semibold title, 13 pt detail line, and trailing disclosure chevron.
struct AO3CollectionCard: View {
    let collection: AO3Collection

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .footnote) private var detailSize: CGFloat = 13

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: [], title: collection.title)
        )
    }

    private var detailText: String {
        ChallengesBoardCopy.collectionsRowDetail(for: collection)
    }

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            ChallengeBoardAvatar(
                text: ChallengesBoardCopy.collectionInitial(
                    title: collection.title,
                    fallbackSlug: collection.name
                ),
                color: palette.accent,
                shapeKind: .roundedSquare(size: 40, radius: 10)
            )
            .padding(.top, dynamicTypeSize.isAccessibilitySize ? 2 : 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailText)
                    .font(.system(size: detailSize))
                    .foregroundStyle(.secondaryInk)
                    .monospacedDigit()
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, dynamicTypeSize.isAccessibilitySize ? 4 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
