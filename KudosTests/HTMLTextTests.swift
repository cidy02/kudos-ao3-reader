import Testing
@testable import Kudos

/// Tests for the HTML/entity helpers used to render EPUB summaries and decode
/// double-encoded TOC titles.
struct HTMLTextTests {
    @Test func decodesNamedEntities() {
        #expect("Rayanne &amp; Lizzy".decodingHTMLEntities() == "Rayanne & Lizzy")
        #expect("a &lt;b&gt; c".decodingHTMLEntities() == "a <b> c")
        #expect("it&#39;s \u{2014} ok".decodingHTMLEntities() == "it's \u{2014} ok")
        #expect("&quot;hi&quot;".decodingHTMLEntities() == "\"hi\"")
    }

    @Test func decodesNumericEntities() {
        #expect("&#65;&#66;&#67;".decodingHTMLEntities() == "ABC")
        #expect("&#x41;&#x42;".decodingHTMLEntities() == "AB")
    }

    @Test func leavesPlainTextAndUnknownEntitiesUntouched() {
        #expect("plain text".decodingHTMLEntities() == "plain text")
        // Over-long / unknown entities are left verbatim rather than mangled.
        #expect("a &notarealentity; b".decodingHTMLEntities() == "a &notarealentity; b")
    }

    @Test func strippingHTMLRemovesTagsAndDecodes() {
        #expect("<p>Hello <b>world</b></p>".strippingHTML() == "Hello world")
        #expect("Tom &amp; Jerry".strippingHTML() == "Tom & Jerry")
    }

    @Test func strippingHTMLTurnsBreaksAndBlocksIntoNewlines() {
        #expect("Line1<br>Line2".strippingHTML() == "Line1\nLine2")
        #expect("<p>A</p><p>B</p>".strippingHTML() == "A\nB")
    }

    @Test func strippingHTMLCollapsesBlankRunsAndTrims() {
        #expect("<p>A</p><p></p><p></p><p>B</p>".strippingHTML() == "A\n\nB")
    }
}
