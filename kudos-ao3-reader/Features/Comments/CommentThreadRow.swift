import SwiftUI

/// Geometry for Threads-style comment conversations.
///
/// Each **top-level** comment is one Library card. Replies stack inside that
/// card on a continuous avatar spine (Meta Threads / Instagram conversation
/// pattern) — not card-within-card bubbles. Logical AO3 depth is preserved in
/// the tree; visual indent is optional and capped so deep chains stay readable.
enum CommentThreadGeometry {
    static let cardPadding: CGFloat = 14
    static let cardCornerRadius: CGFloat = 16
    static let avatarSize: CGFloat = 40
    static let avatarColumnWidth: CGFloat = avatarSize
    static let avatarContentSpacing: CGFloat = 10
    static let postSpacing: CGFloat = 14
    static let spineWidth: CGFloat = 2
    /// Soft horizontal step per reply level (0 = pure single-column spine).
    static let depthIndent: CGFloat = 0
    static let maximumVisualDepth = 3
    /// Direct-reply stacks larger than this start collapsed so a single List
    /// row does not eagerly build an enormous subtree.
    static let autoExpandedMaxDirectReplies = 8

    static func leadingIndent(forDepth depth: Int) -> CGFloat {
        guard depthIndent > 0, depth > 0 else { return 0 }
        return CGFloat(min(depth, maximumVisualDepth)) * depthIndent
    }

    /// Avatar-column center from the card content leading edge at `depth`.
    static func avatarCenterX(forDepth depth: Int) -> CGFloat {
        leadingIndent(forDepth: depth) + avatarColumnWidth / 2
    }
}

// MARK: - Thread environment (highlight + actions)

/// Closures for comment actions. Held in the environment so recursive
/// construction does not re-thread six handlers at every depth.
struct CommentThreadHandlers {
    var onReply: (AO3Comment) -> Void
    var onEdit: (AO3Comment) -> Void
    var onDelete: (AO3Comment) -> Void
    var onCopyLink: (AO3Comment) -> Void
    /// Scrolls to and briefly highlights the given comment id within the
    /// currently-loaded tree — native in-app focus, not an AO3 web page.
    var onFocusThread: (Int) -> Void
    /// Presents the AO3 login sheet (from the disabled-looking "Log in to
    /// Reply" placeholder, which must actually do something when tapped).
    var onRequestLogin: () -> Void

    static let noop = CommentThreadHandlers(
        onReply: { _ in },
        onEdit: { _ in },
        onDelete: { _ in },
        onCopyLink: { _ in },
        onFocusThread: { _ in },
        onRequestLogin: {}
    )
}

private struct CommentHighlightIDKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

private struct CommentThreadHandlersKey: EnvironmentKey {
    static let defaultValue = CommentThreadHandlers.noop
}

extension EnvironmentValues {
    var commentHighlightID: Int? {
        get { self[CommentHighlightIDKey.self] }
        set { self[CommentHighlightIDKey.self] = newValue }
    }

    var commentThreadHandlers: CommentThreadHandlers {
        get { self[CommentThreadHandlersKey.self] }
        set { self[CommentThreadHandlersKey.self] = newValue }
    }
}

// MARK: - Thread card (list row = one top-level conversation)

/// One top-level AO3 comment and its reply tree, rendered as a single card with
/// Threads-style stacking: avatar spine + content, no nested bubbles.
struct CommentThreadRow: View {
    let comment: AO3Comment
    let workAuthors: [String]
    let showChapterBadge: Bool

    @Environment(ThemeManager.self) private var theme
    @Environment(\.commentHighlightID) private var highlightedCommentID

    var body: some View {
        CommentPostNode(
            comment: comment,
            depth: 0,
            workAuthors: workAuthors,
            showChapterBadge: showChapterBadge,
            drawsSpineBelow: !comment.replies.isEmpty,
            spineContinuesAfterSubtree: false
        )
        .padding(CommentThreadGeometry.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.appTheme.cardSurface,
            in: RoundedRectangle(
                cornerRadius: CommentThreadGeometry.cardCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: CommentThreadGeometry.cardCornerRadius,
                style: .continuous
            )
            .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

// MARK: - Post node (recursive, no per-reply card chrome)

/// One comment in the spine. Replies are further `CommentPostNode`s underneath
/// — same surface as the parent card, connected by the avatar rail.
private struct CommentPostNode: View {
    let comment: AO3Comment
    let depth: Int
    let workAuthors: [String]
    let showChapterBadge: Bool
    /// True when another post follows (own replies or a later sibling / aunt).
    let drawsSpineBelow: Bool
    /// True when a later node exists after this whole subtree (sibling of an
    /// ancestor). Passed down so the last child of a non-final branch still
    /// extends the rail toward the next branch.
    let spineContinuesAfterSubtree: Bool

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.commentHighlightID) private var highlightedCommentID
    @Environment(\.commentThreadHandlers) private var handlers

    @State private var forceExpandReplies = false

    private var isHighlighted: Bool { highlightedCommentID == comment.id }

    private var isByWorkAuthor: Bool {
        workAuthors.contains { $0.caseInsensitiveCompare(comment.author) == .orderedSame }
    }

    private var showsReplies: Bool {
        comment.replies.count <= CommentThreadGeometry.autoExpandedMaxDirectReplies
            || forceExpandReplies
    }

    private var hasVisibleReplies: Bool {
        !comment.replies.isEmpty && showsReplies
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            postRow
                .id(comment.id)
                .padding(4)
                .background {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: isHighlighted)

            if !comment.replies.isEmpty {
                // Spine bridge across the gap between this post and the next.
                if drawsSpineBelow || hasVisibleReplies {
                    spineBridge
                }
                replyBlock
            } else if drawsSpineBelow {
                // Later sibling follows this leaf — bridge only.
                spineBridge
            }
        }
        .padding(.leading, CommentThreadGeometry.leadingIndent(forDepth: depth))
    }

    private var postRow: some View {
        HStack(alignment: .top, spacing: CommentThreadGeometry.avatarContentSpacing) {
            // Avatar column: top stub (from previous bridge), avatar, then a
            // flexible rail beside the body when something continues below.
            VStack(spacing: 0) {
                CommentAvatar(comment: comment, size: CommentThreadGeometry.avatarSize)
                    .frame(
                        width: CommentThreadGeometry.avatarColumnWidth,
                        height: CommentThreadGeometry.avatarSize
                    )

                if drawsSpineBelow || hasVisibleReplies {
                    spineSegment
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: CommentThreadGeometry.avatarColumnWidth, alignment: .top)

            commentBody
        }
    }

    /// Fixed-height rail that carries the spine through `postSpacing`.
    private var spineBridge: some View {
        HStack(spacing: 0) {
            spineSegment
                .frame(
                    width: CommentThreadGeometry.avatarColumnWidth,
                    height: CommentThreadGeometry.postSpacing
                )
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    private var spineSegment: some View {
        Rectangle()
            .fill(spineColor)
            .frame(width: CommentThreadGeometry.spineWidth)
            .frame(maxWidth: .infinity) // center in avatar column
            .accessibilityHidden(true)
    }

    private var spineColor: Color {
        Color.primary.opacity(theme.appTheme == .dark ? 0.22 : 0.14)
    }

    @ViewBuilder
    private var replyBlock: some View {
        if showsReplies {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(comment.replies.enumerated()), id: \.element.id) { index, reply in
                    let laterSibling = index < comment.replies.count - 1
                    // Rail continues after this reply's subtree when a later
                    // sibling exists, or when an ancestor still has more posts.
                    let afterSubtree = laterSibling || spineContinuesAfterSubtree
                    CommentPostNode(
                        comment: reply,
                        depth: depth + 1,
                        workAuthors: workAuthors,
                        showChapterBadge: false,
                        drawsSpineBelow: !reply.replies.isEmpty || afterSubtree,
                        spineContinuesAfterSubtree: afterSubtree
                    )
                }
            }
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    forceExpandReplies = true
                }
            } label: {
                Label(
                    "Show \(comment.replies.count) replies",
                    systemImage: "bubble.left.and.bubble.right"
                )
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.leading, CommentThreadGeometry.avatarColumnWidth + CommentThreadGeometry.avatarContentSpacing)
            .accessibilityHint("Expands nested replies for this comment")
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
            actionsRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .layoutPriority(-1)
            }
            Spacer(minLength: 4)
            if showChapterBadge, depth == 0, let chapter = comment.chapterLabel {
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

    private var actionsRow: some View {
        HStack(spacing: 8) {
            if comment.canReply && auth.isLoggedIn {
                Button { handlers.onReply(comment) } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.caption.weight(.medium))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reply to \(comment.author)")
            }
            Spacer()
            Menu {
                if comment.canReply && auth.isLoggedIn {
                    Button { handlers.onReply(comment) } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                } else if comment.canReply {
                    Button { handlers.onRequestLogin() } label: {
                        Label("Log in to Reply", systemImage: "person.crop.circle.badge.questionmark")
                    }
                }
                if comment.editPath != nil {
                    Button { handlers.onEdit(comment) } label: {
                        Label("Edit Comment", systemImage: "pencil")
                    }
                }
                Button { handlers.onCopyLink(comment) } label: {
                    Label("Copy Link", systemImage: "link")
                }
                if comment.threadPath != nil {
                    Button { handlers.onFocusThread(comment.id) } label: {
                        Label("Thread", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                if let parentID = comment.parentCommentID {
                    Button { handlers.onFocusThread(parentID) } label: {
                        Label("Parent Thread", systemImage: "arrowshape.turn.up.backward")
                    }
                }
                if comment.deletePath != nil {
                    Button(role: .destructive) { handlers.onDelete(comment) } label: {
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
/// and is only instantiated for rendered comment cards.
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
