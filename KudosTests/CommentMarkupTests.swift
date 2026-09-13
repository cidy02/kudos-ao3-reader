import Foundation
import Testing
@testable import Kudos

/// Artboard 1bf's tray is only as honest as the buffer underneath it: what the
/// button writes is what posts, so every one of these pins an exact string.
struct CommentMarkupTests {
    /// Applies a tag over a character range, which is how a test says "the user
    /// had these words selected" without spelling out `String.Index` arithmetic.
    private func apply(
        _ tag: CommentMarkupTag,
        _ text: String,
        _ lower: Int,
        _ upper: Int
    ) -> CommentMarkupResult {
        let start = text.index(text.startIndex, offsetBy: lower)
        let end = text.index(text.startIndex, offsetBy: upper)
        return CommentMarkup.apply(tag, to: text, in: start..<end)
    }

    /// What the caret would produce next, so a test can state the point of an
    /// insertion point rather than an offset.
    private func typing(_ typed: String, into result: CommentMarkupResult) -> String {
        var text = result.text
        text.replaceSubrange(result.selection, with: typed)
        return text
    }

    // MARK: - Wrapping

    @Test func wrapsTheSelectionAndLeavesItOnTheWords() {
        let result = apply(.bold, "the coat", 0, 8)
        #expect(result.text == "<strong>the coat</strong>")
        #expect(String(result.text[result.selection]) == "the coat")
    }

    @Test func wrapsOnlyWhatWasSelected() {
        let result = apply(.italic, "he wore the coat home", 8, 16)
        #expect(result.text == "he wore <em>the coat</em> home")
    }

    @Test func aCaretInsertsAnEmptyPairToTypeInto() {
        let result = apply(.italic, "", 0, 0)
        #expect(result.text == "<em></em>")
        #expect(result.selection.isEmpty)
        #expect(typing("soon", into: result) == "<em>soon</em>")
    }

    /// Nesting order matters: AO3's parser rewrites mismatched closing tags, so
    /// the second tag has to land *inside* the first rather than crossing it.
    @Test func aSecondTagNestsAroundTheSameWords() {
        let bold = apply(.bold, "the coat", 0, 8)
        let both = CommentMarkup.apply(.italic, to: bold.text, in: bold.selection)
        #expect(both.text == "<strong><em>the coat</em></strong>")
        #expect(String(both.text[both.selection]) == "the coat")
    }

    // MARK: - Standalone and block tags

    @Test func theDividerStandsAloneOnItsOwnLine() {
        let result = apply(.divider, "done", 4, 4)
        #expect(result.text == "done\n<hr>\n")
        #expect(result.selection.isEmpty)
        #expect(typing("and then", into: result) == "done\n<hr>\nand then")
    }

    /// `<hr>` wraps nothing, so a selection has to survive it — a formatting
    /// button that deletes the user's words is worse than no button.
    @Test func theDividerKeepsTheSelectedWords() {
        let result = apply(.divider, "keep me", 0, 7)
        #expect(result.text == "keep me\n<hr>\n")
    }

    @Test func theDividerDoesNotDoubleAnExistingLineBreak() {
        let result = apply(.divider, "done\n\nmore", 5, 5)
        #expect(result.text == "done\n<hr>\nmore")
    }

    @Test func bulletsMakeOneItemPerNonEmptyLine() {
        let result = apply(.bullets, "one\n\ntwo", 0, 8)
        #expect(result.text == "<ul>\n<li>one</li>\n<li>two</li>\n</ul>")
        #expect(String(result.text[result.selection]) == "<li>one</li>\n<li>two</li>")
    }

    @Test func anEmptyListHasOneItemReadyToTypeInto() {
        let result = apply(.numbers, "", 0, 0)
        #expect(result.text == "<ol>\n<li></li>\n</ol>")
        #expect(typing("first", into: result) == "<ol>\n<li>first</li>\n</ol>")
    }

    @Test func aListOfBlankLinesFallsBackToOneEmptyItem() {
        let result = apply(.bullets, "  \n  ", 0, 5)
        #expect(result.text == "<ul>\n<li></li>\n</ul>")
    }

    // MARK: - Link and spoiler

    @Test func theLinkPutsTheCaretInsideTheEmptyHref() {
        let result = apply(.link, "the coat", 0, 8)
        #expect(result.text == "<a href=\"\">the coat</a>")
        #expect(result.selection.isEmpty)
        #expect(typing("https://example.com", into: result)
            == "<a href=\"https://example.com\">the coat</a>")
    }

    @Test func theSpoilerPutsTheCaretInTheSummaryAndKeepsTheBody() {
        let result = apply(.spoiler, "he dies", 0, 7)
        #expect(result.text == "<details><summary></summary>he dies</details>")
        #expect(typing("Chapter 4", into: result)
            == "<details><summary>Chapter 4</summary>he dies</details>")
    }

    // MARK: - Boundaries

    @Test func aSelectionAtTheStartOfTheBuffer() {
        let result = apply(.bold, "coat", 0, 0)
        #expect(result.text == "<strong></strong>coat")
        #expect(typing("the", into: result) == "<strong>the</strong>coat")
    }

    @Test func aSelectionAtTheEndOfTheBuffer() {
        let result = apply(.bold, "coat", 4, 4)
        #expect(result.text == "coat<strong></strong>")
        #expect(typing("s", into: result) == "coat<strong>s</strong>")
    }

    /// A selection can outlive the string it was taken from. Appending is the
    /// only lossless answer: a stale index clamped into range names a span the
    /// user never selected.
    @Test func aStaleSelectionAppendsInsteadOfTrapping() {
        let older = "a far longer draft than the one in the field now"
        // Kept on one line: a line *starting* with `..<` parses as the prefix
        // PartialRangeUpTo operator, which silently makes this a String.Index.
        let stale = older.index(older.startIndex, offsetBy: 30)..<older.index(older.startIndex, offsetBy: 34)
        let result = CommentMarkup.apply(.bold, to: "short", in: stale)
        #expect(result.text == "short<strong></strong>")
    }

    @Test func aCaretInsideAWordSplitsNothing() {
        let result = apply(.bold, "the coat", 4, 4)
        #expect(result.text == "the <strong></strong>coat")
        #expect(typing("warm ", into: result) == "the <strong>warm </strong>coat")
    }

    // MARK: - The offered set

    /// Only tags AO3's sanitizer keeps. Image is deliberately absent: AO3 hosts
    /// no images, so the tag could only ever point off-site.
    @Test func onlyTheTagsAO3KeepsAreOffered() {
        #expect(CommentMarkupTag.allCases.count == 15)
        #expect(!CommentMarkupTag.allCases.contains { $0.element == "img" })
        #expect(CommentMarkupTag.Group.text.tags.map(\.tagLabel)
            == ["strong", "em", "u", "s", "sup", "sub", "small", "code"])
        #expect(CommentMarkupTag.Group.blocksAndLinks.tags.map(\.tagLabel)
            == ["blockquote", "ul", "ol", "h3", "hr", "a href", "details"])
    }

    /// The artboard labels the heading "h1–h6", which is a range rather than
    /// something anyone can type. One level is written, and the tray prints the
    /// level it writes.
    @Test func theHeadingWritesOneLevelAndPrintsIt() {
        #expect(CommentMarkupTag.heading.element == "h3")
        #expect(CommentMarkupTag.heading.tagLabel == "h3")
        #expect(apply(.heading, "Part two", 0, 8).text == "<h3>Part two</h3>")
    }
}
