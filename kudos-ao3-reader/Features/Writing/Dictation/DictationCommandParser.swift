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
/// Case and trailing punctuation on the command don't matter. Punctuation between the two words
/// (such as "new. Paragraph") stays prose, and a command word inside a longer word doesn't count.
nonisolated enum DictationCommandParser {
    static func parse(_ phrase: String) -> [DictationSegment] {
        let tokens = phrase.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }
        var segments: [DictationSegment] = []
        var prose: [String] = []
        var index = 0

        func flushProse() {
            guard !prose.isEmpty else { return }
            segments.append(.text(prose.joined(separator: " ")))
            prose.removeAll(keepingCapacity: true)
        }

        while index < tokens.count {
            if let command = command(at: index, tokens: tokens) {
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

    private static func command(at index: Int, tokens: [String]) -> DictationCommand? {
        guard index + 1 < tokens.count else { return nil }
        let first = tokens[index].lowercased()
        let second = strippingTrailingPunctuation(tokens[index + 1]).lowercased()
        return switch (first, second) {
        case ("new", "paragraph"): .newParagraph
        case ("scene", "break"): .sceneBreak
        case ("italics", "on"): .italicsOn
        case ("italics", "off"): .italicsOff
        default: nil
        }
    }

    private static func strippingTrailingPunctuation(_ token: String) -> String {
        var scalars = Array(token.unicodeScalars)
        while let last = scalars.last, CharacterSet.punctuationCharacters.contains(last) {
            scalars.removeLast()
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
