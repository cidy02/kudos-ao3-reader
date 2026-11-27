import Foundation

/// Spoken commands Kudos handles itself, on top of the system's punctuation words (`Phone-Dictate.dc.html`).
nonisolated enum DictationCommand: String, CaseIterable, Equatable, Hashable, Sendable {
    case newParagraph
    case sceneBreak
    case italicsOn
    case italicsOff

    var spoken: String {
        switch self {
        case .newParagraph: "new paragraph"
        case .sceneBreak: "scene break"
        case .italicsOn: "italics on"
        case .italicsOff: "italics off"
        }
    }
}

/// One piece of a dictated phrase after commands have been split out of the prose.
nonisolated enum DictationSegment: Equatable, Sendable {
    case text(String)
    case command(DictationCommand)
}

/// What inserting a phrase should do. Italic on/off becomes a toggle only when the caret's
/// mark differs from what the writer asked for.
nonisolated enum DictationPhrasePlan {
    enum Step: Equatable, Sendable {
        case text(String)
        case newParagraph
        case sceneBreak
        case toggleItalic
    }

    static func steps(phrase: String, italicIsOn: Bool) -> [Step] {
        var italic = italicIsOn
        var steps: [Step] = []
        for segment in DictationCommandParser.parse(phrase) {
            switch segment {
            case let .text(text):
                steps.append(.text(text))
            case .command(.newParagraph):
                steps.append(.newParagraph)
            case .command(.sceneBreak):
                steps.append(.sceneBreak)
            case let .command(command):
                if DictationItalics.shouldToggle(isOn: italic, command: command) {
                    steps.append(.toggleItalic)
                    italic.toggle()
                }
            }
        }
        return steps
    }
}

/// On/off only changes the mark when the caret is not already in the asked-for state.
nonisolated enum DictationItalics {
    static func shouldToggle(isOn: Bool, command: DictationCommand) -> Bool {
        switch command {
        case .italicsOn: !isOn
        case .italicsOff: isOn
        case .newParagraph, .sceneBreak: false
        }
    }
}

/// Splits a recognised phrase into prose and commands.
///
/// Case and punctuation stuck to a word don't matter. A command is two whole words, so
/// "paragraphs" or "newparagraph" is prose.
nonisolated enum DictationCommandParser {
    static func parse(_ phrase: String) -> [DictationSegment] {
        let tokens = phrase.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }
        let keys = tokens.map(matchKey)
        var segments: [DictationSegment] = []
        var prose: [String] = []
        var index = 0

        func flushProse() {
            guard !prose.isEmpty else { return }
            segments.append(.text(prose.joined(separator: " ")))
            prose.removeAll(keepingCapacity: true)
        }

        while index < tokens.count {
            if let command = command(at: index, keys: keys) {
                flushProse()
                segments.append(.command(command))
                index += 2
            } else {
                prose.append(tokens[index])
                index += 1
            }
        }
        flushProse()
        return segments
    }

    /// Match key: lowercased, with punctuation peeled off either end. Letters inside the word stay,
    /// so a command cannot match inside a longer word.
    static func matchKey(_ token: String) -> String {
        var scalars = Array(token.unicodeScalars)
        while let first = scalars.first, !isWordScalar(first) {
            scalars.removeFirst()
        }
        while let last = scalars.last, !isWordScalar(last) {
            scalars.removeLast()
        }
        let core = String(String.UnicodeScalarView(scalars))
        return core.lowercased()
    }

    private static func command(at index: Int, keys: [String]) -> DictationCommand? {
        guard index + 1 < keys.count else { return nil }
        switch (keys[index], keys[index + 1]) {
        case ("new", "paragraph"): .newParagraph
        case ("scene", "break"): .sceneBreak
        case ("italics", "on"): .italicsOn
        case ("italics", "off"): .italicsOff
        default: nil
        }
    }

    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar)
    }
}
