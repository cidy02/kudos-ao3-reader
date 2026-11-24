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

    /// The bottom safe-area the bar and mini-player take from every tab's content.
    /// Always the EXPANDED footprint: following the shrunk height would move the
    /// scroll limit while you scroll and flip the bar back and forth at the bottom
    /// of a list (the same feedback `ScrollAwayTopChrome` avoids for its top inset).
    static func contentInset(barHidden: Bool, hasAccessory: Bool) -> CGFloat {
        if barHidden { return 0 }
        return barHeight + gap + (hasAccessory ? accessoryHeight + gap : 0)
    }
}

/// Every screen that wants the bar gone registers here; the bar is hidden while any does.
/// Each caller is keyed by the tab it lives in, so a screen in another tab's stack can
/// never hide the bar of the tab on screen.
struct TabBarHiders: Equatable {
    private(set) var tabs: [UUID: AppTab] = [:]

    func isHidden(in tab: AppTab) -> Bool { tabs.values.contains(tab) }

    mutating func set(_ hidden: Bool, by id: UUID, in tab: AppTab) {
        if hidden { tabs[id] = tab } else { tabs[id] = nil }
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
    private(set) var hiders = TabBarHiders()
    private(set) var reselect: TabReselect?

    var isBarHidden: Bool { hiders.isHidden(in: selectedTab) }

    func setHidden(_ hidden: Bool, by id: UUID, in tab: AppTab) {
        var next = hiders
        next.set(hidden, by: id, in: tab)
        if next != hiders { hiders = next }
    }

    func reselected(_ tab: AppTab) {
        reselect = TabReselect(tab: tab, count: (reselect?.count ?? 0) + 1)
    }
}

private struct ChromeTabKey: EnvironmentKey {
    static let defaultValue: AppTab? = nil
}

extension EnvironmentValues {
    /// The tab whose content this view is in (set by the iPhone shell).
    var chromeTab: AppTab? {
        get { self[ChromeTabKey.self] }
        set { self[ChromeTabKey.self] = newValue }
    }
}

private struct TabBarHiddenModifier: ViewModifier {
    let hidden: Bool
    @Environment(TabChromeState.self) private var chrome: TabChromeState?
    @Environment(\.chromeTab) private var tab
    @State private var id = UUID()
    /// Only a screen that is on screen may hide the bar: a copy still mounted in another
    /// tab's stack (or behind a sheet) sees `hidden` change too, and must not leak it.
    @State private var isVisible = false

    private func register(_ now: Bool) {
        if let tab { chrome?.setHidden(now, by: id, in: tab) }
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        // The system bar still serves iPad / Duo; on iPhone it is always off.
        let base = content.toolbar(hidden || chrome?.usesCustomBar == true ? .hidden : .automatic, for: .tabBar)
        #else
        let base = content
        #endif
        base
            .onAppear { isVisible = true; register(hidden) }
            .onChange(of: hidden) { _, now in if isVisible { register(now) } }
            .onDisappear { isVisible = false; register(false) }
    }
}

extension View {
    /// The one way a screen hides the tab bar (both the system bar and Kudos's own).
    func tabBarHidden(_ hidden: Bool = true) -> some View {
        modifier(TabBarHiddenModifier(hidden: hidden))
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
        let animated = !UIAccessibility.isReduceMotionEnabled
        func go(_ animated: Bool) {
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top), animated: animated)
        }
        go(animated)
        // Scrolling up brings the hidden navigation bar back, which raises the top inset:
        // settle once against the final inset so the title is not left under the bar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak scroll] in
            guard let scroll, scroll.contentOffset.y > -scroll.adjustedContentInset.top + 1 else { return }
            go(false)
        }
    }

    private static func mainScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        var queue = [root]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let scroll = next as? UIScrollView, !scroll.isHidden, scroll.window != nil,
               scroll.bounds.height > 200, scroll.bounds.width >= scroll.bounds.height * 0.4,
               scroll.alwaysBounceVertical || scroll.contentSize.height > scroll.bounds.height,
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
        /// The keyboard covers the bar (as it does the system bar), so no inset while it is up.
        private var keyboardUp = false
        private var observers: [NSObjectProtocol] = []

        override init(frame: CGRect) {
            super.init(frame: frame)
            let center = NotificationCenter.default
            observers = [
                (UIResponder.keyboardWillShowNotification, true),
                (UIResponder.keyboardWillHideNotification, false),
            ].map { name, up in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.keyboardUp = up
                    self?.apply()
                }
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        // The controller can attach after this view does, or be rebuilt (`.id` on the
        // TabView): re-apply on every layout and window change instead of once.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            apply()
        }

        func apply() {
            let found = Self.tabBarController(from: window?.rootViewController)
            if let old = controller, old !== found { old.additionalSafeAreaInsets.bottom = 0 }
            controller = found
            let wanted = keyboardUp ? 0 : inset
            guard let found, found.additionalSafeAreaInsets.bottom != wanted else { return }
            found.additionalSafeAreaInsets.bottom = wanted
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
