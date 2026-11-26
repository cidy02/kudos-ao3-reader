import Foundation
#if os(iOS)
import UIKit
#endif

/// Caret-move direction emitted by `WritingKeysBar`'s arrow keys (§10.3 N3).
nonisolated enum RichEditorCaretDirection: String, Equatable, Hashable, Sendable {
    case left
    case right
}

/// Unified command emitted by the keys bar (N3), edit menu (N2), hardware
/// keyboard shortcuts (N7), and system undo (N6) to the host's command sink.
nonisolated enum RichEditorHostCommand: Equatable, Hashable, Sendable {
    case format(FormatCommand)
    case requestLink
    case moveCaret(RichEditorCaretDirection)
    case insertEmDash
    case insertQuotationMarks
    case openFormatPanel
    case presentFind
    /// Anchor a private note to the selection (T-576d); offered only where a screen stores notes.
    case requestNote

    /// Underlying `FormatCommand` when this command maps directly to one.
    var formatCommand: FormatCommand? {
        if case let .format(command) = self { return command }
        return nil
    }

    /// Maps a `WritingKeysBar` tap or long-press action onto the host's sink payload.
    static func from(_ action: WritingKeyAction) -> RichEditorHostCommand {
        if let command = action.formatCommand {
            return .format(command)
        }
        switch action {
        case .toggleItalic: return .format(.toggleMark(.italic))
        case .toggleBold: return .format(.toggleMark(.bold))
        case .insertSceneBreak: return .format(.insertSceneBreak(.asterism))
        case .undo: return .format(.undo)
        case .redo: return .format(.redo)
        case .insertEmDash: return .insertEmDash
        case .insertQuotationMarks: return .insertQuotationMarks
        case .moveCursorLeft: return .moveCaret(.left)
        case .moveCursorRight: return .moveCaret(.right)
        case .openFormat: return .openFormatPanel
        }
    }
}

/// Formats page-supplied step titles into native Undo / Redo menu labels (§10.3 N6).
nonisolated enum RichEditorUndoTitleFormatter {
    static func undoMenuTitle(for stepTitle: String?) -> String {
        guard let cleaned = clean(stepTitle) else { return "Undo" }
        if cleaned.lowercased().hasPrefix("undo") { return cleaned }
        return "Undo \(cleaned)"
    }

    static func redoMenuTitle(for stepTitle: String?) -> String {
        guard let cleaned = clean(stepTitle) else { return "Redo" }
        if cleaned.lowercased().hasPrefix("redo") { return cleaned }
        return "Redo \(cleaned)"
    }

    private static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Proxy `UndoManager` that routes system undo gestures (shake, three-finger
/// swipe, edit menu) to the Rich Text command sink while Rich Text owns the
/// text (§10.3 N6 / U1) and exposes the page-supplied undo/redo step title.
nonisolated final class RichEditorUndoManager: UndoManager {
    private let lock = NSLock()
    private var _canUndo = false
    private var _canRedo = false
    private var _undoActionName = ""
    private var _redoActionName = ""
    private var _onUndo: (@MainActor @Sendable () -> Void)?
    private var _onRedo: (@MainActor @Sendable () -> Void)?

    func configureHandlers(
        onUndo: (@MainActor @Sendable () -> Void)?,
        onRedo: (@MainActor @Sendable () -> Void)?
    ) {
        lock.lock()
        _onUndo = onUndo
        _onRedo = onRedo
        lock.unlock()
    }

    func update(canUndo: Bool, canRedo: Bool, undoTitle: String?, redoTitle: String?) {
        lock.lock()
        _canUndo = canUndo
        _canRedo = canRedo
        _undoActionName = undoTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        _redoActionName = redoTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        lock.unlock()
    }

    override var canUndo: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _canUndo
    }

    override var canRedo: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _canRedo
    }

    override var undoActionName: String {
        lock.lock()
        defer { lock.unlock() }
        return _undoActionName
    }

    override var redoActionName: String {
        lock.lock()
        defer { lock.unlock() }
        return _redoActionName
    }

    override var undoMenuItemTitle: String {
        RichEditorUndoTitleFormatter.undoMenuTitle(for: undoActionName)
    }

    override var redoMenuItemTitle: String {
        RichEditorUndoTitleFormatter.redoMenuTitle(for: redoActionName)
    }

    override func undo() {
        lock.lock()
        let handler = _onUndo
        lock.unlock()
        guard let handler else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { handler() }
        } else {
            Task { @MainActor in handler() }
        }
    }

    override func redo() {
        lock.lock()
        let handler = _onRedo
        lock.unlock()
        guard let handler else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { handler() }
        } else {
            Task { @MainActor in handler() }
        }
    }
}

/// Cross-platform catalog of the §10.3 N7 hardware keyboard shortcuts.
nonisolated struct RichEditorKeyCommandSpec: Equatable, Hashable, Sendable {
    let input: String
    let requiresShift: Bool
    let title: String
    let command: RichEditorHostCommand

    /// Normative §10.3 N7 shortcuts: ⌘B, ⌘I, ⌘U, ⌘K, ⌘F, ⌘Z, ⇧⌘Z.
    static let all: [RichEditorKeyCommandSpec] = [
        RichEditorKeyCommandSpec(
            input: "b", requiresShift: false, title: "Bold", command: .format(.toggleMark(.bold))
        ),
        RichEditorKeyCommandSpec(
            input: "i", requiresShift: false, title: "Italic", command: .format(.toggleMark(.italic))
        ),
        RichEditorKeyCommandSpec(
            input: "u", requiresShift: false, title: "Underline", command: .format(.toggleMark(.underline))
        ),
        RichEditorKeyCommandSpec(
            input: "k", requiresShift: false, title: "Link", command: .requestLink
        ),
        RichEditorKeyCommandSpec(
            input: "f", requiresShift: false, title: "Find", command: .presentFind
        ),
        RichEditorKeyCommandSpec(
            input: "z", requiresShift: false, title: "Undo", command: .format(.undo)
        ),
        RichEditorKeyCommandSpec(
            input: "z", requiresShift: true, title: "Redo", command: .format(.redo)
        ),
    ]
}

#if os(iOS)
/// Identifiers used when customizing `WKWebView`'s system edit menu (§10.3 N2/N6).
enum RichEditorMenuID {
    static let formatting = UIMenu.Identifier("com.kudos.writing.editMenu.formatting")
    /// Browser-style menus stripped from the writing canvas where UIKit allows.
    static let removedBrowserMenus: [UIMenu.Identifier] = [
        .share,
        .lookup,
        .open,
        .textStyle,
    ]
}

/// Thin testable surface over `UIMenuBuilder` so `RichEditorWebView`'s edit menu
/// configuration can be verified in Swift Testing without private UIKit builders.
@MainActor
protocol RichEditorMenuBuilding {
    func hasMenu(for identifier: UIMenu.Identifier) -> Bool
    func remove(menu identifier: UIMenu.Identifier)
    func insertSibling(_ siblingMenu: UIMenu, afterMenu siblingIdentifier: UIMenu.Identifier)
    func insertChild(_ childMenu: UIMenu, atStartOfMenu parentIdentifier: UIMenu.Identifier)
    func insertChild(_ childMenu: UIMenu, atEndOfMenu parentIdentifier: UIMenu.Identifier)
    func replaceChildren(
        ofMenu parentIdentifier: UIMenu.Identifier,
        from childrenBlock: ([UIMenuElement]) -> [UIMenuElement]
    )
}

@MainActor
struct UIKitMenuBuilderAdapter: RichEditorMenuBuilding {
    let builder: any UIMenuBuilder

    func hasMenu(for identifier: UIMenu.Identifier) -> Bool {
        builder.menu(for: identifier) != nil
    }

    func remove(menu identifier: UIMenu.Identifier) {
        builder.remove(menu: identifier)
    }

    func insertSibling(_ siblingMenu: UIMenu, afterMenu siblingIdentifier: UIMenu.Identifier) {
        builder.insertSibling(siblingMenu, afterMenu: siblingIdentifier)
    }

    func insertChild(_ childMenu: UIMenu, atStartOfMenu parentIdentifier: UIMenu.Identifier) {
        builder.insertChild(childMenu, atStartOfMenu: parentIdentifier)
    }

    func insertChild(_ childMenu: UIMenu, atEndOfMenu parentIdentifier: UIMenu.Identifier) {
        builder.insertChild(childMenu, atEndOfMenu: parentIdentifier)
    }

    func replaceChildren(
        ofMenu parentIdentifier: UIMenu.Identifier,
        from childrenBlock: ([UIMenuElement]) -> [UIMenuElement]
    ) {
        builder.replaceChildren(ofMenu: parentIdentifier, from: childrenBlock)
    }
}
#endif
