import SwiftUI

/// Zero-width break opportunities for a string SwiftUI otherwise will not wrap.
///
/// A space already breaks. `_` and `-` do not, and neither does a long run of
/// letters — "Subscriptions" at Title 3, AX5, is wider than a 320 pt phone.
/// Opportunities only: a run that fits the line stays on one line, so this
/// does not change a size where the original string already fitted.
enum AccessibilitySoftBreak {
    static func opportunities(in text: String, unbrokenLimit: Int = 8) -> String {
        var out = ""
        out.reserveCapacity(text.count + text.count / max(unbrokenLimit, 1))
        var run = ""
        func flushRun() {
            defer { run.removeAll(keepingCapacity: true) }
            guard run.count > unbrokenLimit else {
                out.append(contentsOf: run)
                return
            }
            for (offset, character) in run.enumerated() {
                if offset > 0 { out.append("\u{200B}") }
                out.append(character)
            }
        }
        for character in text {
            if character == "_" || character == "-" {
                flushRun()
                out.append(character)
                out.append("\u{200B}")
            } else if character.isWhitespace {
                flushRun()
                out.append(character)
            } else {
                run.append(character)
            }
        }
        flushRun()
        return out
    }
}

/// Home's resume card. Side by side, the fixed symbol strip and the Resume
/// button are wider than a phone at an accessibility size.
enum HomeResumeLayout {
    static func stacksActions(_ size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }
}

/// Section titles. `layoutPriority` lets the title keep its ideal width beside
/// the count; at accessibility sizes that width is the phone.
enum SectionHeaderLayout {
    static func stacksCount(_ size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }
}
