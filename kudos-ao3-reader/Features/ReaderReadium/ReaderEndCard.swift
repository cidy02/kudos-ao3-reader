import SwiftData
import SwiftUI

/// The end of a work (board 34, T-496).
///
/// Complete: "The End", the title, "Read in 1 h 20 min · moved to Finished" (when finished),
/// Give Kudos (with a given state), Comment, Bookmark, then "Up next in <queue>" with Start.
/// WIP: "You're caught up", the title, "Read in 1 h 20 min", Give Kudos, Comment, Bookmark.
struct ReaderEndCard: View {
    let title: String
    var isComplete: Bool = true
    /// Logged reading time, computed once by the reader on arrival (never fetched in `body`).
    var durationSeconds: Double = 0
    var isFinished: Bool = false
    /// Kudos and Comment exist only for a work that has an AO3 page.
    var showsAO3Actions: Bool = true
    var kudosGiven: Bool = false
    var kudosEnabled: Bool = true
    var isBookmarked: Bool = false
    var bookmarkEnabled: Bool = true
    var upNext: (queueName: String, nextWork: SavedWork)? = nil
    var onKudos: () -> Void = {}
    var onComment: () -> Void = {}
    var onBookmark: () -> Void = {}
    var onStartNextWork: ((SavedWork) -> Void)? = nil

    @Environment(\.accentFill) private var fill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var headingSize: CGFloat = 30

    var body: some View {
        VStack(spacing: 14) {
            headerBlock

            actionsBlock

            if let upNext {
                Divider()
                    .padding(.vertical, 2)

                upNextBlock(upNext)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ReaderEndOfWorkFacts.heading(isComplete: isComplete))
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(ReaderEndOfWorkFacts.heading(isComplete: isComplete))
                .font(.system(size: headingSize, weight: .semibold, design: .serif))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = ReaderEndOfWorkFacts.subtitle(
                durationSeconds: durationSeconds,
                isFinished: isFinished
            ) {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private var actionsBlock: some View {
        VStack(spacing: 10) {
            if showsAO3Actions {
                kudosButton
            }

            secondaryActions
        }
    }

    private var kudosButton: some View {
        Button(action: onKudos) {
            HStack(spacing: 8) {
                Image(systemName: kudosGiven ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .semibold))
                Text(kudosGiven ? "Kudos given" : "Give Kudos")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ThemeManager.label(on: fill))
        .background(fill, in: SubjectMetrics.controlShape(dynamicTypeSize))
        .disabled(!kudosEnabled || kudosGiven)
        .minimumHitTarget()
        .accessibilityLabel(kudosGiven ? "Kudos given" : "Give Kudos")
    }

    @ViewBuilder
    private var secondaryActions: some View {
        let isAccessibility = dynamicTypeSize.isAccessibilitySize
        let laidOut = isAccessibility
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
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.accentInk)
        .background(Color.primary.opacity(0.06), in: SubjectMetrics.controlShape(dynamicTypeSize))
        .disabled(!enabled)
        .minimumHitTarget()
        .accessibilityLabel(label)
    }

    // MARK: - Up next in queue

    private func upNextBlock(_ upNext: (queueName: String, nextWork: SavedWork)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Up next in \(upNext.queueName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // One row at every size so the card stays compact at accessibility sizes.
            HStack(spacing: 10) {
                WorkStatusIconGrid(
                    rating: upNext.nextWork.rating.isEmpty ? nil : upNext.nextWork.rating,
                    categories: upNext.nextWork.workCategories,
                    warnings: upNext.nextWork.workWarnings,
                    completion: upNext.nextWork.completionStatus,
                    tileSize: 17,
                    announcesToVoiceOver: true,
                    backed: true
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(upNext.nextWork.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    let meta = ReaderEndOfWorkFacts.nextWorkMeta(
                        author: upNext.nextWork.author,
                        wordCount: upNext.nextWork.wordCount
                    )
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                startNextWorkButton(for: upNext.nextWork)
            }
        }
    }

    @ViewBuilder
    private func startNextWorkButton(for nextWork: SavedWork) -> some View {
        if let onStartNextWork {
            Button(action: { onStartNextWork(nextWork) }) {
                startBadge
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Start reading \(nextWork.title)")
        }
    }

    private var startBadge: some View {
        Text("Start")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.accentInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .background(Color.primary.opacity(0.06), in: SubjectMetrics.controlShape(dynamicTypeSize))
    }
}
