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
                AccountInboxRows(
                    model: model,
                    limit: nil,
                    onOpen: onOpen,
                    onReply: onReply,
                    onOpenChapter: onOpenChapter,
                    workContext: workContext
                )
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
    private var tally: String? {
        guard let total = model.totalComments else { return nil }
        let comments = total == 1 ? "1 comment" : "\(total.formatted()) comments"
        guard let unread = model.unreadCount, unread > 0 else { return comments }
        return "\(comments) · \(unread.formatted()) unread"
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
