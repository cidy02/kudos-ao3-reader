import SwiftUI

/// The full, wrapping grid behind a Library entity carousel's "See all" chevron —
/// for carousels of entities (Collections, Reading Queues) rather than works, which
/// have their own `LibrarySectionListView`. Reuses each carousel's existing card
/// views unchanged, just laid out in an adaptive grid instead of a horizontal
/// scroll, so a large Collections/Reading Queues list has a real page to land on
/// instead of growing the carousel indefinitely.
///
/// `destination` maps each item to the navigation value pushed when its card is
/// tapped — identity for Collections (detail), a browser route for Reading Queues.
struct LibraryEntityGridView<Item: Identifiable, Destination: Hashable, Card: View>: View {
    let title: String
    let items: [Item]
    let destination: (Item) -> Destination
    /// The toolbar's "+" — it was the grid's first cell (owner, 2026-10-01:
    /// global actions live in the top-right chrome).
    let onNew: () -> Void
    @ViewBuilder let card: (Item) -> Card

    @Environment(ThemeManager.self) private var themeManager

    private var tally: String {
        "\(items.count) \(items.count == 1 ? "collection" : "collections")"
    }

    var body: some View {
        ScrollView {
            SubjectPageFact(tally)
                .padding(.top, 12)
            // Collection piles side by side get `coverStackSpacing` (T-461).
            CarouselCardGrid(
                uniformHeights: true,
                columnSpacing: CarouselCardMetrics.coverStackSpacing,
                cardWidth: CarouselCardMetrics.stackWidth
            ) {
                ForEach(items) { item in
                    NavigationLink(value: destination(item)) { card(item) }
                        .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .subjectScreenWash(title: title, palette: themeManager.scopePalette, role: .content)
        .toolbar {
            ActionToolbar(items: [
                AnyView(ToolbarIconButton(title: "New Collection", systemImage: "plus", action: onNew))
            ])
        }
    }
}
