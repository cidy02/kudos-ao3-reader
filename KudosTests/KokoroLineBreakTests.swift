#if os(iOS)
import Foundation
import ReadiumShared
import Testing
@testable import Kudos

/// `<br>` seams used to be glued back into running prose because matching
/// cssSelectors forced a merge. Chat fic, epistolary works, transcripts and
/// verse need that seam to stay audible. Adjacent `<p>`s, headings, and
/// scene breaks must keep the pauses they already had.
@Suite("Kokoro line-break pauses")
struct KokoroLineBreakTests {
    /// A unit carrying a real CSS selector. `classify` and the line-break
    /// discriminator both read the selector off the locator — a `nil`
    /// locator can never produce a `.line` pause, and a fixture without one
    /// would leave the branch unexercised while still passing.
    private func unit(_ text: String, selector: String) -> TTSSpeechUnit {
        TTSSpeechUnit(
            text: text,
            locator: Locator(
                href: AnyURL(string: "chapter.xhtml")!,
                mediaType: .xhtml,
                locations: .init(otherLocations: ["cssSelector": .string(selector)])
            )
        )
    }

    @Test func linePauseSitsBetweenContinuationAndParagraph() {
        #expect(KokoroBoundary.none.rawValue == 0)
        #expect(KokoroBoundary.continuation.rawValue == 1)
        #expect(KokoroBoundary.line.rawValue == 2)
        #expect(KokoroBoundary.paragraph.rawValue == 3)
        #expect(KokoroBoundary.scene.rawValue == 4)
        #expect(KokoroBoundary.chapter.rawValue == 5)
        #expect(KokoroBoundary.line.pauseSeconds == 0.22)
        #expect(KokoroBoundary.continuation < KokoroBoundary.line)
        #expect(KokoroBoundary.line < KokoroBoundary.paragraph)
        #expect(max(KokoroBoundary.line, KokoroBoundary.scene) == .scene)
        #expect(max(KokoroBoundary.line, KokoroBoundary.chapter) == .chapter)
    }

    @Test func twoLinesInOneParagraphBecomeTwoUtterancesWithALinePause() {
        let units = [
            unit("hey", selector: "html > body > p:nth-child(1)"),
            unit("are you there", selector: "html > body > p:nth-child(1)")
        ]
        let blocks = KokoroSemanticDocument.blocks(from: units)
        #expect(blocks.count == 2)
        #expect(blocks[0].endsAtLineBreak)
        #expect(!blocks[1].endsAtLineBreak)

        let utterances = KokoroUtterancePacker.pack(units: units)
        #expect(utterances.count == 2)
        #expect(utterances[0].pauseAfter == .line)
        #expect(utterances[1].pauseAfter == .paragraph)
        #expect(utterances[0].text == "hey")
        #expect(utterances[1].text == "are you there")
        #expect(
            KokoroUtterancePacker.reconstructedText(from: utterances)
                == "hey are you there"
        )
    }

    @Test func adjacentParagraphsKeepAParagraphPause() {
        let units = [
            unit("Rain stitched the windows.", selector: "html > body > p:nth-child(1)"),
            unit("He opened the letter.", selector: "html > body > p:nth-child(2)")
        ]
        let utterances = KokoroUtterancePacker.pack(units: units)
        #expect(utterances.count == 2)
        #expect(utterances[0].pauseAfter == .paragraph)
        #expect(utterances[1].pauseAfter == .paragraph)
        #expect(
            KokoroUtterancePacker.reconstructedText(from: utterances)
                == "Rain stitched the windows. He opened the letter."
        )
    }

    /// The last line of a `<p>` is followed by a new paragraph, not another
    /// line. It must keep `.paragraph`. The last chat line ends with `?` so
    /// `endsUtterance` still refuses to glue it onto the next `<p>` — that
    /// join path never used the selector shortcut and is unchanged.
    @Test func lastLineOfABrokenParagraphIsAParagraphPause() {
        let units = [
            unit("hey", selector: "html > body > p:nth-child(1)"),
            unit("are you there?", selector: "html > body > p:nth-child(1)"),
            unit("She put the phone down.", selector: "html > body > p:nth-child(2)")
        ]
        let blocks = KokoroSemanticDocument.blocks(from: units)
        #expect(blocks.map(\.endsAtLineBreak) == [true, false, false])

        let utterances = KokoroUtterancePacker.pack(units: units)
        #expect(utterances.count == 3)
        #expect(utterances[0].pauseAfter == .line)
        #expect(utterances[1].pauseAfter == .paragraph)
        #expect(utterances[2].pauseAfter == .paragraph)
        #expect(
            KokoroUtterancePacker.reconstructedText(from: utterances)
                == "hey are you there? She put the phone down."
        )
    }

    @Test func headingStillYieldsAChapterPauseAndDoesNotJoin() {
        let units = [
            unit("Chapter 12", selector: "html > body > h2"),
            unit("Rain stitched the windows.", selector: "html > body > p:nth-child(2)")
        ]
        let utterances = KokoroUtterancePacker.pack(units: units)
        #expect(utterances.count == 2)
        #expect(utterances[0].text == "Chapter 12")
        #expect(utterances[0].pauseAfter == .chapter)
        #expect(utterances[1].text == "Rain stitched the windows.")
    }

    @Test func sceneBreakStillPromotesThePrecedingPause() {
        let units = [
            unit("He opened the letter.", selector: "html > body > p:nth-child(1)"),
            unit("* * *", selector: "html > body > hr"),
            unit("Dawn came anyway.", selector: "html > body > p:nth-child(3)")
        ]
        let utterances = KokoroUtterancePacker.pack(units: units)
        #expect(utterances.count == 2)
        #expect(utterances[0].pauseAfter == .scene)
        #expect(utterances[1].text == "Dawn came anyway.")
        #expect(!KokoroUtterancePacker.reconstructedText(from: utterances).contains("*"))
    }

    @Test func aLineBreakThenASceneBreakPromotesOnlyTheLastLine() {
        let units = [
            unit("line one", selector: "html > body > p:nth-child(1)"),
            unit("line two", selector: "html > body > p:nth-child(1)"),
            unit("* * *", selector: "html > body > hr"),
            unit("Dawn came anyway.", selector: "html > body > p:nth-child(3)")
        ]
        let utterances = KokoroUtterancePacker.pack(units: units)
        #expect(utterances.map(\.pauseAfter) == [.line, .scene, .paragraph])
        #expect(
            KokoroUtterancePacker.reconstructedText(from: utterances)
                == "line one line two Dawn came anyway."
        )
    }

    @Test func brokenLinesFollowedByAHeadingKeepTheChapterPauseOnTheLastLine() {
        let units = [
            unit("the last chat line", selector: "html > body > p:nth-child(1)"),
            unit("ok wait", selector: "html > body > p:nth-child(1)"),
            unit("Chapter 2", selector: "html > body > h2")
        ]
        let utterances = KokoroUtterancePacker.pack(units: units)
        #expect(utterances.count == 3)
        #expect(utterances[0].pauseAfter == .line)
        #expect(utterances[1].pauseAfter == .chapter)
        #expect(utterances[2].pauseAfter == .chapter)
        #expect(utterances[2].text == "Chapter 2")
    }

    /// Adjacent `<p>`s that do not end an utterance still merge. That path
    /// never used the selector shortcut, and must not start splitting.
    @Test func incompleteAdjacentParagraphsStillJoin() {
        let units = [
            unit("She began to", selector: "html > body > p:nth-child(1)"),
            unit("read the letter.", selector: "html > body > p:nth-child(2)")
        ]
        let utterances = KokoroUtterancePacker.pack(units: units)
        #expect(utterances.count == 1)
        #expect(utterances[0].text == "She began to read the letter.")
        #expect(utterances[0].pauseAfter == .paragraph)
    }
    /// A paragraph that does not end a sentence still joins into the next
    /// paragraph's first line — that behaviour predates this change and is
    /// deliberate. But the merged block kept the *first* paragraph's
    /// selector, so the `<br>` seam that follows inside the second paragraph
    /// was invisible and its lines ran together.
    ///
    /// The stored selector has to track the last unit absorbed, because that
    /// is what the next seam is compared against.
    @Test func aCrossParagraphJoinDoesNotHideTheFollowingLineSeam() {
        let units = [
            unit("She began to", selector: "html > body > p:nth-child(1)"),
            unit("read the letter", selector: "html > body > p:nth-child(2)"),
            unit("and then she wept.", selector: "html > body > p:nth-child(2)")
        ]
        let utterances = KokoroUtterancePacker.pack(units: units)
        let pauses = utterances.map(\.pauseAfter)
        #expect(
            pauses.contains(.line),
            "the seam inside the second paragraph should be a line pause, got \(pauses)"
        )
        let spoken = KokoroUtterancePacker.reconstructedText(from: utterances)
        #expect(spoken == "She began to read the letter and then she wept.")
    }
}
#endif
