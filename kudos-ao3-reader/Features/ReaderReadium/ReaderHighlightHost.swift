#if os(iOS)
import ReadiumNavigator
import ReadiumShared
import UIKit

/// Hosts the Readium navigator so the reader's custom selection actions have
/// somewhere to land.
///
/// Readium dispatches `EditingAction(title:action:)` through the **responder
/// chain** (see its own doc comment: "implement the selector in one of your
/// classes in the responder chain. Typically, in the `UIViewController` wrapping
/// the navigator view controller"). A SwiftUI view can't be in that chain, so
/// the navigator gets this parent controller, which implements the selectors and
/// forwards them to closures the SwiftUI layer supplies.
final class ReaderHighlightHostController: UIViewController {
    /// Fired when the reader picks "Highlight" from the selection menu.
    var onHighlight: (() -> Void)?
    /// Fired when the reader picks "Add Note".
    var onAddNote: (() -> Void)?

    private let navigator: UIViewController

    init(navigator: UIViewController) {
        self.navigator = navigator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(navigator)
        navigator.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigator.view)
        NSLayoutConstraint.activate([
            navigator.view.topAnchor.constraint(equalTo: view.topAnchor),
            navigator.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            navigator.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigator.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        navigator.didMove(toParent: self)
    }

    // MARK: Selection actions
    //
    // The selectors' names are what `EditingAction` is built with; keep the two
    // in step (`ReadiumBook.selectionEditingActions`).

    @objc func kudosHighlightSelection(_: Any?) {
        onHighlight?()
    }

    @objc func kudosAddNoteToSelection(_: Any?) {
        onAddNote?()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(kudosHighlightSelection(_:)) || action == #selector(kudosAddNoteToSelection(_:)) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }
}
#endif
