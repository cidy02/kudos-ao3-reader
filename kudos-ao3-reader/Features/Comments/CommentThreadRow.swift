import SwiftUI

/// Fixed geometry for the comment thread's avatar column and connector line.
///
/// The parent row places its avatar in a left column, content beside it.
/// Every reply's avatar sits INSIDE its own nested bubble the same way — an
/// avatar-then-content row — with the whole thing wrapped in a floating card
/// (margin on every side, its own surface/border). The connector line runs
/// down the parent's fixed avatar-column centerline; for replies it only needs
/// to reach each bubble's own top edge, because the bubble's opaque fill —
/// not any per-avatar occlusion trick — hides the rest of the line for
/// whatever height the bubble turns out to be (its content is variable-height
/// AO3 text, so the geometry deliberately never needs to know that height).
/// All values are in the group card's coordinate space; the connector is
/// drawn by `CommentThreadGroupRowModifier`, which owns the same paddings.
enum CommentThreadGeometry {
    /// The group card's inner horizontal padding (both edges).
    static let cardPadding: CGFloat = 14
    /// Row top padding before the parent's own content begins.
    static let firstRowTopPadding: CGFloat = 14
    /// Row top padding before a reply's bubble begins.
    static let replyRowTopPadding: CGFloat = 8
    /// A reply bubble's own left margin (row-local, i.e. relative to the row's
    /// content after the shared `cardPadding` inset) — real space on every
    /// side (this, `replyBubbleTrailingMargin`, `replyRowBottomPadding`) is
    /// what makes a reply read as a floating card, not a full-width strip.
    static let replyBubbleLeadingMargin: CGFloat = 8
    static let replyBubbleTrailingMargin: CGFloat = 10
    static let replyRowBottomPadding: CGFloat = 10

    static let parentAvatarSize: CGFloat = 44
    static let replyAvatarSize: CGFloat = 36
    /// The parent avatar's column width == its size (no extra column margin).
    static let avatarColumnWidth: CGFloat = parentAvatarSize

    /// Extra bubble indent for a reply-to-a-reply (depth 2+), capped at ONE step
    /// past the first reply level. This cap is load-bearing, not just a phone-
    /// width nicety: the connector for a non-last reply runs the row's full
    /// height and relies on the bubble's own opaque fill to hide it (see
    /// `CommentThreadGroupRowModifier.connector`) — that only works while the
    /// bubble's left edge stays at or left of `connectorCenterX`. A per-depth
    /// indent (12pt/level) pushes the edge past that line at depth 3+
    /// (bubble left = cardPadding + replyBubbleLeadingMargin + indent = 14+8+24
    /// = 46 > connectorCenterX's 36), which would leave the line floating,
    /// unhidden, to the left of a triply-nested bubble. Flattening to ONE step
    /// keeps every depth safely at bubbleLeft=34 <= 36, at the cost of not
    /// visually distinguishing depth 3+ from depth 2 — an acceptable trade for
    /// a rare, deep case, since AO3's own UI doesn't distinguish them either.
    static func bubbleIndent(forDepth depth: Int) -> CGFloat {
        CGFloat(min(depth, 2) - 1) * 12
    }

    /// The connector's center x within the group card (padding + column center)
    /// — also the parent avatar's center x. Reply avatars live inside their own
    /// bubble's independent layout and are no longer pinned to this line (see
    /// the type's own doc) — the connector only needs to reach the bubble.
    static var connectorCenterX: CGFloat { cardPadding + avatarColumnWidth / 2 }
    static let connectorWidth: CGFloat = 2
    /// Breathing room between the parent avatar's edge and the line segment
    /// beneath it (replies have no equivalent gap — see `parentContinuationTop`).
    static let connectorGap: CGFloat = 3

    /// Where the continuation segment starts for a PARENT row, measured from
    /// the row's top edge: just below the avatar's real bottom edge. The
    /// parent avatar is top-anchored (plain HStack, no center-offset trick),
    /// so `firstRowTopPadding` is its top edge — the bottom edge is a full
    /// `parentAvatarSize` further down, not half of it.
    static var parentContinuationTop: CGFloat {
        firstRowTopPadding + parentAvatarSize + connectorGap
    }
}

/// The card-within-a-card thread treatment (the mockups' core visual): every row
/// of one top-level thread shares a single continuous `cardSurface` card — the
/// same surface, radius, and margins as the Library's `.cardRow()` — opened by
/// the top-level comment and closed after the thread's last reply. Replies then
/// render as nested bubbles *inside* that card (see `CommentThreadRow`), each
/// with its own avatar-then-content row inside it. The connector line runs down
/// the parent avatar's column centerline and simply reaches down to touch each
/// reply bubble's own top edge — not a rail pasted on the card's left edge, but
/// also not threaded through any reply avatar (which lives inside its own
/// bubble's independent layout). Rows stay flat and lazy (the polish branch's
/// performance architecture); only the backgrounds compose into one visual group.
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
            // Directly behind the content (and above the card fill below), so
            // a reply's own bubble fill — and the parent avatar's opaque
            // backing — occlude the connector rather than drawing over it.
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

    /// The thread's connector segments for this row, drawn BEHIND the whole
    /// row content (including a reply's own bubble fill), which is what lets
    /// this stay simple: a reply's bubble has variable height (AO3 comments
    /// vary in length), so rather than compute where the bubble visually ends,
    /// the line for a non-last reply just runs the row's FULL height — the
    /// bubble's own opaque `nestedCardSurface` fill (in `CommentThreadRow`)
    /// occludes whatever portion falls behind it, and the line naturally
    /// "re-emerges" below the bubble however tall it turns out to be.
    ///
    /// - A reply row's arrival (row top → the bubble's own top edge) is the
    ///   only segment that needs a fixed length; everything past that is
    ///   either occluded by the bubble or, for a non-last reply, simply the
    ///   rest of the row's height.
    /// - A PARENT row has no enclosing bubble, so its continuation (when it
    ///   has replies) still needs the avatar's real bottom edge, precisely.
    @ViewBuilder
    private var connector: some View {
        if depth > 0 || !isLastInThread {
            Group {
                if depth > 0 {
                    if isLastInThread {
                        // Just the arrival: stops at the bubble's top edge:
                        // nothing below needs a visible line (there's no next
                        // reply to reach), so this never runs past the bubble.
                        line
                            .frame(height: CommentThreadGeometry.replyRowTopPadding)
                            .frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        // Full row height — see the doc above.
                        line
                    }
                } else {
                    // Parent with replies: starts precisely below the avatar.
                    line
                        .padding(.top, CommentThreadGeometry.parentContinuationTop)
                }
            }
            .frame(width: CommentThreadGeometry.connectorWidth, alignment: .top)
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
        if isReplyRow {
            replyBubble
        } else {
            // Parent: avatar in the shared column, content directly on the
            // thread card (no nested bubble) — matches the mockup's top-level
            // comment, and anchors the connector's fixed centerline.
            HStack(alignment: .top, spacing: 8) {
                CommentAvatar(comment: comment, size: CommentThreadGeometry.parentAvatarSize)
                    // Opaque backing (the avatar's own placeholder fill is only
                    // 50% quaternary) so the continuation segment — which runs
                    // behind this whole row and passes just below this avatar —
                    // never bleeds through it.
                    .background(Circle().fill(theme.appTheme.cardSurface))
                    .frame(width: CommentThreadGeometry.avatarColumnWidth)
                commentBody
            }
        }
    }

    /// A reply's floating nested card: the avatar sits INSIDE it (avatar-then-
    /// content, exactly like the parent's own layout), with the whole thing
    /// wrapped in a card that has real margin on every side — not overlapping
    /// the card's edge, and not threaded onto the connector's fixed centerline
    /// (which only needs to reach this bubble's top edge; see
    /// `CommentThreadGroupRowModifier.connector`).
    private var replyBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            CommentAvatar(comment: comment, size: CommentThreadGeometry.replyAvatarSize)
            commentBody
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.appTheme.nestedCardSurface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        }
        .padding(.leading,
                 CommentThreadGeometry.replyBubbleLeadingMargin
                    + CommentThreadGeometry.bubbleIndent(forDepth: row.depth))
        .padding(.trailing, CommentThreadGeometry.replyBubbleTrailingMargin)
        .padding(.bottom, CommentThreadGeometry.replyRowBottomPadding)
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
