import SwiftUI

/// The full, wrapping grid behind a Library entity carousel's "See all" chevron —
/// for carousels of entities (Collections, Reading Queues) rather than works, which
/// have their own `LibrarySectionListView`. Reuses each carousel's existing card
/// views unchanged, just laid out in an adaptive grid instead of a horizontal
/// scroll, so a large Collections/Reading Queues list has a real page to land on
/// instead of growing the carousel indefinitely.
struct LibraryEntityGridView<Item: Identifiable & Hashable, Card: View, NewCard: View>: View {
    let title: String
    let items: [Item]
    let onNew: () -> Void
    @ViewBuilder let card: (Item) -> Card
    @ViewBuilder let newCard: () -> NewCard

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Mirrors the same scaled width the cards themselves render at (see
    /// `ScaledCarouselCardSize`), so the grid's minimum column width tracks a
    /// card that's grown wider with Dynamic Type instead of assuming the
    /// static 164pt base — otherwise a scaled-wide card could overflow a
    /// column the grid sized against the unscaled minimum. Not `private` —
    /// a private stored property forces the compiler's synthesized
    /// memberwise init down to `private` too, breaking every other
    /// (needed) caller-supplied parameter.
    var cardSize = ScaledCarouselCardSize()

    /// Adaptive column count from card width normally; collapses to one column at
    /// accessibility Dynamic Type sizes, where `.adaptive(minimum:)` alone would
    /// still fit two cards by raw pixel width even though their scaled text can't
    /// (see `CarouselCardMetrics.adaptiveCardColumns`).
    private var columns: [GridItem] {
        CarouselCardMetrics.adaptiveCardColumns(for: dynamicTypeSize, minimum: cardSize.width)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                Button(action: onNew) { newCard() }
                    .buttonStyle(.plain)
                ForEach(items) { item in
                    NavigationLink(value: item) { card(item) }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .navigationTitle(title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
