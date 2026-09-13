import Foundation
import Testing
@testable import Kudos

/// The comment tray and the chapter editor now write the same tags through the
/// same function. That is only safe while three things hold: every tag survives
/// AO3's sanitizer, each surface still offers its own list, and an href is
/// never written unchecked.
struct AO3MarkupTests {
    /// `Sanitize::Config::ARCHIVE`'s element list, from otwarchive
    /// `config/initializers/gem-plugin_config/sanitizer_config.rb`. A button
    /// that writes anything else produces markup the server strips on the way
    /// in — a control that does nothing, with no way for the user to tell.
    private static let archiveElements: Set<String> = [
        "a", "abbr", "acronym", "address", "b", "big", "blockquote", "br", "caption", "center", "cite",
        "code", "col", "colgroup", "details", "dd", "del", "dfn", "div", "dl", "dt", "em", "figcaption",
        "figure", "h1", "h2", "h3", "h4", "h5", "h6", "hr", "i", "img", "ins", "kbd", "li", "ol", "p",
        "pre", "q", "rp", "rt", "ruby", "s", "samp", "small", "span", "strike", "strong", "sub", "summary",
        "sup", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "tt", "u", "ul", "var"
    ]

    @Test func everyOfferedTagSurvivesAO3sSanitizer() {
        for tag in AO3MarkupTag.allCases {
            #expect(Self.archiveElements.contains(tag.element), "<\(tag.element)> is not in ARCHIVE")
        }
        // `img` is the one element ARCHIVE keeps that neither surface offers:
        // AO3 hosts no images, so the tag could only ever point off-site.
        #expect(Self.archiveElements.contains("img"))
        #expect(!AO3MarkupTag.allCases.contains { $0.element == "img" })
    }

    /// One vocabulary, two lists. `<p>` and `<br>` are the chapter editor's
    /// alone: AO3 paragraphs a comment body itself (`add_paragraphs_to_text`),
    /// so on that surface the buttons would only let a reader double-space
    /// their own comment.
    @Test func theTwoSurfacesOfferTheirOwnSliceOfOneVocabulary() {
        #expect(AO3MarkupTag.comments.count == 15)
        #expect(AO3MarkupTag.writing.count == 17)
        #expect(Set(AO3MarkupTag.comments).isSubset(of: Set(AO3MarkupTag.writing)))
        #expect(!AO3MarkupTag.comments.contains(.paragraph))
        #expect(!AO3MarkupTag.comments.contains(.lineBreak))
        #expect(AO3MarkupTag.writing.contains(.paragraph))
        #expect(AO3MarkupTag.writing.contains(.lineBreak))
        // `CommentMarkupTag` mirrors the comment list case for case; this is the
        // pin that stops the two drifting apart in silence.
        #expect(AO3MarkupTag.comments.map(\.rawValue) == CommentMarkupTag.allCases.map(\.rawValue))
        #expect(CommentMarkupTag.allCases.map(\.element) == AO3MarkupTag.comments.map(\.element))
    }

    /// Where the two implementations disagreed: one wrote an empty href for the
    /// user to fill in, the other demanded a checked, escaped URL. Both survive
    /// — an href is escaped when there is one, and a scheme this app will not
    /// write is refused rather than embedded.
    @Test func anHrefIsEscapedAndOnlyAWebSchemeIsEverWritten() {
        let text = "site"
        let whole = text.startIndex..<text.endIndex

        let written = AO3Markup.splice(.link, in: text, over: whole, link: "https://example.com/?a=1&b=2")
        #expect(written.text == "<a href=\"https://example.com/?a=1&amp;b=2\">site</a>")

        #expect(AO3Markup.safeLink("https://example.com"))
        #expect(AO3Markup.safeLink("HTTP://example.com"))
        #expect(AO3Markup.safeLink("mailto:someone@example.com"))
        #expect(!AO3Markup.safeLink("javascript:alert(1)"))
        #expect(!AO3Markup.safeLink("data:text/html,<script>alert(1)</script>"))
        #expect(!AO3Markup.safeLink("/relative/path"))
        #expect(!AO3Markup.safeLink(""))

        // A refused scheme never reaches the buffer: the tag falls back to the
        // empty href the comment tray writes, not to the string it was handed.
        let refused = AO3Markup.splice(.link, in: text, over: whole, link: "javascript:alert(1)")
        #expect(refused.text == "<a href=\"\">site</a>")
        #expect(WritingMarkup.insertion(tag: "a", selected: "site", link: "javascript:alert(1)") == nil)
        #expect(WritingMarkup.insertion(tag: "a", selected: "site") == nil)
    }

    /// The invariant a shared core is supposed to buy: for the same input, both
    /// surfaces select the same span. Not "the offset is in bounds" — that was
    /// satisfied by the bug it replaced, where `<details>` selected `</summ` and
    /// the next keystroke ate its own closing tag.
    ///
    /// The comment side returns a `Range<String.Index>` over the whole buffer;
    /// the writing side returns a UTF-16 offset and length relative to the
    /// replacement. Compared in the frame they share.
    @Test func bothSurfacesSelectTheSameSpanForTheSameInput() {
        let link = "https://example.com"
        for tag in AO3MarkupTag.comments where AO3MarkupTag.writing.contains(tag) {
            for text in ["", "keep", "one\ntwo", "the coat", "done\n\nmore"] {
                for (lower, upper) in [(0, 0), (0, text.count), (text.count, text.count)] {
                    // Bound separately: a line starting with `..<` parses as the
                    // prefix PartialRangeUpTo operator and silently yields an index.
                    let lowerIndex = text.index(text.startIndex, offsetBy: lower)
                    let upperIndex = text.index(text.startIndex, offsetBy: upper)
                    let range = lowerIndex..<upperIndex
                    // The same link on both sides: `<a>` writes an escaped href
                    // when given a usable URL and an empty one otherwise, so
                    // feeding the two sides different links compares two
                    // different insertions and proves nothing.
                    let splice = AO3Markup.splice(tag, in: text, over: range, link: link)
                    guard let writing = WritingMarkup.insertion(
                        tag: tag.element, in: text, over: range, link: link
                    ) else { continue }

                    let label = "<\(tag.element)> in \(text.debugDescription) over \(lower)..<\(upper)"
                    #expect(writing.text == splice.text, "\(label): replacement differs")
                    #expect(writing.contentOffset == splice.prefix.utf16.count, "\(label): offset differs")
                    #expect(writing.contentLength == splice.body.utf16.count, "\(label): length differs")
                    #expect(
                        writing.contentOffset + writing.contentLength <= writing.text.utf16.count,
                        "\(label): selection runs past the replacement"
                    )
                }
            }
        }
    }

    /// The corruption the shared core introduced on the writing side, pinned per
    /// tag rather than as one blanket rule — because the rule is not blanket.
    ///
    /// `<hr>` and `<details>` place a caret whatever is selected. The lists only
    /// caret when there is nothing to wrap; given lines they come back over the
    /// `<li>` items on purpose, so a second tag nests inside the list instead of
    /// wrapping `<ul>` in `<em>`. Asserting a caret there would contradict the
    /// behaviour the core exists to provide.
    @Test func caretPlacingTagsSelectNothingOnTheWritingSurface() {
        for element in ["hr", "details"] {
            let insertion = WritingMarkup.insertion(tag: element, selected: "secret")
            guard let insertion else {
                Issue.record("<\(element)> wrote nothing")
                continue
            }
            #expect(insertion.contentLength == 0, "<\(element)> re-selected markup instead of placing a caret")
        }

        for element in ["ul", "ol"] {
            let empty = WritingMarkup.insertion(tag: element, selected: "")
            #expect(empty?.contentLength == 0, "<\(element)> with nothing selected should place a caret")

            guard let filled = WritingMarkup.insertion(tag: element, selected: "one\ntwo") else {
                Issue.record("<\(element)> wrote nothing")
                continue
            }
            // Over the items, not over the whole block and not over the old
            // selection's length: that span is what lets a second tag nest.
            let selectedSpan = (filled.text as NSString).substring(
                with: NSRange(location: filled.contentOffset, length: filled.contentLength)
            )
            #expect(selectedSpan == "<li>one</li>\n<li>two</li>", "<\(element)> selected \(selectedSpan.debugDescription)")
        }
    }
}
