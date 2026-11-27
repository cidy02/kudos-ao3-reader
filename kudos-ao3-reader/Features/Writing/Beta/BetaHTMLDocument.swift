import Foundation
import SwiftSoup

// MARK: - Structured AO3 HTML document model (shared by DOCX writer & beta comparison)

nonisolated enum BetaTextAlignment: String, Equatable, Hashable, Sendable {
    case left
    case center
    case right
    case justify

    var ooxmlValue: String {
        switch self {
        case .left: "left"
        case .center: "center"
        case .right: "right"
        case .justify: "both"
        }
    }
}

nonisolated enum BetaVerticalAlign: Equatable, Hashable, Sendable {
    case baseline
    case superscript
    case `subscript`
}

nonisolated struct BetaRunStyle: Equatable, Hashable, Sendable {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var verticalAlign: BetaVerticalAlign = .baseline
    var monospace = false
    var smaller = false
    var linkURL: String?

    static let plain = BetaRunStyle()
}

nonisolated enum BetaInlineRun: Equatable, Hashable, Sendable {
    case text(String, BetaRunStyle)
    case lineBreak
}

nonisolated enum BetaBlockKind: Equatable, Hashable, Sendable {
    case paragraph
    case heading(Int)
    case quote
    case listItem(ordered: Bool, level: Int, listID: Int)
    case sceneBreak
    case preformatted
}

nonisolated struct BetaHTMLBlock: Equatable, Hashable, Sendable {
    var kind: BetaBlockKind
    var alignment: BetaTextAlignment?
    var runs: [BetaInlineRun]

    /// Plain text matching what `BetaDOCXReader` reads back for this paragraph.
    var plainText: String {
        var result = ""
        for run in runs {
            switch run {
            case let .text(string, _): result.append(string)
            case .lineBreak: result.append("\n")
            }
        }
        return result
    }
}

/// Parses AO3 chapter HTML into normalized blocks and inline runs so `BetaDOCXWriter`
/// and `BetaComparisonEngine` agree on paragraph boundaries and text.
nonisolated enum BetaHTMLDocument {
    private static let blockTagNames: Set<String> = [
        "p", "div", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6",
        "ul", "ol", "li", "hr", "pre", "center", "details", "summary",
        "dl", "dt", "dd", "section", "article", "header", "footer", "aside",
    ]

    static func parse(_ html: String) -> [BetaHTMLBlock] {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        guard let document = try? SwiftSoup.parseBodyFragment(html),
              let body = document.body()
        else {
            return fallbackPlainBlocks(from: html)
        }
        var parser = DOMParser()
        parser.walkContainer(
            body,
            context: BlockContext(
                inQuote: false,
                alignment: nil,
                list: nil,
                preserveWhitespace: false
            ),
            style: .plain
        )
        return parser.blocks
    }

    private static func fallbackPlainBlocks(from text: String) -> [BetaHTMLBlock] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [BetaHTMLBlock(kind: .paragraph, alignment: nil, runs: [.text(trimmed, .plain)])]
    }

    private struct ListContext {
        let ordered: Bool
        let level: Int
        let listID: Int
    }

    private struct BlockContext {
        var inQuote: Bool
        var alignment: BetaTextAlignment?
        var list: ListContext?
        var preserveWhitespace: Bool
    }

    private struct DOMParser {
        var blocks: [BetaHTMLBlock] = []
        /// `numId = 1` is reserved for unordered bullets; ordered lists start at `2`.
        var nextOrderedListID = 2

        mutating func walkContainer(
            _ element: Element,
            context: BlockContext,
            style: BetaRunStyle
        ) {
            var pending: [BetaInlineRun] = []
            for node in element.getChildNodes() {
                if node is Comment { continue }
                if let child = node as? Element {
                    let tag = child.tagName().lowercased()
                    if BetaHTMLDocument.blockTagNames.contains(tag) {
                        flushPending(&pending, kind: defaultKind(for: context), context: context)
                        handleBlockElement(child, tag: tag, parentContext: context, style: style)
                        continue
                    }
                }
                collectInline(
                    node,
                    style: style,
                    preserveWhitespace: context.preserveWhitespace,
                    into: &pending
                )
            }
            flushPending(&pending, kind: defaultKind(for: context), context: context)
        }

        private mutating func handleBlockElement(
            _ element: Element,
            tag: String,
            parentContext: BlockContext,
            style: BetaRunStyle
        ) {
            let alignment = parsedAlignment(of: element) ?? parentContext.alignment
            var childContext = parentContext
            childContext.alignment = alignment

            switch tag {
            case "hr":
                blocks.append(
                    BetaHTMLBlock(
                        kind: .sceneBreak,
                        alignment: .center,
                        runs: [.text("* * *", .plain)]
                    )
                )
            case "h1", "h2", "h3", "h4", "h5", "h6":
                let level = Int(tag.dropFirst()) ?? 1
                var runs: [BetaInlineRun] = []
                collectChildrenInline(element, style: style, preserveWhitespace: false, into: &runs)
                flushPending(&runs, kind: .heading(level), context: childContext)
            case "blockquote":
                childContext.inQuote = true
                walkContainer(element, context: childContext, style: style)
            case "center":
                childContext.alignment = .center
                walkContainer(element, context: childContext, style: style)
            case "ul":
                let level = parentContext.list.map { min($0.level + 1, 8) } ?? 0
                childContext.list = ListContext(ordered: false, level: level, listID: 1)
                walkListChildren(element, context: childContext, style: style)
            case "ol":
                let level = parentContext.list.map { min($0.level + 1, 8) } ?? 0
                let listID = nextOrderedListID
                nextOrderedListID += 1
                childContext.list = ListContext(ordered: true, level: level, listID: listID)
                walkListChildren(element, context: childContext, style: style)
            case "li":
                walkContainer(element, context: childContext, style: style)
            case "pre":
                childContext.preserveWhitespace = true
                var preStyle = style
                preStyle.monospace = true
                var runs: [BetaInlineRun] = []
                collectChildrenInline(element, style: preStyle, preserveWhitespace: true, into: &runs)
                flushPending(&runs, kind: .preformatted, context: childContext)
            case "summary":
                var summaryStyle = style
                summaryStyle.bold = true
                var runs: [BetaInlineRun] = []
                collectChildrenInline(element, style: summaryStyle, preserveWhitespace: false, into: &runs)
                flushPending(&runs, kind: .paragraph, context: childContext)
            case "p":
                var runs: [BetaInlineRun] = []
                collectChildrenInline(element, style: style, preserveWhitespace: false, into: &runs)
                flushPending(&runs, kind: defaultKind(for: childContext), context: childContext)
            default:
                walkContainer(element, context: childContext, style: style)
            }
        }

        private mutating func walkListChildren(
            _ listElement: Element,
            context: BlockContext,
            style: BetaRunStyle
        ) {
            for node in listElement.getChildNodes() {
                guard let child = node as? Element else { continue }
                let tag = child.tagName().lowercased()
                if tag == "li" {
                    walkContainer(child, context: context, style: style)
                } else if tag == "ul" || tag == "ol" {
                    handleBlockElement(child, tag: tag, parentContext: context, style: style)
                }
            }
        }

        private func defaultKind(for context: BlockContext) -> BetaBlockKind {
            if let list = context.list {
                return .listItem(ordered: list.ordered, level: list.level, listID: list.listID)
            }
            if context.inQuote {
                return .quote
            }
            return .paragraph
        }

        private func collectChildrenInline(
            _ element: Element,
            style: BetaRunStyle,
            preserveWhitespace: Bool,
            into runs: inout [BetaInlineRun]
        ) {
            for node in element.getChildNodes() {
                collectInline(
                    node,
                    style: style,
                    preserveWhitespace: preserveWhitespace,
                    into: &runs
                )
            }
        }

        private func collectInline(
            _ node: Node,
            style: BetaRunStyle,
            preserveWhitespace: Bool,
            into runs: inout [BetaInlineRun]
        ) {
            if node is Comment { return }
            if let textNode = node as? TextNode {
                appendText(
                    textNode.getWholeText(),
                    style: style,
                    preserveWhitespace: preserveWhitespace,
                    into: &runs
                )
                return
            }
            guard let element = node as? Element else { return }
            let tag = element.tagName().lowercased()
            if tag == "br" {
                runs.append(.lineBreak)
                return
            }
            if tag == "script" || tag == "style" {
                return
            }
            let updatedStyle = applyingInlineTag(tag, element: element, to: style)
            collectChildrenInline(
                element,
                style: updatedStyle,
                preserveWhitespace: preserveWhitespace,
                into: &runs
            )
        }

        private func applyingInlineTag(
            _ tag: String,
            element: Element,
            to base: BetaRunStyle
        ) -> BetaRunStyle {
            var style = base
            switch tag {
            case "em", "i", "cite", "var", "dfn":
                style.italic = true
            case "strong", "b":
                style.bold = true
            case "u", "ins":
                style.underline = true
            case "s", "strike", "del":
                style.strikethrough = true
            case "sup":
                style.verticalAlign = .superscript
            case "sub":
                style.verticalAlign = .subscript
            case "code", "tt", "kbd", "samp":
                style.monospace = true
            case "small":
                style.smaller = true
            case "a":
                if style.linkURL == nil, let href = resolvedLinkHref(from: element) {
                    style.linkURL = href
                }
            default:
                break
            }
            return style
        }

        private func resolvedLinkHref(from element: Element) -> String? {
            guard let raw = try? element.attr("href") else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.hasPrefix("#") { return trimmed }
            return AO3Markup.safeLink(trimmed) ? trimmed : nil
        }

        private func appendText(
            _ raw: String,
            style: BetaRunStyle,
            preserveWhitespace: Bool,
            into runs: inout [BetaInlineRun]
        ) {
            guard !raw.isEmpty else { return }
            if preserveWhitespace {
                let normalized = raw
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                let parts = normalized.components(separatedBy: "\n")
                for (index, part) in parts.enumerated() {
                    if index > 0 { runs.append(.lineBreak) }
                    if !part.isEmpty { runs.append(.text(part, style)) }
                }
                return
            }
            let collapsed = collapseASCIIWhitespace(raw)
            guard !collapsed.isEmpty else { return }
            runs.append(.text(collapsed, style))
        }

        private mutating func flushPending(
            _ pending: inout [BetaInlineRun],
            kind: BetaBlockKind,
            context: BlockContext
        ) {
            let normalized = context.preserveWhitespace
                ? mergeAdjacentRuns(pending)
                : normalizeBlockRuns(pending)
            pending.removeAll()
            guard !normalized.isEmpty else { return }

            let resolvedKind: BetaBlockKind
            if case .paragraph = kind, context.alignment == .center, isSceneBreakText(normalized) {
                resolvedKind = .sceneBreak
            } else {
                resolvedKind = kind
            }
            blocks.append(BetaHTMLBlock(kind: resolvedKind, alignment: context.alignment, runs: normalized))
        }

        private func isSceneBreakText(_ runs: [BetaInlineRun]) -> Bool {
            let combined = runs.compactMap { run -> String? in
                if case let .text(text, _) = run { return text }
                return nil
            }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            return combined == "* * *" || combined == "***" || combined == "⁂"
        }

        private func normalizeBlockRuns(_ raw: [BetaInlineRun]) -> [BetaInlineRun] {
            var cleaned: [BetaInlineRun] = []
            var atLineStart = true
            var previousEndedWithSpace = false

            for run in raw {
                switch run {
                case .lineBreak:
                    trimTrailingSpace(in: &cleaned)
                    cleaned.append(.lineBreak)
                    atLineStart = true
                    previousEndedWithSpace = false
                case let .text(text, style):
                    var value = text
                    if atLineStart || previousEndedWithSpace {
                        while value.first == " " { value.removeFirst() }
                    }
                    guard !value.isEmpty else { continue }
                    cleaned.append(.text(value, style))
                    atLineStart = false
                    previousEndedWithSpace = value.last == " "
                }
            }
            trimTrailingSpace(in: &cleaned)
            return mergeAdjacentRuns(cleaned)
        }

        private func trimTrailingSpace(in runs: inout [BetaInlineRun]) {
            while let last = runs.last {
                guard case var .text(text, style) = last else { break }
                while text.last == " " { text.removeLast() }
                if text.isEmpty {
                    runs.removeLast()
                } else {
                    runs[runs.count - 1] = .text(text, style)
                    break
                }
            }
        }

        private func mergeAdjacentRuns(_ runs: [BetaInlineRun]) -> [BetaInlineRun] {
            var merged: [BetaInlineRun] = []
            for run in runs {
                if case let .text(nextText, nextStyle) = run,
                   case let .text(prevText, prevStyle) = merged.last,
                   prevStyle == nextStyle {
                    merged[merged.count - 1] = .text(prevText + nextText, prevStyle)
                } else {
                    merged.append(run)
                }
            }
            return merged
        }

        private func parsedAlignment(of element: Element) -> BetaTextAlignment? {
            if let alignAttr = try? element.attr("align"),
               let parsed = parseAlignmentToken(alignAttr) {
                return parsed
            }
            if let styleAttr = try? element.attr("style"), !styleAttr.isEmpty {
                for declaration in styleAttr.split(separator: ";") {
                    let parts = declaration.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let property = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if property == "text-align",
                       let parsed = parseAlignmentToken(String(parts[1])) {
                        return parsed
                    }
                }
            }
            return nil
        }

        private func parseAlignmentToken(_ raw: String) -> BetaTextAlignment? {
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "left", "start": .left
            case "center", "centre": .center
            case "right", "end": .right
            case "justify": .justify
            default: nil
            }
        }

        private func collapseASCIIWhitespace(_ input: String) -> String {
            var output = ""
            output.reserveCapacity(input.count)
            var inSpace = false
            for scalar in input.unicodeScalars {
                if scalar == " " || scalar == "\t" || scalar == "\n"
                    || scalar == "\r" || scalar == "\u{000C}" {
                    if !inSpace {
                        output.append(" ")
                        inSpace = true
                    }
                } else {
                    output.unicodeScalars.append(scalar)
                    inSpace = false
                }
            }
            return output
        }
    }
}
