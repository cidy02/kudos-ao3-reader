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
                SubjectHeaderBlock(
                    kicker: "AO3 Account",
                    title: "Inbox",
                    subtitle: tally,
                    palette: theme.scopePalette,
                    gutter: SubjectMetrics.accountGutter
                )
                .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                // The ForEach has to sit in this List. A view that returned
                // every comment from its own body was one row, and a swipe on
                // a comment inside it does not attach.
                if showsCommentFeed {
                    AccountInboxFeedHeader(tally: inboxStatus.headerTallyLine)
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
                        .accountControlCardRow()
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
        .hidesNavigationBarChrome()
        .subjectScreenWash(palette: theme.scopePalette)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingFilters) {
            AccountInboxFilterSheet(model: model)
        }
        .alert("Couldn't update Inbox", isPresented: actionErrorBinding) {
            Button("OK") { model.clearActionError() }
        } message: {
            Text(model.actionError ?? "AO3 couldn't update your Inbox.")
        }
        .task(id: metadataTaskID) { await onEnrichVisible() }
    }

    /// 1l heads the page with what is waiting rather than only what it is.
    /// Awaiting reply counts the loaded page. The heading has no such total —
    /// see `AO3InboxTally.headerLine`.
    private var tally: String? {
        guard let total = model.totalComments else { return nil }
        return AO3InboxTally.headerLine(
            total: total,
            unread: model.unreadCount,
            awaitingOnPage: AO3InboxTally.awaitingReplyCount(model.items),
            totalPages: model.totalPages
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
            ToolbarItemGroup(placement: .primaryAction) {
                if model.canFilter {
                    ToolbarIconButton(
                        title: "Inbox Filters",
                        systemImage: "line.3.horizontal.decrease"
                    ) {
                        showingFilters = true
                    }
                }
                if model.canSelectItems {
                    ToolbarIconButton(
                        title: "Select Inbox Items",
                        systemImage: "checklist",
                        action: model.beginSelection
                    )
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
