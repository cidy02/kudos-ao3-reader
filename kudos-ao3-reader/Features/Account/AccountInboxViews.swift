import SwiftUI

// The AO3 Inbox surfaces of the Account tab: a capped "Recent Comments" preview
// on Overview and the full feed under Activity › Inbox. Inbox entries are
// flat notification summaries (not threads), so each renders as one simple card
// — commenter, subject, excerpt, time — honoring the read/unread and replied
// state AO3 exposes. Read-only v1: no mark-read/delete from the app.

/// Pushes a work's full comments experience from an inbox entry.
nonisolated struct AccountInboxThreadDestination: Hashable {
    let workID: Int
    let title: String
}

/// One inbox notification card.
struct AccountInboxItemRow: View {
    let item: AO3InboxItem
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                avatar

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if item.isUnread {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 8, height: 8)
                                .accessibilityLabel("Unread")
                        }
                        Text(item.commenterName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if item.isGuest {
                            Text("(Guest)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if !item.postedAgo.isEmpty {
                            Text(item.postedAgo)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

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

                    if item.isReplied {
                        WorkStateBadge(text: "Replied", symbol: "checkmark")
                            .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open comments")
    }

    /// 40pt circle — the comment-thread avatar convention (vs. the profile
    /// card's 72pt square), since these rows are comment context.
    private var avatar: some View {
        Group {
            if let url = item.isGuest ? nil : item.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 40, height: 40)
        .background(.quaternary.opacity(0.5), in: Circle())
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 22))
            .foregroundStyle(.secondary)
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
            .cardRow()
        case .loaded where model.items.isEmpty:
            AO3ProfileMessageRow(
                title: "No comments yet",
                systemImage: "bubble.left",
                message: "Comments on your works, and replies to comments you've "
                    + "posted, show up here from your AO3 inbox."
            )
            .cardRow()
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
                .cardRow()
        }
        ForEach(visibleItems) { item in
            AccountInboxItemRow(item: item) { onOpen(item) }
                .cardRow()
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
            .cardRow()
        }
        if limit == nil, model.totalPages > 1 {
            SearchPaginationBar(
                currentPage: model.currentPage,
                totalPages: model.totalPages
            ) { page in
                model.goToPage(page, auth: auth)
            }
            .cardRow()
        }
    }

    private var visibleItems: [AO3InboxItem] {
        if let limit { Array(model.items.prefix(limit)) } else { model.items }
    }
}
