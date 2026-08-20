#if os(iOS)
import ReadiumShared
import XCTest
@testable import Kudos

@MainActor
final class TTSSpeechUnitTests: XCTestCase {

    func testSentenceChunksCarryExactReadiumRanges() {
        let source = "Dr. Smith paused, then smiled. Next, he left."
        let locator = makeLocator(highlight: source)

        let chunks = TTSSpeechUnit.sentenceChunks(
            from: [TTSSpeechUnit(text: source, locator: locator)]
        )

        XCTAssertEqual(chunks.map(\.text), [
            "Dr. Smith paused, then smiled.",
            "Next, he left."
        ])
        XCTAssertEqual(chunks[0].locator?.text.highlight, "Dr. Smith paused, then smiled.")
        XCTAssertEqual(chunks[0].locator?.text.after, " Next, he left.")
        XCTAssertEqual(chunks[1].locator?.text.highlight, "Next, he left.")
        XCTAssertEqual(chunks[1].locator?.text.before, "Dr. Smith paused, then smiled. ")
    }

    func testRepeatedSentenceRangesAdvanceThroughSource() {
        let source = "Repeat. Repeat."
        let locator = makeLocator(highlight: source)

        let chunks = TTSSpeechUnit.sentenceChunks(
            from: [TTSSpeechUnit(text: source, locator: locator)]
        )

        XCTAssertEqual(chunks.compactMap { $0.locator?.text.highlight }, ["Repeat.", "Repeat."])
        XCTAssertEqual(chunks[0].locator?.text.after, " Repeat.")
        XCTAssertEqual(chunks[1].locator?.text.before, "Repeat. ")
    }

    func testRawMarkupWhitespaceDoesNotSplitTheSpokenSentence() {
        let rawSource = "First\n    sentence continues. Then it ends."
        let normalizedText = "First sentence continues. Then it ends."
        let locator = makeLocator(highlight: rawSource)

        let chunks = TTSSpeechUnit.sentenceChunks(
            from: [TTSSpeechUnit(text: normalizedText, locator: locator)]
        )

        XCTAssertEqual(chunks.map(\.text), ["First sentence continues.", "Then it ends."])
        XCTAssertEqual(chunks[0].locator?.text.highlight, "First\n    sentence continues.")
        XCTAssertEqual(chunks[1].locator?.text.highlight, "Then it ends.")
    }

    func testSpokenWordRangeResolvesThroughRawWhitespace() {
        let rawSource = "First\n    sentence continues."
        let spokenText = "First sentence continues."
        let locator = makeLocator(highlight: rawSource)
        let unit = TTSSpeechUnit.sentenceChunks(
            from: [TTSSpeechUnit(text: spokenText, locator: locator)]
        )[0]
        guard let wordRange = spokenText.range(of: "sentence") else {
            return XCTFail("Fixture word range missing")
        }

        let wordLocator = unit.locator(forSpokenRange: wordRange, in: spokenText)

        XCTAssertEqual(wordLocator?.text.highlight, "sentence")
        XCTAssertEqual(wordLocator?.text.before, "First\n    ")
        XCTAssertEqual(wordLocator?.text.after, " continues.")
    }

    func testSoftHyphenMismatchFallsBackInsteadOfRealigningRepeatedWords() {
        let rawSource = "a\u{00AD}b. ab. ab. ab."
        let spokenText = "ab. ab. ab. ab."
        let locator = makeLocator(highlight: rawSource)
        let unit = TTSSpeechUnit(text: spokenText, locator: locator)
        let thirdWordStart = spokenText.index(spokenText.startIndex, offsetBy: 8)
        let thirdWordEnd = spokenText.index(thirdWordStart, offsetBy: 3)

        let result = unit.locator(
            forSpokenRange: thirdWordStart ..< thirdWordEnd,
            in: spokenText
        )

        XCTAssertEqual(result, locator)
    }

    func testUnmatchedNormalizedTextKeepsElementLocator() {
        let locator = makeLocator(highlight: "source text")
        let chunks = TTSSpeechUnit.sentenceChunks(
            from: [TTSSpeechUnit(text: "normalized text", locator: locator)]
        )

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].locator, locator)
    }

    private func makeLocator(highlight: String) -> Locator {
        Locator(
            href: URL(string: "https://example.invalid/chapter.xhtml")!,
            mediaType: .xhtml,
            text: .init(highlight: highlight)
        )
    }
}
#endif
