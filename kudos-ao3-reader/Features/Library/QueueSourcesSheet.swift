import SwiftData
import SwiftUI

/// Pushed Find More destinations from a queue's "From sources" list or Sources sheet.
struct OpenedQueueAuthorSource: Hashable {
    let linkID: UUID
    let route: AO3AuthorRoute
    let label: String
}

struct OpenedQueueSeriesSource: Hashable {
    let linkID: UUID
    let series: AO3SeriesSummary
    let label: String
}

struct OpenedQueueTagSource: Hashable {
    let linkID: UUID
    let request: AO3TagWorksRequest
    let label: String
}

/// Hosts the Sources sheet and pushed Find More destinations for `ReadingQueueBrowserView`.
struct QueueSourcePresentationsModifier: ViewModifier {
    @Binding var showingSources: Bool
    @Binding var openedAuthorSource: OpenedQueueAuthorSource?
    @Binding var openedSeriesSource: OpenedQueueSeriesSource?
    @Binding var openedTagSource: OpenedQueueTagSource?
    let selectedQueue: ReadingQueue?
    let works: [SavedWork]
    let preservedCount: Int
    let isSignedOut: Bool
    let sourcePages: [UUID: QueueSourceFetchedPage]
    let onQueueOpenSource: (QueueSavedSearchLink) -> Void
    let onDismissSources: () -> Void
    let onRecordOpen: (UUID) -> Void

    /// The counted page for this source, only while it is fresh, still the page
    /// the source's listing URL loads, and the reader is signed out.
    private func cachedPage(_ linkID: UUID) -> QueueSourceFetchedPage? {
        guard let link = selectedQueue?.searchLinks.first(where: { $0.id == linkID }) else { return nil }
        return QueueSourceChecks.cachedFetchForFindMore(
            sourcePages[linkID], listingURL: link.listingURL, isSignedOut: isSignedOut
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingSources, onDismiss: onDismissSources) {
                if let selectedQueue {
                    QueueSourcesSheet(
                        queue: selectedQueue,
                        works: works,
                        preservedCount: preservedCount,
                        onOpenSource: onQueueOpenSource
                    )
                    #if os(iOS)
                    .modifier(ScopeSurfaceAccent())
                    #endif
                }
            }
            .navigationDestination(item: $openedAuthorSource) { target in
                AuthorProfileView(
                    route: target.route,
                    initialTab: .works,
                    preloadedWorksHTML: cachedPage(target.linkID)?.html,
                    onWorksPageOneLoaded: { onRecordOpen(target.linkID) }
                )
                .environment(
                    \.queueMembershipOrigin,
                    ReadingQueueMembershipOrigin(
                        kind: .source,
                        searchID: nil,
                        label: target.label,
                        importSourceHint: .author
                    )
                )
            }
            .navigationDestination(item: $openedSeriesSource) { target in
                AO3SeriesDetailView(
                    series: target.series,
                    preloadedPageOneHTML: cachedPage(target.linkID)?.html,
                    initialOrigin: ReadingQueueMembershipOrigin(
                        kind: .source,
                        searchID: nil,
                        label: target.label,
                        importSourceHint: .series
                    ),
                    onPageOneLoaded: { onRecordOpen(target.linkID) }
                )
            }
            .navigationDestination(item: $openedTagSource) { target in
                TagWorksView(
                    request: target.request,
                    preloadedPage: cachedPage(target.linkID)?.page,
                    initialOrigin: ReadingQueueMembershipOrigin(
                        kind: .source,
                        searchID: nil,
                        label: target.label,
                        importSourceHint: .browse
                    ),
                    onPageOneLoaded: { onRecordOpen(target.linkID) }
                )
            }
    }
}

/// Board `Queue-Sources`: manage every source attached to a queue (saved
/// searches, authors, series, tags) and view each source's last-checked new
/// works count. Sources only ever show a count — never auto-add works (§8 Q3).
struct QueueSourcesSheet: View {
    let queue: ReadingQueue
    let works: [SavedWork]
    let preservedCount: Int
    let onOpenSource: (QueueSavedSearchLink) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme
    @Query private var savedSeries: [SavedSeries]
    @State private var showingAddSource = false

    private var savedSeriesByID: [Int: SavedSeries] {
        Dictionary(savedSeries.map { ($0.ao3SeriesID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    queueContextCard
                        .appThemedRows()
                }

                if !queue.savedSearchLinks.isEmpty {
                    Section("Searches") {
                        ForEach(queue.savedSearchLinks) { link in
                            sourceRow(link, kind: .savedSearch)
                                .appThemedRows()
                        }
                    }
                }

                if !queue.authorAndSeriesSources.isEmpty {
                    Section("Authors and series") {
                        ForEach(queue.authorAndSeriesSources) { link in
                            if let kind = link.knownSourceKind {
                                sourceRow(link, kind: kind)
                                    .appThemedRows()
                            }
                        }
                    }
                }

                if !queue.tagSources.isEmpty {
                    Section("Tags") {
                        ForEach(queue.tagSources) { link in
                            sourceRow(link, kind: .tag)
                                .appThemedRows()
                        }
                    }
                }

                if queue.allVisibleSources.isEmpty {
                    Section {
                        Text(
                            "Link saved searches, authors, series, or tags to check for new works "
                                + "when you open this queue."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .appThemedRows()
                    }
                }

                Section {
                    Button {
                        showingAddSource = true
                    } label: {
                        Text("Add a Source…")
                            .foregroundStyle(.accentInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityLabel("Add a source to \(queue.displayName)")
                    .appThemedRows()
                } footer: {
                    Text(
                        "Kudos checks a source when you open this queue. "
                            + "Nothing is fetched in the background."
                    )
                    .foregroundStyle(.secondaryInk)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .appThemedScroll()
            .navigationTitle("Sources")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .sheetConfirmStyle()
                }
            }
        }
        .screenTint(theme.scopePalette)
        #if DEBUG
        .onAppear { if DebugLaunchRoute.takeSheet("addsource") { showingAddSource = true } }
        #endif
        .sheet(isPresented: $showingAddSource) {
            AddQueueSourceSheet(
                queueName: queue.displayName,
                existingSearchIDs: Set(queue.savedSearchLinks.compactMap { $0.search?.id }),
                existingSourceKeys: Set(queue.nonSearchSources.map(\.dedupKey)),
                onAddSearch: { search in
                    _ = ReadingQueueService.addSavedSearchSource(search, to: queue, in: context)
                },
                onAddSource: { draft in
                    _ = ReadingQueueService.addSource(draft, to: queue, in: context)
                }
            )
            #if os(iOS)
            .modifier(ScopeSurfaceAccent())
            #endif
        }
    }

    private var queueContextCard: some View {
        QueueContextCard(queue: queue, works: works, offlineCount: preservedCount)
    }

    private func sourceSubtitle(for link: QueueSavedSearchLink, kind: QueueSourceKind) -> String? {
        if kind == .series, let id = link.ao3SeriesID, let cached = savedSeriesByID[id] {
            let count = cached.snapshot.effectivePartCount
            if count > 0 {
                return ReadingQueueFacts.seriesSourceSubtitle(
                    partCount: count,
                    isComplete: cached.snapshot.isComplete
                )
            }
        }
        return link.effectiveSubtitle
    }

    private func sourceRow(_ link: QueueSavedSearchLink, kind: QueueSourceKind) -> some View {
        let name = link.effectiveDisplayName
        let subtitle = sourceSubtitle(for: link, kind: kind)
        let count = link.displayedNewCount
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))

        return Button {
            dismiss()
            onOpenSource(link)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                QueueSourceIconTile(symbolName: kind.symbolName)
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    if let count {
                        QueueNewCountBadge(text: QueueSourceChecks.badge(count))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondaryInk)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(QueueSourceChecks.sourceAccessibilityLabel(
            name: name,
            kind: kind,
            count: link.newResultCount,
            filters: link.search?.filters
        ))
        .accessibilityAction(named: "Remove") {
            ReadingQueueService.removeSource(link, from: queue, in: context)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                ReadingQueueService.removeSource(link, from: queue, in: context)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                dismiss()
                onOpenSource(link)
            } label: {
                Label("Open on AO3", systemImage: kind.symbolName)
            }
            Button(role: .destructive) {
                ReadingQueueService.removeSource(link, from: queue, in: context)
            } label: {
                Label("Remove Source", systemImage: "trash")
            }
        }
    }
}
