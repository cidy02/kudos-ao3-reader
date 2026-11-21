import SwiftUI

/// Which logical edge of a Duo split pane faces the fold, so horizontal carousels
/// mask right at the fold clearance while outer edges keep their 16 pt screen margin.
nonisolated enum DuoPaneFoldEdge: Equatable, Sendable {
    case none
    case leading
    case trailing
}

extension EnvironmentValues {
    @Entry var duoPaneFoldEdge: DuoPaneFoldEdge = .none
    @Entry var duoScrollAnchorContext: DuoScrollAnchorContext?
}

// MARK: - Scroll anchor preservation across fold / rotation layout swaps

nonisolated enum DuoScrollLayoutMode: Equatable, Sendable {
    case fallback
    case openSplit
    case bookSplit
}

nonisolated enum DuoScrollPane: Equatable, Sendable {
    case shared
    case leading
    case trailing
}

nonisolated struct DuoScrollAnchorRect: Equatable, Sendable {
    let minY: CGFloat
    let maxY: CGFloat
}

nonisolated struct DuoScrollRestoreTargets: Equatable, Sendable {
    var shared: String?
    var leading: String?
    var trailing: String?
}

/// Pure, testable scroll-anchor state kept above layout branch swaps (Open ↔ Book ↔
/// Upright / Cover / inspector-open fallback) so folding or rotating restores the
/// reader's visible section instead of snapping back to the top.
nonisolated struct DuoScrollAnchorState: Equatable, Sendable {
    var leadingFrames: [String: DuoScrollAnchorRect] = [:]
    var trailingFrames: [String: DuoScrollAnchorRect] = [:]
    var sharedFrames: [String: DuoScrollAnchorRect] = [:]

    var sharedAnchor: String?
    var leadingAnchor: String?
    var trailingAnchor: String?
    var lastInteractedBookPane: DuoScrollPane = .leading
    var lastMode: DuoScrollLayoutMode?

    mutating func recordFrame(_ rect: DuoScrollAnchorRect, for id: String, pane: DuoScrollPane) {
        switch pane {
        case .shared:
            sharedFrames[id] = rect
        case .leading:
            leadingFrames[id] = rect
            sharedFrames[id] = rect
        case .trailing:
            trailingFrames[id] = rect
            sharedFrames[id] = rect
        }
    }

    mutating func recordScroll(
        fromTop: CGFloat,
        previousFromTop: CGFloat,
        pane: DuoScrollPane,
        mode: DuoScrollLayoutMode
    ) {
        guard lastMode == mode, abs(fromTop - previousFromTop) >= 0.5 else { return }
        switch (mode, pane) {
        case (.openSplit, .shared):
            sharedAnchor = Self.topmostAnchor(in: sharedFrames, fromTop: fromTop)
            leadingAnchor = Self.topmostAnchor(in: leadingFrames, fromTop: fromTop)
            trailingAnchor = Self.topmostAnchor(in: trailingFrames, fromTop: fromTop)
        case (.fallback, .shared):
            sharedAnchor = Self.topmostAnchor(in: sharedFrames, fromTop: fromTop)
            // Fresh single-column scrolling supersedes stale per-pane Book anchors.
            leadingAnchor = nil
            trailingAnchor = nil
        case (.bookSplit, .leading):
            leadingAnchor = Self.topmostAnchor(in: leadingFrames, fromTop: fromTop)
            lastInteractedBookPane = .leading
            sharedAnchor = leadingAnchor
        case (.bookSplit, .trailing):
            trailingAnchor = Self.topmostAnchor(in: trailingFrames, fromTop: fromTop)
            lastInteractedBookPane = .trailing
            sharedAnchor = trailingAnchor
        default:
            break
        }
    }

    /// Computes restore targets when moving into `newMode`, clearing stale layout
    /// frames from the outgoing container. Returns all `nil` on initial mount or
    /// when `newMode` matches `lastMode`.
    mutating func beginTransition(
        to newMode: DuoScrollLayoutMode
    ) -> DuoScrollRestoreTargets {
        guard let previous = lastMode else {
            lastMode = newMode
            return DuoScrollRestoreTargets()
        }
        guard previous != newMode else { return DuoScrollRestoreTargets() }
        leadingFrames = [:]
        trailingFrames = [:]
        sharedFrames = [:]
        lastMode = newMode

        switch newMode {
        case .bookSplit:
            return DuoScrollRestoreTargets(
                leading: leadingAnchor ?? sharedAnchor,
                trailing: trailingAnchor ?? sharedAnchor
            )
        case .openSplit, .fallback:
            if previous == .bookSplit {
                let target = lastInteractedBookPane == .trailing
                    ? (trailingAnchor ?? leadingAnchor)
                    : (leadingAnchor ?? trailingAnchor)
                sharedAnchor = target
                return DuoScrollRestoreTargets(shared: target)
            }
            return DuoScrollRestoreTargets(shared: sharedAnchor)
        }
    }

    /// Picks the section whose top sits closest to `fromTop` among those still
    /// extending below the top edge, returning `nil` while resting at the top.
    static func topmostAnchor(
        in frames: [String: DuoScrollAnchorRect],
        fromTop: CGFloat
    ) -> String? {
        guard fromTop > 8, !frames.isEmpty else { return nil }
        let ordered = frames.sorted { lhs, rhs in
            lhs.value.minY != rhs.value.minY ? lhs.value.minY < rhs.value.minY : lhs.key < rhs.key
        }
        let visible = ordered.filter { $0.value.maxY > fromTop + 16 }
        if let closest = visible.min(by: { lhs, rhs in
            let d1 = abs(lhs.value.minY - fromTop)
            let d2 = abs(rhs.value.minY - fromTop)
            return d1 != d2 ? d1 < d2 : lhs.key < rhs.key
        }) {
            return closest.key
        }
        return ordered.last?.key
    }
}

/// Non-observable reference box held in `@State` above layout branches so recording
/// scroll offsets and frames never invalidates SwiftUI view bodies during scrolling.
@MainActor
final class DuoScrollAnchorStore {
    private(set) var state = DuoScrollAnchorState()
    private var pendingShared: String?
    private var pendingLeading: String?
    private var pendingTrailing: String?
    private var restoreDepth = 0

    var isRestoring: Bool { restoreDepth > 0 }

    func recordFrame(_ rect: DuoScrollAnchorRect, for id: String, pane: DuoScrollPane) {
        state.recordFrame(rect, for: id, pane: pane)
    }

    func recordScroll(
        fromTop: CGFloat,
        previousFromTop: CGFloat,
        pane: DuoScrollPane,
        mode: DuoScrollLayoutMode
    ) {
        guard !isRestoring else { return }
        state.recordScroll(fromTop: fromTop, previousFromTop: previousFromTop, pane: pane, mode: mode)
    }

    func consumeRestoreTarget(for pane: DuoScrollPane, entering mode: DuoScrollLayoutMode) -> String? {
        if state.lastMode != mode {
            let targets = state.beginTransition(to: mode)
            pendingShared = targets.shared
            pendingLeading = targets.leading
            pendingTrailing = targets.trailing
        }
        switch pane {
        case .shared:
            let target = pendingShared
            pendingShared = nil
            return target
        case .leading:
            let target = pendingLeading
            pendingLeading = nil
            return target
        case .trailing:
            let target = pendingTrailing
            pendingTrailing = nil
            return target
        }
    }

    func beginRestore() { restoreDepth += 1 }
    func endRestore() { restoreDepth = max(0, restoreDepth - 1) }
}

struct DuoScrollAnchorContext {
    let store: DuoScrollAnchorStore
    let space: AnyHashable
    let pane: DuoScrollPane
}

private struct DuoScrollAnchorModifier: ViewModifier {
    let id: String
    @Environment(\.duoScrollAnchorContext) private var anchorContext

    func body(content: Content) -> some View {
        if let anchorContext {
            content
                .id(id)
                .background {
                    Color.clear.onGeometryChange(for: DuoScrollAnchorRect.self) { proxy in
                        let frame = proxy.frame(in: .named(anchorContext.space))
                        return DuoScrollAnchorRect(
                            minY: frame.minY.rounded(),
                            maxY: frame.maxY.rounded()
                        )
                    } action: { rect in
                        anchorContext.store.recordFrame(rect, for: id, pane: anchorContext.pane)
                    }
                }
        } else {
            content.id(id)
        }
    }
}

extension View {
    /// Marks a section or card as a scroll-restoration anchor across Duo fold/rotation
    /// layout changes while keeping `.id(id)` intact for `ScrollViewReader`.
    func duoScrollAnchor(_ id: String) -> some View {
        modifier(DuoScrollAnchorModifier(id: id))
    }
}

/// Restores a saved section anchor when a scroll container mounts after a layout swap,
/// while suppressing mount-frame scroll-offset callbacks so they cannot wipe saved state.
private struct DuoScrollRestorationModifier: ViewModifier {
    let store: DuoScrollAnchorStore
    let proxy: ScrollViewProxy
    let pane: DuoScrollPane
    let mode: DuoScrollLayoutMode

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { old, new in
                store.recordScroll(fromTop: new, previousFromTop: old, pane: pane, mode: mode)
            }
            .task(id: mode) {
                guard let target = store.consumeRestoreTarget(for: pane, entering: mode) else { return }
                store.beginRestore()
                proxy.scrollTo(target, anchor: .top)
                await Task.yield()
                proxy.scrollTo(target, anchor: .top)
                await Task.yield()
                store.endRestore()
            }
    }
}

extension View {
    func duoScrollRestoration(
        store: DuoScrollAnchorStore,
        proxy: ScrollViewProxy,
        pane: DuoScrollPane,
        mode: DuoScrollLayoutMode
    ) -> some View {
        modifier(DuoScrollRestorationModifier(store: store, proxy: proxy, pane: pane, mode: mode))
    }
}

// MARK: - Split scroll containers

/// Two panes split at the iPhone Duo's vertical fold:
/// - Open flat (`!panes.isBookPose`): one shared `ScrollView`; both panes scroll together
///   with 40 pt clear across the fold (`Duo-Open-Home`, `Duo-Open-Library-Root`).
/// - Book pose (`panes.isBookPose`): two independent `ScrollView`s, each inset 16 pt from
///   the fold shadow (`Duo-Book-Home`).
///
/// Inside each pane, `\.dashboardContentRegions` is cleared so nested carousels render
/// single-row horizontal shelves rather than 2-row wide grids, and `.dashboardLeadingRegion()`
/// becomes a no-op so trailing-pane sections stay in the trailing pane. The fold-facing
/// built-in 16 pt section gutter is absorbed with negative edge padding while
/// `\.duoPaneFoldEdge` clips horizontal carousels cleanly at the pane edge.
struct DuoFoldSplitScrollView<Leading: View, Trailing: View>: View {
    let panes: DuoFoldPanes
    let viewportWidth: CGFloat
    var spacing: CGFloat = SubjectMetrics.sectionSpacing
    var verticalPadding: CGFloat = 12
    var onRefresh: (@Sendable () async -> Void)?
    var anchorStore: DuoScrollAnchorStore?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.layoutDirection) private var layoutDirection
    @Namespace private var sharedScrollSpace
    @Namespace private var leadingScrollSpace
    @Namespace private var trailingScrollSpace

    var body: some View {
        let ordered = panes.ordered(rightToLeft: layoutDirection == .rightToLeft)
        let paneRects = [ordered.leading, ordered.trailing]
        if panes.isBookPose {
            DashboardRegionRow(panes: paneRects, width: viewportWidth, fillsHeight: true) {
                paneScroll(
                    foldEdge: .trailing,
                    width: ordered.leading.width,
                    pane: .leading,
                    space: leadingScrollSpace
                ) { leading() }
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(1)
                paneScroll(
                    foldEdge: .leading,
                    width: ordered.trailing.width,
                    pane: .trailing,
                    space: trailingScrollSpace
                ) { trailing() }
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(0)
            }
        } else {
            ScrollViewReader { proxy in
                sharedScroll {
                    DashboardRegionRow(panes: paneRects, width: viewportWidth) {
                        paneColumn(
                            foldEdge: .trailing,
                            width: ordered.leading.width,
                            pane: .leading,
                            space: sharedScrollSpace
                        ) { leading() }
                            .accessibilityElement(children: .contain)
                            .accessibilitySortPriority(1)
                        paneColumn(
                            foldEdge: .leading,
                            width: ordered.trailing.width,
                            pane: .trailing,
                            space: sharedScrollSpace
                        ) { trailing() }
                            .accessibilityElement(children: .contain)
                            .accessibilitySortPriority(0)
                    }
                    .padding(.vertical, verticalPadding)
                    .coordinateSpace(name: sharedScrollSpace)
                }
                .modifier(OptionalScrollRestoration(
                    store: anchorStore, proxy: proxy, pane: .shared, mode: .openSplit
                ))
            }
        }
    }

    @ViewBuilder
    private func sharedScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let onRefresh {
            ScrollView { content() }
                .refreshable { await onRefresh() }
        } else {
            ScrollView { content() }
        }
    }

    @ViewBuilder
    private func paneScroll<Content: View>(
        foldEdge: DuoPaneFoldEdge,
        width: CGFloat,
        pane: DuoScrollPane,
        space: Namespace.ID,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ScrollViewReader { proxy in
            let scroll = ScrollView {
                paneColumn(foldEdge: foldEdge, width: width, pane: pane, space: space) { content() }
                    .padding(.vertical, verticalPadding)
                    .coordinateSpace(name: space)
            }
            .modifier(OptionalScrollRestoration(
                store: anchorStore, proxy: proxy, pane: pane, mode: .bookSplit
            ))
            if let onRefresh {
                scroll.refreshable { await onRefresh() }
            } else {
                scroll
            }
        }
    }

    private func paneColumn<Content: View>(
        foldEdge: DuoPaneFoldEdge,
        width: CGFloat,
        pane: DuoScrollPane,
        space: Namespace.ID,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(foldEdge == .trailing ? .trailing : .leading, -SubjectMetrics.gutter)
        .frame(width: width, alignment: .topLeading)
        .environment(\.dashboardContentRegions, nil)
        .environment(\.duoPaneFoldEdge, foldEdge)
        .environment(
            \.duoScrollAnchorContext,
            anchorStore.map { DuoScrollAnchorContext(store: $0, space: space, pane: pane) }
        )
    }
}

private struct OptionalScrollRestoration: ViewModifier {
    let store: DuoScrollAnchorStore?
    let proxy: ScrollViewProxy
    let pane: DuoScrollPane
    let mode: DuoScrollLayoutMode

    func body(content: Content) -> some View {
        if let store {
            content.duoScrollRestoration(store: store, proxy: proxy, pane: pane, mode: mode)
        } else {
            content
        }
    }
}

/// Reads `\.duoLayout`, `\.dashboardContentRegions` and `\.dashboardViewportMinX`
/// *inside* `DashboardRegionHost` so dashboard screens (`HomeView`, `LibraryView`)
/// switch to two fold-split panes on the open/Book iPhone Duo, preserve scroll
/// anchors across layout swaps, and keep single-column fallbacks clear of the fold
/// when a trailing filter inspector narrows the host.
struct DuoFoldAdaptiveScrollHost<Leading: View, Trailing: View, Fallback: View>: View {
    var spacing: CGFloat = SubjectMetrics.sectionSpacing
    var verticalPadding: CGFloat = 12
    var onRefresh: (@Sendable () async -> Void)?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var fallback: () -> Fallback

    @Environment(\.duoLayout) private var duoLayout
    @Environment(\.dashboardContentRegions) private var regions
    @Environment(\.dashboardViewportMinX) private var viewportMinX
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var anchorStore = DuoScrollAnchorStore()
    @Namespace private var fallbackScrollSpace

    private var activeVerticalDivision: CGRect? {
        regions?.divisionFrames.first { $0.height > $0.width }
            .map { $0.offsetBy(dx: -(regions?.viewport.minX ?? 0), dy: 0) }
    }

    var body: some View {
        if let regions,
           let panes = duoLayout.foldPanes(
               viewportWidth: regions.viewport.width,
               viewportMinX: viewportMinX,
               viewportHeight: regions.viewport.height,
               activeDivision: activeVerticalDivision
           ) {
            DuoFoldSplitScrollView(
                panes: panes,
                viewportWidth: regions.viewport.width,
                spacing: spacing,
                verticalPadding: verticalPadding,
                onRefresh: onRefresh,
                anchorStore: anchorStore,
                leading: leading,
                trailing: trailing
            )
        } else {
            let clearance = regions.map {
                duoLayout.singlePaneTrailingFoldClearance(
                    viewportWidth: $0.viewport.width,
                    viewportMinX: viewportMinX,
                    rightToLeft: layoutDirection == .rightToLeft,
                    activeDivision: activeVerticalDivision
                )
            } ?? 0
            fallbackScroll(trailingClearance: clearance)
        }
    }

    @ViewBuilder
    private func fallbackScroll(trailingClearance: CGFloat) -> some View {
        ScrollViewReader { proxy in
            let scroll = ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    fallback()
                }
                .padding(.vertical, verticalPadding)
                .coordinateSpace(name: fallbackScrollSpace)
                .environment(
                    \.duoScrollAnchorContext,
                    DuoScrollAnchorContext(store: anchorStore, space: fallbackScrollSpace, pane: .shared)
                )
            }
            .duoScrollRestoration(store: anchorStore, proxy: proxy, pane: .shared, mode: .fallback)

            Group {
                if let onRefresh {
                    scroll.refreshable { await onRefresh() }
                } else {
                    scroll
                }
            }
            .padding(.trailing, trailingClearance)
            .environment(\.dashboardContentRegions, trailingClearance > 0 ? nil : regions)
        }
    }
}
