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
    /// Captured when the Inbox row opened this destination. The destination and
    /// any context it returns remain scoped to that same private session.
    let sessionGeneration: Int

    var id: String {
        "\(workID):\(commentID):\(focus.rawValue):\(opensReplyComposer):\(sessionGeneration)"
    }
}

/// Account's shared toolbar, with Inbox select mode taking over the same slots
/// that Library selection uses. Keeping this separate from `AccountView` keeps
/// the profile hub focused on navigation and state ownership.
struct AccountToolbarContent: ToolbarContent {
    let isInboxVisible: Bool
    var model: AO3InboxModel
    @Binding var showingInboxFilters: Bool
    let isWorksVisible: Bool
    @Binding var showingWorksFilter: Bool
    let showsMatureRevealControl: Bool

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
            // WorkListMoreMenu's own gate widened to `showsWorkListControls ||
            // showsMatureRevealControl` — Privacy now lives inside it, so it needs
            // a home even when the work-list controls themselves aren't showing.
            ActionToolbar(items: actionItems)
        }
    }

    /// The account's action buttons as plain views.
    ///
    /// 1m has no navigation bar: its chrome is a glass circle floating over the
    /// wash with the page scrolling under it, so `AccountView` renders these in an
    /// overlay instead. They stay defined once, here, so the floating row and the
    /// bar the inbox's selection mode still needs cannot drift apart.
    var actionItems: [AnyView] {
        [
            showsMatureRevealControl
                    ? AnyView(WorkListMoreMenu {
                        MatureRevealToggle()
                    })
                    : nil,
                (isInboxVisible && model.canFilter)
                    ? AnyView(ToolbarIconButton(
                        title: "Inbox Filters",
                        systemImage: "line.3.horizontal.decrease"
                    ) {
                        showingInboxFilters = true
                    })
                    : nil,
                isWorksVisible
                    ? AnyView(ToolbarIconButton(
                        title: "Works Filters",
                        systemImage: "line.3.horizontal.decrease"
                    ) {
                        showingWorksFilter = true
                    })
                    : nil,
                (isInboxVisible && model.canSelectItems)
                    ? AnyView(ToolbarIconButton(
                        title: "Select Inbox Items",
                        systemImage: "checklist",
                        action: model.beginSelection
                    ))
                    : nil,
            AnyView(
                NavigationLink(value: AccountView.Route.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            )
        ].compactMap { $0 }
    }
}

/// The compact notification row used by the Account sheet's two-item preview.
/// The full Inbox keeps `AccountInboxItemRow` and all of its actions.
struct AccountInboxPreviewRow: View {
    let item: AO3InboxItem
    let onOpen: () -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var avatarPalette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: CoverArt.hue(for: item.commenterName))
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Text(item.commenterName.first.map { String($0).uppercased() } ?? "?")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(avatarPalette.labelOnAccent)
                    .frame(width: 30, height: 30)
                    .background(avatarPalette.accent, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    byline
                    Text(item.isUnavailable ? "A comment here is unavailable" : item.excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the comment thread")
    }

    @ViewBuilder
    private var byline: some View {
        let subject = item.workTitle.isEmpty ? item.subjectTitle : item.workTitle
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.commenterName)
                    .font(.caption.weight(.semibold))
                if !subject.isEmpty {
                    Text("on \(subject)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !item.postedAgo.isEmpty {
                    Text(item.postedAgo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            HStack(spacing: 5) {
                if item.isUnread {
                    Circle()
                        .fill(.accentFill)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
                Text(item.commenterName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if !subject.isEmpty {
                    Text("on \(subject)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if !item.postedAgo.isEmpty {
                    Text(item.postedAgo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var accessibilityLabel: String {
        if item.isUnavailable { return "A comment here is unavailable" }
        return [
            item.isUnread ? "Unread" : nil,
            item.commenterName,
            item.subjectTitle.isEmpty ? nil : "on \(item.subjectTitle)",
            item.excerpt.isEmpty ? nil : item.excerpt,
            item.postedAgo.isEmpty ? nil : item.postedAgo
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmDelete = false
    @State private var actionNotice: String?

    var body: some View {
        if isSelecting {
            Button(action: onToggleSelection) {
                selectionContent
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable)
            // Matches `SelectableAO3WorkRow`'s selection idiom (X5): an explicit
            // label/value/trait instead of relying on the hidden checkmark alone
            // to carry selected state (UI-2/T91-RF10).
            .accessibilityLabel(accessibilitySummary)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this notification.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else if item.isUnavailable {
            unavailableContent
        } else {
            interactiveContent
                .inboxDeleteConfirmation(isPresented: $confirmDelete, perform: onDeleteFromInbox)
                .alert("Inbox", isPresented: actionNoticeBinding) {
                    Button("OK") { actionNotice = nil }
                } message: {
                    Text(actionNotice ?? "")
                }
        }
    }

    /// Board 40: a plain Mail-style row. Tapping opens the thread; every other
    /// action (Reply, Chapter Comments, Copy Link, read state, delete) is in the
    /// long-press menu, and the same ones are VoiceOver actions. The row is one
    /// accessibility element whose default action opens the thread (UI-2/T91-RF10).
    private var interactiveContent: some View {
        Button(action: onOpen) {
            rowBody
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { rowMenuItems }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Open the comment's thread")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { onOpen() }
        .accessibilityActions {
            if item.chapterPosition != nil {
                Button("Open Chapter Comments") { onOpenChapter() }
            }
            if item.canReply {
                Button("Reply") { onReply() }
            }
            Button("Copy Link") { copyLink() }
            if canToggleReadState && !isPerformingAction {
                Button(item.isUnread ? "Mark Read" : "Mark Unread") { onToggleReadState() }
            }
            if canDeleteFromInbox && !isPerformingAction {
                Button("Delete From Inbox", role: .destructive) { confirmDelete = true }
            }
        }
    }

    /// Unread dot, name line (+ small markers + time), "on Work · Chapter N",
    /// two-line excerpt. A read row keeps the dot's column so names align.
    private var rowBody: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(.accentFill)
                .opacity(item.isUnread ? 1 : 0)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                byline
                if !item.subjectTitle.isEmpty {
                    Text(subjectLine)
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(2)
                }
                if !item.excerpt.isEmpty {
                    Text(item.excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "on Keeper of the Northern Light · Chapter 7"; tag and other targets keep
    /// AO3's own subject text.
    private var subjectLine: String {
        if let chapter = item.chapterIndicatorTitle {
            return "on \(item.workTitle) · \(chapter)"
        }
        return "on \(item.subjectTitle)"
    }

    private var timeLabel: AO3InboxTimeLabel.Label? {
        AO3InboxTimeLabel.label(for: item.postedAgo)
    }

    /// The admin-hidden/unavailable tombstone shape (T91-RF6): AO3 rendered a
    /// real row with an id (and, when present, its selection checkbox) but no
    /// byline, subject, or excerpt — so there is genuinely nothing to open.
    /// Still counted and still selectable in bulk-select mode via
    /// `selectionContent`, just not wired to `onOpen`.
    private var unavailableContent: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
            Text("A comment here is unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A comment here is unavailable")
    }

    private var selectionContent: some View {
        HStack(alignment: .top, spacing: 10) {
            // Visual selected state only — the wrapping Button in `body` carries
            // the real `.isSelected` accessibility trait/value (UI-2/T91-RF10),
            // so this glyph staying hidden no longer leaves selection unannounced.
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 28)
                .accessibilityHidden(true)
            if item.isUnavailable {
                Text("A comment here is unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                rowBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// One VoiceOver-friendly summary of this notification, shared by the
    /// consolidated `interactiveContent` element and the select-mode row
    /// (UI-2/T91-RF10) — both need the same context that used to be spread
    /// across several separately-focusable pieces.
    private var accessibilitySummary: String {
        if item.isUnavailable {
            return "A comment here is unavailable"
        }
        var parts: [String] = []
        if item.isUnread { parts.append("Unread") }
        parts.append(item.commenterName)
        let role = item.participantRole(
            workAuthors: workAuthors,
            workAuthorIdentities: workAuthorIdentities,
            currentUsername: auth.username
        )
        if role != .user { parts.append(role.rawValue) }
        if !item.subjectTitle.isEmpty { parts.append("on \(item.subjectTitle)") }
        if !item.excerpt.isEmpty { parts.append(item.excerpt) }
        if let timeLabel { parts.append(timeLabel.spoken) }
        if item.isReplied { parts.append("Replied") }
        return parts.joined(separator: ". ")
    }

    @ViewBuilder
    private var byline: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // On one line the name and the time were both cut at the
            // accessibility sizes: the name's line, then the time's.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { bylineWho }
                HStack(alignment: .firstTextBaseline, spacing: 6) { bylineWhen }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                bylineWho
                Spacer(minLength: 4)
                bylineWhen
            }
        }
    }

    @ViewBuilder
    private var bylineWho: some View {
        Text(item.commenterName)
            .font(.body.weight(item.isUnread ? .semibold : .regular))
            .lineLimit(1)
        CommentParticipantBadge(role: item.participantRole(
            workAuthors: workAuthors,
            workAuthorIdentities: workAuthorIdentities,
            currentUsername: auth.username
        ))
    }

    @ViewBuilder
    private var bylineWhen: some View {
        // Board 40: Replied is the small reply glyph beside the time.
        if item.isReplied {
            Image(systemName: "arrow.turn.up.left")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Replied")
        }
        if let timeLabel {
            Text(timeLabel.display)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// The long-press menu: everything the old per-row Reply button and "…" held.
    @ViewBuilder
    private var rowMenuItems: some View {
        if item.canReply {
            Button(action: onReply) {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }
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
        if canToggleReadState && !isPerformingAction {
            Button(action: onToggleReadState) {
                Label(
                    item.isUnread ? "Mark Read" : "Mark Unread",
                    systemImage: item.isUnread ? "envelope.open" : "envelope.badge"
                )
            }
        }
        if canDeleteFromInbox && !isPerformingAction {
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete From Inbox", systemImage: "trash")
            }
        }
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

/// Loading, failure, and empty states for the Inbox list. The comments
/// themselves are `AccountInboxCommentListRow`s, one List row each, so a
/// swipe can mark a single comment read. State lives in the host's
/// `AO3InboxModel`.
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

    /// Status only. The comment rows are direct children of the Inbox `List`
    /// (`AccountInboxScreen`), because `.swipeActions` attaches to a row and
    /// this view used to pack every comment into one `VStack`.
    var body: some View {
        switch model.phase {
        case .idle where model.items.isEmpty, .loading where model.items.isEmpty:
            loadingRows
        case let .failed(message):
            statusRow(
                title: "Couldn't load your inbox",
                systemImage: "exclamationmark.triangle",
                message: message,
                actionTitle: "Try Again"
            )
        case .loaded where model.items.isEmpty:
            AO3ProfileMessageRow(
                title: "No comments yet",
                systemImage: "bubble.left",
                message: "Comments on your works and replies to your comments appear here "
                    + "from your AO3 inbox."
            )
            .accountControlCardRow()
        case let .paginationFailed(requestedPage, message):
            // The loaded page's rows stay in the list above this one. A failed
            // page 2 must not hide page 1's comments (T91-RF8).
            statusRow(
                title: "Couldn't load page \(requestedPage)",
                systemImage: "exclamationmark.triangle",
                message: message,
                actionTitle: "Try Again"
            )
        default:
            EmptyView()
        }
    }

    private func statusRow(
        title: String,
        systemImage: String,
        message: String,
        actionTitle: String
    ) -> some View {
        AO3ProfileMessageRow(
            title: title,
            systemImage: systemImage,
            message: message,
            actionTitle: actionTitle,
            action: { model.retry(auth: auth) }
        )
        .accountControlCardRow()
    }

    private var loadingRows: some View {
        VStack(spacing: 0) {
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
                .padding(.horizontal, 14)
                .skeletonShimmer()
            }
        }
        .subjectPanel()
        .listRowInsets(EdgeInsets(
            top: 12,
            leading: SubjectMetrics.accountGutter,
            bottom: 12,
            trailing: SubjectMetrics.accountGutter
        ))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// "N messages · N unread · N awaiting your reply · page X of Y".
    ///
    /// The message count is the heading total on the full feed (`totalComments`),
    /// and the preview cap when `limit` is set. Unread is that same heading.
    /// Awaiting reply is not in the heading, so it counts `model.items` — the
    /// loaded page — rather than a total this response does not carry. The page
    /// clause stays last: it says where you are, not how many comments.
    var headerTallyLine: String {
        let shown = limit != nil ? visibleItems.count : (model.totalComments ?? model.items.count)
        var line = shown == 1 ? "1 message" : "\(shown) messages"
        if let unread = model.unreadCount, unread > 0 {
            line += " · \(unread) unread"
        }
        let awaiting = AO3InboxTally.awaitingReplyCount(model.items)
        if awaiting > 0 {
            line += " · \(awaiting) awaiting your reply"
        }
        if limit == nil, model.totalPages > 1 {
            line += " · page \(model.currentPage) of \(model.totalPages)"
        }
        return line
    }

    private var visibleItems: [AO3InboxItem] {
        if let limit { Array(model.items.prefix(limit)) } else { model.items }
    }
}

/// One comment in the Inbox list (board 40). Trailing swipe: read/unread and
/// Delete (asks first); leading swipe: Reply. All of them, and Copy Link and
/// the chapter jump, are in the long-press menu too.
struct AccountInboxCommentListRow: View {
    var model: AO3InboxModel
    let item: AO3InboxItem
    var workContext: AO3CommentsWorkContext
    var isSelecting: Bool
    var isFirst: Bool
    var isLast: Bool
    var onOpen: () -> Void
    var onOpenChapter: () -> Void
    var onReply: () -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.screenTint) private var screenTint
    @State private var confirmDelete = false

    private var readAction: AO3InboxBulkAction {
        item.isUnread ? .markRead : .markUnread
    }

    private var canToggleReadState: Bool {
        model.canPerformItemAction(readAction, item: item)
    }

    private var isPerformingAction: Bool {
        model.isPerformingBulkAction
    }

    var body: some View {
        AccountInboxItemRow(
            item: item,
            workAuthors: workContext.authors,
            workAuthorIdentities: workContext.authorIdentities,
            isSelecting: isSelecting,
            isSelected: model.selectedItemIDs.contains(item.id),
            isSelectable: model.selectableItemIDs.contains(item.id),
            onOpen: onOpen,
            onOpenChapter: onOpenChapter,
            onToggleSelection: { model.toggleSelection(for: item) },
            canToggleReadState: canToggleReadState,
            canDeleteFromInbox: model.canPerformItemAction(.delete, item: item),
            isPerformingAction: isPerformingAction,
            onReply: onReply,
            onToggleReadState: toggleReadState,
            onDeleteFromInbox: { model.startItemAction(.delete, item: item, auth: auth) }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Full swipe stays off. Marking read posts to AO3, and a flick
            // must not be the thing that sends it. Same gate as the overflow,
            // and absent in Select mode: that write clears the whole selection.
            if !isSelecting && canToggleReadState && !isPerformingAction {
                Button(action: toggleReadState) {
                    Label(
                        item.isUnread ? "Mark Read" : "Mark Unread",
                        systemImage: item.isUnread ? "envelope.open" : "envelope.badge"
                    )
                }
                .tint(screenTint ?? themeManager.effectiveTint)
            }
            // The row's destructive action is its trailing swipe, as on every
            // other list (pass2-11). It asks first.
            if !isSelecting && model.canPerformItemAction(.delete, item: item) && !isPerformingAction {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        // Reply is the leading swipe; the long-press menu holds it too.
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !isSelecting && item.canReply && !item.isUnavailable {
                Button(action: onReply) {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                .tint(screenTint ?? themeManager.effectiveTint)
            }
        }
        .inboxDeleteConfirmation(isPresented: $confirmDelete) {
            model.startItemAction(.delete, item: item, auth: auth)
        }
        .modifier(InboxPlainRow())
    }

    private func toggleReadState() {
        model.startItemAction(readAction, item: item, auth: auth)
    }
}

/// The cached-data line, as the first segment of the same panel as the comments.
struct AccountInboxStaleCacheRow: View {
    var isLast: Bool

    var body: some View {
        Label("Showing cached AO3 data", systemImage: "wifi.slash")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(InboxPlainRow())
    }
}

struct AccountInboxSeeAllRow: View {
    var unreadCount: Int?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("See All Comments")
                Spacer()
                if let unreadCount, unreadCount > 0 {
                    Text("\(unreadCount) unread")
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
}

/// Board 40's plain row: no card, the List's hairline between rows, a 10pt
/// leading gutter (the unread dot's) and 16pt trailing.
private struct InboxPlainRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.visible, edges: .bottom)
    }
}

/// Identity includes whether the row is the panel's first or last segment.
/// List keeps a row's background when only the id's payload changes, so a
/// comment that becomes the bottom of the card would keep square corners.
struct AccountInboxPanelSegment: Identifiable {
    let id: String
    let item: AO3InboxItem
    let isFirst: Bool
    let isLast: Bool

    static func rows(items: [AO3InboxItem], hasStaleBanner: Bool) -> [AccountInboxPanelSegment] {
        let offset = hasStaleBanner ? 1 : 0
        let count = items.count + offset
        guard count > 0 else { return [] }
        let lastIndex = count - 1
        return items.enumerated().map { index, item in
            let segment = index + offset
            let isFirst = segment == 0
            let isLast = segment == lastIndex
            return AccountInboxPanelSegment(
                id: "\(item.id)|\(isFirst)|\(isLast)",
                item: item,
                isFirst: isFirst,
                isLast: isLast
            )
        }
    }
}

/// Native control surface for AO3's parsed Inbox GET filters. It deliberately
/// presents the real rendered options rather than maintaining a parallel list of
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
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Mark Read")

            Divider().frame(height: 22)

            Button {
                perform(.markUnread)
            } label: {
                Image(systemName: "envelope.badge")
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Mark Unread")
        }
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
            "Delete \(model.selectedItems.count) notification"
                + "\(model.selectedItems.count == 1 ? "" : "s") from your AO3 Inbox?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete From Inbox", role: .destructive) {
                perform(.delete)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected notifications from your AO3 Inbox. "
                + "Your works in Kudos aren't deleted.")
        }
    }

    private func perform(_ action: AO3InboxBulkAction) {
        model.startBulkAction(action, auth: auth)
    }
}

extension View {
    /// One ask for deleting a single notification, from the swipe or the overflow.
    func inboxDeleteConfirmation(isPresented: Binding<Bool>, perform: @escaping () -> Void) -> some View {
        confirmationDialog(
            "Delete this notification from your AO3 Inbox?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete From Inbox", role: .destructive, action: perform)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the notification from your AO3 Inbox. The comment stays on AO3.")
        }
    }
}
