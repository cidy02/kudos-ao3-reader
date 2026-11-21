import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Two side-by-side panes split across the iPhone Duo's vertical fold, in the
/// consuming viewport's local coordinates (`0 ... viewportWidth`).
nonisolated struct DuoFoldPanes: Equatable, Sendable {
    /// Physical left pane (`0 ... left.maxX`).
    let left: CGRect
    /// Physical right pane (`right.minX ... viewportWidth`).
    let right: CGRect
    /// True in Book pose (active vertical division): each pane is inset 16 pt from
    /// the fold shadow and scrolls independently (`Duo-Book-Home`). False in Open
    /// flat: 40 pt clear across the fold (`Duo-Open-Home`, `Duo-Open-Library-Root`).
    let isBookPose: Bool

    /// Logical leading and trailing panes (swapped in right-to-left).
    func ordered(rightToLeft: Bool) -> (leading: CGRect, trailing: CGRect) {
        rightToLeft ? (right, left) : (left, right)
    }

    var foldClearance: CGFloat { right.minX - left.maxX }
}

/// Trailing inspector width and host fold clearance for the open/Book iPhone Duo,
/// resolved from the physical pane corresponding to logical trailing (LTR and RTL,
/// either rail side).
nonisolated struct DuoInspectorSplitGeometry: Equatable, Sendable {
    /// Width of the logical trailing pane occupied by `.inspector` (from the fold's
    /// clear edge on the inspector side to the window/rail edge).
    let inspectorWidth: CGFloat
    /// Logical trailing inset the host content needs while `.inspector` is open so
    /// content stops at the fold's clear edge (40 pt in Open, 56 pt in Book).
    let leadingFoldClearance: CGFloat
    /// Logical trailing inset the host content needs when `.inspector` is hidden
    /// (e.g. Search bulk selection) to stay bounded to the logical leading pane.
    var leadingPaneTrailingReserve: CGFloat { inspectorWidth + leadingFoldClearance }
}

/// What the screen's layout says about the iPhone Duo (T-562c/h), decided from traits and
/// reserved regions, never from the device: the same signal the reader's Duo chrome uses
/// (`ReaderChromeLayout`, `verticalBarEdge` + the fold region). Every other screen reads
/// `\.duoLayout`; on an iPhone, iPad or Mac it stays at its default (all false).
nonisolated struct DuoLayoutSignal: Equatable, Sendable {
    /// The system puts its bars on a side edge (the Duo's cover and its inner screen in
    /// landscape): the toolbar and tab bar are a vertical rail.
    var hasVerticalBar = false
    /// True when the system vertical bar stands on the physical left edge (180° landscape).
    var isVerticalBarLeft = false
    /// The screen has a fold running across it (the Duo's inner screen upright), active
    /// or not, with its bars along the top and bottom.
    var hasHorizontalFold = false
    /// The fold's frame in the probe's (the window's) coordinates, when it is vertical.
    var verticalFold: CGRect?
    /// True when the system reports the vertical division as active (Book pose).
    var isVerticalFoldActive = false
    /// The probe's width, in the same coordinates as `verticalFold`.
    var width: CGFloat = 0

    var isUprightFold: Bool { hasHorizontalFold && !hasVerticalBar }

    init() {}

    #if os(iOS)
    /// From the reader's own classification (`ReaderChromeLayout.resolve`), so the app and the
    /// reader cannot disagree on the same bar edge and fold: a fold with no rail is the upright
    /// layout whatever its orientation.
    init(regions: ReaderHostRegions, width: CGFloat, isVerticalFoldActive: Bool = false) {
        let layout = ReaderChromeLayout.resolve(regions)
        if case .rail = layout { hasVerticalBar = true }
        isVerticalBarLeft = regions.verticalBar == .left
        hasHorizontalFold = layout == .foldTopBar
        verticalFold = regions.fold.flatMap { $0.height > $0.width ? $0 : nil }
        self.isVerticalFoldActive = isVerticalFoldActive && verticalFold != nil
        self.width = width
    }
    #endif

    /// The trailing inspector's column on the rail layouts: from the fold to the rail
    /// (`Duo-Open-Library`), so it stands on the trailing pane and never crosses the
    /// crease. `nil` without a vertical fold, and for a pane too narrow to be that.
    static let railReserve: CGFloat = 84
    /// Open flat keeps 40 pt clear across the fold (`Duo-Open-Home`, `Duo-Open-Library-Root`).
    static let openFoldClearance: CGFloat = 40
    /// Book pose insets each pane 16 pt from the active fold shadow (`Duo-Book-Home`).
    static let bookFoldInset: CGFloat = 16
    /// Minimum readable width for each half of a two-pane split; narrower hosts
    /// (e.g. Library while its filter inspector occupies the trailing pane) stay single-column.
    static let minimumSplitPaneWidth: CGFloat = 240

    /// Resolves the logical trailing inspector column width and the host's logical
    /// trailing fold clearance together from the physical pane matching `rightToLeft`
    /// and the current rail edge. Returns `nil` without a vertical fold + rail or
    /// when the trailing pane is narrower than 280 pt.
    func inspectorSplit(rightToLeft: Bool = false) -> DuoInspectorSplitGeometry? {
        guard hasVerticalBar, let fold = verticalFold, width > 0 else { return nil }
        let halfOpen = max(fold.width / 2, Self.openFoldClearance / 2)
        let baseMinX = min(fold.minX, fold.midX - halfOpen)
        let baseMaxX = max(fold.maxX, fold.midX + halfOpen)
        let extraInset: CGFloat = isVerticalFoldActive ? Self.bookFoldInset : 0
        let clearMinX = max(0, baseMinX - extraInset)
        let clearMaxX = min(width, baseMaxX + extraInset)
        let leftRailReserve: CGFloat = isVerticalBarLeft ? Self.railReserve : 0
        let rightRailReserve: CGFloat = isVerticalBarLeft ? 0 : Self.railReserve

        let paneWidth: CGFloat
        let clearance: CGFloat
        if rightToLeft {
            // Logical trailing is physical left; host occupies baseMinX... to the right.
            paneWidth = baseMinX - leftRailReserve
            clearance = max(0, clearMaxX - baseMinX)
        } else {
            // Logical trailing is physical right; host occupies ...baseMaxX to the left.
            paneWidth = width - baseMaxX - rightRailReserve
            clearance = max(0, baseMaxX - clearMinX)
        }
        guard paneWidth >= 280 else { return nil }
        return DuoInspectorSplitGeometry(inspectorWidth: paneWidth, leadingFoldClearance: clearance)
    }

    func inspectorWidth(rightToLeft: Bool) -> CGFloat? {
        inspectorSplit(rightToLeft: rightToLeft)?.inspectorWidth
    }

    var inspectorWidth: CGFloat? {
        inspectorWidth(rightToLeft: false)
    }

    /// True on the open or Book-pose inner landscape Duo where a vertical fold divides two
    /// side-by-side panes alongside the vertical rail. False on Cover, Upright, iPhone, iPad, Mac.
    func isFoldSplitLandscape(rightToLeft: Bool) -> Bool {
        inspectorSplit(rightToLeft: rightToLeft) != nil
    }

    var isFoldSplitLandscape: Bool {
        isFoldSplitLandscape(rightToLeft: false)
    }

    /// Logical trailing inset on Search's leading pane so results, summaries and the
    /// pagination pill stay clear of the fold both while Filters is docked and while
    /// bulk selection hides the inspector.
    func searchLeadingFoldClearance(rightToLeft: Bool, inspectorVisible: Bool = true) -> CGFloat {
        guard let split = inspectorSplit(rightToLeft: rightToLeft) else { return 0 }
        return inspectorVisible ? split.leadingFoldClearance : split.leadingPaneTrailingReserve
    }

    var searchLeadingFoldClearance: CGFloat {
        searchLeadingFoldClearance(rightToLeft: false, inspectorVisible: true)
    }

    private struct LocalFoldClearBounds {
        let clearMinX: CGFloat
        let clearMaxX: CGFloat
        let isBook: Bool
    }

    private func localFoldClearBounds(
        viewportWidth: CGFloat,
        viewportMinX: CGFloat,
        activeDivision: CGRect?
    ) -> LocalFoldClearBounds? {
        guard hasVerticalBar, let windowFold = verticalFold, viewportWidth > 0 else { return nil }
        let isBook: Bool
        let localFold: CGRect
        if let activeDivision, activeDivision.height > activeDivision.width {
            isBook = true
            localFold = activeDivision
        } else {
            isBook = isVerticalFoldActive
            localFold = windowFold.offsetBy(dx: -viewportMinX, dy: 0)
        }
        let halfOpen = max(localFold.width / 2, Self.openFoldClearance / 2)
        let baseMinX = min(localFold.minX, localFold.midX - halfOpen)
        let baseMaxX = max(localFold.maxX, localFold.midX + halfOpen)
        let extraInset: CGFloat = isBook ? Self.bookFoldInset : 0
        let clearMinX = max(0, baseMinX - extraInset)
        let clearMaxX = min(viewportWidth, baseMaxX + extraInset)
        return LocalFoldClearBounds(clearMinX: clearMinX, clearMaxX: clearMaxX, isBook: isBook)
    }

    /// Splits a viewport into physical left and right panes across the vertical fold.
    /// Returns `nil` when there is no vertical fold + vertical rail (iPhone, iPad, Mac,
    /// Cover, Upright) or when either side would be narrower than `minimumSplitPaneWidth`
    /// (such as Library while its filter inspector is open).
    func foldPanes(
        viewportWidth: CGFloat,
        viewportMinX: CGFloat = 0,
        viewportHeight: CGFloat,
        activeDivision: CGRect? = nil
    ) -> DuoFoldPanes? {
        guard viewportHeight > 0,
              let bounds = localFoldClearBounds(
                  viewportWidth: viewportWidth,
                  viewportMinX: viewportMinX,
                  activeDivision: activeDivision
              ) else { return nil }
        let leftWidth = bounds.clearMinX
        let rightWidth = viewportWidth - bounds.clearMaxX
        guard leftWidth >= Self.minimumSplitPaneWidth,
              rightWidth >= Self.minimumSplitPaneWidth else { return nil }
        return DuoFoldPanes(
            left: CGRect(x: 0, y: 0, width: leftWidth, height: viewportHeight),
            right: CGRect(x: bounds.clearMaxX, y: 0, width: rightWidth, height: viewportHeight),
            isBookPose: bounds.isBook
        )
    }

    /// When a Duo viewport cannot split into two panes (e.g. Library while its filter
    /// inspector occupies the trailing pane), returns the logical trailing inset needed
    /// to keep single-column content out of the fold clearance strip.
    func singlePaneTrailingFoldClearance(
        viewportWidth: CGFloat,
        viewportMinX: CGFloat = 0,
        rightToLeft: Bool = false,
        activeDivision: CGRect? = nil
    ) -> CGFloat {
        guard let bounds = localFoldClearBounds(
            viewportWidth: viewportWidth,
            viewportMinX: viewportMinX,
            activeDivision: activeDivision
        ) else { return 0 }
        let leftWidth = bounds.clearMinX
        let rightWidth = viewportWidth - bounds.clearMaxX
        // Two-pane split applies instead.
        if leftWidth >= Self.minimumSplitPaneWidth && rightWidth >= Self.minimumSplitPaneWidth {
            return 0
        }
        if rightToLeft {
            guard bounds.clearMaxX > 0, rightWidth >= Self.minimumSplitPaneWidth else { return 0 }
            return bounds.clearMaxX
        } else {
            guard leftWidth >= Self.minimumSplitPaneWidth, leftWidth < viewportWidth else { return 0 }
            return viewportWidth - leftWidth
        }
    }
}

extension EnvironmentValues {
    @Entry var duoLayout = DuoLayoutSignal()
}

extension View {
    /// Publishes `\.duoLayout` to everything below. Attach once, near the app root.
    func duoLayoutProbe() -> some View {
        #if os(iOS)
        modifier(DuoLayoutProbeModifier())
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct DuoLayoutProbeModifier: ViewModifier {
    @State private var signal = DuoLayoutSignal()

    func body(content: Content) -> some View {
        content
            .environment(\.duoLayout, signal)
            .background(DuoLayoutProbe(signal: $signal).allowsHitTesting(false))
    }
}

private struct DuoLayoutProbe: UIViewRepresentable {
    @Binding var signal: DuoLayoutSignal

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = { new in
            if new != signal { signal = new }
        }
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onChange = { new in
            if new != signal { signal = new }
        }
    }

    final class ProbeView: UIView {
        var onChange: ((DuoLayoutSignal) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            if #available(iOS 27.1, *) {
                registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) {
                    (view: ProbeView, _: UITraitCollection) in view.report()
                }
                addInteraction(UIHingeInteraction { [weak self] _, _ in self?.report() })
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private func report() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onChange?(self.current())
            }
        }

        private func current() -> DuoLayoutSignal {
            guard #available(iOS 27.1, *), let window else { return DuoLayoutSignal() }
            var regions = ReaderHostRegions()
            switch traitCollection.verticalBarEdge {
            case .leading: regions.verticalBar = effectiveUserInterfaceLayoutDirection == .leftToRight ? .left : .right
            case .trailing: regions.verticalBar = effectiveUserInterfaceLayoutDirection == .leftToRight ? .right : .left
            default: break
            }
            let bounds = window.bounds
            let divisionRegions = window.reservedRegions(kind: .division, options: .includeInactive)
            let divisions = divisionRegions.map(\.frame)
            regions.fold = ReaderHostRegions.foldFrame(from: divisions, in: bounds)
            let isFoldActive = regions.fold.flatMap { fold in
                divisionRegions.first { $0.frame == fold }?.isActive
            } ?? false
            return DuoLayoutSignal(
                regions: regions, width: bounds.width, isVerticalFoldActive: isFoldActive
            )
        }
    }
}
#endif
