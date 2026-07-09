import SwiftUI

/// Fixed geometry for the comment thread's avatar column and connector line.
/// Every row of a thread — parent and replies at any depth — places its avatar
/// centered in ONE shared left column, so the mockups' key invariant holds with
/// a single straight line and no elbows:
///
///     connectorLineX == parentAvatar.centerX == childAvatar.centerX
///
/// Depth is expressed by indenting the reply *bubble* (the card to the right of
/// the column), never the avatar column itself. All values are in the group
/// card's coordinate space; the connector is drawn by
/// `CommentThreadGroupRowModifier`, which owns the same paddings.
enum CommentThreadGeometry {
    /// The group card's inner horizontal padding (both edges).
    static let cardPadding: CGFloat = 14
    /// Top padding inside the card: opening (parent) row vs. reply rows.
    static let firstRowTopPadding: CGFloat = 14
    static let replyRowTopPadding: CGFloat = 4
    /// One shared avatar column; avatars of both sizes center inside it.
    static let avatarColumnWidth: CGFloat = 38
    static let parentAvatarSize: CGFloat = 38
    static let replyAvatarSize: CGFloat = 30
    /// Extra bubble indent per depth level past the first reply, capped so long
    /// AO3 comments keep a readable measure on phone widths.
    static func bubbleIndent(forDepth depth: Int) -> CGFloat {
        CGFloat(min(depth, 4) - 1) * 12
    }

    /// The connector's center x within the group card (padding + column center).
    static var connectorCenterX: CGFloat { cardPadding + avatarColumnWidth / 2 }
    static let connectorWidth: CGFloat = 2
    /// Breathing room between an avatar's edge and the line segment beneath it.
    static let connectorGap: CGFloat = 3

    /// Where the continuation segment starts, measured from the row's top edge:
    /// just below this row's avatar.
    static func continuationTop(forDepth depth: Int) -> CGFloat {
        if depth == 0 {
            return firstRowTopPadding + parentAvatarSize + connectorGap
        }
        return replyRowTopPadding + replyAvatarSize + connectorGap
    }

    /// Where a reply row's arrival segment ends, measured from the row's top
    /// edge: this row's avatar center (the line runs behind the avatar's top
    /// half, which is opaquely backed, so it visually meets the circle's edge).
    static var arrivalBottom: CGFloat {
        replyRowTopPadding + replyAvatarSize / 2
    }
}

/// The card-within-a-card thread treatment (the mockups' core visual): every row
/// of one top-level thread shares a single continuous `cardSurface` card — the
/// same surface, radius, and margins as the Library's `.cardRow()` — opened by
/// the top-level comment and closed after the thread's last reply. Replies then
/// render as nested bubbles *inside* that card (see `CommentThreadRow`), and the
/// connector line runs down the shared avatar column's centerline, connecting
/// avatar to avatar — not a rail pasted on the card's left edge. Rows stay flat
/// and lazy (the polish branch's performance architecture); only the backgrounds
/// compose into one visual group.
private struct CommentThreadGroupRowModifier: ViewModifier {
    let depth: Int
    let isLastInThread: Bool
    /// Briefly true right after "Thread"/"Parent Thread" scrolls to this row —
    /// a tint flash confirms which comment got focused (scrolling to a comment
    /// already on-screen would otherwise be invisible).
    var isHighlighted = false

    @Environment(ThemeManager.self) private var theme

    private var isFirst: Bool { depth == 0 }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, CommentThreadGeometry.cardPadding)
            .padding(.top, isFirst
                ? CommentThreadGeometry.firstRowTopPadding
                : CommentThreadGeometry.replyRowTopPadding)
            .padding(.bottom, isLastInThread ? 14 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Directly behind the content (and above the card fill below), so the
            // arrival segment passes behind the opaquely-backed avatar instead of
            // drawing over it.
            .background { connector }
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: isFirst ? 16 : 0,
                    bottomLeadingRadius: isLastInThread ? 16 : 0,
                    bottomTrailingRadius: isLastInThread ? 16 : 0,
                    topTrailingRadius: isFirst ? 16 : 0,
                    style: .continuous
                )
                .fill(theme.appTheme.cardSurface)
                .overlay {
                    if isHighlighted {
                        UnevenRoundedRectangle(
                            topLeadingRadius: isFirst ? 16 : 0,
                            bottomLeadingRadius: isLastInThread ? 16 : 0,
                            bottomTrailingRadius: isLastInThread ? 16 : 0,
                            topTrailingRadius: isFirst ? 16 : 0,
                            style: .continuous
                        )
                        .fill(Color.accentColor.opacity(0.14))
                    }
                }
            }
            .listRowInsets(EdgeInsets(
                top: isFirst ? 6 : 0, leading: 16,
                bottom: isLastInThread ? 6 : 0, trailing: 16
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }

    /// The thread's connector segments for this row, on the avatar centerline.
    /// Rows are stacked flush inside the group card, so a continuation ending at
    /// this row's bottom edge meets the next row's arrival starting at its top
    /// edge — one continuous line through every avatar center in the thread.
    ///
    /// - Arrival (replies only): row top → this row's avatar center.
    /// - Continuation (any row followed by another in the same thread):
    ///   just below this row's avatar → row bottom.
    @ViewBuilder
    private var connector: some View {
        if depth > 0 || !isLastInThread {
            ZStack(alignment: .top) {
                if depth > 0 {
                    line
                        .frame(height: CommentThreadGeometry.arrivalBottom)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                if !isLastInThread {
                    line
                        .padding(.top, CommentThreadGeometry.continuationTop(forDepth: depth))
                }
            }
            .frame(
                width: CommentThreadGeometry.connectorWidth,
                alignment: .top
            )
            .padding(.leading,
                     CommentThreadGeometry.connectorCenterX
                        - CommentThreadGeometry.connectorWidth / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var line: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(.quaternary)
            .frame(width: CommentThreadGeometry.connectorWidth)
    }
}

extension View {
    func commentThreadGroupRow(depth: Int, isLastInThread: Bool, isHighlighted: Bool = false) -> some View {
        modifier(CommentThreadGroupRowModifier(
            depth: depth, isLastInThread: isLastInThread, isHighlighted: isHighlighted
        ))
    }
}

/// One stable, shallow row from `CommentsModel.displayRows`. Top-level comments
/// sit directly on the thread card; replies render as indented nested bubbles
/// with a quiet connector line — a conversation group, not a timeline rail.
struct CommentThreadRow: View {
    let row: AO3CommentRow
    let workAuthors: [String]
    let showChapterBadge: Bool
    let onReply: (AO3Comment) -> Void
    let onEdit: (AO3Comment) -> Void
    let onDelete: (AO3Comment) -> Void
    let onCopyLink: (AO3Comment) -> Void
    /// Scrolls to and briefly highlights the given comment id within the
    /// currently-loaded list — native in-app focus, not an AO3 web page.
    let onFocusThread: (Int) -> Void
    /// Presents the AO3 login sheet (from the disabled-looking "Log in to
    /// Reply" placeholder, which must actually do something when tapped).
    let onRequestLogin: () -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    private var comment: AO3Comment { row.comment }
    private var isReplyRow: Bool { row.depth > 0 }

    private var isByWorkAuthor: Bool {
        workAuthors.contains { $0.caseInsensitiveCompare(comment.author) == .orderedSame }
    }

    var body: some View {
        // Both layouts share ONE avatar column (the connector's centerline runs
        // through it — see CommentThreadGeometry); only what sits to the right
        // differs: the parent's content directly on the thread card, or a reply's
        // nested bubble. Depth indents the bubble, never the avatar column, so
        // every avatar center stays on the line.
        HStack(alignment: .top, spacing: 8) {
            CommentAvatar(
                comment: comment,
                size: isReplyRow
                    ? CommentThreadGeometry.replyAvatarSize
                    : CommentThreadGeometry.parentAvatarSize
            )
            // Opaque backing so the connector's arrival segment (drawn behind
            // the content, ending at the avatar's center) visually stops at the
            // circle's edge instead of showing through its translucent fill.
            .background(Circle().fill(theme.appTheme.cardSurface))
            .frame(width: CommentThreadGeometry.avatarColumnWidth)

            if isReplyRow {
                // Reply bubble: its own soft surface one elevation step inside
                // the thread card.
                commentBody
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        theme.appTheme.nestedCardSurface,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                    }
                    .padding(.leading, CommentThreadGeometry.bubbleIndent(forDepth: row.depth))
            } else {
                commentBody
            }
        }
    }

    private var commentBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            byline
            if !comment.bodyText.isEmpty {
                Text(comment.bodyText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            timestampAndActions
        }
    }

    private var byline: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(comment.author)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .layoutPriority(1)
            if isByWorkAuthor {
                Text("Author")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.tint, in: Capsule())
                    .foregroundStyle(.white)
            } else if comment.isGuest {
                Text("Guest")
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if showChapterBadge, let chapter = comment.chapterLabel {
                Text(chapter)
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var timestampAndActions: some View {
        // Mockup order: Reply anchors the left, the overflow menu the right,
        // with the (long, AO3-format) timestamp quiet in between.
        HStack(spacing: 8) {
            if comment.canReply && auth.isLoggedIn {
                Button { onReply(comment) } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.caption.weight(.medium))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reply to \(comment.author)")
            }
            Spacer()
            if !comment.postedText.isEmpty {
                Text(comment.postedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // Yields first when space is tight — the actions must not shrink.
                    .layoutPriority(-1)
            }
            Menu {
                if comment.canReply && auth.isLoggedIn {
                    Button { onReply(comment) } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                } else if comment.canReply {
                    Button { onRequestLogin() } label: {
                        Label("Log in to Reply", systemImage: "person.crop.circle.badge.questionmark")
                    }
                }
                if comment.editPath != nil {
                    Button { onEdit(comment) } label: {
                        Label("Edit Comment", systemImage: "pencil")
                    }
                }
                Button { onCopyLink(comment) } label: {
                    Label("Copy Link", systemImage: "link")
                }
                if comment.threadPath != nil {
                    // Scrolls to this comment in the native list (mostly useful
                    // as a "where am I" re-center after browsing a long page).
                    Button { onFocusThread(comment.id) } label: {
                        Label("Thread", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                if let parentID = comment.parentCommentID {
                    Button { onFocusThread(parentID) } label: {
                        Label("Parent Thread", systemImage: "arrowshape.turn.up.backward")
                    }
                }
                if comment.deletePath != nil {
                    Button(role: .destructive) { onDelete(comment) } label: {
                        Label("Delete Comment", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("More actions for \(comment.author)'s comment")
        }
    }
}

/// AO3 user icon when the fetched comment included one; otherwise a quiet,
/// neutral placeholder (AO3 red stays an accent elsewhere — a red disk per row
/// overwhelmed the list). `AsyncImage` uses the shared URL loading/cache stack
/// and is only instantiated for lazy rows that become visible.
struct CommentAvatar: View {
    let comment: AO3Comment
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url = comment.isGuest ? nil : comment.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        placeholder
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary.opacity(0.5), in: Circle())
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.43, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
