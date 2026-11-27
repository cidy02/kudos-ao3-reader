import Foundation
import os

/// Kudos-only action URLs embedded in the in-chapter end-of-chapter card (T-578)
/// and intercepted by Readium's navigator delegate.
nonisolated enum ReaderChapterEndAction: Equatable, Sendable {
    static let urlScheme = "kudos-chapter-end"

    case comment(chapter: Int)
    case kudos

    var urlString: String {
        switch self {
        case let .comment(chapter):
            return "\(Self.urlScheme)://comment?chapter=\(chapter)"
        case .kudos:
            return "\(Self.urlScheme)://kudos"
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        switch self {
        case let .comment(chapter):
            components.host = "comment"
            components.queryItems = [URLQueryItem(name: "chapter", value: String(chapter))]
        case .kudos:
            components.host = "kudos"
        }
        return components.url ?? URL(fileURLWithPath: "/")
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.urlScheme else { return nil }
        switch url.host?.lowercased() {
        case "comment":
            let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "chapter" }?
                .value
            guard let value, let chapter = Int(value), chapter > 0 else { return nil }
            self = .comment(chapter: chapter)
        case "kudos":
            self = .kudos
        default:
            return nil
        }
    }
}

/// Accent colours baked into the in-chapter card's CSS custom properties so the
/// card matches the app accent on Light, Sepia, Dark, and OLED without reloading.
nonisolated struct ReaderChapterEndStyle: Equatable, Sendable {
    let accentHex: String
    let accentLabelHex: String
    let lightAccentInkHex: String
    let sepiaAccentInkHex: String
    let darkAccentInkHex: String

    static let `default` = ReaderChapterEndStyle(
        accentHex: "#821019",
        accentLabelHex: "#FFFFFF",
        lightAccentInkHex: "#821019",
        sepiaAccentInkHex: "#821019",
        darkAccentInkHex: "#EE8A93"
    )
}

/// Thread-safe kudos flag shared between the reader view and the Readium resource
/// transformer so chapters served later already render "Kudos Given".
nonisolated final class ReaderChapterEndKudosState: Sendable {
    private let lock: OSAllocatedUnfairLock<Bool>

    init(isGiven: Bool) {
        lock = OSAllocatedUnfairLock(initialState: isGiven)
    }

    var isGiven: Bool {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}

/// Thread-safe accent style holder shared with the Readium resource transformer
/// so chapters loaded after an accent change pick up the updated colour tokens.
nonisolated final class ReaderChapterEndStyleState: Sendable {
    private let lock: OSAllocatedUnfairLock<ReaderChapterEndStyle>

    init(style: ReaderChapterEndStyle) {
        lock = OSAllocatedUnfairLock(initialState: style)
    }

    var style: ReaderChapterEndStyle {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}

/// Work-level metadata passed when opening an EPUB so the resource transformer
/// can build each non-final chapter's end-of-chapter card.
nonisolated struct ReaderChapterEndWorkContext: Sendable {
    let chapterWordCounts: [Int]
    let totalChapters: Int?
    let postedChapters: Int
    let isComplete: Bool
    let showsAO3Actions: Bool
    let kudosState: ReaderChapterEndKudosState
    let styleState: ReaderChapterEndStyleState

    var style: ReaderChapterEndStyle { styleState.style }

    init(
        chapterWordCounts: [Int],
        totalChapters: Int?,
        postedChapters: Int,
        isComplete: Bool,
        showsAO3Actions: Bool,
        kudosState: ReaderChapterEndKudosState,
        style: ReaderChapterEndStyle = .default
    ) {
        self.chapterWordCounts = chapterWordCounts
        self.totalChapters = totalChapters
        self.postedChapters = postedChapters
        self.isComplete = isComplete
        self.showsAO3Actions = showsAO3Actions
        self.kudosState = kudosState
        styleState = ReaderChapterEndStyleState(style: style)
    }
}

/// Per-chapter card content fed into `ReaderChapterEndHTML.inject(into:card:)`.
nonisolated struct ReaderChapterEndCardContext: Equatable, Sendable {
    let chapter: Int
    let nextChapterTitle: String
    let nextChapterHref: String
    let nextChapterTime: String?
    let footer: String
    let showsAO3Actions: Bool
    let kudosGiven: Bool
    let style: ReaderChapterEndStyle

    init(
        chapter: Int,
        nextChapterTitle: String,
        nextChapterHref: String,
        nextChapterTime: String? = nil,
        footer: String,
        showsAO3Actions: Bool = true,
        kudosGiven: Bool = false,
        style: ReaderChapterEndStyle = .default
    ) {
        self.chapter = chapter
        self.nextChapterTitle = nextChapterTitle
        self.nextChapterHref = nextChapterHref
        self.nextChapterTime = nextChapterTime
        self.footer = footer
        self.showsAO3Actions = showsAO3Actions
        self.kudosGiven = kudosGiven
        self.style = style
    }
}

/// Transforms chapter XHTML as Readium serves it to append the in-flow
/// end-of-chapter card (Reader-ChapterEnd, T-578).
///
/// Output is strict XHTML (`application/xhtml+xml` safe): every void tag is
/// self-closing, every inline `<svg>` declares the SVG namespace, no HTML-only
/// named entities are emitted, and the injected `<style>` avoids `<`, `>`, and `&`.
nonisolated enum ReaderChapterEndHTML {
    static let sectionID = "kudos-chapter-end"
    static let anchorID = "kudos-chapter-end-anchor"
    static let styleID = "kudos-chapter-end-style"
    static let kudosLinkID = "kudos-chapter-end-kudos"
    static let commentLinkID = "kudos-chapter-end-comment"
    static let nextLinkID = "kudos-chapter-end-next"
    static let noteToggleID = "kudos-chapter-end-note-toggle"

    /// Builds a card context for `spineIndex`, or `nil` when this spine item
    /// should not carry an end-of-chapter card (front/back matter or last chapter).
    @MainActor
    static func cardContext(
        forSpineIndex spineIndex: Int,
        sections: [ReaderSection],
        work: ReaderChapterEndWorkContext
    ) -> ReaderChapterEndCardContext? {
        guard let end = ReaderChapterEndFacts.chapterEnd(
            endingSpineIndex: spineIndex, sections: sections
        ) else {
            return nil
        }
        let storyTotal = sections.storyChapterCount
        let nextSection = sections[end.nextSpineIndex]
        let nextTitle = ReaderChapterEndFacts.nextChapterTitle(
            number: end.nextStoryChapter,
            sectionTitle: nextSection.title
        )
        let nextHref = relativeHref(
            from: sections[end.spineIndex].href,
            to: nextSection.href
        )
        let nextTime = ReaderChapterEndFacts.nextChapterTime(
            chapterWordCounts: work.chapterWordCounts,
            storyChapterTotal: storyTotal,
            nextStoryChapter: end.nextStoryChapter
        )
        let footer = ReaderChapterEndFacts.footer(
            chapter: end.storyChapter,
            totalChapters: work.totalChapters ?? (work.isComplete ? storyTotal : nil),
            postedChapters: work.postedChapters
        )
        return ReaderChapterEndCardContext(
            chapter: end.storyChapter,
            nextChapterTitle: nextTitle,
            nextChapterHref: nextHref,
            nextChapterTime: nextTime,
            footer: footer,
            showsAO3Actions: work.showsAO3Actions,
            kudosGiven: work.kudosState.isGiven,
            style: work.style
        )
    }

    /// Computes a relative link href from `currentHref` to `targetHref` within an EPUB.
    static func relativeHref(from currentHref: String, to targetHref: String) -> String {
        let targetTrimmed = targetHref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetTrimmed.isEmpty else { return "" }

        let (targetPathRaw, targetSuffix) = splitPathAndSuffix(targetTrimmed)
        let (currentPathRaw, _) = splitPathAndSuffix(currentHref)

        let fromParts = pathComponents(currentPathRaw)
        let toParts = pathComponents(targetPathRaw)
        guard let targetFile = toParts.last else { return targetTrimmed }

        let fromDirs = Array(fromParts.dropLast())
        let toDirs = Array(toParts.dropLast())
        var common = 0
        while common < fromDirs.count && common < toDirs.count && fromDirs[common] == toDirs[common] {
            common += 1
        }
        let upSteps = Array(repeating: "..", count: fromDirs.count - common)
        let relativeParts = upSteps + Array(toDirs[common...]) + [targetFile]
        return relativeParts.joined(separator: "/") + targetSuffix
    }

    /// Appends the end-of-chapter section once before `</body>` and injects its
    /// scoped stylesheet (plus end-note hiding CSS only when the chapter has an end note).
    static func inject(into xhtml: String, card: ReaderChapterEndCardContext) -> String {
        guard !xhtml.isEmpty,
              !xhtml.contains("id=\"\(sectionID)\""),
              let bodyClose = xhtml.range(of: "</body>", options: [.caseInsensitive, .backwards])
        else { return xhtml }

        let noteMatch = ReaderChapterEndFacts.endNoteMatch(fromChapterXHTML: xhtml)
        let css = ReaderChapterEndStylesheet.stylesheet(style: card.style, noteMatch: noteMatch)
        let styleBlock = "<style id=\"\(styleID)\">\(css)</style>"
        let sectionBlock = renderSection(card: card, endNote: noteMatch?.text)

        if let headClose = xhtml.range(
            of: "</head>",
            options: [.caseInsensitive, .backwards],
            range: xhtml.startIndex..<bodyClose.lowerBound
        ) {
            return String(xhtml[..<headClose.lowerBound])
                + "\n\(styleBlock)\n"
                + String(xhtml[headClose.lowerBound..<bodyClose.lowerBound])
                + "\n\(sectionBlock)\n"
                + String(xhtml[bodyClose.lowerBound...])
        }
        return String(xhtml[..<bodyClose.lowerBound])
            + "\n\(styleBlock)\n\(sectionBlock)\n"
            + String(xhtml[bodyClose.lowerBound...])
    }

    /// Escapes text and attribute values for strict XHTML and HTML5.
    static func escapeHTML(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for char in text {
            switch char {
            case "&": result.append("&amp;")
            case "<": result.append("&lt;")
            case ">": result.append("&gt;")
            case "\"": result.append("&quot;")
            case "'": result.append("&#39;")
            default: result.append(char)
            }
        }
        return result
    }

    /// JavaScript evaluated on the navigator once kudos succeeds so the card flips
    /// from "Give Kudos" to "Kudos Given" in place without reloading the chapter.
    static var markKudosGivenJS: String {
        """
        (function() {
            var el = document.getElementById('\(kudosLinkID)');
            if (!el) return false;
            el.setAttribute('data-kudos-given', 'true');
            el.setAttribute('aria-pressed', 'true');
            el.setAttribute('aria-disabled', 'true');
            el.setAttribute('aria-label', 'Kudos Given');
            el.removeAttribute('href');
            var label = el.querySelector('.kudos-ce-kudos-label');
            if (label) label.textContent = 'Kudos Given';
            return true;
        })();
        """
    }

    /// Updates the card's accent custom properties live if the user changes accent colour.
    static func updateAccentJS(style: ReaderChapterEndStyle) -> String {
        let accent = ReaderChapterEndStylesheet.safeCSSColor(style.accentHex, fallback: "#821019")
        let label = ReaderChapterEndStylesheet.safeCSSColor(style.accentLabelHex, fallback: "#FFFFFF")
        let lightInk = ReaderChapterEndStylesheet.safeCSSColor(style.lightAccentInkHex, fallback: accent)
        let sepiaInk = ReaderChapterEndStylesheet.safeCSSColor(style.sepiaAccentInkHex, fallback: accent)
        let darkInk = ReaderChapterEndStylesheet.safeCSSColor(style.darkAccentInkHex, fallback: "#EE8A93")
        return """
        (function() {
            var el = document.getElementById('\(sectionID)');
            if (!el) return false;
            el.style.setProperty('--kudos-ce-accent', '\(accent)');
            el.style.setProperty('--kudos-ce-accent-label', '\(label)');
            el.style.setProperty('--kudos-ce-accent-ink', '\(lightInk)');
            el.style.setProperty('--kudos-ce-accent-sepia-ink', '\(sepiaInk)');
            el.style.setProperty('--kudos-ce-accent-dark-ink', '\(darkInk)');
            return true;
        })();
        """
    }

    // MARK: - Section rendering

    private static func renderSection(
        card: ReaderChapterEndCardContext,
        endNote: String?
    ) -> String {
        let heading = "End of Chapter \(card.chapter)"
        let escapedHeading = escapeHTML(heading)
        let escapedNextTitle = escapeHTML(card.nextChapterTitle)
        let escapedNextHref = escapeHTML(card.nextChapterHref)
        let escapedFooter = escapeHTML(card.footer)

        let nextParts: [String?] = [card.nextChapterTitle, card.nextChapterTime]
        let nextAriaLabel = escapeHTML(nextParts.compactMap { $0 }.joined(separator: ", "))

        var parts: [String] = []
        // Zero-height marker right after the chapter's original prose so progression
        // normalization can separate original text length from the appended card.
        parts.append("<span id=\"\(anchorID)\" aria-hidden=\"true\"></span>")
        parts.append("<section id=\"\(sectionID)\" aria-label=\"\(escapedHeading)\">")
        parts.append(
            "<div class=\"kudos-ce-rule\" role=\"heading\" aria-level=\"2\">"
                + "<span class=\"kudos-ce-line\" aria-hidden=\"true\"></span>"
                + "<span class=\"kudos-ce-heading\">\(escapedHeading)</span>"
                + "<span class=\"kudos-ce-line\" aria-hidden=\"true\"></span>"
                + "</div>"
        )

        if let endNote, !endNote.isEmpty {
            parts.append(renderNoteBlock(endNote))
        }

        let timeMarkup: String = if let time = card.nextChapterTime, !time.isEmpty {
            "<span class=\"kudos-ce-next-time\">\(escapeHTML(time))</span>"
        } else {
            ""
        }
        parts.append(
            "<a id=\"\(nextLinkID)\" class=\"kudos-ce-next\" href=\"\(escapedNextHref)\" "
                + "aria-label=\"\(nextAriaLabel)\">"
                + "<span class=\"kudos-ce-next-text\">"
                + "<span class=\"kudos-ce-next-title\">\(escapedNextTitle)</span>"
                + timeMarkup
                + "</span>"
                + chevronSVG
                + "</a>"
        )

        if card.showsAO3Actions {
            parts.append(renderAO3Actions(chapter: card.chapter, kudosGiven: card.kudosGiven))
        }

        parts.append("<p class=\"kudos-ce-footer\">\(escapedFooter)</p>")
        parts.append("</section>")
        return parts.joined(separator: "\n")
    }

    private static func renderNoteBlock(_ endNote: String) -> String {
        let escapedNote = escapeHTML(endNote)
        return "<div class=\"kudos-ce-note\">"
            + "<span class=\"kudos-ce-note-heading\">Author’s note</span>"
            + "<input type=\"checkbox\" id=\"\(noteToggleID)\" class=\"kudos-ce-note-input\" "
            + "aria-label=\"Show all of the author’s note\" />"
            + "<p class=\"kudos-ce-note-text\">\(escapedNote)</p>"
            + "<label for=\"\(noteToggleID)\" class=\"kudos-ce-note-more\">"
            + "<span class=\"kudos-ce-more-text\">More</span>"
            + "<span class=\"kudos-ce-less-text\">Less</span>"
            + "</label>"
            + "</div>"
    }

    private static func renderAO3Actions(chapter: Int, kudosGiven: Bool) -> String {
        let commentHref = escapeHTML(ReaderChapterEndAction.comment(chapter: chapter).urlString)
        let commentLabel = escapeHTML("Comment on Ch \(chapter)")
        let commentAria = escapeHTML("Comment on chapter \(chapter)")

        let kudosHrefAttr = kudosGiven
            ? ""
            : " href=\"\(escapeHTML(ReaderChapterEndAction.kudos.urlString))\""
        let kudosGivenAttr = kudosGiven ? "true" : "false"
        let kudosDisabledAttr = kudosGiven ? " aria-disabled=\"true\"" : ""
        let kudosText = kudosGiven ? "Kudos Given" : "Give Kudos"

        return "<div class=\"kudos-ce-actions\">"
            + "<a id=\"\(commentLinkID)\" class=\"kudos-ce-btn\" href=\"\(commentHref)\" "
            + "role=\"button\" aria-label=\"\(commentAria)\">"
            + commentSVG
            + "<span class=\"kudos-ce-btn-label\">\(commentLabel)</span>"
            + "</a>"
            + "<a id=\"\(kudosLinkID)\" class=\"kudos-ce-btn kudos-ce-kudos\"\(kudosHrefAttr) "
            + "role=\"button\" aria-pressed=\"\(kudosGivenAttr)\"\(kudosDisabledAttr) "
            + "aria-label=\"\(kudosText)\" data-kudos-given=\"\(kudosGivenAttr)\">"
            + heartOutlineSVG
            + heartFillSVG
            + "<span class=\"kudos-ce-kudos-label\">\(kudosText)</span>"
            + "</a>"
            + "</div>"
    }

    // MARK: - Inline SVG icons (XHTML namespace declared)

    private static let chevronSVG =
        "<svg xmlns=\"http://www.w3.org/2000/svg\" aria-hidden=\"true\" width=\"8\" height=\"14\" "
        + "viewBox=\"0 0 8 14\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" "
        + "stroke-linecap=\"round\" stroke-linejoin=\"round\">"
        + "<path d=\"m1.5 1.5 5 5.5-5 5.5\" /></svg>"

    private static let commentSVG =
        "<svg xmlns=\"http://www.w3.org/2000/svg\" aria-hidden=\"true\" width=\"18\" height=\"18\" "
        + "viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.9\" "
        + "stroke-linecap=\"round\" stroke-linejoin=\"round\">"
        + "<path d=\"M4 5h16v11H9l-5 4z\" /></svg>"

    private static let heartOutlineSVG =
        "<svg xmlns=\"http://www.w3.org/2000/svg\" class=\"kudos-ce-heart-outline\" aria-hidden=\"true\" "
        + "width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" "
        + "stroke-width=\"1.9\" stroke-linecap=\"round\" stroke-linejoin=\"round\">"
        + "<path d=\"M12 20s-7.5-4.6-7.5-10.2A4.2 4.2 0 0 1 12 7.2a4.2 4.2 0 0 1 7.5 2.6"
        + "C19.5 15.4 12 20 12 20z\" /></svg>"

    private static let heartFillSVG =
        "<svg xmlns=\"http://www.w3.org/2000/svg\" class=\"kudos-ce-heart-fill\" aria-hidden=\"true\" "
        + "width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"currentColor\" stroke=\"none\">"
        + "<path d=\"M12 20s-7.5-4.6-7.5-10.2A4.2 4.2 0 0 1 12 7.2a4.2 4.2 0 0 1 7.5 2.6"
        + "C19.5 15.4 12 20 12 20z\" /></svg>"

    // MARK: - Helpers

    private static func splitPathAndSuffix(_ href: String) -> (path: String, suffix: String) {
        if let idx = href.firstIndex(where: { $0 == "#" || $0 == "?" }) {
            return (String(href[..<idx]), String(href[idx...]))
        }
        return (href, "")
    }

    private static func pathComponents(_ path: String) -> [String] {
        var normalized = path
        while normalized.hasPrefix("/") { normalized.removeFirst() }
        return normalized.split(separator: "/").map(String.init)
    }
}
