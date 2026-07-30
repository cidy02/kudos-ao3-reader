import OSLog
import SwiftData
import SwiftUI
#if os(iOS)
import ReadiumNavigator
import ReadiumShared
import UIKit
import WebKit
#endif

/// The reader's interactive dismiss peel: the drag surface plus the UIKit
/// representables that host its snapshot animation and dim anchor.
///
/// Split out of `ReadiumReaderView.swift` (see `ReadiumBook.swift` for why).
/// One non-movement change was unavoidable: `ReaderDismissPeelHost` and
/// `ReaderDismissDimAnchor` were `private`, and `ReadiumReaderView` builds both,
/// so they are now internal. `ReaderDismissPeelContainerController` had to follow:
/// it is `ReaderDismissPeelHost`'s `UIViewControllerType`, and Swift requires an
/// associated type to be at least as visible as the protocol method returning it.
/// These three visibility widenings are the only non-movement changes in the split.

#if os(iOS)

/// Owns the interactive dismiss peel. Once latched, peels a **bitmap snapshot**
/// of the whole card in the key window — never the live SwiftUI/WebKit tree —
/// so host updates cannot bounce or fight the gesture.
@MainActor
final class ReaderDismissDragSurface {
    weak var cardView: UIView?
    weak var dimView: UIView?
    /// Full-card still used for the peel; strongly retained while installed.
    private var peelSnapshot: UIImageView?
    private(set) var offset: CGFloat = 0
    private(set) var isAnimating = false

    /// The view that actually moves (snapshot if peeling, else live card).
    private var transformTarget: UIView? { peelSnapshot ?? cardView }

    func lockTransformForExit() {
        isAnimating = true
    }

    /// Capture the full reader card and peel that bitmap. Call once on latch.
    func beginCardSnapshotIfNeeded() {
        guard peelSnapshot == nil, let card = cardView, card.bounds.width > 1,
              let window = card.window
        else { return }
        card.layoutIfNeeded()
        let frameInWindow = card.convert(card.bounds, to: window)
        guard frameInWindow.width > 1, frameInWindow.height > 1 else { return }

        let format = UIGraphicsImageRendererFormat()
        format.scale = card.traitCollection.displayScale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: card.bounds, format: format)
        let image = renderer.image { _ in
            card.drawHierarchy(in: card.bounds, afterScreenUpdates: false)
        }
        guard image.size.width > 1 else { return }

        let snap = UIImageView(image: image)
        snap.frame = frameInWindow
        snap.contentMode = .scaleToFill
        snap.clipsToBounds = true
        snap.isUserInteractionEnabled = false
        window.addSubview(snap)
        peelSnapshot = snap
        // Live tree stays for hit-testing freeze only — not visible under the peel.
        card.isHidden = true
        // Carry any in-progress offset onto the snapshot.
        applyTransformOnly(y: offset, reduceMotion: false)
    }

    func endCardSnapshot() {
        peelSnapshot?.removeFromSuperview()
        peelSnapshot = nil
        if let card = cardView {
            card.isHidden = false
            card.transform = .identity
            card.layer.cornerRadius = 0
            card.layer.masksToBounds = false
        }
    }

    func applyInteractiveOffset(_ raw: CGFloat, reduceMotion: Bool) {
        let y = max(0, raw)
        offset = y
        applyTransformOnly(y: y, reduceMotion: reduceMotion)
    }

    func reassertTransform(reduceMotion: Bool) {
        applyTransformOnly(y: offset, reduceMotion: reduceMotion)
    }

    private func applyTransformOnly(y: CGFloat, reduceMotion: Bool) {
        guard let target = transformTarget else { return }
        target.transform = CGAffineTransform(translationX: 0, y: y)
        if reduceMotion {
            target.layer.cornerRadius = 0
            target.layer.masksToBounds = false
        } else {
            let peeling = y > 0.5
            target.layer.cornerRadius = peeling ? 14 : 0
            target.layer.cornerCurve = .continuous
            target.layer.masksToBounds = peeling
        }
        dimView?.alpha = CGFloat(min(y / 280, 1) * 0.35)
    }

    func animate(
        to raw: CGFloat,
        reduceMotion: Bool,
        duration: TimeInterval,
        spring: Bool,
        completion: (() -> Void)? = nil
    ) {
        isAnimating = true
        let target = max(0, raw)
        let finish: () -> Void = {
            self.isAnimating = false
            self.applyInteractiveOffset(target, reduceMotion: reduceMotion)
            completion?()
        }
        if reduceMotion || duration <= 0 {
            applyInteractiveOffset(target, reduceMotion: reduceMotion)
            finish()
            return
        }
        reassertTransform(reduceMotion: reduceMotion)
        if spring {
            UIView.animate(
                withDuration: duration,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.2,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.applyInteractiveOffset(target, reduceMotion: reduceMotion)
            } completion: { _ in finish() }
        } else {
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.curveEaseIn, .beginFromCurrentState]
            ) {
                self.applyInteractiveOffset(target, reduceMotion: reduceMotion)
            } completion: { _ in finish() }
        }
    }

    func reset(reduceMotion: Bool) {
        isAnimating = false
        applyInteractiveOffset(0, reduceMotion: reduceMotion)
        endCardSnapshot()
    }
}

/// Outer UIKit container whose **own** view is transformed for the peel.
/// The SwiftUI tree lives in a child `UIHostingController` so `rootView =`
/// never zeros the peel transform (that was the bounce-up / wrong dismiss).
final class ReaderDismissPeelContainerController<Content: View>: UIViewController {
    let host: UIHostingController<Content>
    let surface: ReaderDismissDragSurface
    var reduceMotion: Bool

    init(content: Content, surface: ReaderDismissDragSurface, reduceMotion: Bool) {
        self.host = UIHostingController(rootView: content)
        self.surface = surface
        self.reduceMotion = reduceMotion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        // Transform the container, never the hosting child.
        surface.cardView = view
    }

    func update(content: Content) {
        // During an interactive peel / fly-off, skip rootView churn so chrome
        // doesn't rebuild mid-gesture (transform still lives on `view`).
        if surface.isAnimating || surface.offset > 0.5 {
            surface.cardView = view
            return
        }
        host.rootView = content
        surface.cardView = view
        surface.reassertTransform(reduceMotion: reduceMotion)
    }
}

/// Hosts the full dismissable card (page + chrome) so the peel transform applies
/// to one real UIView — not a SwiftUI `.background` sibling (which would leave
/// chrome behind) and not per-sample `@State` (which rebuilt the reader tree).
struct ReaderDismissPeelHost<Content: View>: UIViewControllerRepresentable {
    let surface: ReaderDismissDragSurface
    let reduceMotion: Bool
    let content: Content

    init(
        surface: ReaderDismissDragSurface,
        reduceMotion: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.surface = surface
        self.reduceMotion = reduceMotion
        self.content = content()
    }

    func makeUIViewController(context: Context) -> ReaderDismissPeelContainerController<Content> {
        ReaderDismissPeelContainerController(
            content: content,
            surface: surface,
            reduceMotion: reduceMotion
        )
    }

    func updateUIViewController(
        _ container: ReaderDismissPeelContainerController<Content>,
        context: Context
    ) {
        container.reduceMotion = reduceMotion
        container.update(content: content)
    }
}

/// Registers a full-screen dim layer updated only from UIKit during the peel.
struct ReaderDismissDimAnchor: UIViewRepresentable {
    let surface: ReaderDismissDragSurface

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .black
        view.alpha = 0
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        surface.dimView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        surface.dimView = uiView
    }
}

#endif
