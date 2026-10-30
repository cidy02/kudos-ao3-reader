#if os(iOS)
import SwiftUI

/// The end of a work (board 34). Give Kudos is the full-width action; Comment
/// and Bookmark sit side by side under it. All three call actions the reader
/// already had. There is no new AO3 request here.
struct ReaderEndCard: View {
    let title: String
    /// Kudos and Comment exist only for a work that has an AO3 page.
    var showsAO3Actions: Bool
    var kudosGiven: Bool
    var kudosEnabled: Bool
    var isBookmarked: Bool
    var bookmarkEnabled: Bool
    var onKudos: () -> Void
    var onComment: () -> Void
    var onBookmark: () -> Void

    @Environment(\.accentFill) private var fill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The End")
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)

            if showsAO3Actions {
                Button(action: onKudos) {
                    Text(kudosGiven ? "Kudos given" : "Give Kudos")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ThemeManager.label(on: fill))
                .background(fill, in: SubjectMetrics.controlShape(dynamicTypeSize))
                .disabled(!kudosEnabled)
                .accessibilityLabel(kudosGiven ? "Kudos given" : "Give Kudos")
            }

            secondaryActions
        }
        .padding(16)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    /// Side by side at the sizes where both labels fit. At the accessibility
    /// sizes they stack, so neither title is cut.
    @ViewBuilder
    private var secondaryActions: some View {
        let laidOut = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        laidOut {
            if showsAO3Actions {
                secondaryButton(
                    title: "Comment",
                    systemImage: "bubble.left",
                    label: "Comment",
                    action: onComment
                )
            }
            secondaryButton(
                title: isBookmarked ? "Bookmarked" : "Bookmark",
                systemImage: isBookmarked ? "bookmark.fill" : "bookmark",
                label: isBookmarked ? "Remove bookmark" : "Add bookmark",
                enabled: bookmarkEnabled,
                action: onBookmark
            )
        }
    }

    private func secondaryButton(
        title: String,
        systemImage: String,
        label: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.accentInk)
        .background(Color.primary.opacity(0.06), in: SubjectMetrics.controlShape(dynamicTypeSize))
        .disabled(!enabled)
        .minimumHitTarget()
        .accessibilityLabel(label)
    }
}
#endif
