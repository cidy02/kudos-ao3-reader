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

    /// `WritingTextController.command` re-selects the *original* selection
    /// length at the offset this returns, so an offset that pushes that length
    /// past the replacement would hand a `UITextView` a range outside its own
    /// text. The caret-placing tags (`<hr>`, `<details>`, the lists) are the
    /// ones that can overshoot, so every tag is checked at every selection.
    @Test func aWritingInsertionNeverSelectsPastItsOwnText() {
        for tag in AO3MarkupTag.writing {
            for selected in ["", "keep", "one\ntwo"] {
                let insertion = WritingMarkup.insertion(
                    tag: tag.element, selected: selected, link: "https://example.com"
                )
                guard let insertion else {
                    Issue.record("<\(tag.element)> wrote nothing for \(selected.debugDescription)")
                    continue
                }
                #expect(insertion.contentOffset >= 0)
                #expect(insertion.contentOffset + selected.utf16.count <= insertion.text.utf16.count)
            }
        }
    }
}
