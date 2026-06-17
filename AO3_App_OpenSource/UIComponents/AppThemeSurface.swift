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

    /// Soft elevation under each card. Light/Sepia get a subtle shadow for depth so
    /// cards lift off the flatter backdrops; Dark stays flat (shadows muddy the dark
    /// surfaces, and the high card↔backdrop contrast there already reads well).
    /// Kept small enough to sit within the inter-card gap so it isn't clipped.
    var cardShadow: (color: Color, radius: CGFloat, y: CGFloat) {
        switch self {
        case .dark: (.clear, 0, 0)
        case .light: (Color.black.opacity(0.12), 4, 2)
        // Warm brown shadow rather than neutral grey, so it reads as paper depth.
        case .sepia: (Color(red: 0.34, green: 0.22, blue: 0.08).opacity(0.20), 4, 2)
        }
    }

    /// A hairline edge that crisps the card against the flatter Light/Sepia
    /// backdrops (does the bulk of the separation; never clips). None in Dark.
    var cardBorder: Color {
        switch self {
        case .dark: .clear
        case .light: Color.black.opacity(0.06)
        case .sepia: Color(red: 0.34, green: 0.22, blue: 0.08).opacity(0.15)
        }
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
                    // Hairline edge for crisp separation on flat Light/Sepia backdrops.
                    .overlay(
                        RoundedRectangle(cornerRadius: CardListMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                    )
                    // Subtle elevation (Light/Sepia only).
                    .shadow(color: theme.appTheme.cardShadow.color,
                            radius: theme.appTheme.cardShadow.radius,
                            x: 0, y: theme.appTheme.cardShadow.y)
                    // Inset the fill so adjacent cards leave `interCardSpacing` between
                    // them and `sideMargin` from the screen edges (and leave room for
                    // the shadow within the gap).
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
