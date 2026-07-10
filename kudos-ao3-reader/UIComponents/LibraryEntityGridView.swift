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

    private let columns = [GridItem(.adaptive(minimum: CarouselCardMetrics.width), spacing: 16)]

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
