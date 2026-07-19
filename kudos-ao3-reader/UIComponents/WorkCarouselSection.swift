import SwiftUI

/// A dashboard section used across Home and Library: a header with a collapse
/// toggle and a `>` chevron that opens the full vertical list, over a horizontal
/// card carousel (or a per-section empty state). Collapse state persists per
/// section via `@AppStorage`.
///
/// Per the layout spec: horizontal cards by default, collapsible, and a `>` chevron
/// (not a "See all" button) that opens the full list. Follows the Kudos design
/// philosophy — simple and scannable by default, with depth one tap away.
struct WorkCarouselSection<Cards: View, Empty: View>: View {
    private let title: String
    private let hasItems: Bool
    private let onSeeAll: (() -> Void)?
    private let cards: () -> Cards
    private let emptyState: () -> Empty

    @AppStorage private var collapsed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        collapseKey: String,
        hasItems: Bool,
        onSeeAll: (() -> Void)? = nil,
        @ViewBuilder cards: @escaping () -> Cards,
        @ViewBuilder emptyState: @escaping () -> Empty
    ) {
        self.title = title
        self.hasItems = hasItems
        self.onSeeAll = onSeeAll
        self.cards = cards
        self.emptyState = emptyState
        _collapsed = AppStorage(wrappedValue: false, "section.collapsed.\(collapseKey)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !collapsed {
                if hasItems {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) { cards() }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                } else {
                    emptyState()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            // Tap the title (or its disclosure chevron) to collapse/expand.
            Button {
                withAnimationUnlessReduced(.snappy(duration: 0.22), reduceMotion: reduceMotion) {
                    collapsed.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(title).font(.title2.bold()).foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                }
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel(collapsed ? "Expand \(title)" : "Collapse \(title)")

            Spacer(minLength: 8)

            // The `>` chevron opens the full vertical list (only when there's content).
            if let onSeeAll, hasItems {
                Button(action: onSeeAll) {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .accessibilityLabel("See all \(title)")
            }
        }
        .padding(.horizontal, 16)
    }
}

/// A small, reusable section empty-state label for the carousels.
struct SectionEmptyState: View {
    let message: String
    var systemImage: String = "tray"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}
