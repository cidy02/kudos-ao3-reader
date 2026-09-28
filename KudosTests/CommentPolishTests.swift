import Foundation
import SwiftUI
import Testing
@testable import Kudos

/// T-271. The comment polish decisions that are rules rather than pixels:
/// the composer's header word and drag-taller footer, the tray's columns and
/// heading range, and the signed-out action strip.
struct CommentPolishTests {
    private func applyHeading(_ level: Int, _ text: String = "Part two") -> CommentMarkupResult {
        let end = text.index(text.startIndex, offsetBy: text.count)
        return CommentMarkup.apply(.heading, to: text, in: text.startIndex..<end, headingLevel: level)
    }

    // MARK: - Composer copy (1ba)

    @Test func aReplyPostsAsPost() {
        #expect(CommentComposerSheet.confirmationAction(isEdit: false, isReply: true) == "Post")
        #expect(CommentComposerSheet.confirmationAction(isEdit: false, isReply: false) == "Post")
        #expect(CommentComposerSheet.confirmationAction(isEdit: true, isReply: true) == "Save")
        #expect(!CommentComposerSheet.confirmationAction(isEdit: false, isReply: true).contains("Reply"))
    }

    @Test func theFooterSaysTheSheetDragsTaller() {
        #expect(CommentComposerSheet.dragTallerFooter == "Drag the sheet taller")
    }

    // MARK: - Tray (1bf)

    @Test func theTrayIsFourColumnsUntilAccessibilitySizes() {
        #expect(CommentFormattingLayout.columnCount(for: .large) == 4)
        #expect(CommentFormattingLayout.columnCount(for: .xxxLarge) == 4)
        #expect(CommentFormattingLayout.restingColumnCount == 4)
        #expect(CommentFormattingLayout.gridGap == 7)
        #expect(CommentFormattingLayout.tileMinHeight == 58)
        #expect(CommentFormattingLayout.columnCount(for: .accessibility1) == 2)
        #expect(CommentFormattingLayout.columnCount(for: .accessibility2) == 2)
        #expect(CommentFormattingLayout.columnCount(for: .accessibility3) == 1)
        #expect(CommentFormattingLayout.columnCount(for: .accessibility5) == 1)
        #expect(CommentFormattingLayout.tilePaddingH > 0)
        #expect(CommentFormattingLayout.tilePaddingV > 0)
    }

    /// Q20: a comment may contain h1 through h6, and not a level past that.
    /// The shared vocabulary's default element stays h3 for the chapter editor.
    @Test func commentsOfferEveryHeadingTheSanitizerKeeps() {
        #expect(CommentMarkup.headingLevels == Array(1 ... 6))
        #expect(CommentMarkup.headingLevels.map { CommentMarkup.headingElement(level: $0) }
            == ["h1", "h2", "h3", "h4", "h5", "h6"])
        #expect(CommentMarkup.headingElement(level: 0) == nil)
        #expect(CommentMarkup.headingElement(level: 7) == nil)
        #expect(CommentMarkupTag.heading.element == "h3")

        #expect(applyHeading(1).text == "<h1>Part two</h1>")
        #expect(applyHeading(6).text == "<h6>Part two</h6>")
        #expect(applyHeading(3).text == "<h3>Part two</h3>")
        // Out of range falls back to h3 rather than writing a tag AO3 strips.
        #expect(applyHeading(7).text == "<h3>Part two</h3>")
        let wrapped = applyHeading(2)
        #expect(String(wrapped.text[wrapped.selection]) == "Part two")
    }

    /// The Heading tile then an h1 chip re-levels the heading; tapping chips
    /// in turn never stacks one heading inside another.
    @Test func aHeadingChipRelevelsTheHeadingAroundTheSelection() {
        let tiled = applyHeading(CommentMarkup.defaultHeadingLevel)
        let chipped = CommentMarkup.apply(
            .heading, to: tiled.text, in: tiled.selection, headingLevel: 1
        )
        #expect(chipped.text == "<h1>Part two</h1>")
        #expect(String(chipped.text[chipped.selection]) == "Part two")
        let again = CommentMarkup.apply(
            .heading, to: chipped.text, in: chipped.selection, headingLevel: 5
        )
        #expect(again.text == "<h5>Part two</h5>")
        // Not a wrapper of the selection itself: a heading elsewhere is kept.
        let prose = "<h2>Title</h2> body"
        let body = prose.range(of: "body")!
        #expect(CommentMarkup.apply(.heading, to: prose, in: body, headingLevel: 1).text
            == "<h2>Title</h2> <h1>body</h1>")
    }

    /// Part of a heading's body, a word beside inline markup, a heading in a
    /// list item: each re-levels the heading it sits in, whole body kept.
    @Test func aHeadingChipRelevelsTheHeadingThatContainsThePartialSelection() {
        func relevel(_ text: String, selecting word: String, to level: Int) -> CommentMarkupResult {
            CommentMarkup.apply(.heading, to: text, in: text.range(of: word)!, headingLevel: level)
        }
        let partial = relevel("<h3>one two</h3>", selecting: "two", to: 1)
        #expect(partial.text == "<h1>one two</h1>")
        #expect(String(partial.text[partial.selection]) == "one two")
        #expect(relevel("<h3><em>one</em> two</h3>", selecting: "one", to: 2).text
            == "<h2><em>one</em> two</h2>")
        #expect(relevel("<ul><li><h4>item</h4></li></ul>", selecting: "item", to: 5).text
            == "<ul><li><h5>item</h5></li></ul>")
        // A closed heading earlier on the line does not capture later prose.
        #expect(relevel("<h3>one</h3> two", selecting: "two", to: 1).text
            == "<h3>one</h3> <h1>two</h1>")
    }

    // MARK: - Signed-out action row

    @Test func aSignedOutStripDoesNotReserveTheReplyBand() {
        #expect(CommentActionRowLayout.showsLeadingReply(canReply: true, isLoggedIn: true))
        #expect(!CommentActionRowLayout.showsLeadingReply(canReply: true, isLoggedIn: false))
        #expect(!CommentActionRowLayout.showsLeadingReply(canReply: false, isLoggedIn: true))

        #expect(CommentActionRowLayout.layoutHeight(showsLeadingReply: true) == 40)
        #expect(CommentActionRowLayout.layoutHeight(showsLeadingReply: false) == 28)
        #expect(
            CommentActionRowLayout.layoutHeight(showsLeadingReply: false)
                < CommentActionRowLayout.hitTarget
        )
        // The 44pt target is still there; it overlaps instead of adding height.
        let overlap = CommentActionRowLayout.verticalOverlap(showsLeadingReply: false)
        #expect(overlap > CommentActionRowLayout.verticalOverlap(showsLeadingReply: true))
        #expect(
            CommentActionRowLayout.layoutHeight(showsLeadingReply: false) + 2 * overlap
                == CommentActionRowLayout.hitTarget
        )
    }
}
