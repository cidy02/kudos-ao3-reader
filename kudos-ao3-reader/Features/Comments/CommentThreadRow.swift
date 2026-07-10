import SwiftUI

/// Fixed geometry for recursive comment cards. The values intentionally mirror
/// the owner-approved T-84 card language: a top-level thread uses the app's
/// normal `cardSurface`; replies are complete nested cards on
/// `nestedCardSurface`, with the same avatar/body/actions structure.
enum CommentThreadGeometry {
    static let cardPadding: CGFloat = 14
    static let firstRowTopPadding: CGFloat = 14
    static let rootBottomPadding: CGFloat = 14
    static let replyBubblePadding: CGFloat = 10
    static let replyBubbleLeadingMargin: CGFloat = 8
    static let replyBubbleTrailingMargin: CGFloat = 10
    static let replyRowBottomPadding: CGFloat = 10
    static let childStackTopPadding: CGFloat = 10
    static let childStackSpacing: CGFloat = 10
    static let parentAvatarSize: CGFloat = 44
    static let replyAvatarSize: CGFloat = 36
    static let avatarColumnWidth: CGFloat = parentAvatarSize
    static let rootCornerRadius: CGFloat = 16
    static let replyCornerRadius: CGFloat = 16
    static let maximumIndentedVisualDepth = 3

    /// Each child is already contained by its parent card; this small extra
    /// leading inset makes the relationship visible without letting deep AO3
    /// conversations collapse into unusably narrow columns. Logical depth is
    /// never capped — only this additional visual inset stops after depth 3.
    static func childLeadingInset(forDepth depth: Int) -> CGFloat {
        guard depth > 0, depth <= maximumIndentedVisualDepth else { return 0 }
        return replyBubbleLeadingMargin
    }

    static func avatarSize(forDepth depth: Int) -> CGFloat {
        depth == 0 ? parentAvatarSize : replyAvatarSize
    }
}

/// One recursive comment card node. The same component renders top-level
/// comments and every reply; replies are nested inside the specific comment
/// they answer, preserving AO3's parent-child tree at arbitrary logical depth.
struct CommentThreadRow: View {
    let comment: AO3Comment
    let depth: Int
    let workAuthors: [String]
    let showChapterBadge: Bool
    let highlightedCommentID: Int?
    let onReply: (AO3Comment) -> Void
    let onEdit: (AO3Comment) -> Void
    let onDelete: (AO3Comment) -> Void
    let onCopyLink: (AO3Comment) -> Void
    /// Scrolls to and briefly highlights the given comment id within the
    /// currently-loaded tree — native in-app focus, not an AO3 web page.
    let onFocusThread: (Int) -> Void
    /// Presents the AO3 login sheet (from the disabled-looking "Log in to
    /// Reply" placeholder, which must actually do something when tapped).
    let onRequestLogin: () -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    private var isRoot: Bool { depth == 0 }
    private var isHighlighted: Bool { highlightedCommentID == comment.id }
    private var showsChapterBadgeHere: Bool { showChapterBadge && isRoot }

    private var isByWorkAuthor: Bool {
        workAuthors.contains { $0.caseInsensitiveCompare(comment.author) == .orderedSame }
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
            .overlay(highlightOverlay(cornerRadius: CommentThreadGeometry.rootCornerRadius))
            .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }

    private var nestedCard: some View {
        cardContents
            .padding(CommentThreadGeometry.replyBubblePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme.appTheme.nestedCardSurface,
                in: RoundedRectangle(
                    cornerRadius: CommentThreadGeometry.replyCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: CommentThreadGeometry.replyCornerRadius,
                    style: .continuous
                )
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            }
            .overlay(highlightOverlay(cornerRadius: CommentThreadGeometry.replyCornerRadius))
            .padding(.leading, CommentThreadGeometry.childLeadingInset(forDepth: depth))
            .padding(.trailing, CommentThreadGeometry.replyBubbleTrailingMargin)
            .padding(.bottom, CommentThreadGeometry.replyRowBottomPadding)
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
                CommentAvatar(
                    comment: comment,
                    size: CommentThreadGeometry.avatarSize(forDepth: depth)
                )
                .frame(width: isRoot ? CommentThreadGeometry.avatarColumnWidth : nil)
                commentBody
            }

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: CommentThreadGeometry.childStackSpacing) {
                    ForEach(comment.replies) { reply in
                        CommentThreadRow(
                            comment: reply,
                            depth: depth + 1,
                            workAuthors: workAuthors,
                            showChapterBadge: false,
                            highlightedCommentID: highlightedCommentID,
                            onReply: onReply,
                            onEdit: onEdit,
                            onDelete: onDelete,
                            onCopyLink: onCopyLink,
                            onFocusThread: onFocusThread,
                            onRequestLogin: onRequestLogin
                        )
                    }
                }
                .padding(.top, CommentThreadGeometry.childStackTopPadding)
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
