#if os(iOS)
import Foundation
import XCTest
@testable import Kudos

/// Kokoro's vocab carries `“` and `”` as tokens distinct from `"`, and reads
/// them as different intonation cues. `KokoroSpeechNormalizer` therefore
/// resolves every double quote to a direction instead of flattening it, and
/// these tests pin the direction it picks.
@MainActor
final class KokoroQuoteDirectionTests: XCTestCase {
    /// The double quotes left in `text`, in order. A straight `"` showing up
    /// here is itself the failure.
    private func quoteShape(_ text: String) -> String {
        String(text.filter { $0 == "\"" || $0 == "\u{201C}" || $0 == "\u{201D}" })
    }

    func testCurlyQuotesSurviveAsThemselves() {
        let normalized = KokoroSpeechNormalizer.normalize(KokoroNaturalnessCorpus.curlyQuoted)
        XCTAssertEqual(quoteShape(normalized), "\u{201C}\u{201D}")
        XCTAssertFalse(normalized.contains("\""))
    }

    func testStraightQuotesArePromotedByPosition() {
        let normalized = KokoroSpeechNormalizer.normalize("\"Hello,\" he said. \"Goodbye.\"")
        XCTAssertEqual(normalized, "\u{201C}Hello,\u{201D} he said. \u{201C}Goodbye.\u{201D}")
    }

    func testStraightQuoteAroundNarrationIsPromoted() {
        // Mid-sentence open (after a space) and close (after a letter), with
        // no sentence punctuation to lean on.
        let normalized = KokoroSpeechNormalizer.normalize("He said \"maybe\" and left.")
        XCTAssertEqual(normalized, "He said \u{201C}maybe\u{201D} and left.")
    }

    func testUnclosedQuoteKeepsOpeningTheNextParagraph() {
        // A speech running across paragraphs opens every paragraph and closes
        // only the last. A toggle would call the second one a close.
        let normalized = KokoroSpeechNormalizer.normalize(
            "\"I went there first.\n\"Then I came back.\""
        )
        XCTAssertEqual(quoteShape(normalized), "\u{201C}\u{201C}\u{201D}")
    }

    func testInterruptedDialogueClosesOnTheDash() {
        let normalized = KokoroSpeechNormalizer.normalize(
            KokoroNaturalnessCorpus.interruptedPair
        )
        XCTAssertEqual(quoteShape(normalized), "\u{201C}\u{201D}\u{201C}\u{201D}")
        XCTAssertTrue(normalized.contains("\u{2014}\u{201D}"))
    }

    func testQuoteReopeningAfterADashIsAnOpen() {
        // `—"` is the one place the running state has to break the tie: it
        // closes an open speech and opens a closed one.
        let normalized = KokoroSpeechNormalizer.normalize("He turned—\"Wait!\"")
        XCTAssertEqual(quoteShape(normalized), "\u{201C}\u{201D}")
    }

    func testNestedQuoteResolvesInnerAndOuterPairs() {
        let normalized = KokoroSpeechNormalizer.normalize(
            "\"I heard him say \"get out\" and then he left.\""
        )
        XCTAssertEqual(quoteShape(normalized), "\u{201C}\u{201C}\u{201D}\u{201D}")
    }

    func testQuoteAtEitherEndOfTheTextIsResolved() {
        XCTAssertEqual(KokoroSpeechNormalizer.normalize("\""), "\u{201C}")
        XCTAssertEqual(KokoroSpeechNormalizer.normalize("Fine.\""), "Fine.\u{201D}")
    }

    func testGuillemetsAndLowNineMapToVocabQuotes() {
        XCTAssertEqual(
            KokoroSpeechNormalizer.normalize("\u{00AB}Bonjour.\u{00BB}"),
            "\u{201C}Bonjour.\u{201D}"
        )
        XCTAssertEqual(
            KokoroSpeechNormalizer.normalize("\u{201E}Guten Tag.\u{201D}"),
            "\u{201C}Guten Tag.\u{201D}"
        )
    }

    func testApostrophesAreUntouchedByQuoteDirection() {
        // FluidAudio #774: `’` must still fold to ASCII `'`, and must never be
        // mistaken for a quote that needs a direction.
        let normalized = KokoroSpeechNormalizer.normalize("\u{201C}She wasn\u{2019}t his.\u{201D}")
        XCTAssertEqual(normalized, "\u{201C}She wasn't his.\u{201D}")
        XCTAssertEqual(KokoroSpeechNormalizer.words(in: normalized), ["She", "wasn't", "his"])
    }

    func testStraightQuotedBlockIsStillClassifiedAsDialogue() {
        let blocks = KokoroSemanticDocument.blocks(from: [
            KokoroNaturalnessCorpus.unit("\"No.\"", selector: "html > body > p:nth-child(1)"),
            KokoroNaturalnessCorpus.unit("Rain fell.", selector: "html > body > p:nth-child(2)")
        ])
        XCTAssertEqual(blocks.first?.kind, .dialogue)
        XCTAssertEqual(blocks.last?.kind, .paragraph)
    }

    func testOverBudgetSentenceDoesNotSplitInsideAQuote() {
        let narration = String(
            repeating: "The corridor stretched on, lined with portraits, ",
            count: 8
        )
        let quoted = "\"stop, please, just stop,\""
        let units = [KokoroNaturalnessCorpus.unit(
            "\(narration)and she said, \(quoted) before \(narration)the end."
        )]
        let utterances = KokoroUtterancePacker.pack(units: units)
        XCTAssertGreaterThan(utterances.count, 1, "expected the comma split to fire")
        XCTAssertTrue(
            utterances.contains {
                $0.text.contains("\u{201C}stop, please, just stop,\u{201D}")
            },
            "the quoted clause was cut at one of its inner commas"
        )
    }
}
#endif
