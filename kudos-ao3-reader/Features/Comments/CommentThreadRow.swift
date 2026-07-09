import SwiftUI

/// A lightweight bubble background for one flattened comment row. Replies get a
/// capped indent and a guide line, while every comment remains an independent
/// lazy List row instead of recursively instantiating its descendants.
private struct CommentBubbleRowModifier: ViewModifier {
    let depth: Int

    @Environment(ThemeManager.self) private var theme

    private var indent: CGFloat { CGFloat(min(depth, 3)) * 18 }

    func body(content: Content) -> some View {
        content
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.appTheme.carouselCardSurface)
                    .overlay {
                        if depth > 0 {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.accentColor.opacity(0.025))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.appTheme.carouselCardBorder(hue: nil), lineWidth: 0.5)
            }
            .padding(.leading, indent)
            .overlay(alignment: .leading) {
                if depth > 0 {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.30))
                        .frame(width: 2)
                        .padding(.leading, max(0, indent - 10))
                        .padding(.vertical, 4)
                }
            }
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

extension View {
    func commentBubbleRow(depth: Int) -> some View {
        modifier(CommentBubbleRowModifier(depth: depth))
    }
}

/// One stable, shallow row from `CommentsModel.displayRows`.
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

    private var comment: AO3Comment { row.comment }

    private var isByWorkAuthor: Bool {
        workAuthors.contains { $0.caseInsensitiveCompare(comment.author) == .orderedSame }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(comment: comment, size: row.depth == 0 ? 40 : 34)

            VStack(alignment: .leading, spacing: 7) {
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
/// theme-safe placeholder. `AsyncImage` uses the shared URL loading/cache stack
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
        .background(Color.accentColor.opacity(0.10), in: Circle())
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.accentColor.opacity(0.14), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.43, weight: .medium))
            .foregroundStyle(Color.accentColor.opacity(0.78))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
