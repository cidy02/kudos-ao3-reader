import SwiftUI

/// Semantic status/role colors, keyed by `ReaderTheme` exactly like the card and
/// carousel tokens in `AppThemeSurface.swift` / `CarouselCardStyle.swift` — so call
/// sites stop hardcoding `.red`/`.yellow`/`.green` (which don't adapt to Sepia's
/// warm palette or OLED's true-black contrast needs) and instead read a themed role
/// that can be retuned per theme without touching call sites.
extension ReaderTheme {
    /// Destructive/error state: failed session, validation error, delete
    /// confirmation. Warmer and less saturated on Sepia to avoid a cold system red
    /// clashing with the paper palette; lighter on Dark/OLED to hold contrast
    /// against near-black/true-black backdrops.
    var errorColor: Color {
        switch self {
        case .light: Color(red: 0.80, green: 0.15, blue: 0.15)
        case .sepia: Color(red: 0.62, green: 0.20, blue: 0.14)
        case .dark, .oled: Color(red: 0.95, green: 0.38, blue: 0.38)
        }
    }

    /// The "exclude" state in Search's three-state tag/filter cycle
    /// (`FilterSelectionState.excluded`). Kept as its own named role rather than
    /// every call site reusing `errorColor` directly: exclude is a deliberate filter
    /// choice, not a failure, so the two are free to diverge later without a rename
    /// at every call site.
    var excludeColor: Color { errorColor }

    /// The favorite/starred-work indicator (Library star, Work Detail favorite
    /// toggle). Desaturated on Sepia so it doesn't fight the warm paper backdrop;
    /// slightly lighter on Dark/OLED for contrast.
    var favoriteColor: Color {
        switch self {
        case .light: Color(red: 0.90, green: 0.65, blue: 0.05)
        case .sepia: Color(red: 0.72, green: 0.52, blue: 0.10)
        case .dark, .oled: Color(red: 1.00, green: 0.78, blue: 0.20)
        }
    }

    /// Positive/success status: healthy session, replied-to comment, saved
    /// confirmation. Olive-leaning on Sepia so it reads on cream rather than a
    /// clinical system green.
    var statusSuccessColor: Color {
        switch self {
        case .light: Color(red: 0.20, green: 0.55, blue: 0.25)
        case .sepia: Color(red: 0.35, green: 0.50, blue: 0.20)
        case .dark, .oled: Color(red: 0.40, green: 0.78, blue: 0.45)
        }
    }
}
