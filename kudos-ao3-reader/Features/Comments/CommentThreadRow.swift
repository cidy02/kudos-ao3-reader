import SwiftUI

/// Fixed geometry for the comment thread's avatar column and connector line.
///
/// The parent row places its avatar in a left column; every reply's avatar
/// overlaps its OWN bubble's top-left corner (the mockup's "avatar badge" —
/// half poking above/outside the card, half over its top-left interior)
/// instead of sitting inside the bubble's content. Both constructions still
/// share one fixed centerline, so the mockups' key invariant holds with a
/// single straight line and no elbows:
///
///     connectorLineX == parentAvatar.centerX == replyAvatar.centerX
///
/// True at every depth: a reply's avatar offset explicitly cancels out its own
/// bubble's `bubbleIndent`, so the avatar's absolute x never moves even though
/// the bubble around it does (see that function's doc for the resulting depth
/// ≥ 3 trade-off). All values are in the group card's coordinate space; the
/// connector is drawn by `CommentThreadGroupRowModifier`, which owns the same
/// paddings.
enum CommentThreadGeometry {
    /// The group card's inner horizontal padding (both edges).
    static let cardPadding: CGFloat = 14
    /// Row top padding before the parent's own content begins.
    static let firstRowTopPadding: CGFloat = 14
    /// Row top padding before a reply's bubble begins — sized so the avatar,
    /// which overlaps the bubble's top edge and pokes `replyAvatarSize / 2`
    /// above it, stays fully within this row rather than into the row above.
    static let replyRowTopPadding: CGFloat = 22
    /// Extra margin a reply's own bubble gets beyond the group card's shared
    /// trailing inset, and the row's own bottom gap before the next row —
    /// together with the corner-overlapping avatar, this is what makes a reply
    /// read as a floating card rather than a full-width tinted strip.
    static let replyBubbleTrailingMargin: CGFloat = 10
    static let replyRowBottomPadding: CGFloat = 10

    static let parentAvatarSize: CGFloat = 44
    static let replyAvatarSize: CGFloat = 36
    /// The parent avatar's column width == its size (no extra column margin).
    static let avatarColumnWidth: CGFloat = parentAvatarSize

    /// Extra bubble indent per depth level past the first reply, capped so long
    /// AO3 comments keep a readable measure on phone widths. Zero at depth 1
    /// (the first reply) — its bubble sits exactly where `replyBubbleLeadingMargin`
    /// places it, so its avatar overlaps THAT bubble's real corner exactly.
    ///
    /// At depth ≥ 2 the bubble indents further right, but the avatar's own
    /// offset (see `CommentThreadRow.replyBubble`) explicitly subtracts this
    /// same amount, so the avatar's ABSOLUTE position never moves — the
    /// connector stays a single straight line with no elbow at every depth.
    /// The trade-off lands on the avatar instead: at depth 2 it still clips the
    /// (now-indented) bubble's corner by `replyAvatarSize/2 - bubbleIndent(2)`
    /// (6pt here); at depth ≥ 3 the numbers cross and the avatar sits fully
    /// detached in the gap to the bubble's left. Accepted, since keeping the
    /// connector's integrity at the common depth-0/1/2 cases matters more than
    /// a precise corner-overlap this deep, and AO3 threads rarely nest this far.
    static func bubbleIndent(forDepth depth: Int) -> CGFloat {
        CGFloat(min(depth, 4) - 1) * 12
    }

    /// The connector's center x within the group card (padding + column center)
    /// — also every avatar's center x, parent or reply.
    static var connectorCenterX: CGFloat { cardPadding + avatarColumnWidth / 2 }
    static let connectorWidth: CGFloat = 2
    /// Breathing room between an avatar's edge and the line segment beneath it.
    static let connectorGap: CGFloat = 3

    /// A reply bubble's own left margin (row-local, i.e. relative to the row's
    /// content after the shared `cardPadding` inset): exactly enough that its
    /// top-left corner sits ON the fixed centerline, so the corner-overlapping
    /// avatar (see `CommentThreadRow`) lands on the same line as the parent's.
    static var replyBubbleLeadingMargin: CGFloat { avatarColumnWidth / 2 }

    /// Leading/top padding inside a reply's bubble content, clearing the
    /// avatar's inside half (the half that overlaps the bubble's interior).
    static var replyContentInset: CGFloat { replyAvatarSize / 2 + 8 }

    /// Where the continuation segment starts, measured from the row's top edge:
    /// just below this row's avatar.
    static func continuationTop(forDepth depth: Int) -> CGFloat {
        if depth == 0 {
            // The parent avatar is top-anchored (plain HStack, no center-offset
            // trick), so `firstRowTopPadding` is its TOP edge, not its center —
            // its bottom edge is a full `parentAvatarSize` below that, not half.
            return firstRowTopPadding + parentAvatarSize + connectorGap
        }
        // A reply's avatar IS center-anchored (the corner-overlap offset in
        // `CommentThreadRow.replyBubble` puts its center at `replyRowTopPadding`
        // exactly), so its bottom edge is only half a diameter further down.
        return replyRowTopPadding + replyAvatarSize / 2 + connectorGap
    }

    /// Where a reply row's arrival segment ends, measured from the row's top
    /// edge: this row's avatar center. A reply's avatar center sits exactly at
    /// its bubble's top edge (that's the corner-overlap), which is
    /// `replyRowTopPadding` below the row's own top.
    static var arrivalBottom: CGFloat {
        replyRowTopPadding
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

    /// A reply's floating nested card (the mockup's "avatar badge" look): the
    /// avatar overlaps the bubble's own top-left corner — half poking above and
    /// outside the card, half over its top-left interior — rather than sitting
    /// inline inside the bubble's content. Positioned via `.overlay` + `.offset`
    /// so it's a pure visual overlap that doesn't affect the bubble's own
    /// layout; the bubble reserves `replyContentInset` of leading/top padding
    /// so its text never runs under the avatar's inside half.
    private var replyBubble: some View {
        commentBody
            .padding(.leading, CommentThreadGeometry.replyContentInset)
            .padding(.top, CommentThreadGeometry.replyContentInset)
            .padding(.trailing, 10)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme.appTheme.nestedCardSurface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            }
            .overlay(alignment: .topLeading) {
                CommentAvatar(comment: comment, size: CommentThreadGeometry.replyAvatarSize)
                    // Opaque backing (the avatar's own placeholder fill is only
                    // 50% quaternary) so the connector's arrival segment, which
                    // ends exactly at this avatar's center, disappears cleanly
                    // behind it instead of bleeding through.
                    .background(Circle().fill(theme.appTheme.nestedCardSurface))
                    // Shifts the avatar so its CENTER (not its top-left) lands
                    // on the bubble's corner — the point the overlap pivots on.
                    // The x-offset ALSO subtracts this row's own bubbleIndent:
                    // the outer .padding(.leading, ...) below moves the whole
                    // bubble+overlay composite right by that same amount at
                    // depth ≥ 2, so without this the avatar would drift off the
                    // fixed centerline the connector draws at. Subtracting it
                    // here cancels that shift, keeping the avatar's ABSOLUTE x
                    // pinned to the centerline at every depth (see
                    // CommentThreadGeometry.bubbleIndent's doc for the resulting
                    // depth ≥ 3 trade-off: the avatar stays on the line, not on
                    // the deeper bubble's own corner).
                    .offset(
                        x: -CommentThreadGeometry.replyAvatarSize / 2
                            - CommentThreadGeometry.bubbleIndent(forDepth: row.depth),
                        y: -CommentThreadGeometry.replyAvatarSize / 2
                    )
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
