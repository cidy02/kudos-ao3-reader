import Foundation

// MARK: - Formatting contract (plan §3.5, §6.3, §6.4, §7.2)

/// Inline character marks supported by AO3's Rich Text editor and sanitizer.
nonisolated enum FormatMark: String, CaseIterable, Identifiable, Hashable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
    case superscript
    case `subscript`
    case smaller
    case code

    var id: String { rawValue }

    /// Short glyph drawn on toolbar and Format panel buttons (matches `Editor-Format.dc.html`).
    var buttonGlyph: String {
        switch self {
        case .bold: "B"
        case .italic: "I"
        case .underline: "U"
        case .strikethrough: "S"
        case .superscript: "x²"
        case .`subscript`: "x₂"
        case .smaller: "sm"
        case .code: "‹›"
        }
    }

    /// Spoken label for VoiceOver and tooltips.
    var accessibilityLabel: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .strikethrough: "Strikethrough"
        case .superscript: "Superscript"
        case .`subscript`: "Subscript"
        case .smaller: "Smaller text"
        case .code: "Code"
        }
    }
}

/// Paragraph and block styles offered in the Format panel (matches `Editor-Format.dc.html`).
nonisolated enum FormatBlock: String, CaseIterable, Identifiable, Hashable, Sendable {
    case body
    case heading
    case subheading
    case centred
    case quote
    case bulletedList
    case numberedList
    case foldOut

    var id: String { rawValue }

    /// Visible chip title in the Format panel.
    var title: String {
        switch self {
        case .body: "Body"
        case .heading: "Heading"
        case .subheading: "Subheading"
        case .centred: "Centred"
        case .quote: "Quote"
        case .bulletedList: "• List"
        case .numberedList: "1. List"
        case .foldOut: "Fold-out"
        }
    }

    /// Spoken label for VoiceOver (expands punctuation-heavy labels).
    var accessibilityLabel: String {
        switch self {
        case .body: "Body"
        case .heading: "Heading"
        case .subheading: "Subheading"
        case .centred: "Centred"
        case .quote: "Quote"
        case .bulletedList: "Bulleted list"
        case .numberedList: "Numbered list"
        case .foldOut: "Fold-out section"
        }
    }
}

/// Text alignment values serialized to AO3's `align` attribute (§3.5).
nonisolated enum FormatAlignment: String, CaseIterable, Identifiable, Hashable, Sendable {
    case left
    case centre
    case right
    case justify

    var id: String { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .left: "Align left"
        case .centre: "Centre"
        case .right: "Align right"
        case .justify: "Justify"
        }
    }

    var systemImage: String {
        switch self {
        case .left: "text.alignleft"
        case .centre: "text.aligncenter"
        case .right: "text.alignright"
        case .justify: "text.justify"
        }
    }
}

/// Text direction values serialized to AO3's `dir` attribute (§3.5).
nonisolated enum FormatDirection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case leftToRight
    case rightToLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftToRight: "Left to right"
        case .rightToLeft: "Right to left"
        }
    }

    var decoratedTitle: String {
        switch self {
        case .leftToRight: "¶→ Left to right"
        case .rightToLeft: "Right to left ←¶"
        }
    }
}

/// Scene break variants writers commonly insert on AO3.
nonisolated enum SceneBreakStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case asterism
    case asterisks
    case line

    var id: String { rawValue }

    var title: String {
        switch self {
        case .asterism: "Asterism (⁂)"
        case .asterisks: "Asterisks (* * *)"
        case .line: "Horizontal Line"
        }
    }

    var previewGlyph: String {
        switch self {
        case .asterism: "⁂"
        case .asterisks: "* * *"
        case .line: "—"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .asterism: "Insert asterism scene break"
        case .asterisks: "Insert three asterisks scene break"
        case .line: "Insert horizontal line scene break"
        }
    }
}

/// Parameters for inserting an AO3-compatible external image (`img[src,alt,width,height]`, §3.2).
nonisolated struct FormatImageSpec: Equatable, Hashable, Sendable {
    var address: String
    var description: String
    var width: Int?
    var height: Int?

    init(address: String, description: String = "", width: Int? = nil, height: Int? = nil) {
        self.address = address
        self.description = description
        self.width = width
        self.height = height
    }
}

/// Commands emitted by the native editor chrome to the editing surface host.
nonisolated enum FormatCommand: Equatable, Hashable, Sendable {
    case toggleMark(FormatMark)
    case setBlock(FormatBlock)
    case setAlignment(FormatAlignment)
    case setDirection(FormatDirection)
    case setLink(url: String)
    case unlink
    case insertImage(FormatImageSpec)
    case insertSceneBreak(SceneBreakStyle)
    case insertFootnote
    case openTableInHTML
    case undo
    case redo
    case clearFormatting
}

/// Live formatting state reported by the editing surface for the current selection.
nonisolated struct FormatState: Equatable, Hashable, Sendable {
    var activeMarks: Set<FormatMark>
    var block: FormatBlock
    var alignment: FormatAlignment
    var direction: FormatDirection
    var canUndo: Bool
    var canRedo: Bool
    var isInLink: Bool
    var currentLinkURL: String?

    init(
        activeMarks: Set<FormatMark> = [],
        block: FormatBlock = .body,
        alignment: FormatAlignment = .left,
        direction: FormatDirection = .leftToRight,
        canUndo: Bool = false,
        canRedo: Bool = false,
        isInLink: Bool = false,
        currentLinkURL: String? = nil
    ) {
        self.activeMarks = activeMarks
        self.block = block
        self.alignment = alignment
        self.direction = direction
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.isInLink = isInLink
        self.currentLinkURL = currentLinkURL
    }

    func isActive(_ mark: FormatMark) -> Bool {
        activeMarks.contains(mark)
    }
}

/// Validation helpers shared by the Link and Image forms (matches AO3 sanitizer §3.2 & §6.4).
nonisolated enum FormatInputValidation {
    /// AO3's Kudos link sheet permits `http`, `https`, and `mailto` (§6.4, reuses `AO3Markup.safeLink`).
    static func isValidLinkAddress(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return AO3Markup.safeLink(trimmed)
    }

    /// AO3's sanitizer allows only `http` and `https` URLs for `img src` (§3.2).
    static func isValidImageAddress(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    /// Parses an optional positive pixel dimension from a text field.
    static func parsePositiveDimension(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    /// True when the dimension field is empty or holds a valid positive integer.
    static func isValidOptionalDimension(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || parsePositiveDimension(trimmed) != nil
    }
}
