import SwiftUI

/// Artboard 1l: the Inbox as its own pushed screen.
///
/// It used to render inline under the Account hub's Activity scope, which meant
/// its filter, Select and bulk-action controls lived on the hub's toolbar behind
/// an `isInboxVisible` gate — hub furniture that existed only for this one
/// subsection. With the hub flattened into a single sectioned list there is no
/// scope left to select, so the Inbox needs somewhere of its own to be, and its
/// controls come with it.
///
/// The navigation bar is kept here rather than swapped for floating chrome, and
/// that is deliberate: selection mode puts Select All in `.confirmationAction`
/// and the bulk actions in `.bottomBar`, and neither has anywhere to live
/// without a bar. The hub around it has no bar; this screen does.
///
/// Every write this screen can start — mark read, mark unread, delete from the
/// inbox — still belongs to `AO3InboxModel`. Nothing about that moved.
struct AccountInboxScreen: View {
    var model: AO3InboxModel
    var onOpen: (AO3InboxItem) -> Void
    var onReply: (AO3InboxItem) -> Void
    var onOpenChapter: (AO3InboxItem) -> Void
    var workContext: (AO3InboxItem) -> AO3CommentsWorkContext
    /// The hub owns the enrichment because it owns the caches it seeds from.
    var metadataTaskID: String
    var onEnrichVisible: () async -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @State private var showingFilters = false

    var body: some View {
        List {
            Section {
                if let tally {
                    SubjectPageFact(tally, gutter: SubjectMetrics.accountGutter)
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            Section {
                // The ForEach has to sit in this List. A view that returned
                // every comment from its own body was one row, and a swipe on
                // a comment inside it does not attach.
                if showsCommentFeed {
                    if model.isShowingStaleCache {
                        AccountInboxStaleCacheRow(isLast: model.items.isEmpty)
                            .id("inbox-stale-\(model.items.isEmpty)")
                    }
                    ForEach(commentSegments) { segment in
                        AccountInboxCommentListRow(
                            model: model,
                            item: segment.item,
                            workContext: workContext(segment.item),
                            isSelecting: model.isSelecting,
                            isFirst: segment.isFirst,
                            isLast: segment.isLast,
                            onOpen: { onOpen(segment.item) },
                            onOpenChapter: { onOpenChapter(segment.item) },
                            onReply: { onReply(segment.item) }
                        )
                    }
                    if let onSeeAll = inboxStatus.onSeeAll, !model.items.isEmpty {
                        AccountInboxSeeAllRow(
                            unreadCount: model.unreadCount,
                            action: onSeeAll
                        )
                    }
                    if model.totalPages > 1 {
                        SearchPaginationBar(
                            currentPage: model.currentPage,
                            totalPages: model.totalPages
                        ) { page in
                            model.goToPage(page, auth: auth)
                        }
                        // The pill floats, as on every other paged list; a
                        // card behind it read as a second, empty panel.
                        .bareListRow()
                        .disabled(model.isPerformingBulkAction)
                    }
                    if case .paginationFailed = model.phase {
                        inboxStatus
                    }
                } else {
                    inboxStatus
                }
            }
        }
        .cardList()
        .refreshable {
            await model.refresh(auth: auth)
        }
        .subjectScreenWash(title: "Inbox", palette: theme.scopePalette)
        .toolbar { toolbarContent }
        #if os(iOS)
        .toolbar(model.isSelecting ? .hidden : .automatic, for: .tabBar)
        #endif
        .sheet(isPresented: $showingFilters) {
            AccountInboxFilterSheet(model: model)
            #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            #endif
        }
        .alert("Couldn't update Inbox", isPresented: actionErrorBinding) {
            Button("OK") { model.clearActionError() }
        } message: {
            Text(model.actionError ?? "AO3 couldn't update your Inbox.")
        }
        .task(id: metadataTaskID) { await onEnrichVisible() }
    }

    private var availablePills: [AO3InboxPill] {
        AO3InboxPill.available(in: model.filterForm)
    }

    /// A pill waits while a page is on its way: the checked one names the rows shown.
    private var isLoadingPage: Bool {
        if case .loading = model.phase { return true }
        return false
    }

    /// Board 40: the All / Unread / Awaiting reply / Replied choice lives in the
    /// filter button's menu (AO3's own server-side filters, so a pick reloads
    /// page 1); "More Filters…" opens the full sheet.
    private var filterMenu: some View {
        let selected = AO3InboxPill.selected(in: model.currentFilterValues)
        return Menu {
            if !availablePills.isEmpty {
                Picker("Show", selection: Binding(
                    get: { selected },
                    set: { if let pill = $0 { model.applyFilters(pill.values, auth: auth) } }
                )) {
                    ForEach(availablePills) { pill in
                        Text(pill.title).tag(Optional(pill))
                    }
                }
                .disabled(model.isPerformingBulkAction || isLoadingPage)
            }
            Button { showingFilters = true } label: {
                Label("More Filters…", systemImage: "slider.horizontal.3")
            }
        } label: {
            Label("Inbox Filters", systemImage: "line.3.horizontal.decrease")
        }
        .labelStyle(.iconOnly)
    }

    /// 1l heads the page with what is waiting rather than only what it is.
    /// Awaiting reply counts the loaded page. The heading has no such total —
    /// see `AO3InboxTally.headerLine`.
    private var tally: String? {
        guard let total = model.totalComments else { return nil }
        return AO3InboxTally.summaryLine(
            total: total,
            unread: model.unreadCount,
            awaitingOnPage: AO3InboxTally.awaitingReplyCount(model.items),
            totalPages: model.totalPages,
            showing: AO3InboxPill.selected(in: model.currentFilterValues)
        )
    }

    /// Comments stay on screen through a failed page turn. An empty first load
    /// does not: that is the loading or empty state, not a blank panel.
    private var showsCommentFeed: Bool {
        switch model.phase {
        case .paginationFailed:
            true
        case .idle, .loading, .loaded:
            !model.items.isEmpty
        case .failed:
            false
        }
    }

    private var commentSegments: [AccountInboxPanelSegment] {
        AccountInboxPanelSegment.rows(
            items: model.items,
            hasStaleBanner: model.isShowingStaleCache
        )
    }

    private var inboxStatus: AccountInboxRows {
        AccountInboxRows(
            model: model,
            limit: nil,
            onOpen: onOpen,
            onReply: onReply,
            onOpenChapter: onOpenChapter,
            workContext: workContext
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if model.isSelecting {
            ToolbarItem(placement: .confirmationAction) {
                SelectAllButton(
                    allSelected: model.allCurrentPageSelected,
                    action: model.toggleSelectAllCurrentPage
                )
            }
            #if os(iOS)
                ToolbarItemGroup(placement: .bottomBar) {
                    AccountInboxBulkActionBar(model: model)
                }
            #else
                ToolbarItemGroup(placement: .primaryAction) {
                    AccountInboxBulkActionBar(model: model)
                }
            #endif
        } else {
            // Board 40: filter and "…" share one glass pill (no spacer between
            // them). Select lives in the "…", as on every other list.
            ToolbarItemGroup(placement: .primaryAction) {
                if model.canFilter { filterMenu }
                if model.canSelectItems {
                    WorkListMoreMenu {
                        Button(action: model.beginSelection) {
                            Label("Select", systemImage: "checklist")
                        }
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.clearActionError() } }
        )
    }
}
