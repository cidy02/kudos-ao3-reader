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
