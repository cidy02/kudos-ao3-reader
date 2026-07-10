import SwiftUI

/// Geometry for comment threads.
///
/// **Two card shells only** (no matryoshka):
/// 1. Top-level conversation card
/// 2. One nested card **per reply** (any logical depth), all sitting inside the
///    root card — never a card inside a reply card.
///
/// Hierarchy is the Threads-style avatar spine connecting those reply cards
/// in depth-first order.
enum CommentThreadGeometry {
    static let cardPadding: CGFloat = 14
    static let cardCornerRadius: CGFloat = 16
    static let nestedCardPadding: CGFloat = 12
    static let nestedCardCornerRadius: CGFloat = 14
    static let nestedCardSpacing: CGFloat = 12
    static let avatarSize: CGFloat = 40
    static let avatarColumnWidth: CGFloat = avatarSize
    static let avatarContentSpacing: CGFloat = 10
    /// Vertical gap between spine posts; carried inside the rail so the line
    /// never breaks across SwiftUI `VStack` spacing.
    static let postSpacing: CGFloat = 12
    static let spineWidth: CGFloat = 2
    /// Card nesting cap: root shell + reply shells only (reply cards are never
    /// nested inside each other).
    static let maximumCardDepth = 1
    /// Direct-reply stacks larger than this start collapsed.
    static let autoExpandedMaxDirectReplies = 8

    static func avatarCenterX(forDepth depth: Int) -> CGFloat {
        _ = depth
        return avatarColumnWidth / 2
    }

    /// Depth-first list of every reply under a root (root itself excluded),
    /// each becoming its own nested card.
    static func flattenedReplies(from root: AO3Comment) -> [FlattenedReply] {
        flatten(root.replies, depth: 1)
    }

    private static func flatten(_ comments: [AO3Comment], depth: Int) -> [FlattenedReply] {
        comments.flatMap { comment in
            [FlattenedReply(comment: comment, depth: depth)]
                + flatten(comment.replies, depth: depth + 1)
        }
    }
}

/// One reply in display order (DFS under a top-level comment).
struct FlattenedReply: Identifiable, Equatable {
    var id: Int { comment.id }
    let comment: AO3Comment
    /// Logical AO3 depth (1 = direct reply to the root card).
    let depth: Int
}

// MARK: - Thread environment (highlight + actions)

struct CommentThreadHandlers {
    var onReply: (AO3Comment) -> Void
    var onEdit: (AO3Comment) -> Void
    var onDelete: (AO3Comment) -> Void
    var onCopyLink: (AO3Comment) -> Void
    var onFocusThread: (Int) -> Void
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

// MARK: - Top-level list row (card level 0)

/// One top-level AO3 comment as a Library card. Every reply in its tree is a
/// separate nested card inside this shell, linked by the avatar spine.
struct CommentThreadRow: View {
    let comment: AO3Comment
    let workAuthors: [String]
    let showChapterBadge: Bool

    @Environment(ThemeManager.self) private var theme
    @Environment(\.commentHighlightID) private var highlightedCommentID

    @State private var forceExpandReplies = false

    private var replyItems: [FlattenedReply] {
        CommentThreadGeometry.flattenedReplies(from: comment)
    }

    private var showsReplies: Bool {
        comment.replies.count <= CommentThreadGeometry.autoExpandedMaxDirectReplies
            || forceExpandReplies
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Root post — spine continues under the avatar when replies show.
            SpinePostRow(
                comment: comment,
                workAuthors: workAuthors,
                showChapterBadge: showChapterBadge,
                drawsSpineBelow: !comment.replies.isEmpty && showsReplies
            )
            .id(comment.id)
            .highlightChrome(isHighlighted: highlightedCommentID == comment.id)

            if !comment.replies.isEmpty {
                if showsReplies {
                    // Root `SpinePostRow` already reserves `postSpacing` in the
                    // rail; each reply is its own card (no card-in-card).
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(replyItems.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                spineOnlyBridge
                            }
                            NestedReplyCard(
                                comment: item.comment,
                                workAuthors: workAuthors,
                                drawsSpineBelow: index < replyItems.count - 1
                            )
                        }
                    }
                } else {
                    expandRepliesButton(count: comment.replies.count) {
                        forceExpandReplies = true
                    }
                    .padding(.top, CommentThreadGeometry.postSpacing)
                    .padding(
                        .leading,
                        CommentThreadGeometry.avatarColumnWidth
                            + CommentThreadGeometry.avatarContentSpacing
                    )
                }
            }
        }
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

    /// Rail segment between sibling nested reply cards.
    private var spineOnlyBridge: some View {
        HStack(spacing: 0) {
            ThreadSpineSegment()
                .frame(
                    width: CommentThreadGeometry.avatarColumnWidth,
                    height: CommentThreadGeometry.nestedCardSpacing
                )
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Nested reply card (one reply = one card)

/// A single reply enclosed in its own card. Sits inside the root conversation
/// card; never wraps further nested card shells.
private struct NestedReplyCard: View {
    let comment: AO3Comment
    let workAuthors: [String]
    /// When true, the post’s spine continues under the body so the inter-card
    /// bridge (or next card) can meet it.
    let drawsSpineBelow: Bool

    @Environment(ThemeManager.self) private var theme
    @Environment(\.commentHighlightID) private var highlightedCommentID

    var body: some View {
        let elevation = theme.appTheme.nestedCardShadow
        let shape = RoundedRectangle(
            cornerRadius: CommentThreadGeometry.nestedCardCornerRadius,
            style: .continuous
        )

        SpinePostRow(
            comment: comment,
            workAuthors: workAuthors,
            showChapterBadge: false,
            // Inter-card gap is the parent bridge; in-card tail only needed if
            // we drew multiple posts here (we don't).
            drawsSpineBelow: drawsSpineBelow,
            includeTrailingGap: false
        )
        .id(comment.id)
        .highlightChrome(isHighlighted: highlightedCommentID == comment.id)
        // Leading 0 keeps avatars on the root spine column.
        .padding(.top, 8)
        .padding(.bottom, 8)
        .padding(.trailing, CommentThreadGeometry.nestedCardPadding)
        .padding(.leading, 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.appTheme.cardSurface, in: shape)
        .overlay {
            shape.strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        }
        .shadow(
            color: elevation.color,
            radius: elevation.radius,
            x: 0,
            y: elevation.y
        )
    }
}

// MARK: - Spine post row

/// One comment on the Threads-style avatar rail. The rail under the avatar
/// grows with the body and can include the inter-post gap so SwiftUI spacing
/// never punches a hole in the line.
private struct SpinePostRow: View {
    let comment: AO3Comment
    let workAuthors: [String]
    let showChapterBadge: Bool
    let drawsSpineBelow: Bool
    /// When true, reserves `postSpacing` under the body and fills it with rail
    /// so the next avatar sits on a continuous line.
    var includeTrailingGap: Bool = true

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.commentThreadHandlers) private var handlers

    private var isByWorkAuthor: Bool {
        workAuthors.contains { $0.caseInsensitiveCompare(comment.author) == .orderedSame }
    }

    private var reserveGap: Bool {
        drawsSpineBelow && includeTrailingGap
    }

    var body: some View {
        HStack(alignment: .top, spacing: CommentThreadGeometry.avatarContentSpacing) {
            VStack(spacing: 0) {
                CommentAvatar(comment: comment, size: CommentThreadGeometry.avatarSize)
                    .frame(
                        width: CommentThreadGeometry.avatarColumnWidth,
                        height: CommentThreadGeometry.avatarSize
                    )

                if drawsSpineBelow {
                    ThreadSpineSegment()
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: CommentThreadGeometry.avatarColumnWidth, alignment: .top)

            VStack(alignment: .leading, spacing: 0) {
                commentBody
                if reserveGap {
                    Color.clear
                        .frame(height: CommentThreadGeometry.postSpacing)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Spine primitive

private struct ThreadSpineSegment: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(theme.appTheme == .dark ? 0.28 : 0.16))
            .frame(width: CommentThreadGeometry.spineWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

// MARK: - Shared chrome helpers

private extension View {
    @ViewBuilder
    func highlightChrome(isHighlighted: Bool) -> some View {
        self
            .padding(4)
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }
}

private func expandRepliesButton(count: Int, action: @escaping () -> Void) -> some View {
    Button {
        withAnimation(.easeInOut(duration: 0.2), action)
    } label: {
        Label(
            "Show \(count) replies",
            systemImage: "bubble.left.and.bubble.right"
        )
        .font(.caption.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .accessibilityHint("Expands nested replies for this comment")
}

// MARK: - Avatar

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
