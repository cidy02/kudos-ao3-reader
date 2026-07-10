import SwiftUI

/// Fixed geometry for recursive comment cards. The values intentionally mirror
/// the owner-approved T-84 card language: a top-level thread uses the app's
/// normal `cardSurface`; replies are complete nested cards on the **same**
/// `cardSurface`, differentiated by a surrounding theme shadow rather than a
/// second shade.
///
/// Visual nesting is recursive (T-86). That intentionally trades the T-83
/// one-row-per-comment List virtualization for card-within-card containment.
/// Mitigations: reply stacks auto-collapse past a direct-reply threshold
/// (local expand, no network), outer insets stop after depth 3, and
/// highlight/actions travel via Environment so the recursive call site stays
/// shallow.
enum CommentThreadGeometry {
    static let cardPadding: CGFloat = 14
    static let firstRowTopPadding: CGFloat = 14
    static let rootBottomPadding: CGFloat = 14
    /// Comfortable inset inside nested cards — must clear the 16pt corner
    /// radius so avatars never sit in the curve (the flush-pad "edge clash").
    static let replyBubblePadding: CGFloat = 10
    static let replyBubbleTrailingMargin: CGFloat = 10
    /// Spacing between sibling nested cards — single mechanism (no per-child
    /// bottom padding on top of this, which was stacking to ~20pt).
    static let childStackSpacing: CGFloat = 10
    static let childStackTopPadding: CGFloat = 10
    static let parentAvatarSize: CGFloat = 44
    static let replyAvatarSize: CGFloat = 36
    /// Shared column for every depth so avatar *centers* share one vertical
    /// axis; smaller reply avatars are centered inside this width.
    static let avatarColumnWidth: CGFloat = parentAvatarSize
    static let rootCornerRadius: CGFloat = 16
    static let replyCornerRadius: CGFloat = 16
    static let threadConnectorWidth: CGFloat = 1
    static let maximumIndentedVisualDepth = 3
    /// Direct-reply stacks larger than this start collapsed so a single List
    /// row does not eagerly build an enormous nested subtree (T-83 stall path).
    static let autoExpandedMaxDirectReplies = 8

    /// Outer leading inset on a nested card. Equals `-replyBubblePadding` so
    /// after the card's comfortable inner pad the avatar column lines up with
    /// the parent's — without flush-to-corner content. Nesting still reads via
    /// shadow + trailing inset + the thread connector.
    static func childLeadingInset(forDepth depth: Int) -> CGFloat {
        guard depth > 0 else { return 0 }
        return -replyBubblePadding
    }

    /// Trailing inset while the indent language is active; past the visual depth
    /// cap it drops to 0 so deep cards don't keep narrowing.
    static func childTrailingInset(forDepth depth: Int) -> CGFloat {
        guard depth > 0, depth <= maximumIndentedVisualDepth else { return 0 }
        return replyBubbleTrailingMargin
    }

    static func avatarSize(forDepth depth: Int) -> CGFloat {
        depth == 0 ? parentAvatarSize : replyAvatarSize
    }

    /// Inner padding on every side of a nested card (comfortable, corner-safe).
    static func nestedContentLeadingPadding(forDepth depth: Int) -> CGFloat {
        guard depth > 0 else { return replyBubblePadding }
        return replyBubblePadding
    }

    /// Distance from the shared parent-content leading edge to this node's
    /// avatar-column center. Parent and every nested depth resolve to the same
    /// value (`avatarColumnWidth / 2`) so centers share a vertical axis.
    static func avatarCenterX(forDepth depth: Int) -> CGFloat {
        if depth <= 0 {
            return avatarColumnWidth / 2
        }
        return childLeadingInset(forDepth: depth)
            + nestedContentLeadingPadding(forDepth: depth)
            + avatarColumnWidth / 2
    }
}

// MARK: - Thread environment (highlight + actions)

/// Closures for comment actions. Held in the environment so recursive
/// `CommentThreadRow` construction does not re-thread six handlers at every depth.
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

// MARK: - Row

/// One recursive comment card node. The same component renders top-level
/// comments and every reply; replies are nested inside the specific comment
/// they answer, preserving AO3's parent-child tree at arbitrary logical depth.
struct CommentThreadRow: View {
    let comment: AO3Comment
    let depth: Int
    let workAuthors: [String]
    let showChapterBadge: Bool

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.commentHighlightID) private var highlightedCommentID
    @Environment(\.commentThreadHandlers) private var handlers

    /// Local expand override for large direct-reply stacks (starts collapsed
    /// when over the auto-expand threshold).
    @State private var forceExpandReplies = false

    private var isRoot: Bool { depth == 0 }
    private var isHighlighted: Bool { highlightedCommentID == comment.id }
    private var showsChapterBadgeHere: Bool { showChapterBadge && isRoot }

    private var isByWorkAuthor: Bool {
        workAuthors.contains { $0.caseInsensitiveCompare(comment.author) == .orderedSame }
    }

    private var repliesStartExpanded: Bool {
        comment.replies.count <= CommentThreadGeometry.autoExpandedMaxDirectReplies
    }

    private var showsReplies: Bool {
        repliesStartExpanded || forceExpandReplies
    }

    var body: some View {
        if isRoot {
            rootCard
                .id(comment.id)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            nestedCard
                .id(comment.id)
        }
    }

    private var rootCard: some View {
        cardContents
            .padding(.horizontal, CommentThreadGeometry.cardPadding)
            .padding(.top, CommentThreadGeometry.firstRowTopPadding)
            .padding(.bottom, CommentThreadGeometry.rootBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme.appTheme.cardSurface,
                in: RoundedRectangle(
                    cornerRadius: CommentThreadGeometry.rootCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: CommentThreadGeometry.rootCornerRadius,
                    style: .continuous
                )
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            }
            .overlay(highlightOverlay(cornerRadius: CommentThreadGeometry.rootCornerRadius))
            .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }

    private var nestedCard: some View {
        let shape = RoundedRectangle(
            cornerRadius: CommentThreadGeometry.replyCornerRadius,
            style: .continuous
        )
        let elevation = theme.appTheme.nestedCardShadow
        let pad = CommentThreadGeometry.replyBubblePadding
        return cardContents
            // Uniform padding clears the corner radius; outer leading inset
            // (negative pad) re-aligns the avatar column with the parent.
            .padding(pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Same surface as the parent thread card — nesting reads via shadow,
            // not a second fill shade.
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
            .overlay(highlightOverlay(cornerRadius: CommentThreadGeometry.replyCornerRadius))
            .padding(.leading, CommentThreadGeometry.childLeadingInset(forDepth: depth))
            .padding(.trailing, CommentThreadGeometry.childTrailingInset(forDepth: depth))
            .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }

    @ViewBuilder
    private func highlightOverlay(cornerRadius: CGFloat) -> some View {
        if isHighlighted {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
        }
    }

    private var cardContents: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                // Avatar column: fixed width so centers share a vertical axis
                // with nested replies; a thread connector fills the space under
                // the avatar when this node has visible children (mockup rail).
                VStack(spacing: 0) {
                    CommentAvatar(
                        comment: comment,
                        size: CommentThreadGeometry.avatarSize(forDepth: depth)
                    )
                    if !comment.replies.isEmpty, showsReplies {
                        threadConnector
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: CommentThreadGeometry.avatarColumnWidth, alignment: .top)

                commentBody
            }

            if !comment.replies.isEmpty {
                replySection
            }
        }
    }

    /// Thin vertical rail under the avatar, matching the mockup's parent→child
    /// connector. Drawn in the avatar column so it stays on the shared centerline.
    private var threadConnector: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: CommentThreadGeometry.threadConnectorWidth)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var replySection: some View {
        if showsReplies {
            VStack(alignment: .leading, spacing: CommentThreadGeometry.childStackSpacing) {
                ForEach(comment.replies) { reply in
                    CommentThreadRow(
                        comment: reply,
                        depth: depth + 1,
                        workAuthors: workAuthors,
                        showChapterBadge: false
                    )
                }
            }
            .padding(.top, CommentThreadGeometry.childStackTopPadding)
            // Bridge the gap between the parent row and the first nested card
            // so the rail reads continuous down to the child.
            .background(alignment: .topLeading) {
                threadConnector
                    .frame(
                        width: CommentThreadGeometry.threadConnectorWidth,
                        height: CommentThreadGeometry.childStackTopPadding
                    )
                    .frame(
                        width: CommentThreadGeometry.avatarColumnWidth,
                        alignment: .center
                    )
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
            .padding(.top, CommentThreadGeometry.childStackTopPadding)
            .padding(.leading, CommentThreadGeometry.avatarColumnWidth + 8)
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
            if showsChapterBadgeHere, let chapter = comment.chapterLabel {
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
        // with the timestamp quiet in between (T-85's polished rendering —
        // relative within a day, else a readable local date — in T-84's
        // owner-approved placement).
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
            if !comment.postedText.isEmpty {
                Text(AO3CommentTimestamp.displayText(
                    rawText: comment.postedText,
                    date: comment.postedAt
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // Yields first when space is tight — the actions must not shrink.
                .layoutPriority(-1)
            }
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
                    // Scrolls to this comment in the native list (mostly useful
                    // as a "where am I" re-center after browsing a long page).
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
