import SwiftUI

/// Owner, 2026-10-01: scrolling down hides the top chrome and scrolling back up
/// (or returning to the top) brings it back, as other apps do. The tab bar's
/// half (T-572) is the same rule below, written to `TabChromeState.isShrunk`, which
/// `ShrinkingTabBar` reads.
///
/// With `isHidden` bound, the caller hides its own chrome (Account floats a gear
/// over a bar-less page) and the navigation bar is left alone.
struct ScrollAwayTopChrome: ViewModifier {
    var external: Binding<Bool>?
    @State private var own = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TabChromeState.self) private var chrome: TabChromeState?

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
                // The tab bar has its own state: tab switches and pushes reset it, and the
                // navigation bar's `own` must not gate it.
                if let chrome {
                    let shrunk = Self.barShrinks(chrome.isShrunk, from: old.offset, to: new.offset, fromTop: new.fromTop)
                    if shrunk != chrome.isShrunk {
                        withAnimationUnlessReduced(.easeInOut(duration: 0.22), reduceMotion: reduceMotion) {
                            chrome.isShrunk = shrunk
                        }
                    }
                }
                let next = Self.hides(isHidden, from: old.offset, to: new.offset, fromTop: new.fromTop)
                guard next != isHidden else { return }
                withAnimationUnlessReduced(.easeInOut(duration: 0.22), reduceMotion: reduceMotion) {
                    if let external { external.wrappedValue = next } else { own = next }
                }
            }
            // Pushing a screen leaves this root; the bar comes back with the new page.
            .onDisappear { chrome?.isShrunk = false }
    }
    #endif

    struct Position: Equatable {
        let offset: CGFloat
        let fromTop: CGFloat
    }

    /// The tab bar's half of the rule. It keeps its own state, apart from the navigation bar's
    /// `hidden`: a tab switch or push resets the bar but leaves the nav bar's flag alone.
    nonisolated static func barShrinks(_ shrunk: Bool, from old: CGFloat, to new: CGFloat, fromTop: CGFloat) -> Bool {
        hides(shrunk, from: old, to: new, fromTop: fromTop)
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

#if os(iOS)
private struct TabBarShrinksOnScroll: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TabChromeState.self) private var chrome: TabChromeState?

    // shortcut: screens combining cardList + subjectScreenWash observe twice (same rule, same
    // state, so harmless). An environment flag to dedupe leaked into pushed destinations
    // declared inside a root and silenced them; upgrade only with a non-inheriting marker.
    func body(content: Content) -> some View {
        observed(content)
    }

    private func observed(_ content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollAwayTopChrome.Position.self) { geometry in
                .init(offset: geometry.contentOffset.y, fromTop: geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { old, new in
                guard let chrome else { return }
                let next = ScrollAwayTopChrome.barShrinks(chrome.isShrunk, from: old.offset, to: new.offset, fromTop: new.fromTop)
                guard next != chrome.isShrunk else { return }
                withAnimationUnlessReduced(.easeInOut(duration: 0.22), reduceMotion: reduceMotion) {
                    chrome.isShrunk = next
                }
            }
            .onDisappear { chrome?.isShrunk = false }
    }
}
#endif

extension View {
    /// A tab root that keeps its navigation bar but still shrinks the tab bar on scroll.
    @ViewBuilder
    func shrinksTabBarOnScroll() -> some View {
        #if os(iOS)
        modifier(TabBarShrinksOnScroll()).rootChromeScope()
        #else
        self
        #endif
    }
}
