import Foundation

// The one mapping from the native editor chrome to the page's commands (docs/WRITING_EDITOR_ARCHITECTURE.md §7.2,
// `command`). Names and attributes are 576c's `FormatCommand` vocabulary, which editor-core's page speaks directly
// (`editor-core/src/editor/editor.ts`, `resolve`). The shared fixtures in `editor-core/test/bridge-fixtures/` hold one
// example of every command; Swift and JS tests both read them.

extension FormatCommand {
    /// The page command for this format command, or nil for one the native side handles itself (`openTableInHTML`).
    var bridgeCommand: RichEditorCommandArgs? {
        switch self {
        case let .toggleMark(mark):
            RichEditorCommandArgs(name: "toggleMark", attrs: ["mark": .string(mark.rawValue)])
        case let .setBlock(block):
            RichEditorCommandArgs(name: "setBlock", attrs: ["block": .string(block.rawValue)])
        case let .setAlignment(alignment):
            RichEditorCommandArgs(name: "setAlignment", attrs: ["alignment": .string(alignment.rawValue)])
        case let .setDirection(direction):
            RichEditorCommandArgs(name: "setDirection", attrs: ["direction": .string(direction.rawValue)])
        case let .setLink(url):
            RichEditorCommandArgs(name: "setLink", attrs: ["url": .string(url)])
        case .unlink:
            RichEditorCommandArgs(name: "unlink")
        case let .insertImage(spec):
            RichEditorCommandArgs(name: "insertImage", attrs: Self.imageAttrs(spec))
        case let .insertSceneBreak(style):
            RichEditorCommandArgs(name: "insertSceneBreak", attrs: ["style": .string(style.rawValue)])
        case .insertFootnote:
            RichEditorCommandArgs(name: "insertFootnote")
        case .openTableInHTML:
            nil
        case .undo:
            RichEditorCommandArgs(name: "undo")
        case .redo:
            RichEditorCommandArgs(name: "redo")
        case .clearFormatting:
            RichEditorCommandArgs(name: "clearFormatting")
        }
    }

    private static func imageAttrs(_ spec: FormatImageSpec) -> [String: RichEditorJSONValue] {
        var attrs: [String: RichEditorJSONValue] = [
            "address": .string(spec.address),
            "description": .string(spec.description),
        ]
        if let width = spec.width { attrs["width"] = .int(width) }
        if let height = spec.height { attrs["height"] = .int(height) }
        return attrs
    }
}

extension RichEditorHostCommand {
    /// The page command for a keys-bar, edit-menu or key-command action, or nil for one that opens native UI.
    var bridgeCommand: RichEditorCommandArgs? {
        switch self {
        case let .format(command):
            command.bridgeCommand
        case let .moveCaret(direction):
            RichEditorCommandArgs(name: "moveCaret", attrs: ["by": .int(direction == .left ? -1 : 1)])
        case .insertEmDash:
            RichEditorCommandArgs(name: "insertText", attrs: ["text": .string("—")])
        case .insertQuotationMarks:
            RichEditorCommandArgs(name: "insertQuotes", attrs: ["open": .string("“"), "close": .string("”")])
        case .requestLink, .openFormatPanel, .presentFind:
            nil
        }
    }
}

extension DraftSession {
    /// Live formatting state for the Format panel, keys bar and menus (from the page's `toolbarState`).
    var formatState: FormatState { toolbarState.toFormatState() }

    /// Sends one format command to the editor that owns the text. Undo and redo go to the owner's own history
    /// (U1); everything else applies only while Rich Text owns the text.
    func apply(_ command: FormatCommand) {
        switch command {
        case .undo: undo()
        case .redo: redo()
        default:
            guard let args = command.bridgeCommand else { return }
            applyRichCommand(name: args.name, attrs: args.attrs)
        }
    }

    /// Sends a keys-bar, edit-menu or key-command action; native-only actions are the caller's to handle.
    func apply(_ command: RichEditorHostCommand) {
        if let format = command.formatCommand {
            apply(format)
        } else if let args = command.bridgeCommand {
            applyRichCommand(name: args.name, attrs: args.attrs)
        }
    }
}

/// One paste into Rich Text, numbered so a view can tell a new paste from the last one.
nonisolated struct DraftPasteReport: Equatable, Sendable {
    let sequence: Int
    let event: RichEditorPasteEvent
}

/// One tap on a note or TK highlight, numbered like `DraftPasteReport`.
nonisolated struct DraftAnnotationTap: Equatable, Sendable {
    let sequence: Int
    let id: String
}

/// One typed "TK", numbered; `range` is in the HTML a snapshot would return at that moment.
nonisolated struct DraftTypedTK: Equatable, Sendable {
    let sequence: Int
    let range: RichEditorTextRange
}

extension DraftSession {
    /// Draws notes and TKs in Rich Text (T-576d). Ranges are UTF-16 offsets in the text HTML mode holds
    /// (`text`, anchored with `WritingDocumentStore`'s quotes); the page moves them with every edit after that.
    @discardableResult
    func setAnnotations(_ items: [RichEditorAnnotationItem]) async -> [RichEditorAnnotationsResult.Placed] {
        guard state == .richOwned, let transport = richTransport else { return [] }
        do {
            return try await transport.setAnnotations(RichEditorAnnotationsArgs(items: items)).placed
        } catch {
            logNonFatal("setAnnotations failed: \(error.localizedDescription)")
            return []
        }
    }

    /// The Rich Text selection, with the HTML it is a range of: what a new note is anchored to (T-576d).
    func selectionForAnchoring() async -> (html: String, range: RichEditorTextRange)? {
        guard state == .richOwned, let transport = richTransport else { return nil }
        do {
            let snapshot = try await transport.snapshot(RichEditorSnapshotArgs(caret: false, selection: true))
            guard let range = snapshot.selection else { return nil }
            return (snapshot.html, range)
        } catch {
            logNonFatal("selection snapshot failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Replaces the word before the caret with a suggestion (a name from the work's story notes, T-576d).
    func completeWord(_ text: String) {
        applyRichCommand(name: "completeWord", attrs: ["text": .string(text)])
    }
}
