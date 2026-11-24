import SwiftUI
#if os(iOS)
import UIKit
#endif

// T-572 (owner, 2026-11-24): on iPhone the bottom bar is Kudos's own. At rest it is the
// TabBar board (capsule + Search circle, icon + label per tab); scrolling down shrinks the
// WHOLE bar in place (shorter, narrower, labels fade) instead of the system's corner layout.
// The TabView stays the source of truth for selection and navigation stacks.

/// Which layouts draw Kudos's own bar, and how much room it takes.
enum ShrinkingTabBarPolicy {
    /// iPhone at compact width only; iPad, the Duo layouts and macOS keep the system bar.
    static func usesCustomBar(isPhone: Bool, isCompactWidth: Bool, isDuo: Bool) -> Bool {
        isPhone && isCompactWidth && !isDuo
    }

    static let barHeight: CGFloat = 62
    static let shrunkBarHeight: CGFloat = 44
    static let accessoryHeight: CGFloat = 54
    static let gap: CGFloat = 8

    /// How far a pill laid out above the EXPANDED bar must drop to sit on the shrunk one.
    static func pillDrop(isShrunk: Bool) -> CGFloat {
        isShrunk ? barHeight - shrunkBarHeight : 0
    }

    /// The bottom safe-area the bar and mini-player take from every tab's content.
    /// Always the EXPANDED footprint: following the shrunk height would move the
    /// scroll limit while you scroll and flip the bar back and forth at the bottom
    /// of a list (the same feedback `ScrollAwayTopChrome` avoids for its top inset).
    static func contentInset(barHidden: Bool, hasAccessory: Bool) -> CGFloat {
        if barHidden { return 0 }
        return barHeight + gap + (hasAccessory ? accessoryHeight + gap : 0)
    }
}

/// A tap on the already-selected tab; `count` makes repeated taps distinct.
struct TabReselect: Equatable {
    let tab: AppTab
    let count: Int
}

/// Shared by the root shell (draws the bar), the scroll rule (shrinks it) and
/// `tabBarHidden` (hides it).
@Observable
final class TabChromeState {
    var isShrunk = false
    /// True while Kudos's own bar replaces the system one.
    var usesCustomBar = false
    var selectedTab: AppTab = .home
    /// Each tab root's combined `tabBarHidden` preference, read from the live view tree
    /// (so a popped or dismissed screen stops contributing by itself; sheets never reach it).
    private(set) var hiddenByTab: [AppTab: Bool] = [:]
    private(set) var reselect: TabReselect?

    var isBarHidden: Bool { hiddenByTab[selectedTab] ?? false }

    func setHidden(_ hidden: Bool, in tab: AppTab) {
        if (hiddenByTab[tab] ?? false) != hidden { hiddenByTab[tab] = hidden }
    }

    func reselected(_ tab: AppTab) {
        reselect = TabReselect(tab: tab, count: (reselect?.count ?? 0) + 1)
    }
}

/// What every `tabBarHidden` caller contributes; the combined value is "any caller hides it".
struct TabBarHiddenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension TabChromeState {
    /// Only the root tab stacks drive the chrome: anything inside a sheet or cover gets none.
    /// `inRoot` is nil until the probe has looked: a sheet must never touch the root bar first.
    static func scoped(_ chrome: TabChromeState?, inRoot: Bool?) -> TabChromeState? {
        inRoot == true ? chrome : nil
    }
}

/// Only the screen on top of its stack may hide the bar (the system's rule): a screen
/// covered by a push stops contributing and contributes again when it is back on top.
/// A sheet or cover over a screen does not disappear it, so the reader stays hidden behind Comments.
enum TabBarHiddenPolicy {
    static func emitted(hidden: Bool, onScreen: Bool) -> Bool { hidden && onScreen }
}

private struct UsesCustomTabBarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Plain (unscoped) flag: true while Kudos's own bar replaces the system one on this device.
    var usesCustomTabBar: Bool {
        get { self[UsesCustomTabBarKey.self] }
        set { self[UsesCustomTabBarKey.self] = newValue }
    }
}

private struct TabBarHiddenModifier: ViewModifier {
    let hidden: Bool
    @Environment(\.usesCustomTabBar) private var usesCustomBar
    /// Starts true so a screen that mounts already on top hides the bar from its first frame.
    @State private var onScreen = true

    func body(content: Content) -> some View {
        #if os(iOS)
        // The system bar still serves iPad / Duo; on iPhone it is always off.
        content
            .toolbar(hidden || usesCustomBar ? .hidden : .automatic, for: .tabBar)
            .preference(key: TabBarHiddenKey.self, value: TabBarHiddenPolicy.emitted(hidden: hidden, onScreen: onScreen))
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
        #else
        content
        #endif
    }
}

#if os(iOS)
enum TabChromeCover {
    /// True when `view` lives in a presented sheet / cover rather than the root hierarchy.
    static func isModal(_ view: UIView) -> Bool {
        var responder: UIResponder? = view
        while let current = responder, !(current is UIViewController) { responder = current.next }
        guard var controller = responder as? UIViewController else { return false }
        while let parent = controller.parent { controller = parent }
        return controller.presentingViewController != nil
    }
}

private struct ModalProbe: UIViewRepresentable {
    @Binding var inRoot: Bool?

    final class Probe: UIView {
        var onChange: ((Bool) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // The controller chain is only complete once the layout pass has run.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                onChange?(!TabChromeCover.isModal(self))
            }
        }
    }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.onChange = { now in if inRoot != now { inRoot = now } }
    }
}
#endif

/// Hides the chrome environment from everything inside a sheet or cover.
private struct RootChromeScope: ViewModifier {
    @Environment(TabChromeState.self) private var chrome: TabChromeState?
    @State private var inRoot: Bool?

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .environment(TabChromeState.scoped(chrome, inRoot: inRoot))
            .background(ModalProbe(inRoot: $inRoot))
        #else
        content
        #endif
    }
}

extension View {
    /// The one way a screen hides the tab bar (both the system bar and Kudos's own).
    func tabBarHidden(_ hidden: Bool = true) -> some View {
        modifier(TabBarHiddenModifier(hidden: hidden))
    }

    /// Everything inside this view ignores the tab-bar chrome when it sits in a sheet or cover.
    func rootChromeScope() -> some View {
        modifier(RootChromeScope())
    }

    /// For a tab's root: tapping the selected tab again pops its stack to the root, and at
    /// the root scrolls to the top (what the system bar did before T-572).
    func tabReselect(_ tab: AppTab, path: Binding<NavigationPath>) -> some View {
        modifier(TabReselectModifier(tab: tab, path: path))
    }
}

private struct TabReselectModifier: ViewModifier {
    let tab: AppTab
    @Binding var path: NavigationPath
    @Environment(TabChromeState.self) private var chrome: TabChromeState?
    @State private var scrollToken = 0

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .background(ScrollToTopProbe(token: scrollToken))
            .onChange(of: chrome?.reselect) { _, event in
                guard let event, event.tab == tab else { return }
                if path.isEmpty { scrollToken += 1 } else { path = NavigationPath() }
            }
        #else
        content
        #endif
    }
}

/// Pure choices behind scroll-to-top.
enum ScrollToTopPolicy {
    /// A tall vertical scroll view, not a carousel.
    static func qualifies(
        size: CGSize, contentHeight: CGFloat, alwaysBounceVertical: Bool, alwaysBounceHorizontal: Bool = false
    ) -> Bool {
        size.height > 200 && size.width >= size.height * 0.4
            && !(alwaysBounceHorizontal && !alwaysBounceVertical)
            && (alwaysBounceVertical || contentHeight > size.height)
    }

    /// The post-scroll correction only fixes a small miss from the nav bar's return; it never
    /// fights a user who has started scrolling, or has already moved well away from the top.
    /// It runs only if the top inset grew (the nav bar came back): otherwise there is nothing to fix.
    static func shouldSettle(offset: CGFloat, top: CGFloat, initialTop: CGFloat, userIsScrolling: Bool) -> Bool {
        !userIsScrolling && top < initialTop - 1 && offset > top + 1 && offset < top + 160
    }
}

#if os(iOS)
/// Scrolls the page's main scroll view to the top when `token` changes.
/// shortcut: finds the scroll view by walking UIKit (SwiftUI has no handle to a List/ScrollView
/// it did not build with a proxy): up from this view to the enclosing navigation controller,
/// taking the largest tall VERTICAL one; upgrade to `scrollPosition` per root if a screen ever
/// has two competing tall scroll views.
private struct ScrollToTopProbe: UIViewRepresentable {
    let token: Int

    final class Coordinator { var last = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard context.coordinator.last != token else { return }
        context.coordinator.last = token
        var ancestor = view.superview
        var hops = 0
        while let current = ancestor, hops < 40 {
            if let scroll = Self.mainScrollView(in: current) {
                Self.scrollToTop(scroll)
                return
            }
            if current.next is UINavigationController { return }
            ancestor = current.superview
            hops += 1
        }
    }

    private static func scrollToTop(_ scroll: UIScrollView) {
        let reduce = UIAccessibility.isReduceMotionEnabled
        func go(_ animated: Bool) {
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top), animated: animated)
        }
        let initialTop = -scroll.adjustedContentInset.top
        go(!reduce)
        // Scrolling up brings the hidden navigation bar back, which raises the top inset:
        // settle once against the final inset, unless the user has taken over by then.
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduce ? 0.1 : 0.5)) { [weak scroll] in
            guard let scroll else { return }
            let top = -scroll.adjustedContentInset.top
            guard ScrollToTopPolicy.shouldSettle(
                offset: scroll.contentOffset.y,
                top: top,
                initialTop: initialTop,
                userIsScrolling: scroll.isTracking || scroll.isDragging || scroll.isDecelerating
            ) else { return }
            go(false)
        }
    }

    private static func mainScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        var queue = [root]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let scroll = next as? UIScrollView, !scroll.isHidden, scroll.window != nil,
               ScrollToTopPolicy.qualifies(
                   size: scroll.bounds.size,
                   contentHeight: scroll.contentSize.height,
                   alwaysBounceVertical: scroll.alwaysBounceVertical,
                   alwaysBounceHorizontal: scroll.alwaysBounceHorizontal
               ),
               scroll.bounds.height * scroll.bounds.width > (best.map { $0.bounds.height * $0.bounds.width } ?? 0) {
                best = scroll
            }
            queue.append(contentsOf: next.subviews)
        }
        return best
    }
}

/// Gives every tab the bottom room Kudos's own bar takes, the way the system bar's
/// safe area does: an inset on the `UITabBarController` reaches pushed screens too,
/// which a SwiftUI inset outside a `NavigationStack` does not.
struct TabBarContentInset: UIViewRepresentable {
    let inset: CGFloat

    final class Probe: UIView {
        var inset: CGFloat = 0
        private weak var controller: UITabBarController?
        /// Test seam: where the tab controller comes from.
        var controllerProvider: ((UIWindow?) -> UITabBarController?)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            apply()
        }

        func apply() {
            let found = controllerProvider?(window) ?? Self.tabBarController(from: window?.rootViewController)
            if let old = controller, old !== found { old.additionalSafeAreaInsets.bottom = 0 }
            controller = found
            guard let found, found.additionalSafeAreaInsets.bottom != inset else { return }
            found.additionalSafeAreaInsets.bottom = inset
        }

        func reset() {
            controller?.additionalSafeAreaInsets.bottom = 0
            controller = nil
        }

        private static func tabBarController(from root: UIViewController?) -> UITabBarController? {
            guard let root else { return nil }
            if let tabs = root as? UITabBarController { return tabs }
            for child in root.children {
                if let found = tabBarController(from: child) { return found }
            }
            return nil
        }
    }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.inset = inset
        probe.apply()
    }

    static func dismantleUIView(_ probe: Probe, coordinator: ()) {
        probe.reset()
    }
}
#endif

/// The bar itself: capsule of tabs + the Search circle (TabBar board). `isShrunk` shortens
/// and narrows it and fades the labels; every tab stays where it is.
struct ShrinkingTabBar: View {
    let tabs: [AppTab]
    let selection: AppTab
    let isShrunk: Bool
    let onSelect: (AppTab) -> Void

    @Environment(\.accentFill) private var accentFill
    @Environment(\.accentInk) private var accentInk
    @State private var availableWidth: CGFloat = 0

    private var height: CGFloat {
        isShrunk ? ShrinkingTabBarPolicy.shrunkBarHeight : ShrinkingTabBarPolicy.barHeight
    }

    private var barWidth: CGFloat? {
        guard availableWidth > 0 else { return nil }
        // Tab 52 + capsule padding 8 + gap 10 + Search circle.
        let shrunk = CGFloat(tabs.count) * 52 + 8 + 10 + ShrinkingTabBarPolicy.shrunkBarHeight
        return isShrunk ? min(availableWidth, shrunk) : availableWidth
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in tabButton(tab) }
                }
                .padding(.horizontal, 4)
                .frame(height: height)
                .glassEffect(.regular.interactive(), in: .capsule)

                searchButton
            }
            .frame(width: barWidth)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isTabBar)
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .padding(.horizontal, 17)
        .animation(unlessReduced: .easeInOut(duration: 0.22), value: isShrunk)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let selected = selection == tab
        return Button { onSelect(tab) } label: {
            VStack(spacing: isShrunk ? 0 : 2) {
                Image(systemName: selected ? tab.selectedSymbol : tab.symbol)
                    .font(.system(size: 20))
                    .scaleEffect(isShrunk ? 0.9 : 1.15)
                    .frame(height: 24)
                // Fixed size on purpose: the bar never outgrows the board at accessibility
                // sizes; the Large Content Viewer below shows the title instead.
                Text(tab.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .opacity(isShrunk ? 0 : 1)
                    .frame(height: isShrunk ? 0 : 12)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(selected ? accentInk : Color.primary)
            .frame(maxWidth: .infinity)
            // The tap target is the full bar height (44 pt shrunk); only the tint is inset.
            .frame(height: height)
            .background {
                Capsule().fill(selected ? accentFill.opacity(0.10) : .clear).padding(.vertical, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(tab.title, systemImage: tab.symbol)
        }
    }

    private var searchButton: some View {
        let selected = selection == .search
        return Button { onSelect(.search) } label: {
            Image(systemName: AppTab.search.symbol)
                .font(.system(size: 20, weight: .medium))
                .scaleEffect(isShrunk ? 0.9 : 1.15)
                .foregroundStyle(selected ? accentInk : Color.primary)
                .frame(width: height, height: height)
                .background(selected ? accentFill.opacity(0.10) : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(AppTab.search.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(AppTab.search.title, systemImage: AppTab.search.symbol)
        }
    }
}
