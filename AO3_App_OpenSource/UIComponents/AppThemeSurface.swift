import SwiftUI

/// App-wide surface theming for the Sepia theme. Light and Dark use the native
/// system surfaces unchanged; Sepia (which the system has no scheme for) swaps in
/// warm backgrounds so pages, lists, and forms match the reader's sepia paper.
///
/// Apply `.appThemedScroll()` to a List/Form to warm its background, and
/// `.appThemedRows()` to its rows/sections to warm the cells. Both are no-ops in
/// Light and Dark.
private struct AppThemedScroll: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    func body(content: Content) -> some View {
        if let base = theme.appTheme.appBaseBackground {
            content
                .scrollContentBackground(.hidden)
                .background(base.ignoresSafeArea())
        } else {
            content
        }
    }
}

private struct AppThemedRows: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    func body(content: Content) -> some View {
        if let cell = theme.appTheme.appElevatedBackground {
            content.listRowBackground(cell)
        } else {
            content
        }
    }
}

extension View {
    /// Warms a List/Form's background for the app's Sepia theme (no-op in Light/Dark).
    func appThemedScroll() -> some View {
        modifier(AppThemedScroll())
    }

    /// Warms List/Form rows (cells) for Sepia. Apply to the rows, a ForEach, or a
    /// Section inside a List/Form (no-op in Light/Dark).
    func appThemedRows() -> some View {
        modifier(AppThemedRows())
    }
}

// MARK: - Card-style lists (experimental)

/// Theme-aware surfaces for the modern card-based list treatment. Sepia reuses the
/// reader's warm paper colors; Light/Dark fall back to the system grouped surfaces,
/// so cards read the same as the grouped style did — just rounded on all four sides.
private extension ReaderTheme {
    /// The page behind the cards.
    var cardBackdrop: Color {
        #if os(iOS)
        appBaseBackground ?? Color(uiColor: .systemGroupedBackground)
        #else
        appBaseBackground ?? Color(nsColor: .underPageBackgroundColor)
        #endif
    }

    /// The elevated card surface itself.
    var cardSurface: Color {
        #if os(iOS)
        appElevatedBackground ?? Color(uiColor: .secondarySystemGroupedBackground)
        #else
        appElevatedBackground ?? Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

/// Card-list spacing constants, kept in one place so every adopting list matches.
private enum CardListMetrics {
    static let cornerRadius: CGFloat = 16
    static let interCardSpacing: CGFloat = 12   // vertical gap between cards
    static let sideMargin: CGFloat = 16         // card inset from the screen edges
    static let innerVertical: CGFloat = 10      // padding inside the card (on top of row content)
    static let innerHorizontal: CGFloat = 16
}

/// Makes a List render as plain (ungrouped) over the themed backdrop, so each row's
/// `.cardRow()` background reads as a free-standing card.
private struct CardList: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.appTheme.cardBackdrop.ignoresSafeArea())
    }
}

/// Turns a List row into a fully-rounded card with consistent spacing. The card is
/// the row's background (inset to create the gap between cards); row insets add the
/// inner padding. Applies to a row, a `ForEach`, or a `Section`.
private struct CardRow: ViewModifier {
    @Environment(ThemeManager.self) private var theme

    func body(content: Content) -> some View {
        let half = CardListMetrics.interCardSpacing / 2
        content
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: half + CardListMetrics.innerVertical,
                leading: CardListMetrics.sideMargin + CardListMetrics.innerHorizontal,
                bottom: half + CardListMetrics.innerVertical,
                trailing: CardListMetrics.sideMargin + CardListMetrics.innerHorizontal
            ))
            .listRowBackground(
                RoundedRectangle(cornerRadius: CardListMetrics.cornerRadius, style: .continuous)
                    .fill(theme.appTheme.cardSurface)
                    // Inset the fill so adjacent cards leave `interCardSpacing` between
                    // them and `sideMargin` from the screen edges.
                    .padding(EdgeInsets(
                        top: half, leading: CardListMetrics.sideMargin,
                        bottom: half, trailing: CardListMetrics.sideMargin
                    ))
            )
    }
}

extension View {
    /// Plain, card-style list over the themed backdrop. Pair with `.cardRow()` on rows.
    func cardList() -> some View { modifier(CardList()) }

    /// Renders a list row (or every row in a `ForEach`/`Section`) as a rounded card
    /// with ~12pt spacing between cards. Keeps taps, swipe actions, etc. intact.
    func cardRow() -> some View { modifier(CardRow()) }
}
