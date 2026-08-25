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

    func testLineBreakFragmentsJoinIntoOneSentence() {
        let chunks = TTSSpeechUnit.sentenceChunks(
            from: [
                TTSSpeechUnit(text: "She began to", locator: makeLocator(highlight: "She began to")),
                TTSSpeechUnit(text: "read the letter."),
            ]
        )

        XCTAssertEqual(chunks.map(\.text), ["She began to read the letter."])
        XCTAssertFalse(chunks.contains(where: { $0.text == "read" }))
    }

    func testIsolatedHomographIsNotItsOwnUtterance() {
        let chunks = TTSSpeechUnit.sentenceChunks(
            from: [
                TTSSpeechUnit(text: "I will"),
                TTSSpeechUnit(text: "read"),
                TTSSpeechUnit(text: "it now."),
            ]
        )

        XCTAssertEqual(chunks.map(\.text), ["I will read it now."])
    }

    func testCompleteSentencesStaySeparateAfterJoin() {
        let chunks = TTSSpeechUnit.sentenceChunks(
            from: [
                TTSSpeechUnit(text: "He opened the door."),
                TTSSpeechUnit(text: "Night had fallen."),
            ]
        )

        XCTAssertEqual(chunks.map(\.text), [
            "He opened the door.",
            "Night had fallen."
        ])
    }

    func testTrailingFragmentJoinsTheFollowingLine() {
        let chunks = TTSSpeechUnit.sentenceChunks(
            from: [
                TTSSpeechUnit(text: "He stopped."),
                TTSSpeechUnit(text: "Then he"),
                TTSSpeechUnit(text: "continued walking."),
            ]
        )

        XCTAssertEqual(chunks.map(\.text), [
            "He stopped.",
            "Then he continued walking."
        ])
    }

    func testAttachingPunctuationDoesNotInsertASpace() {
        let chunks = TTSSpeechUnit.sentenceChunks(
            from: [
                TTSSpeechUnit(text: "She said hello"),
                TTSSpeechUnit(text: "."),
            ]
        )

        XCTAssertEqual(chunks.map(\.text), ["She said hello."])
    }

    /// Apple `packedChunks` must not space-join units that share a
    /// cssSelector — that is Readium's signal a `<br>` split one `<p>`.
    /// Without a selector this assertion is vacuous.
    func testPackedChunksSplitsAtSharedSelectorLineBreakSeam() {
        let chunks = TTSSpeechUnit.packedChunks(from: [
            unit("hey", selector: "html > body > p:nth-child(1)"),
            unit("are you there", selector: "html > body > p:nth-child(1)")
        ])
        XCTAssertEqual(chunks.map(\.text), ["hey", "are you there"])
    }

    /// Complete sentences still pack together up to 250 characters. If the
    /// seam only stopped concatenation and `packAdjacent` still ran across
    /// it, this pair would collapse to one utterance.
    func testPackedChunksDoesNotGlueCompleteSentencesAcrossALineBreakSeam() {
        let chunks = TTSSpeechUnit.packedChunks(from: [
            unit("Hello.", selector: "html > body > p:nth-child(1)"),
            unit("How are you?", selector: "html > body > p:nth-child(1)")
        ])
        XCTAssertEqual(chunks.map(\.text), ["Hello.", "How are you?"])
    }

    /// One-word lines inside a broken `<p>` are names, handles, and
    /// sign-offs — they want their own utterance. Same discriminator.
    func testPackedChunksKeepsAOneWordLineAsItsOwnUtterance() {
        let chunks = TTSSpeechUnit.packedChunks(from: [
            unit("mimi", selector: "html > body > p:nth-child(1)"),
            unit("are you there", selector: "html > body > p:nth-child(1)")
        ])
        XCTAssertEqual(chunks.map(\.text), ["mimi", "are you there"])
    }

    /// Adjacent `<p>`s do not share a selector, so the existing join/pack
    /// behaviour is unchanged: a mid-sentence wrap across paragraphs is
    /// still one G2P input.
    func testPackedChunksStillJoinsAdjacentParagraphs() {
        let chunks = TTSSpeechUnit.packedChunks(from: [
            unit("She began to", selector: "html > body > p:nth-child(1)"),
            unit("read the letter.", selector: "html > body > p:nth-child(2)")
        ])
        XCTAssertEqual(chunks.map(\.text), ["She began to read the letter."])
    }

    /// A paragraph that does not end a sentence still joins into the next
    /// paragraph's first line, but that join must not hide the `<br>` seam
    /// inside the second paragraph. Selector tracking follows the unit just
    /// absorbed, matching `KokoroSemanticDocument`.
    func testPackedChunksDoesNotHideALineSeamAfterACrossParagraphJoin() {
        let chunks = TTSSpeechUnit.packedChunks(from: [
            unit("She began to", selector: "html > body > p:nth-child(1)"),
            unit("read the letter", selector: "html > body > p:nth-child(2)"),
            unit("and then she wept.", selector: "html > body > p:nth-child(2)")
        ])
        XCTAssertEqual(chunks.map(\.text), [
            "She began to read the letter",
            "and then she wept."
        ])
    }

    /// Word highlighting keys off each utterance's locator. Splitting at the
    /// seam must keep each line's own highlight, not a concatenated quote
    /// covering both — otherwise `willSpeakRange` maps into the wrong span.
    func testPackedChunksPreservesEachLinesLocatorAcrossASeam() {
        let chunks = TTSSpeechUnit.packedChunks(from: [
            unit("hey", selector: "html > body > p:nth-child(1)"),
            unit("are you there", selector: "html > body > p:nth-child(1)")
        ])
        XCTAssertEqual(chunks.map { $0.locator?.text.highlight }, ["hey", "are you there"])
        XCTAssertEqual(
            chunks.map { $0.locator?.locations.cssSelector },
            ["html > body > p:nth-child(1)", "html > body > p:nth-child(1)"]
        )
    }


    // MARK: - Sherpa (sentenceChunks) must agree with the other two engines

    /// Sherpa is the iOS 26 engine and was the odd one out: Core ML and Apple
    /// both broke `<br>` lines while this path space-joined them, so the same
    /// chapter read differently depending on which engine was chosen.
    func testSentenceChunksSplitsAtASharedSelectorSeam() {
        let chunks = TTSSpeechUnit.sentenceChunks(from: [
            unit("hey", selector: "html > body > p:nth-child(1)"),
            unit("are you there", selector: "html > body > p:nth-child(1)")
        ])
        XCTAssertEqual(chunks.map(\.text), ["hey", "are you there"])
    }

    /// The counterpart: adjacent paragraphs have different selectors and must
    /// still join, or this becomes "never merge anything".
    func testSentenceChunksStillJoinsAdjacentParagraphs() {
        let chunks = TTSSpeechUnit.sentenceChunks(from: [
            unit("She began to", selector: "html > body > p:nth-child(1)"),
            unit("read the letter.", selector: "html > body > p:nth-child(2)")
        ])
        XCTAssertEqual(chunks.map(\.text), ["She began to read the letter."])
    }

    /// A one-word line stays its own chunk — 10.5% of lines inside broken
    /// blocks are names, handles and sign-offs, which want their own delivery.
    func testSentenceChunksKeepsAOneWordLineSeparate() {
        let chunks = TTSSpeechUnit.sentenceChunks(from: [
            unit("sincerely", selector: "html > body > p:nth-child(1)"),
            unit("Ari", selector: "html > body > p:nth-child(1)")
        ])
        XCTAssertEqual(chunks.map(\.text), ["sincerely", "Ari"])
    }


    // MARK: - Apple's structural pauses

    /// Apple used a flat postUtteranceDelay for every utterance, so a chapter
    /// break sounded exactly like a mid-sentence split and the developer
    /// panel's pause sliders did nothing on that engine.
    func testPackedChunksTagsALineBoundaryAtASeam() {
        let chunks = TTSSpeechUnit.packedChunks(from: [
            unit("hey", selector: "html > body > p:nth-child(1)"),
            unit("are you there", selector: "html > body > p:nth-child(1)")
        ])
        XCTAssertEqual(chunks.map(\.pauseAfter), [.line, .paragraph])
    }

    /// The final chunk closes a paragraph, not a line — otherwise every
    /// paragraph would end with the shorter gap.
    func testPackedChunksEndsOnAParagraphBoundary() {
        let chunks = TTSSpeechUnit.packedChunks(from: [
            unit("A complete sentence.", selector: "html > body > p:nth-child(1)")
        ])
        XCTAssertEqual(chunks.map(\.pauseAfter), [.paragraph])
    }

    /// A unit built directly carries no boundary, so callers that predate this
    /// keep the flat delay rather than silently changing.
    func testAUnitBuiltDirectlyHasNoBoundary() {
        XCTAssertNil(TTSSpeechUnit(text: "plain").pauseAfter)
    }

    /// The defect this pins: labelling by position made every mid-group
    /// boundary a `.continuation` (0.14s). Real paragraph breaks are the
    /// common case there, and that would have shortened them from the 0.22s
    /// that shipped — a regression dressed up as an improvement.
    func testAParagraphBreakIsNotLabelledAContinuation() {
        let first = String(repeating: "The rain had not stopped falling. ", count: 5)
        let second = String(repeating: "He said nothing at all to her. ", count: 5)
        let chunks = TTSSpeechUnit.packedChunks(from: [
            unit(first, selector: "html > body > p:nth-child(1)"),
            unit(second, selector: "html > body > p:nth-child(2)")
        ])
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertFalse(chunks.dropLast().contains { $0.pauseAfter == .continuation })
        XCTAssertEqual(chunks.last?.pauseAfter, .paragraph)
    }

    /// A sentence too long for one utterance is the only true continuation:
    /// the split falls mid-sentence, so the gap should be the shortest one.
    func testALengthDrivenSplitIsAContinuation() {
        let long = String(repeating: "and the rain kept falling on the roof ", count: 12)
        let chunks = TTSSpeechUnit.packedChunks(from: [
            unit(long, selector: "html > body > p:nth-child(1)")
        ])
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.first?.pauseAfter, .continuation)
    }

    /// Kokoro packs consecutive sentences of one paragraph into a single
    /// utterance, so it has no boundary for the gap between them. Apple splits
    /// them only because of its length cap, and `nil` keeps the flat sentence
    /// pause that already shipped instead of inventing a shorter one.
    func testASentenceBoundaryInsideAParagraphKeepsTheFlatPause() {
        let sentence = String(repeating: "The clock ticked on and on and on. ", count: 8)
        let chunks = TTSSpeechUnit.packedChunks(from: [
            unit(sentence, selector: "html > body > p:nth-child(1)")
        ])
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertNil(chunks.first?.pauseAfter)
    }

    private func unit(_ text: String, selector: String) -> TTSSpeechUnit {
        TTSSpeechUnit(
            text: text,
            locator: Locator(
                href: AnyURL(string: "chapter.xhtml")!,
                mediaType: .xhtml,
                locations: .init(otherLocations: ["cssSelector": .string(selector)]),
                text: .init(highlight: text)
            )
        )
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
