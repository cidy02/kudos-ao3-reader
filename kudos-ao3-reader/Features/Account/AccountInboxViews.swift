import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// The AO3 Inbox surfaces of the Account tab: a capped "Recent Comments" preview
// on Overview and the full feed under Activity › Inbox. Inbox entries are
// flat notification summaries (not threads), so each renders as one simple card
// — commenter, subject, excerpt, time — honoring the read/unread and replied
// state AO3 exposes. Activity › Inbox additionally supports AO3's native form
// actions when the loaded page provides a complete, parseable form.

/// Pushes a work's full comments experience from an inbox entry.
nonisolated enum AccountInboxThreadFocus: String, Hashable {
    case parentOrSelf
    case chapter
}

nonisolated struct AccountInboxThreadDestination: Hashable, Identifiable {
    let workID: Int
    let workContext: AO3CommentsWorkContext
    let commentID: Int
    let chapterPosition: Int?
    let focus: AccountInboxThreadFocus
    let opensReplyComposer: Bool

    var id: String { "\(workID):\(commentID):\(focus.rawValue):\(opensReplyComposer)" }
}

/// Account's shared toolbar, with Inbox select mode taking over the same slots
/// that Library selection uses. Keeping this separate from `AccountView` keeps
/// the profile hub focused on navigation and state ownership.
struct AccountToolbarContent: ToolbarContent {
    let isInboxVisible: Bool
    var model: AO3InboxModel
    @Binding var showingInboxFilters: Bool
    let showsMatureRevealControl: Bool
    let showsWorkListControls: Bool
    @Binding var displayMode: WorkListDisplayMode
    @Binding var expandAll: Bool

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if isInboxVisible, model.isSelecting {
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
            // One tight HStack — matches Library/Home so controls don't inherit
            // the wide system spacing of separate toolbar items.
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 2) {
                    if showsMatureRevealControl {
                        MatureRevealToggle()
                    }
                    if showsWorkListControls {
                        WorkListMoreMenu {
                            DisplayModeMenuPicker(mode: $displayMode)
                            if displayMode == .detailed {
                                ExpandAllMenuItem(expandAll: $expandAll)
                            }
                        }
                    }
                    if isInboxVisible, model.canFilter {
                        Button {
                            showingInboxFilters = true
                        } label: {
                            Label("Inbox Filters", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                    if isInboxVisible, model.canSelectItems {
                        Button(action: model.beginSelection) {
                            Label("Select Inbox Items", systemImage: "checklist")
                        }
                    }
                    NavigationLink(value: AccountView.Route.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                .labelStyle(.iconOnly)
            }
        }
    }
}

/// One inbox notification card.
struct AccountInboxItemRow: View {
    let item: AO3InboxItem
    var workAuthors: [String] = []
    var workAuthorIdentities: [AO3AuthorIdentity] = []
    var isSelecting = false
    var isSelected = false
    var isSelectable = false
    var onOpen: () -> Void
    var onOpenChapter: () -> Void = {}
    var onToggleSelection: () -> Void = {}
    var canToggleReadState = false
    var canDeleteFromInbox = false
    var isPerformingAction = false
    var onReply: () -> Void = {}
    var onToggleReadState: () -> Void = {}
    var onDeleteFromInbox: () -> Void = {}

    @Environment(AO3AuthService.self) private var auth
    @State private var confirmDelete = false
    @State private var actionNotice: String?

    var body: some View {
        if isSelecting {
            Button(action: onToggleSelection) {
                selectionContent
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable)
            .accessibilityHint("Toggle selection")
        } else {
            interactiveContent
                .confirmationDialog(
                    "Remove this notification from your AO3 Inbox?",
                    isPresented: $confirmDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete From Inbox", role: .destructive, action: onDeleteFromInbox)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes only the Inbox notification. It does not delete the comment.")
                }
                .alert("Inbox", isPresented: actionNoticeBinding) {
                    Button("OK") { actionNotice = nil }
                } message: {
                    Text(actionNotice ?? "")
                }
        }
    }

    private var interactiveContent: some View {
        ZStack {
            // Keeps the visible card surface (including the words around the
            // Chapter chip and inter-control whitespace) tappable. Sibling
            // Chapter/Reply buttons sit above it and retain their own actions.
            Button(action: onOpen) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.commenterName)'s comment thread")

            HStack(alignment: .top, spacing: 10) {
                Button(action: onOpen) { avatar }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(item.commenterName)'s comment thread")

                VStack(alignment: .leading, spacing: 4) {
                    Button(action: onOpen) {
                        byline
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Open the comment's thread")

                    subjectControl

                    if !item.excerpt.isEmpty {
                        Button(action: onOpen) {
                            Text(item.excerpt)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Open the comment's thread")
                    }

                    HStack(spacing: 8) {
                        if item.canReply {
                            CommentReplyButton(
                                accessibilityLabel: "Reply to \(item.commenterName)",
                                action: onReply
                            )
                        }
                        Spacer(minLength: 0)
                        if item.isReplied {
                            InboxRepliedBadge()
                        }
                        moreActionsMenu
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }

    private var selectionContent: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 24, height: 40)
                .accessibilityHidden(true)
            avatar

            VStack(alignment: .leading, spacing: 4) {
                byline
                if !item.subjectTitle.isEmpty {
                    Text("on \(item.subjectTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !item.excerpt.isEmpty {
                    Text(item.excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if item.isReplied { InboxRepliedBadge() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var byline: some View {
        HStack(alignment: .center, spacing: 6) {
            if item.isUnread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unread")
            }
            Text(item.commenterName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            CommentParticipantBadge(role: item.participantRole(
                workAuthors: workAuthors,
                workAuthorIdentities: workAuthorIdentities,
                currentUsername: auth.username
            ))
            Spacer(minLength: 4)
            if !item.postedAgo.isEmpty {
                Text(item.postedAgo)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var subjectControl: some View {
        if !item.subjectTitle.isEmpty {
            if let chapter = item.chapterIndicatorTitle {
                HStack(spacing: 4) {
                    Text("on")
                    Button(action: onOpenChapter) {
                        Text(chapter)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open \(chapter) comments and focus this thread")
                    Text("of \(item.workTitle)")
                        .lineLimit(2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Button(action: onOpen) {
                    Text("on \(item.subjectTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open the comment's thread")
            }
        }
    }

    /// Uses the same paced avatar pipeline as native comment cards.
    private var avatar: some View {
        CommentAvatar(isGuest: item.isGuest, avatarURL: item.avatarURL, size: 40)
    }

    private var moreActionsMenu: some View {
        Menu {
            Button(action: onOpen) {
                Label(
                    item.workID == nil ? "Open Comment" : "Open Thread",
                    systemImage: "bubble.left.and.bubble.right"
                )
            }
            if item.chapterPosition != nil {
                Button(action: onOpenChapter) {
                    Label("Chapter Comments", systemImage: "text.bubble")
                }
            }
            Button(action: copyLink) {
                Label("Copy Link", systemImage: "link")
            }
            if canToggleReadState {
                Button(action: onToggleReadState) {
                    Label(
                        item.isUnread ? "Mark Read" : "Mark Unread",
                        systemImage: item.isUnread ? "envelope.open" : "envelope.badge"
                    )
                }
            }
            if canDeleteFromInbox {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete From Inbox", systemImage: "trash")
                }
            }
        } label: {
            CommentOverflowButtonLabel()
        }
        .buttonStyle(.borderless)
        .disabled(isPerformingAction)
        .accessibilityLabel("More actions for \(item.commenterName)'s Inbox comment")
    }

    private var actionNoticeBinding: Binding<Bool> {
        Binding(get: { actionNotice != nil }, set: { if !$0 { actionNotice = nil } })
    }

    private func copyLink() {
        let url = AO3Client.commentThreadURL(commentID: item.id)
        #if os(iOS)
        UIPasteboard.general.url = url
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #endif
        actionNotice = "Link copied."
    }
}

/// AO3's replied state, visually distinct from neutral work-state chips. The
/// confirmation mark intentionally follows the text to match reading order.
private struct InboxRepliedBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Replied")
            Image(systemName: "checkmark")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.green.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Replied")
    }
}

/// The inbox rows for one Account section — the Overview preview (`limit` set)
/// or the full Activity feed (`limit` nil, with pagination). State lives in the
/// host's shared `AO3InboxModel`, so the two surfaces share one fetch.
struct AccountInboxRows: View {
    var model: AO3InboxModel
    /// Caps the rows for the Overview preview; nil shows the whole page.
    var limit: Int?
    var onOpen: (AO3InboxItem) -> Void
    var onReply: (AO3InboxItem) -> Void
    var onOpenChapter: (AO3InboxItem) -> Void = { _ in }
    var workContext: (AO3InboxItem) -> AO3CommentsWorkContext = {
        AO3CommentsWorkContext(title: $0.workTitle, authors: [])
    }
    /// Overview's trailing "See All Comments" row action (nil in the full feed).
    var onSeeAll: (() -> Void)?

    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        switch model.phase {
        case .idle, .loading:
            if model.items.isEmpty {
                loadingRows
            } else {
                itemRows
            }
        case let .failed(message):
            AO3ProfileMessageRow(
                title: "Couldn't load your inbox",
                systemImage: "exclamationmark.triangle",
                message: message,
                actionTitle: "Try Again",
                action: { model.retry(auth: auth) }
            )
            .accountControlCardRow()
        case .loaded where model.items.isEmpty:
            AO3ProfileMessageRow(
                title: "No comments yet",
                systemImage: "bubble.left",
                message: "Comments on your works, and replies to comments you've "
                    + "posted, show up here from your AO3 inbox."
            )
            .accountControlCardRow()
        case .loaded:
            itemRows
        }
    }

    private var loadingRows: some View {
        ForEach(0..<3, id: \.self) { _ in
            HStack(alignment: .top, spacing: 10) {
                SkeletonBlock(height: 40, width: 40, cornerRadius: 20)
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonTextLine(width: 140)
                    SkeletonTextLine(width: 220)
                    SkeletonTextLine(width: 180)
                }
            }
            .padding(.vertical, 2)
            .skeletonShimmer()
            .cardRow()
        }
    }

    @ViewBuilder
    private var itemRows: some View {
        if model.isShowingStaleCache {
            Label("Showing cached AO3 data", systemImage: "wifi.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accountControlCardRow()
        }
        ForEach(visibleItems) { item in
            let context = workContext(item)
            AccountInboxItemRow(
                item: item,
                workAuthors: context.authors,
                workAuthorIdentities: context.authorIdentities,
                isSelecting: limit == nil && model.isSelecting,
                isSelected: model.selectedItemIDs.contains(item.id),
                isSelectable: model.selectableItemIDs.contains(item.id),
                onOpen: { onOpen(item) },
                onOpenChapter: { onOpenChapter(item) },
                onToggleSelection: { model.toggleSelection(for: item) },
                canToggleReadState: model.canPerformItemAction(
                    item.isUnread ? .markRead : .markUnread, item: item
                ),
                canDeleteFromInbox: model.canPerformItemAction(.delete, item: item),
                isPerformingAction: model.isPerformingBulkAction,
                onReply: { onReply(item) },
                onToggleReadState: {
                    perform(item.isUnread ? .markRead : .markUnread, for: item)
                },
                onDeleteFromInbox: { perform(.delete, for: item) }
            )
                .accountControlCardRow()
        }
        if let onSeeAll, !model.items.isEmpty {
            Button(action: onSeeAll) {
                HStack {
                    Text("See All Comments")
                    Spacer()
                    if let unread = model.unreadCount, unread > 0 {
                        Text("\(unread) unread")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accountControlCardRow()
        }
        if limit == nil, model.totalPages > 1 {
            SearchPaginationBar(
                currentPage: model.currentPage,
                totalPages: model.totalPages
            ) { page in
                model.goToPage(page, auth: auth)
            }
            .accountControlCardRow()
            .disabled(model.isPerformingBulkAction)
        }
    }

    private var visibleItems: [AO3InboxItem] {
        if let limit { Array(model.items.prefix(limit)) } else { model.items }
    }

    private func perform(_ action: AO3InboxBulkAction, for item: AO3InboxItem) {
        Task { await model.performItemAction(action, item: item, auth: auth) }
    }
}

/// Native control surface for AO3's parsed Inbox GET filters. It deliberately
/// presents the real rendered options rather than maintaining a parallel list of
/// AO3 query values in the app.
struct AccountInboxFilterSheet: View {
    var model: AO3InboxModel

    @Environment(AO3AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.filterForm?.fields ?? []) { field in
                    Section(field.title) {
                        ForEach(field.options) { option in
                            Button {
                                model.applyFilter(
                                    fieldName: field.name,
                                    value: option.value,
                                    auth: auth
                                )
                                dismiss()
                            } label: {
                                HStack {
                                    Text(option.label)
                                    Spacer()
                                    if selectedValue(for: field) == option.value {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Inbox Filters")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    private func selectedValue(for field: AO3InboxFilterField) -> String? {
        model.filterValues[field.name] ?? field.selectedValue
    }
}

/// Mirrors the three-part Library bulk-action arrangement: destructive action on
/// the left, non-destructive actions clustered in the middle, and Done on the
/// right. Inbox delete only removes AO3's notification row; it never touches a
/// local work or its EPUB.
struct AccountInboxBulkActionBar: View {
    var model: AO3InboxModel

    @Environment(AO3AuthService.self) private var auth
    @State private var confirmDelete = false

    private var isDisabled: Bool {
        model.selectedItems.isEmpty || model.isPerformingBulkAction
    }

    var body: some View {
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(isDisabled)

        Spacer()

        HStack(spacing: 0) {
            Button {
                perform(.markRead)
            } label: {
                Image(systemName: "envelope.open")
                    .frame(minWidth: 44, minHeight: 32)
            }
            .accessibilityLabel("Mark Read")

            Divider().frame(height: 22)

            Button {
                perform(.markUnread)
            } label: {
                Image(systemName: "envelope.badge")
                    .frame(minWidth: 44, minHeight: 32)
            }
            .accessibilityLabel("Mark Unread")
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule())
        .disabled(isDisabled)

        Spacer()

        Button {
            model.endSelection()
        } label: {
            Image(systemName: "checkmark")
        }
        .accessibilityLabel("Done")
        .disabled(model.isPerformingBulkAction)
        .confirmationDialog(
            "Remove \(model.selectedItems.count) notification"
                + "\(model.selectedItems.count == 1 ? "" : "s") from your AO3 Inbox?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete From Inbox", role: .destructive) {
                perform(.delete)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes the selected notifications from AO3's Inbox. "
                + "It does not delete any work from your Kudos library.")
        }
    }

    private func perform(_ action: AO3InboxBulkAction) {
        Task { await model.performBulkAction(action, auth: auth) }
    }
}
