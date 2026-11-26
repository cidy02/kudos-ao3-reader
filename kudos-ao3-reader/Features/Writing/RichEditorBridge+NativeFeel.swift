import Foundation

/// Native appearance payload pushed via `setAppearance` whenever the system
/// trait collection or editor typography changes (docs/WRITING_EDITOR_ARCHITECTURE.md §10.3 N5).
///
/// JSON shape sent to `window.KudosEditor.call("setAppearance", args)`:
/// ```json
/// {
///   "fontFamily": "'New York', ui-serif, Georgia, serif",
///   "fontSizePx": 17.0,
///   "lineHeight": 1.62,
///   "contentSizeCategory": "UICTContentSizeCategoryL",
///   "isAccessibilityCategory": false,
///   "colorScheme": "dark",
///   "increaseContrast": false,
///   "boldText": false
/// }
/// ```
/// The page maps these to CSS custom properties / root attributes without using
/// WebKit's text-size adjustment (`-webkit-text-size-adjust: none`).
nonisolated struct RichEditorAppearance: Codable, Equatable, Hashable, Sendable {
    var fontFamily: String
    var fontSizePx: Double
    var lineHeight: Double
    /// Platform content-size category identifier (iOS `UIContentSizeCategory.rawValue`,
    /// up to AX5 `"UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"`, or `"macOS"`).
    var contentSizeCategory: String
    var isAccessibilityCategory: Bool
    /// `"light"` or `"dark"`.
    var colorScheme: String
    var increaseContrast: Bool
    var boldText: Bool

    init(
        fontFamily: String = RichEditorTheme.defaultFontFamily,
        fontSizePx: Double = 15.5,
        lineHeight: Double = RichEditorTheme.defaultLineHeight,
        contentSizeCategory: String = "UICTContentSizeCategoryL",
        isAccessibilityCategory: Bool = false,
        colorScheme: String = "light",
        increaseContrast: Bool = false,
        boldText: Bool = false
    ) {
        self.fontFamily = fontFamily
        self.fontSizePx = fontSizePx
        self.lineHeight = lineHeight
        self.contentSizeCategory = contentSizeCategory
        self.isAccessibilityCategory = isAccessibilityCategory
        self.colorScheme = colorScheme
        self.increaseContrast = increaseContrast
        self.boldText = boldText
    }
}

/// Caret bounding rectangle reported by the page in document CSS pixels (§10.3 N4), and the top-level block
/// holding the caret (§7.10's highlight). Sent at most once a frame, only when the caret's line or block changes.
///
/// ```json
/// { "type": "caretRect", "x": 16, "y": 420, "width": 1, "height": 24, "block": 3 }
/// ```
nonisolated struct RichEditorCaretRect: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var block: Int?

    init(x: Double, y: Double, width: Double, height: Double, block: Int? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.block = block
    }
}

/// One top-level block of the §7.10 HTML mirror, with the text between it and the next block.
nonisolated struct RichEditorMirrorBlock: Codable, Equatable, Hashable, Sendable {
    var html: String
    var separatorAfter: String
}

/// An update of the §7.10 read-only HTML mirror, sent by the page only while the mirror is shown (`setMirror`):
/// first a `reset` with every block, then, about 300 ms after typing stops, a splice replacing blocks
/// `[from, to)` with `blocks`. The blocks joined are the HTML a snapshot would return at `revision`.
///
/// ```json
/// { "type": "mirrorBlocks", "revision": 12, "totalBlocks": 4, "activeBlockIndex": 1, "reset": false,
///   "from": 0, "to": 3, "blocks": [ { "html": "<p>One</p>", "separatorAfter": "\n" }, ... ] }
/// ```
nonisolated struct RichEditorMirrorBlocksEvent: Codable, Equatable, Hashable, Sendable {
    var revision: Int
    var totalBlocks: Int
    var activeBlockIndex: Int?
    var reset: Bool
    var from: Int
    var to: Int
    var blocks: [RichEditorMirrorBlock]
}

/// `setMirror` arguments: whether the HTML mirror is on screen.
nonisolated struct RichEditorMirrorArgs: Codable, Equatable, Sendable {
    var enabled: Bool
}

extension RichEditorToolbarState {
    /// Localized edit-menu / shortcut-overlay Undo title incorporating the page's
    /// optional step name (§10.3 N6), e.g. `"Bold"` → `"Undo Bold"`.
    var undoMenuTitle: String {
        RichEditorUndoTitleFormatter.undoMenuTitle(for: undoTitle)
    }

    /// Localized edit-menu / shortcut-overlay Redo title incorporating the page's
    /// optional step name (§10.3 N6).
    var redoMenuTitle: String {
        RichEditorUndoTitleFormatter.redoMenuTitle(for: redoTitle)
    }

    /// Maps the page's `toolbarState` (576c's vocabulary: `FormatMark`, `FormatBlock`, `FormatAlignment` and
    /// `FormatDirection` raw values, §7.2) onto the native `FormatState` the Format panel, keys bar and menus read.
    func toFormatState() -> FormatState {
        FormatState(
            activeMarks: Set(marks.compactMap(FormatMark.init(rawValue:))),
            block: FormatBlock(rawValue: block) ?? .body,
            alignment: align.flatMap(FormatAlignment.init(rawValue:)) ?? .left,
            direction: dir.flatMap(FormatDirection.init(rawValue:)) ?? .leftToRight,
            canUndo: canUndo,
            canRedo: canRedo,
            isInLink: inLink,
            currentLinkURL: linkURL
        )
    }
}
