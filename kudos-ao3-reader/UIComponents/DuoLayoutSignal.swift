import SwiftUI
#if os(iOS)
import UIKit
#endif

/// What the screen's layout says about the iPhone Duo (T-562c), decided from traits and
/// reserved regions, never from the device: the same signal the reader's Duo chrome uses
/// (`ReaderChromeLayout`, `verticalBarEdge` + the fold region). Every other screen reads
/// `\.duoLayout`; on an iPhone, iPad or Mac it stays at its default (all false).
nonisolated struct DuoLayoutSignal: Equatable, Sendable {
    /// The system puts its bars on a side edge (the Duo's cover and its inner screen in
    /// landscape): the toolbar and tab bar are a vertical rail.
    var hasVerticalBar = false
    /// The screen has a fold running across it (the Duo's inner screen upright), active
    /// or not, with its bars along the top and bottom.
    var hasHorizontalFold = false
    /// The fold's frame in the probe's (the window's) coordinates, when it is vertical.
    var verticalFold: CGRect?
    /// The probe's width, in the same coordinates as `verticalFold`.
    var width: CGFloat = 0

    var isUprightFold: Bool { hasHorizontalFold && !hasVerticalBar }

    /// The trailing inspector's column on the rail layouts: from the fold to the rail
    /// (`Duo-Open-Library`), so it stands on the trailing pane and never crosses the
    /// crease. `nil` without a vertical fold, and for a pane too narrow to be that.
    static let railReserve: CGFloat = 84
    var inspectorWidth: CGFloat? {
        guard hasVerticalBar, let fold = verticalFold, width > 0 else { return nil }
        let pane = width - fold.maxX - Self.railReserve
        return pane >= 280 ? pane : nil
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
            var next = DuoLayoutSignal()
            guard #available(iOS 27.1, *), let window else { return next }
            next.hasVerticalBar = traitCollection.verticalBarEdge != .unspecified
            let bounds = window.bounds
            next.width = bounds.width
            let divisions = window.reservedRegions(kind: .division, options: .includeInactive).map(\.frame)
            if let fold = ReaderHostRegions.foldFrame(from: divisions, in: bounds) {
                if fold.height > fold.width {
                    next.verticalFold = fold
                } else {
                    next.hasHorizontalFold = true
                }
            }
            return next
        }
    }
}
#endif
