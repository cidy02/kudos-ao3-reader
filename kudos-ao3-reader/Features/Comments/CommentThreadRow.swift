import SwiftUI

/// The card-within-a-card thread treatment (the mockups' core visual): every row
/// of one top-level thread shares a single continuous `cardSurface` card — the
/// same surface, radius, and margins as the Library's `.cardRow()` — opened by
/// the top-level comment and closed after the thread's last reply. Replies then
/// render as nested bubbles *inside* that card (see `CommentThreadRow`). Rows
/// stay flat and lazy (the polish branch's performance architecture); only the
/// backgrounds compose into one visual group.
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
            .padding(.horizontal, 14)
            .padding(.top, isFirst ? 14 : 4)
            .padding(.bottom, isLastInThread ? 14 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
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
}

extension View {
    func commentThreadGroupRow(depth: Int, isLastInThread: Bool, isHighlighted: Bool = false) -> some View {
        modifier(CommentThreadGroupRowModifier(
            depth: depth, isLastInThread: isLastInThread, isHighlighted: isHighlighted
        ))
    }
}

/// Pure layout constants for the lazy threaded rows. Logical depth is never
/// capped in `AO3CommentRow`; only the on-screen indent is capped so deeply
/// nested AO3 conversations retain a readable text measure on phones.
enum CommentThreadGeometry {
    static let maximumVisualDepth = 3
    static let rootAvatarSize: CGFloat = 38
    static let replyAvatarSize: CGFloat = 30
    static let replyBubblePadding: CGFloat = 10
    static let firstReplyIndent: CGFloat = 28
    static let depthStep: CGFloat = 22

    static func visualDepth(for logicalDepth: Int) -> Int {
        min(max(logicalDepth, 0), maximumVisualDepth)
    }

    static func bubbleLeadingInset(for logicalDepth: Int) -> CGFloat {
        let depth = visualDepth(for: logicalDepth)
        guard depth > 0 else { return 0 }
        return firstReplyIndent + CGFloat(depth - 1) * depthStep
    }

    static func avatarCenterX(for logicalDepth: Int) -> CGFloat {
        guard logicalDepth > 0 else { return rootAvatarSize / 2 }
        return bubbleLeadingInset(for: logicalDepth)
            + replyBubblePadding
            + replyAvatarSize / 2
    }
}

/// Draws only the connector segments needed by one shallow row. Incoming and
/// outgoing segments meet across adjacent List rows, while ancestor lines stay
/// open through branched subtrees. Lines stop at avatar edges so they sit
/// behind the conversation hierarchy rather than painting over profile icons.
private struct CommentThreadConnector: View {
    let row: AO3CommentRow

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let height = geometry.size.height
                let avatarCenterX = CommentThreadGeometry.avatarCenterX(for: row.depth)

                for ancestorDepth in row.continuingAncestorDepths {
                    let x = CommentThreadGeometry.avatarCenterX(for: ancestorDepth)
                    guard abs(x - avatarCenterX) > 0.5 else { continue }
                    path.move(to: CGPoint(x: x, y: -10))
                    path.addLine(to: CGPoint(x: x, y: height + 10))
                }

                if row.depth == 0 {
                    if row.hasReplies {
                        path.move(to: CGPoint(
                            x: avatarCenterX,
                            y: CommentThreadGeometry.rootAvatarSize
                        ))
                        path.addLine(to: CGPoint(x: avatarCenterX, y: height + 10))
                    }
                    return
                }

                let parentX = CommentThreadGeometry.avatarCenterX(for: row.depth - 1)
                let avatarTop = CommentThreadGeometry.replyBubblePadding
                let branchY = avatarTop / 2

                path.move(to: CGPoint(x: parentX, y: -10))
                path.addLine(to: CGPoint(
                    x: parentX,
                    y: row.hasNextSibling ? height + 10 : branchY
                ))
                path.move(to: CGPoint(x: parentX, y: branchY))
                path.addQuadCurve(
                    to: CGPoint(x: avatarCenterX, y: avatarTop),
                    control: CGPoint(x: parentX, y: avatarTop)
                )

                if row.hasReplies {
                    path.move(to: CGPoint(
                        x: avatarCenterX,
                        y: avatarTop + CommentThreadGeometry.replyAvatarSize
                    ))
                    path.addLine(to: CGPoint(x: avatarCenterX, y: height + 10))
                }
            }
            .stroke(
                Color.secondary.opacity(0.24),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
    private var bubbleLeadingInset: CGFloat {
        CommentThreadGeometry.bubbleLeadingInset(for: row.depth)
    }

    private var isByWorkAuthor: Bool {
        workAuthors.contains { $0.caseInsensitiveCompare(comment.author) == .orderedSame }
    }

    private var canShowReply: Bool {
        comment.canReply && auth.isLoggedIn
    }

    var body: some View {
        if isReplyRow {
            // Reply bubble: its own soft surface one elevation step inside the
            // card. The full-height overlay reads the row's projection metadata,
            // so reply-to-reply and branched paths remain visible without
            // rebuilding the recursive comment tree.
            commentContent
                .padding(CommentThreadGeometry.replyBubblePadding)
                .background(
                    theme.appTheme.nestedCardSurface,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                }
                .padding(.leading, bubbleLeadingInset)
                .overlay { CommentThreadConnector(row: row) }
        } else {
            commentContent
                .overlay { CommentThreadConnector(row: row) }
        }
    }

    private var commentContent: some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(
                comment: comment,
                size: isReplyRow
                    ? CommentThreadGeometry.replyAvatarSize
                    : CommentThreadGeometry.rootAvatarSize
            )

            VStack(alignment: .leading, spacing: 6) {
                byline
                if !comment.bodyText.isEmpty {
                    Text(comment.bodyText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                commentActions
            }
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
            if !comment.postedText.isEmpty {
                Text(AO3CommentTimestamp.displayText(
                    rawText: comment.postedText,
                    date: comment.postedAt
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
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

    private var commentActions: some View {
        HStack(spacing: 8) {
            if canShowReply {
                Button { onReply(comment) } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.caption.weight(.medium))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reply to \(comment.author)")
            }
            Spacer(minLength: 0)
            Menu {
                if comment.canReply && !canShowReply {
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
            .tint(.secondary)
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
