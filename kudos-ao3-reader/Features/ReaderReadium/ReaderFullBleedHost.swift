#if os(iOS)
import SwiftUI
import UIKit

/// Hosts the reader's SwiftUI tree in a `UIHostingController` whose safe-area regions
/// are zeroed, so the page renders full-bleed and owns its own insets.
///
/// This is what survives of the reader's old drag-to-dismiss "peel": the transform,
/// the mid-drag page freeze, the CPU snapshot and the dim layer are gone, replaced by
/// the system zoom transition's interactive dismissal (`WorkCardZoomTransition.swift`),
/// which was verified on device to preserve the reading position — the one guarantee
/// all that machinery existed to protect.
///
/// The zeroing is not incidental. `ReadiumBook.pageBoxContentInsets` and
/// `ReaderPageSkeleton` both compute their own padding from the *window* safe area on
/// the assumption that this host hands none down; take `safeAreaRegions = []` away and
/// both immediately double-inset. That is why this container remains rather than the
/// reader hosting its content directly.
final class ReaderFullBleedHostController<Content: View>: UIViewController {
    let host: UIHostingController<Content>

    init(content: Content) {
        self.host = UIHostingController(rootView: content)
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
    }

    func update(content: Content) {
        host.rootView = content
    }
}

struct ReaderFullBleedHost<Content: View>: UIViewControllerRepresentable {
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context: Context) -> ReaderFullBleedHostController<Content> {
        ReaderFullBleedHostController(content: content())
    }

    func updateUIViewController(
        _ controller: ReaderFullBleedHostController<Content>,
        context: Context
    ) {
        controller.update(content: content())
    }
}
#endif
