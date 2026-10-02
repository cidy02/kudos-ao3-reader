import SwiftUI

/// Owner, 2026-10-01: scrolling down hides the top chrome and scrolling back up
/// (or returning to the top) brings it back, as other apps do. The tab bar's
/// half is `tabBarMinimizeBehavior(.onScrollDown)` on the root `TabView`.
///
/// With `isHidden` bound, the caller hides its own chrome (Account floats a gear
/// over a bar-less page) and the navigation bar is left alone.
struct ScrollAwayTopChrome: ViewModifier {
    var external: Binding<Bool>?
    @State private var own = false

    private var isHidden: Bool { external?.wrappedValue ?? own }

    func body(content: Content) -> some View {
        #if os(iOS)
        if external == nil {
            observed(content).toolbarVisibility(isHidden ? .hidden : .visible, for: .navigationBar)
        } else {
            observed(content)
        }
        #else
        content
        #endif
    }

    #if os(iOS)
    private func observed(_ content: Content) -> some View {
        content
            // Direction from the raw offset: only scrolling moves it. Hiding the
            // bar changes the top inset, and an inset-based reading fed that back
            // as a scroll and toggled the bar forever at the bottom of a list.
            .onScrollGeometryChange(for: Position.self) { geometry in
                Position(
                    offset: geometry.contentOffset.y,
                    fromTop: geometry.contentOffset.y + geometry.contentInsets.top
                )
            } action: { old, new in
                let next = Self.hides(isHidden, from: old.offset, to: new.offset, fromTop: new.fromTop)
                guard next != isHidden else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    if let external { external.wrappedValue = next } else { own = next }
                }
            }
    }
    #endif

    struct Position: Equatable {
        let offset: CGFloat
        let fromTop: CGFloat
    }

    /// Hides once you scroll down past the bar's own height; any deliberate
    /// upward scroll, or being back near the top, shows it again.
    nonisolated static func hides(_ hidden: Bool, from old: CGFloat, to new: CGFloat, fromTop: CGFloat) -> Bool {
        if fromTop <= 44 { return false }
        let delta = new - old
        if delta > 1 { return true }
        if delta < -6 { return false }
        return hidden
    }
}

extension View {
    /// For a tab's root scroll view (see `ScrollAwayTopChrome`).
    func scrollAwayTopChrome(isHidden: Binding<Bool>? = nil) -> some View {
        modifier(ScrollAwayTopChrome(external: isHidden))
    }
}
