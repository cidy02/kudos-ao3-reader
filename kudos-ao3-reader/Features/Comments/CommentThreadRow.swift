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
            }
            .listRowInsets(EdgeInsets(
                top: isFirst ? 6 : 0, leading: 16,
                bottom: isLastInThread ? 6 : 0, trailing: 16
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

extension View {
    func commentThreadGroupRow(depth: Int, isLastInThread: Bool) -> some View {
        modifier(CommentThreadGroupRowModifier(depth: depth, isLastInThread: isLastInThread))
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
    let onOpenURL: (URL) -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    private var comment: AO3Comment { row.comment }
    private var isReplyRow: Bool { row.depth > 0 }
    /// Nested indent inside the thread card, capped so long AO3 comments keep a
    /// readable measure on phone widths.
    private var bubbleIndent: CGFloat { CGFloat(min(row.depth, 3) - 1) * 14 }

    private var isByWorkAuthor: Bool {
        workAuthors.contains { $0.caseInsensitiveCompare(comment.author) == .orderedSame }
    }

    var body: some View {
        if isReplyRow {
            // Reply bubble: its own soft surface one elevation step inside the
            // card, guided by a subtle (never red) connector line. The connector
            // is an overlay — an HStack sibling shape would collapse to its 10pt
            // ideal height under a List row's nil height proposal.
            commentContent
                .padding(10)
                .background(
                    theme.appTheme.nestedCardSurface,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.quaternary)
                        .frame(width: 2)
                }
                .padding(.leading, bubbleIndent)
        } else {
            commentContent
        }
    }

    private var commentContent: some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(comment: comment, size: isReplyRow ? 30 : 38)

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
        HStack(spacing: 8) {
            if !comment.postedText.isEmpty {
                Text(comment.postedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if comment.canReply && auth.isLoggedIn {
                Button { onReply(comment) } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.caption.weight(.medium))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reply to \(comment.author)")
            }
            Menu {
                if comment.canReply && auth.isLoggedIn {
                    Button { onReply(comment) } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                } else if comment.canReply {
                    Button {} label: {
                        Label("Log in to Reply", systemImage: "person.crop.circle.badge.questionmark")
                    }
                    .disabled(true)
                }
                if comment.editPath != nil {
                    Button { onEdit(comment) } label: {
                        Label("Edit Comment", systemImage: "pencil")
                    }
                }
                Button { onCopyLink(comment) } label: {
                    Label("Copy Link", systemImage: "link")
                }
                if let url = comment.threadActionURL {
                    Button { onOpenURL(url) } label: {
                        Label("Thread", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                if let url = comment.parentThreadURL {
                    Button { onOpenURL(url) } label: {
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
