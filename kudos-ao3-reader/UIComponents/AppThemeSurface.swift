import SwiftUI

/// App-wide surface theming, driven entirely by `ReaderTheme.appBaseBackground` /
/// `appElevatedBackground`. Light keeps the native system surfaces unchanged;
/// Sepia (which the system has no scheme for) swaps in warm paper backgrounds;
/// Dark and OLED swap in their own dark/true-black surfaces so the app shell
/// matches the reader instead of the system's default near-black.
///
/// Apply `.appThemedScroll()` to a List/Form to theme its background, and
/// `.appThemedRows()` to its rows/sections to theme the cells. Both are no-ops
/// only where the theme's tokens are `nil` (currently just Light).
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

private struct CardShadow {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}

/// Theme-aware surfaces for the modern card-based list treatment, so cards read the
/// same as the grouped style did — just rounded on all four sides. Sepia/Dark/OLED
/// pull from `appBaseBackground`/`appElevatedBackground`; Light falls back to the
/// system grouped surfaces (the only theme where those tokens are `nil`).
/// Internal (not private) so feature-specific card treatments (e.g. the comments
/// thread cards) build on the SAME surfaces instead of inventing near-misses that
/// drift from the Library baseline.
extension ReaderTheme {
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
    /// cards lift off the flatter backdrops; Dark and OLED stay flat (a shadow can't
    /// read against a near-black or true-black backdrop — the high card↔backdrop
    /// contrast there already reads well on its own).
    /// Kept small enough to sit within the inter-card gap so it isn't clipped.
    fileprivate var cardShadow: CardShadow {
        switch self {
        case .dark, .oled: CardShadow(color: .clear, radius: 0, y: 0)
        case .light: CardShadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
        // Warm brown shadow rather than neutral grey, so it reads as paper depth.
        case .sepia:
            CardShadow(
                color: Color(red: 0.34, green: 0.22, blue: 0.08).opacity(0.20),
                radius: 4,
                y: 2
            )
        }
    }

    /// A hairline edge that crisps the card against the flatter Light/Sepia
    /// backdrops (does the bulk of the separation; never clips). None in Dark/OLED,
    /// where the card↔backdrop tonal contrast already does that job.
    var cardBorder: Color {
        switch self {
        case .dark, .oled: .clear
        case .light: Color.black.opacity(0.06)
        case .sepia: Color(red: 0.34, green: 0.22, blue: 0.08).opacity(0.15)
        }
    }

    /// A surface nested INSIDE a `cardSurface` card (the comments thread's reply
    /// bubbles). One elevation step past the card, so the bubble reads distinct in
    /// all three themes: Light/Dark use the system's tertiary grouped level; Sepia
    /// steps back to the paper backdrop for a subtle warm inset.
    var nestedCardSurface: Color {
        if self == .sepia { return cardBackdrop }
        #if os(iOS)
        return Color(uiColor: .tertiarySystemGroupedBackground)
        #else
        return Color(nsColor: .underPageBackgroundColor)
        #endif
    }
}

/// Card-list spacing constants, kept in one place so every adopting list matches.
private enum CardListMetrics {
    static let cornerRadius: CGFloat = 16
    static let interCardSpacing: CGFloat = 12 // vertical gap between cards
    static let sideMargin: CGFloat = 16 // card inset from the screen edges
    static let innerVertical: CGFloat = 10 // padding inside the card (on top of row content)
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
    /// True draws the card's own border in accent color instead of the default
    /// hairline — the selection outline for a row, at its true outer edge (the row's
    /// own background), rather than an inset overlay drawn on the row's content.
    var isSelected: Bool

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
                    // Hairline edge for crisp separation on flat Light/Sepia backdrops —
                    // or the accent-color selection outline, at the same true card edge.
                    .overlay(
                        RoundedRectangle(cornerRadius: CardListMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : theme.appTheme.cardBorder,
                                lineWidth: isSelected ? 2 : 0.5
                            )
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
    func cardList() -> some View {
        modifier(CardList())
    }

    /// Renders a list row (or every row in a `ForEach`/`Section`) as a rounded card
    /// with ~12pt spacing between cards. Keeps taps, swipe actions, etc. intact.
    /// `isSelected` draws the card's own border in accent color instead of the
    /// default hairline — pass this per-row (inside the `ForEach` content, not on
    /// the `ForEach` itself) wherever rows are individually selectable.
    func cardRow(isSelected: Bool = false) -> some View {
        modifier(CardRow(isSelected: isSelected))
    }

    /// Value-based row navigation **without** the trailing disclosure chevron — the
    /// `>` clutters the rounded work cards. The List still makes the whole card
    /// tappable, and inner controls (tag / fandom / expand buttons) keep their own
    /// taps because the link sits behind the content rather than wrapping it.
    func cardNavigation(to value: some Hashable) -> some View {
        background {
            NavigationLink(value: value) { EmptyView() }
                .opacity(0)
        }
    }
}
