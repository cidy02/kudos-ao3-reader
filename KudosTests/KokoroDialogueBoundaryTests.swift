#if os(iOS)
import Foundation
import ReadiumShared
import Testing
@testable import Kudos

/// `.dialogue` used to be dead: `isBody()` treated it like `.paragraph`, so a
/// standalone `"Don't."` glued into surrounding narration and was voiced with
/// a long-form style row. Short quoted lines must stay their own utterance;
/// adjacent dialogue may still join so a back-and-forth that arrived as
/// fragments of one paragraph does not become one inference per line.
@Suite("Kokoro dialogue boundaries")
struct KokoroDialogueBoundaryTests {
    /// A unit carrying a real CSS selector. `classify` reads the selector off
    /// the locator — a `nil` locator makes these tests vacuous.
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

    /// Incomplete narration must not absorb the following quoted line.
    /// `endsUtterance` is false on the open block, which is the path that
    /// used to glue them.
    @Test func standaloneDialogueDoesNotJoinPrecedingNarration() {
        let units = [
            unit("She looked at him", selector: "html > body > p:nth-child(1)"),
            unit("\"Don't.\"", selector: "html > body > p:nth-child(2)")
        ]
        let blocks = KokoroSemanticDocument.blocks(from: units)
        #expect(blocks.map(\.kind) == [.paragraph, .dialogue])
        #expect(!blocks.contains { $0.text.contains("looked") && $0.text.contains("Don't") })

        let utterances = KokoroUtterancePacker.pack(units: units)
        #expect(!utterances.contains { $0.text.contains("looked") && $0.text.contains("Don't") })
        #expect(utterances.contains { $0.text.contains("Don't") })
    }

    /// Incomplete dialogue must not be absorbed into the following narration.
    @Test func standaloneDialogueDoesNotJoinFollowingNarration() {
        let units = [
            unit("\"Wait\"", selector: "html > body > p:nth-child(1)"),
            unit("she said, turning away.", selector: "html > body > p:nth-child(2)")
        ]
        let blocks = KokoroSemanticDocument.blocks(from: units)
        #expect(blocks.map(\.kind) == [.dialogue, .paragraph])
        #expect(!blocks.contains { $0.text.contains("Wait") && $0.text.contains("turning") })

        let utterances = KokoroUtterancePacker.pack(units: units)
        #expect(!utterances.contains { $0.text.contains("Wait") && $0.text.contains("turning") })
    }

    /// Curly close-quote is not in `endsUtterance`'s ASCII wrapper set, so a
    /// complete `“Don’t.”` used to look unfinished and swallow the next
    /// paragraph. The dialogue/narration barrier has to catch that.
    @Test func curlyQuotedDialogueDoesNotSwallowTheNextParagraph() {
        let units = [
            unit("“Don’t.”", selector: "html > body > p:nth-child(1)"),
            unit("He stepped backward.", selector: "html > body > p:nth-child(2)")
        ]
        let blocks = KokoroSemanticDocument.blocks(from: units)
        #expect(blocks.map(\.kind) == [.dialogue, .paragraph])
        #expect(!blocks.contains { $0.text.contains("Don’t") && $0.text.contains("stepped") })
        #expect(!blocks.contains { $0.text.contains("Don't") && $0.text.contains("stepped") })

        let utterances = KokoroUtterancePacker.pack(units: units)
        #expect(!utterances.contains { $0.text.contains("Don't") && $0.text.contains("stepped") })
        #expect(!utterances.contains { $0.text.contains("Don’t") && $0.text.contains("stepped") })
    }

    /// Adjacent dialogue still joins when the open line does not end an
    /// utterance. An interrupted exchange that Readium delivered as two
    /// `<p>`s must not become one inference per line.
    @Test func adjacentDialogueStillJoins() {
        let units = [
            unit("\"I told you—\"", selector: "html > body > p:nth-child(1)"),
            unit("\"No. You didn't.\"", selector: "html > body > p:nth-child(2)")
        ]
        let blocks = KokoroSemanticDocument.blocks(from: units)
        #expect(blocks.map(\.kind) == [.dialogue])
        #expect(blocks.contains { $0.text.contains("told you") && $0.text.contains("didn't") })

        let utterances = KokoroUtterancePacker.pack(units: units)
        #expect(utterances.contains { $0.text.contains("told you") && $0.text.contains("didn't") })
    }

    /// A back-and-forth that already lives in one HTML paragraph is one
    /// unit. We do not add a split that would make each quoted sentence its
    /// own inference.
    @Test func dialogueExchangeInsideOneParagraphStaysPacked() {
        let units = [
            unit(
                "\"Where are you going?\" \"Home.\" \"You can't.\"",
                selector: "html > body > p:nth-child(1)"
            )
        ]
        let blocks = KokoroSemanticDocument.blocks(from: units)
        #expect(blocks.map(\.kind) == [.dialogue])
        #expect(blocks.count == 1)

        let utterances = KokoroUtterancePacker.pack(units: units)
        #expect(utterances.count == 1)
        #expect(utterances[0].text.contains("Where are you going?"))
        #expect(utterances[0].text.contains("You can't."))
    }
}
#endif
