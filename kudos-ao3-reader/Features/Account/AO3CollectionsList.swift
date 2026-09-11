import SwiftUI

/// The signed-in user's AO3 collections — artboards **1r** (the list) and **1bm**
/// (its sort-and-filter sheet). Tapping a collection pushes its works, reusing
/// `AO3AccountWorksList` via the `.collection` kind.
///
/// Read-only. Joining, leaving and submitting a work to a collection are AO3 writes
/// the app does not surface here; the networking exists (`AO3CollectionActions`) and
/// the screens for it are Phase 10's remaining work.
struct AO3CollectionsList: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @State private var collections: [AO3Collection] = []
    @State private var phase: Phase = .idle
    @State private var showLogin = false
    @State private var filters = AO3CollectionsFilter()
    @State private var showingFilters = false

    private enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    /// What the list draws: AO3's rows, sorted and narrowed in memory. Spec 1bm's
    /// own note says why that is client-side — AO3 sorts collections by title and
    /// date only.
    private var visibleCollections: [AO3Collection] {
        filters.apply(to: collections)
    }

    var body: some View {
        Group {
            if auth.isLoggedIn { signedInContent } else { signedOutPrompt }
        }
        .hidesFloatingTabBar()
        .toolbar {
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
        .task(id: auth.isLoggedIn) {
            if auth.isLoggedIn, phase == .idle { await load() }
        }
        .sheet(isPresented: $showLogin) { AO3LoginView() }
    }

    @ViewBuilder
    private var signedInContent: some View {
        switch phase {
        case .loaded where collections.isEmpty:
            ContentUnavailableView {
                Label("No collections", systemImage: "square.stack")
            } description: {
                Text("Collections you create or maintain on AO3 show up here.")
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't load collections", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load() } }
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
                if !filters.summaryLabels.isEmpty {
                    filterRail.pageBodyRow(top: 12, gutter: 0)
                }
            }

            if visibleCollections.isEmpty {
                Section {
                    noMatchesCard.pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
                }
            } else {
                Section {
                    ForEach(visibleCollections) { collection in
                        AO3CollectionCard(collection: collection, palette: palette)
                            .cardNavigation(
                                to: AO3AccountWorksList.Kind.collection(
                                    name: collection.name,
                                    title: collection.title
                                ),
                                accessibilityLabel: collection.title
                            )
                            .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
                    }
                }
            }
        }
        .cardList()
        .subjectScreenWash(palette: palette)
        .refreshable { await load() }
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
        return line
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

    private var noMatchesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No collections match")
                .font(.system(size: 15, weight: .semibold))
            Text("\(collections.count) collection\(collections.count == 1 ? "" : "s") are hidden "
                + "by the current filters.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Clear Filters") { filters = AO3CollectionsFilter() }
                .buttonStyle(.borderless)
                .font(.system(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectPanel()
    }

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: theme.scopeHue)
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

    private func load() async {
        guard auth.isLoggedIn, let username = auth.username,
              let url = AO3Client.collectionsURL(username: username, page: 1) else { return }
        if collections.isEmpty { phase = .loading }
        do {
            let request = try auth.authenticatedRequest(for: url)
            collections = try await AO3Client.shared.collectionsPage(for: request)
            phase = .loaded
            AO3AccountListCountsCache.shared.record(
                AO3AccountListCount(exact: collections.count),
                kind: .collections,
                authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
            )
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

/// One collection on the list — spec 1r's card: title, maintainers, summary, and
/// the counts and state flags AO3 gives for it.
///
/// The four flags are shown as chips rather than folded into prose because they are
/// independent on AO3 (a collection can be closed *and* moderated *and* anonymous),
/// and because each changes what submitting to it means.
struct AO3CollectionCard: View {
    let collection: AO3Collection
    let palette: SubjectPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(collection.title)
                .font(.system(size: 16.5, weight: .semibold))
                .lineLimit(2)

            if !collection.byline.isEmpty {
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

            if !countsLine.isEmpty {
                Text(countsLine)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if !flagLabels.isEmpty {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(flagLabels, id: \.self) { label in
                        SubjectChip(text: label, style: .neutral, palette: palette)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectCard(palette: palette)
    }

    /// Each count is dropped rather than zeroed when AO3 did not give one — a
    /// collection whose works count failed to parse is not a collection with no
    /// works.
    private var countsLine: String {
        var parts: [String] = []
        if let works = collection.worksCount {
            parts.append("\(works) work\(works == 1 ? "" : "s")")
        }
        if let bookmarks = collection.bookmarksCount, bookmarks > 0 {
            parts.append("\(bookmarks) bookmark\(bookmarks == 1 ? "" : "s")")
        }
        if !collection.updatedAtText.isEmpty {
            parts.append(collection.updatedAtText)
        }
        return parts.joined(separator: "  ·  ")
    }

    private var flagLabels: [String] {
        var labels: [String] = []
        if collection.isClosed { labels.append("Closed") }
        if collection.isModerated { labels.append("Moderated") }
        if collection.isUnrevealed { labels.append("Unrevealed") }
        if collection.isAnonymous { labels.append("Anonymous") }
        if let challenge = collection.challengeKind { labels.append(challenge.displayName) }
        return labels
    }
}
