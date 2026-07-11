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
    /// Comment cards use the app-wide card radius, so a thread card reads exactly
    /// like a Library/Search card rather than a near-miss.
    static let cardCornerRadius = CardListMetrics.cornerRadius
    static let nestedCardPadding: CGFloat = 12
    static let nestedCardCornerRadius = CardListMetrics.cornerRadius
    static let nestedCardSpacing = CardListMetrics.interCardSpacing
    static let avatarSize: CGFloat = 40
    static let avatarColumnWidth: CGFloat = avatarSize
    static let avatarContentSpacing: CGFloat = 10
    /// Vertical gap between spine posts; carried inside the rail so the line
    /// never breaks across SwiftUI `VStack` spacing.
    static let postSpacing: CGFloat = 12
    static let spineWidth: CGFloat = 2
    /// Reply cards carry their own `nestedCardPadding`, which insets their avatars
    /// from the card's edge. The root post and the bridges between reply cards take
    /// the SAME leading inset, so every avatar — and the rail joining them — sits on
    /// one column. Without it the rail misses each reply avatar by exactly
    /// `nestedCardPadding`.
    static let railInset: CGFloat = nestedCardPadding
    /// Shared centre of the avatar rail, from the root card's content edge.
    static let railCenterX: CGFloat = railInset + avatarColumnWidth / 2
    /// Reply stacks larger than this start collapsed. Counts EVERY reply in the
    /// thread — the whole depth-first stack is what expanding actually renders —
    /// not just the root's direct children.
    static let autoExpandedMaxReplies = 8
    /// Collapsed body height before "Read more".
    static let collapsedBodyLineLimit = 5

    /// Depth-first list of every reply under a root (root itself excluded),
    /// each becoming its own nested card.
    static func flattenedReplies(from root: AO3Comment) -> [FlattenedReply] {
        var result: [FlattenedReply] = []
        // An explicit stack, not recursion: AO3 doesn't cap reply nesting, and a
        // long reply-to-reply chain would otherwise cost one frame per level. The
        // single accumulator also avoids the O(depth²) copying that `[node] +
        // flatten(children)` incurs at every level.
        var stack: [FlattenedReply] = root.replies.reversed().map {
            FlattenedReply(comment: $0, depth: 1)
        }
        while let item = stack.popLast() {
            result.append(item)
            for child in item.comment.replies.reversed() {
                stack.append(FlattenedReply(comment: child, depth: item.depth + 1))
            }
        }
        return result
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
    /// Opens a commenter's native profile (Works/Series/Bookmarks/About). nil is
    /// a valid, common default — `AO3AuthorBylineView` renders plain, untappable
    /// text when no route handler is supplied, matching every other call site.
    /// The `= nil` default (not just an Optional type) is load-bearing: it's
    /// what makes the synthesized memberwise init treat this param as optional
    /// too, so `.noop` below keeps compiling unchanged.
    var onOpenAuthor: ((AO3AuthorRoute) -> Void)? = nil

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
    /// Forced open by "Thread"/"Parent Thread" focus, so a collapsed thread can
    /// never swallow the comment being scrolled to.
    var startsExpanded = false

    @Environment(ThemeManager.self) private var theme
    @Environment(\.commentHighlightID) private var highlightedCommentID

    @State private var forceExpandReplies = false

    private var replyItems: [FlattenedReply] {
        CommentThreadGeometry.flattenedReplies(from: comment)
    }

    /// Gated on the total reply count, because expanding renders every descendant
    /// (`replyItems`), not just the root's direct children.
    private var showsReplies: Bool {
        forceExpandReplies || startsExpanded
            || replyItems.count <= CommentThreadGeometry.autoExpandedMaxReplies
    }

    var body: some View {
        let elevation = theme.appTheme.cardShadow
        let replies = replyItems
        let shape = RoundedRectangle(
            cornerRadius: CommentThreadGeometry.cardCornerRadius,
            style: .continuous
        )
        let isHighlighted = highlightedCommentID == comment.id

        return VStack(alignment: .leading, spacing: 0) {
            // Root post — spine continues under the avatar when replies show.
            SpinePostRow(
                comment: comment,
                workAuthors: workAuthors,
                showChapterBadge: showChapterBadge,
                drawsSpineBelow: !replies.isEmpty && showsReplies
            )
            .id(comment.id)
            // Puts the root avatar on the same rail column as the reply avatars,
            // which sit inside their own cards' padding.
            .padding(.leading, CommentThreadGeometry.railInset)

            if !replies.isEmpty {
                if showsReplies {
                    // Root post owns the only in-card spine (down to the first
                    // reply). Nested reply cards have no internal rail — only
                    // the bridges between them.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(replies.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                spineBridge(height: CommentThreadGeometry.nestedCardSpacing)
                            }
                            NestedReplyCard(
                                comment: item.comment,
                                workAuthors: workAuthors
                            )
                        }
                    }
                } else {
                    expandRepliesButton(count: replies.count) {
                        forceExpandReplies = true
                    }
                    .padding(.top, CommentThreadGeometry.postSpacing)
                    .padding(
                        .leading,
                        CommentThreadGeometry.railInset
                            + CommentThreadGeometry.avatarColumnWidth
                            + CommentThreadGeometry.avatarContentSpacing
                    )
                }
            }
        }
        .padding(CommentThreadGeometry.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.appTheme.cardSurface, in: shape)
        .highlightOverlay(shape, isHighlighted: isHighlighted)
        .overlay {
            shape.strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        }
        // Same elevation every other card list gets (flat in Dark, by convention).
        .shadow(color: elevation.color, radius: elevation.radius, x: 0, y: elevation.y)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .onAppear {
            // Latch a naturally-expanded thread open. A reload that pushes it past
            // the collapse threshold — commonly the user's OWN just-posted reply —
            // must not snap it shut and hide the very reply they just wrote.
            if replies.count <= CommentThreadGeometry.autoExpandedMaxReplies {
                forceExpandReplies = true
            }
        }
    }

    private func spineBridge(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ThreadSpineSegment()
                .frame(width: CommentThreadGeometry.avatarColumnWidth, height: height)
            Spacer(minLength: 0)
        }
        .padding(.leading, CommentThreadGeometry.railInset)
        .accessibilityHidden(true)
    }
}

// MARK: - Nested reply card (one reply = one card)

/// A single reply enclosed in its own card. No internal spine — the rail lives
/// only on the root post and in the gaps between these cards.
private struct NestedReplyCard: View {
    let comment: AO3Comment
    let workAuthors: [String]

    @Environment(ThemeManager.self) private var theme
    @Environment(\.commentHighlightID) private var highlightedCommentID

    var body: some View {
        let elevation = theme.appTheme.cardShadow
        let shape = RoundedRectangle(
            cornerRadius: CommentThreadGeometry.nestedCardCornerRadius,
            style: .continuous
        )
        let isHighlighted = highlightedCommentID == comment.id

        SpinePostRow(
            comment: comment,
            workAuthors: workAuthors,
            showChapterBadge: false,
            drawsSpineBelow: false
        )
        .id(comment.id)
        // Equal inset on every side so the avatar isn’t pushed down relative
        // to the leading edge (top used to be 8 while leading was 0).
        .padding(CommentThreadGeometry.nestedCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Dark reads the nesting off the surface (cards stay flat there); Light and
        // Sepia keep `cardSurface` and lift with the same shadow every card uses.
        .background(theme.appTheme.nestedCardSurface, in: shape)
        .highlightOverlay(shape, isHighlighted: isHighlighted)
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
    /// Also reserves `postSpacing` under the body and fills it with rail, so the
    /// next avatar sits on a continuous line.
    let drawsSpineBelow: Bool

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.commentThreadHandlers) private var handlers

    private var isByWorkAuthor: Bool {
        workAuthors.contains { $0.caseInsensitiveCompare(comment.author) == .orderedSame }
    }

    var body: some View {
        // Formatted once and handed to both byline candidates: `ViewThatFits` builds
        // every candidate in order to measure it, and the date formatting isn't free.
        let timestamp = comment.postedText.isEmpty
            ? ""
            : AO3CommentTimestamp.displayText(
                rawText: comment.postedText, date: comment.postedAt
            )

        return HStack(alignment: .top, spacing: CommentThreadGeometry.avatarContentSpacing) {
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
                commentBody(timestamp: timestamp)
                if drawsSpineBelow {
                    Color.clear
                        .frame(height: CommentThreadGeometry.postSpacing)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func commentBody(timestamp: String) -> some View {
        if comment.isDeleted {
            // Deleted-comment tombstone, presented the way AO3 itself does: just
            // the placeholder text — no byline, no actions (AO3 renders none).
            // The avatar placeholder stays so the reply rail passes through.
            Text(comment.bodyText.isEmpty ? "(Previous comment deleted.)" : comment.bodyText)
                .font(.subheadline.italic())
                .foregroundStyle(.secondary)
                .frame(minHeight: CommentThreadGeometry.avatarSize, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                byline(timestamp: timestamp)
                if !comment.bodyText.isEmpty {
                    ExpandableCommentBody(text: comment.bodyText)
                }
                // Tighter gap above the action strip so bottom padding matches the
                // card’s side inset instead of a tall empty actions band.
                actionsRow
                    .padding(.top, 2)
            }
        }
    }

    private func byline(timestamp: String) -> some View {
        // Prefer author + timestamp on one line; when the timestamp won't fit
        // next to the name (long names, Author/Guest + chapter badge), drop it
        // onto the line under the author.
        ViewThatFits(in: .horizontal) {
            bylineSingleLine(timestamp: timestamp)
            bylineWrappedTimestamp(timestamp: timestamp)
        }
    }

    /// Author, role badge, and timestamp on one row (preferred when space allows).
    private func bylineSingleLine(timestamp: String) -> some View {
        HStack(alignment: .center, spacing: 6) {
            authorIdentity
            if !timestamp.isEmpty {
                timestampText(timestamp)
            }
            Spacer(minLength: 4)
            chapterBadge
        }
    }

    /// Timestamp under the author when the single-line layout is too wide.
    private func bylineWrappedTimestamp(timestamp: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                authorIdentity
                if !timestamp.isEmpty {
                    timestampText(timestamp)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            chapterBadge
        }
    }

    /// Tappable, pseud-correct author name — routes to the native profile when
    /// AO3 gave us a resolvable `/users/...` link (registered, non-guest
    /// commenters only); guests and unresolvable bylines render as plain text
    /// via the same component's own fallback.
    private var authorIdentity: some View {
        HStack(spacing: 6) {
            AO3AuthorBylineView(
                names: [comment.author],
                identities: commentIdentity.map { [$0] } ?? [],
                includesBy: false,
                font: .subheadline,
                compact: true,
                emphasized: true,
                onOpenRoute: handlers.onOpenAuthor
            )
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
        }
    }

    private func timestampText(_ timestamp: String) -> some View {
        Text(timestamp)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var chapterBadge: some View {
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

    /// The AO3 identity behind this comment's byline, when it's a real
    /// resolvable account — `AO3AuthorBylineView` falls back to plain text for
    /// guests and any comment whose byline link didn't resolve to a route.
    private var commentIdentity: AO3AuthorIdentity? {
        guard !comment.isGuest, let path = comment.userPath else { return nil }
        return AO3AuthorIdentity(displayName: comment.author, href: path)
    }

    /// Compact bottom strip: Reply bottom-leading, overflow bottom-trailing.
    /// Visual height stays tight so card padding reads even; hit targets use
    /// contentShape rather than a 44pt layout frame that inflated the strip.
    private var actionsRow: some View {
        HStack(alignment: .center, spacing: 4) {
            if comment.canReply && auth.isLoggedIn {
                Button { handlers.onReply(comment) } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.caption.weight(.medium))
                        .padding(.vertical, 4)
                        .padding(.trailing, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reply to \(comment.author)")
            }
            Spacer(minLength: 0)
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
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("More actions for \(comment.author)'s comment")
        }
    }
}

// MARK: - Expandable body

/// Comment body with a collapsed line limit and a Read more / Show less control
/// when the text is long enough to need it.
private struct ExpandableCommentBody: View {
    let text: String
    @State private var isExpanded = false
    @State private var clampedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    /// Truncation is a layout fact. A character budget can't know the reader's
    /// Dynamic Type size or the card's width, so it both misses long comments at
    /// accessibility sizes and offers "Read more" on short ones.
    private var needsExpansion: Bool {
        fullHeight > clampedHeight + 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            bodyText
                .lineLimit(isExpanded ? nil : CommentThreadGeometry.collapsedBodyLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .background(alignment: .top) { truncationProbes }

            if needsExpansion {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Show less" : "Read more")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityHint(
                    isExpanded
                        ? "Collapses the full comment"
                        : "Expands the full comment"
                )
            }
        }
    }

    private var bodyText: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.primary)
    }

    /// Hidden copies of the body laid out at the live width: one clamped to the
    /// collapsed line limit, one unclamped. The unclamped copy being taller is the
    /// only reliable "this truncates" signal. Measured with the clamp always
    /// applied, so the control survives expanding (it becomes "Show less"). Neither
    /// height depends on `needsExpansion`, so this can't feed back into layout.
    private var truncationProbes: some View {
        ZStack(alignment: .top) {
            bodyText
                .lineLimit(CommentThreadGeometry.collapsedBodyLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    clampedHeight = $0
                }
            bodyText
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    fullHeight = $0
                }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Spine primitive

private struct ThreadSpineSegment: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.appTheme.threadSpine)
            .frame(width: CommentThreadGeometry.spineWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

// MARK: - Shared chrome helpers

private extension View {
    /// "Thread"/"Parent Thread" focus tint, sized to the CARD's own shape (not
    /// its content) so the flash reads as the whole card lighting up, edge to
    /// edge, rather than a smaller fill inset behind the row content. Painted
    /// between the card's background fill and its border stroke, so the border
    /// stays crisp on top.
    @ViewBuilder
    func highlightOverlay(_ shape: RoundedRectangle, isHighlighted: Bool) -> some View {
        self
            .overlay {
                if isHighlighted {
                    shape.fill(Color.accentColor.opacity(0.12))
                        .allowsHitTesting(false)
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
