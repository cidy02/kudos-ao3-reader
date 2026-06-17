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
