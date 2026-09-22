import SwiftUI

/// The signed-in user's AO3 collections — artboards **1r** (the list) and **1bm**
/// (its sort-and-filter sheet). Tapping a collection pushes its works, reusing
/// `AO3AccountWorksList` via the `.collection` kind.
///
/// Read-only. Joining, leaving and submitting a work to a collection are AO3 writes
/// the app does not surface here; the networking exists (`AO3CollectionActions`) and
/// the screens for it are Phase 10's remaining work. Deleting a collection stays on
/// AO3's confirm page — this list opens that page and does not POST.
struct AO3CollectionsList: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(AppRouter.self) private var router

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

    private enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    /// What the list draws: AO3's rows, sorted and narrowed in memory. Spec 1bm's
    /// own note says why that is client-side — AO3 sorts collections by title and
    /// date only. The sort sees the page on screen, not every page of the index.
    private var visibleCollections: [AO3Collection] {
        filters.apply(to: collections)
    }

    private var showPagination: Bool { totalPages > 1 }

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
            if phase == .loaded, !collections.isEmpty {
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
                filters: $filters,
                onApply: { showingFilters = false },
                onReset: { filters = AO3CollectionsFilter() }
            )
            .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
        }
        .navigationDestination(item: $editingCollection) { destination in
            AO3CollectionFormView(slug: destination.slug)
        }
        .navigationDestination(item: $yourItems) { destination in
            AO3CollectionItemsView(slug: destination.slug, title: destination.title)
        }
        .task(id: auth.isLoggedIn) {
            if auth.isLoggedIn, phase == .idle { await load(page: 1) }
        }
        .sheet(isPresented: $showLogin) { AO3LoginView() }
    }

    @ViewBuilder
    private var signedInContent: some View {
        switch phase {
        case let .failed(message) where collections.isEmpty:
            ContentUnavailableView {
                Label("Couldn't load collections", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load(page: currentPage) } }
            }
        case .loading where collections.isEmpty:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
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
        }
        .cardList()
        .subjectScreenWash(palette: palette)
        .refreshable { await load(page: currentPage) }
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
                Button(role: .destructive) {
                    openDeleteOnAO3(collection)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    openDeleteOnAO3(collection)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
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

    /// Delete is AO3's confirm page. The app does not remove the collection itself.
    private func openDeleteOnAO3(_ collection: AO3Collection) {
        router.open(AO3CollectionURL.confirmDelete(slug: collection.name))
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

    /// Counts what is on screen, not what was fetched — a tally that ignored the
    /// filters would contradict the rows under it.
    private var tallyLine: String {
        let shown = visibleCollections.count
        var line = "\(shown) collection\(shown == 1 ? "" : "s")"
        if shown != collections.count {
            line += " · \(collections.count) in all"
        }
        if totalPages > 1 {
            line += " · page \(currentPage) of \(totalPages)"
        }
        return line
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
        SubjectFilterRail(
            onOpenFilters: { showingFilters = true },
            activeFilterCount: filters.summaryLabels.count
        ) {
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
            Text(collections.isEmpty ? "No collections" : "No collections match")
                .font(.system(size: 15, weight: .semibold))
            Text(emptyDetail)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !collections.isEmpty {
                Button("Clear Filters") { filters = AO3CollectionsFilter() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectPanel()
    }

    private var emptyDetail: String {
        if collections.isEmpty {
            return "Collections you create or maintain on AO3 show up here."
        }
        let count = collections.count
        return "\(count) collection\(count == 1 ? "" : "s") are hidden by the current filters."
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

    private func load(page: Int) async {
        let expectedSessionGeneration = auth.sessionGeneration
        guard auth.isLoggedIn, let username = auth.username,
              let url = AO3Client.collectionsURL(username: username, page: page) else { return }
        loadGeneration += 1
        let generation = loadGeneration
        phase = .loading
        do {
            let request = try auth.authenticatedRequest(for: url)
            let result = try await AO3Client.shared.collectionsIndex(for: request, page: page)
            guard generation == loadGeneration,
                  auth.sessionGeneration == expectedSessionGeneration else { return }
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
            guard generation == loadGeneration,
                  auth.sessionGeneration == expectedSessionGeneration else { return }
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            guard generation == loadGeneration,
                  auth.sessionGeneration == expectedSessionGeneration else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

/// One collection on the list. The hue is the collection's own, from its title,
/// the way a queue carries a colour. Approval queues and "works of yours" are
/// not on AO3's collection blurb, so they are not drawn.
struct AO3CollectionCard: View {
    let collection: AO3Collection

    @Environment(ThemeManager.self) private var theme

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
            isUnrevealed: collection.isUnrevealed,
            challengeName: collection.challengeKind?.displayName
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
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(2)
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
        if !eyebrow.isEmpty || collection.isAnonymous {
            HStack(alignment: .top, spacing: 6) {
                if !eyebrow.isEmpty {
                    SubjectKicker(
                        text: eyebrow,
                        palette: palette,
                        ruleWidth: 22,
                        ruleSpacing: 5
                    )
                }
                if collection.isAnonymous {
                    SubjectChip(text: "Anonymous", style: .neutral, palette: palette)
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
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !collection.updatedAtText.isEmpty {
                Text(collection.updatedAtText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
