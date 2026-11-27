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
    /// "Chapter 15 of 30 is the latest · updated Nov 3, 2026": WIP only (Reader-CaughtUp).
    var latestChapterLine: String? = nil
    /// The downloaded EPUB holds fewer chapters than AO3 has posted: its end is not "caught up".
    var copyBehind: Bool = false
    /// Cap on the card's height (the reader passes what the screen can spare). Past it the content
    /// scrolls inside the card, so no action is ever off-screen at a large text size.
    var maxHeight: CGFloat? = nil
    /// Offers Subscribe on a WIP (needs an AO3 page, like Kudos). Once subscribed the filled
    /// button becomes Give Kudos and Subscribe moves into the row as "Subscribed".
    var offersSubscribe: Bool = false
    var isSubscribed: Bool = false
    var subscribeEnabled: Bool = true
    var onSubscribe: () -> Void = {}
    var onKudos: () -> Void = {}
    var onComment: () -> Void = {}
    var onBookmark: () -> Void = {}
    var onStartNextWork: ((SavedWork) -> Void)? = nil

    @Environment(\.accentFill) private var fill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var headingSize: CGFloat = 30

    private var content: some View {
        VStack(spacing: 14) {
            headerBlock

            actionsBlock

            if let upNext {
                Divider()
                    .padding(.vertical, 2)

                upNextBlock(upNext)
            }
        }
    }

    var body: some View {
        Group {
            if let maxHeight {
                // Content that fits shows as is; anything taller scrolls inside the card.
                ReaderContentCappedScroll(maxHeight: maxHeight) { content }
            } else {
                content
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
        .accessibilityLabel(ReaderEndOfWorkFacts.heading(isComplete: isComplete, copyBehind: copyBehind))
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(ReaderEndOfWorkFacts.heading(isComplete: isComplete, copyBehind: copyBehind))
                .font(.system(size: headingSize, weight: .semibold, design: .serif))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)

            if let latestChapterLine {
                Text(latestChapterLine)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .multilineTextAlignment(.center)
            }

            if let subtitle = ReaderEndOfWorkFacts.subtitle(
                durationSeconds: durationSeconds,
                isFinished: isFinished
            ) {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    /// Subscribe is the one filled button until it is done; then Give Kudos takes its place.
    private var showsSubscribeButton: Bool { offersSubscribe && showsAO3Actions && !isSubscribed }

    private var actionsBlock: some View {
        VStack(spacing: 10) {
            if showsSubscribeButton {
                subscribeButton
            } else if showsAO3Actions {
                kudosButton
            }

            secondaryActions

            if showsSubscribeButton {
                Text("Subscribed works show new chapters on Home.")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var subscribeButton: some View {
        Button(action: onSubscribe) {
            HStack(spacing: 8) {
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .semibold))
                Text("Subscribe")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ThemeManager.label(on: fill))
        .background(fill, in: SubjectMetrics.controlShape(dynamicTypeSize))
        .disabled(!subscribeEnabled)
        .minimumHitTarget()
        .accessibilityLabel("Subscribe")
    }

    private var kudosButton: some View {
        Button(action: onKudos) {
            HStack(spacing: 8) {
                Image(systemName: kudosGiven ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .semibold))
                Text(ReaderEndCopy.kudosButtonTitle(given: kudosGiven))
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
        .accessibilityLabel(ReaderEndCopy.kudosButtonTitle(given: kudosGiven))
    }

    @ViewBuilder
    private var secondaryActions: some View {
        let isAccessibility = dynamicTypeSize.isAccessibilitySize
        // Three across (Kudos, Comment, Bookmark / Subscribed, Comment, Bookmark) is tighter:
        // the board drops those labels a step.
        let threeAcross = offersSubscribe && showsAO3Actions
        let laidOut = isAccessibility
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: threeAcross ? 8 : 10))
        let font: Font = threeAcross ? .footnote.weight(.semibold) : .callout.weight(.semibold)

        laidOut {
            if showsSubscribeButton {
                ReaderEndSecondaryButton(
                    title: "Kudos",
                    systemImage: kudosGiven ? "heart.fill" : "heart",
                    label: ReaderEndCopy.kudosButtonTitle(given: kudosGiven),
                    font: font,
                    isEnabled: kudosEnabled && !kudosGiven,
                    isSelected: kudosGiven,
                    isCompact: threeAcross,
                    action: onKudos
                )
            } else if offersSubscribe && showsAO3Actions && isSubscribed {
                ReaderEndSecondaryButton(
                    title: "Subscribed",
                    systemImage: "bell.fill",
                    label: "Subscribed. Double tap to unsubscribe",
                    font: font,
                    isEnabled: subscribeEnabled,
                    isSelected: true,
                    isCompact: threeAcross,
                    action: onSubscribe
                )
            }
            if showsAO3Actions {
                ReaderEndSecondaryButton(
                    title: "Comment",
                    systemImage: "bubble.left",
                    label: "Comment",
                    font: font,
                    isCompact: threeAcross,
                    action: onComment
                )
            }
            ReaderEndSecondaryButton(
                title: isBookmarked ? "Bookmarked" : "Bookmark",
                systemImage: isBookmarked ? "bookmark.fill" : "bookmark",
                label: isBookmarked ? "Remove bookmark" : "Add bookmark",
                font: font,
                isEnabled: bookmarkEnabled,
                isSelected: isBookmarked,
                isCompact: threeAcross,
                action: onBookmark
            )
        }
    }

    // MARK: - Up next in queue

    private func upNextBlock(_ upNext: (queueName: String, nextWork: SavedWork)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Up next in \(upNext.queueName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondaryInk)

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
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
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
            .background(Color.primary.opacity(0.07), in: SubjectMetrics.controlShape(dynamicTypeSize))
    }
}

/// The neutral pill under an end card's filled button (Comment, Bookmark, Subscribed, Kudos).
/// Shared by the end-of-work and end-of-chapter cards so the two cannot drift.
struct ReaderEndSecondaryButton: View {
    let title: String
    let systemImage: String
    let label: String
    var font: Font = .callout.weight(.semibold)
    var isEnabled: Bool = true
    var isSelected: Bool = false
    var isCompact: Bool = false
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: isCompact ? 5 : 7) {
                Image(systemName: systemImage)
                    .font(.system(size: isCompact ? 17 : 18, weight: .semibold))
                Text(title)
                    .font(font)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AnyShapeStyle(.accentInk) : AnyShapeStyle(.primary))
        .background(Color.primary.opacity(0.07), in: SubjectMetrics.controlShape(dynamicTypeSize))
        .disabled(!isEnabled)
        .minimumHitTarget()
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Plain content at ordinary sizes; at accessibility text sizes or a short (compact-height)
/// screen the content scrolls inside a card capped at `maxHeight`, so no action is ever
/// off-screen. (Measured-height and `ViewThatFits` variants both misrendered, so the plain
/// path is untouched at ordinary sizes.)
struct ReaderContentCappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize || verticalSizeClass == .compact {
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: maxHeight)
        } else {
            content
        }
    }
}
