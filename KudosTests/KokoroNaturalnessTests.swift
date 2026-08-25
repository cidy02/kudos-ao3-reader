#if os(iOS)
import Foundation
import ReadiumShared
import XCTest
@testable import Kudos

/// Synthetic AO3-like prose covering the hard cases in the long-form Kokoro
/// naturalness work: dialogue, contractions, scene breaks, headings, and
/// leftover short utterances. Not copyrighted source text.
enum KokoroNaturalnessCorpus {
    static let curlyContraction = "She wasn’t ready."
    static let asciiContraction = "Don't do that."
    static let curlyQuoted = "“Don’t do that.”"
    static let oneWordDialogue = "\"No.\""
    static let interrupted = "\"Wait—what?\""
    static let ellipsis = "\"I... don't know.\""
    static let honorifics = "Dr. Smith walked away. Mr. Potter looked up."
    static let decimal = "It was 3.14 exactly."
    static let initials = "The U.S.A. replied."
    static let splitDialogue = "\"What?\" she asked. \"Why?\""
    static let rapidExchange = """
    "Where are you going?"
    "Home."
    "You can't."
    "I can."
    """
    static let interruptedPair = """
    "I told you—"
    "No. You didn't."
    """
    static let names = "Sephiroth met Kakashi near Pallet Town."
    static let shout = "RUN. HARRY! NOW."
    static let sceneAndChapter = """
    Chapter 12
    Rain stitched the windows.
    * * *
    He opened the letter.
    """
    static let longNarration = String(
        repeating: "The corridor stretched on, lined with portraits that whispered as she passed. ",
        count: 8
    ) + "She kept walking."
    static let shortNarration = "Night had fallen."
    static let mixedChapter: [TTSSpeechUnit] = [
        unit("Chapter 3", selector: "html > body > h2"),
        unit("She wasn’t sure.", selector: "html > body > p:nth-child(2)"),
        unit("\"No.\"", selector: "html > body > p:nth-child(3)"),
        unit("He stepped backward.", selector: "html > body > p:nth-child(4)"),
        unit("\"You're lying.\"", selector: "html > body > p:nth-child(5)"),
        unit("* * *", selector: "html > body > p:nth-child(6)"),
        unit("Dawn came anyway.", selector: "html > body > p:nth-child(7)")
    ]

    static func unit(_ text: String, selector: String? = nil) -> TTSSpeechUnit {
        var locations = Locator.Locations()
        if let selector {
            locations.cssSelector = selector
        }
        return TTSSpeechUnit(
            text: text,
            locator: Locator(
                href: URL(string: "https://example.invalid/chapter.xhtml")!,
                mediaType: .xhtml,
                locations: locations,
                text: .init(highlight: text)
            )
        )
    }
}

@MainActor
final class KokoroNaturalnessTests: XCTestCase {
    func testCurlyApostropheKeepsNegation() {
        let words = KokoroSpeechNormalizer.words(in: KokoroNaturalnessCorpus.curlyContraction)
        XCTAssertEqual(words, ["She", "wasn't", "ready"])
        XCTAssertFalse(words.contains("was"))
        XCTAssertFalse(words.contains("nt"))
        XCTAssertTrue(KokoroSpeechNormalizer.normalize("wasn’t").contains("wasn't"))
    }

    func testQuotedCurlyContractionIsPreserved() {
        let words = KokoroSpeechNormalizer.words(in: KokoroNaturalnessCorpus.curlyQuoted)
        XCTAssertTrue(words.contains { $0.replacingOccurrences(of: "'", with: "").lowercased() == "dont" })
        XCTAssertFalse(words.contains("Don"))
        XCTAssertFalse(words.contains("t"))
    }

    func testEllipsisAndEmDashSurvive() {
        XCTAssertTrue(KokoroSpeechNormalizer.normalize("Wait--what?").contains("—"))
        XCTAssertTrue(KokoroSpeechNormalizer.normalize("I... don't know.").contains("…"))
        XCTAssertTrue(KokoroSpeechNormalizer.normalize(KokoroNaturalnessCorpus.interrupted).contains("—"))
    }

    /// A `<br>` that cuts a sentence in half is now **spoken as two
    /// utterances** with a `.line` pause, not merged.
    ///
    /// This test used to assert the opposite, and it kept passing after the
    /// change because `reconstructedText` re-joins the texts with a space —
    /// so the string assertion held while the behaviour it guarded had
    /// reversed. Rewritten to say what actually happens.
    ///
    /// The cost is real and measured. Across 29 unique corpus works there are
    /// 9,681 seams; 60.9% follow a line that ends in terminal punctuation, so
    /// the pause is free. Of the rest, only **97 — 1.0% of all seams** — are
    /// followed by a lowercase-initial line, which is the signature of a
    /// sentence genuinely continuing. Those lose G2P context across the split.
    ///
    /// An earlier version of this comment promised that no seam may strand a
    /// one-word utterance. **It does not, and should not.** One-word lines are
    /// 10.5% of all lines inside broken blocks, and measuring what they
    /// actually are settles it: names, social handles and sign-offs —
    /// `mimi`, `umbridge`, `tangtwins`, `sincerely`. Those *want* their own
    /// utterance and their own pause. Not one of them was a heteronym, so the
    /// citation-form hazard that would justify a guard does not occur here.
    func testLineBreakSplitsIntoSeparateUtterances() {
        let utterances = KokoroUtterancePacker.pack(units: [
            KokoroNaturalnessCorpus.unit("She began to", selector: "html > body > p"),
            KokoroNaturalnessCorpus.unit("read the letter.", selector: "html > body > p")
        ])
        XCTAssertEqual(utterances.map(\.pauseAfter), [.line, .paragraph])
        XCTAssertEqual(utterances.map(\.text), ["She began to", "read the letter."])

        // Nothing may be lost or reordered by the split.
        let spoken = KokoroUtterancePacker.reconstructedText(from: utterances)
        XCTAssertEqual(spoken, "She began to read the letter.")
    }

    func testHonorificsAndInitialsStayWithTheSentence() {
        let utterances = KokoroUtterancePacker.pack(units: [
            KokoroNaturalnessCorpus.unit(KokoroNaturalnessCorpus.honorifics)
        ])
        let spoken = KokoroUtterancePacker.reconstructedText(from: utterances)
        XCTAssertTrue(spoken.contains("Dr. Smith"))
        XCTAssertTrue(spoken.contains("Mr. Potter"))
        XCTAssertFalse(spoken.contains("Dr "))
    }

    func testShortDialogueMergesInsideAParagraph() {
        let utterances = KokoroUtterancePacker.pack(units: [
            KokoroNaturalnessCorpus.unit("\"No.\" He stepped backward. \"You're lying.\"")
        ])
        XCTAssertEqual(utterances.count, 1)
        XCTAssertTrue(utterances[0].text.contains("No."))
        XCTAssertTrue(utterances[0].text.contains("You're lying."))
    }

    func testSceneBreakIsNotSpokenAndWidensPause() {
        let utterances = KokoroUtterancePacker.pack(units: KokoroNaturalnessCorpus.mixedChapter)
        let spoken = KokoroUtterancePacker.reconstructedText(from: utterances)
        XCTAssertFalse(spoken.contains("*"))
        XCTAssertTrue(spoken.contains("She wasn't sure.") || spoken.contains("She wasn't sure.".replacingOccurrences(of: "'", with: "'")))
        XCTAssertTrue(spoken.contains("Dawn came anyway."))
        XCTAssertTrue(utterances.contains { $0.pauseAfter == .scene || $0.pauseAfter == .chapter })
        XCTAssertEqual(utterances.first?.pauseAfter, .chapter)
    }

    func testHeadingIsItsOwnUtterance() {
        let utterances = KokoroUtterancePacker.pack(units: KokoroNaturalnessCorpus.mixedChapter)
        XCTAssertEqual(utterances.first?.text, "Chapter 3")
    }

    func testPackedChunksStayInsideEmergencyPhonemeCap() {
        let estimator = KokoroPhonemeEstimator()
        let units = [KokoroNaturalnessCorpus.unit(KokoroNaturalnessCorpus.longNarration)]
        let utterances = KokoroUtterancePacker.pack(units: units, estimator: estimator)
        XCTAssertFalse(utterances.isEmpty)
        for utterance in utterances {
            // The packer now guarantees the *split* budget, well under the
            // model cap — Kokoro rushes long before `encode` throws. (The
            // duplicate assertion this replaces checked `modelLimit` twice.)
            XCTAssertLessThanOrEqual(
                estimator.estimatePhonemeLength(utterance.text),
                KokoroPhonemeBudget.splitThreshold
            )
        }
    }

    /// Digits are the one thing the grapheme factor cannot cover: `1985` is
    /// four characters and speaks as a whole year. The reference lengths are
    /// **measured**, by running real Misaki G2P (espeak fallback for OOV
    /// names) over each string — not derived from the estimator, or this would
    /// only be asserting the formula against itself.
    ///
    /// Before `digitPhonemeBonus` the first case estimated 43 against a real
    /// 64 and the second 52 against a real 102 — under by half. An
    /// under-estimate is not fatal (synthesis re-splits on the true phoneme
    /// count) but that split cuts at the midpoint, blind to prosody.
    func testNumericTextIsNotEstimatedBelowItsRealPhonemeLength() {
        let estimator = KokoroPhonemeEstimator()
        let measured: [(text: String, realPhonemes: Int)] = [
            ("She was born in 1985 and died in 2011.", 64),
            ("Stardate 41153.7, log entry 2, section 15.", 102),
            ("The bill came to 1247 credits and 38 pence.", 67),
        ]
        for case_ in measured {
            XCTAssertGreaterThanOrEqual(
                estimator.estimatePhonemeLength(case_.text),
                case_.realPhonemes,
                "under-estimated \(case_.text)"
            )
        }
    }

    /// The digit term must stay a *tail* fix. Prose carries no digits, so its
    /// estimate has to be exactly what it was before the term existed —
    /// otherwise every chunk boundary in the app moves, which is a tuning
    /// change and needs ears, not a bug fix.
    func testProseEstimateIsUnaffectedByTheDigitTerm() {
        let estimator = KokoroPhonemeEstimator()
        let prose = "She walked to the window and looked out at the rain."
        XCTAssertEqual(estimator.estimatePhonemeLength(prose), 59)
    }

    func testLongCompleteSentenceIsNotCutToHitTheGroupingTarget() {
        let sentence = """
        When she finally reached the end of the corridor, the portraits had \
        gone silent, the candles had burned down to nubs, and the only sound \
        left was her own breath against the cold stone, which felt less like \
        victory than like the moment before a door opens.
        """
        let estimator = KokoroPhonemeEstimator()
        let estimate = estimator.estimatePhonemeLength(sentence)
        XCTAssertGreaterThan(estimate, KokoroPhonemeBudget.preferredTarget)
        XCTAssertLessThan(estimate, KokoroPhonemeBudget.splitThreshold)

        let utterances = KokoroUtterancePacker.pack(
            units: [KokoroNaturalnessCorpus.unit(sentence)],
            estimator: estimator
        )
        XCTAssertEqual(utterances.count, 1)
        XCTAssertEqual(utterances[0].text, KokoroSpeechNormalizer.normalize(sentence))
        XCTAssertFalse(utterances[0].text.hasSuffix("corridor,"))
    }

    func testPackingGroupsWholeSentencesWithoutSplittingThem() {
        let first = "The corridor stretched on, lined with portraits that whispered as she passed."
        let second = "She kept walking toward the stair."
        let utterances = KokoroUtterancePacker.pack(units: [
            KokoroNaturalnessCorpus.unit("\(first) \(second)")
        ])
        XCTAssertEqual(utterances.count, 1)
        XCTAssertTrue(utterances[0].text.contains(first))
        XCTAssertTrue(utterances[0].text.contains(second))
        XCTAssertEqual(
            KokoroUtterancePacker.completeSentences(in: utterances[0].text).count,
            2
        )
    }

    func testLongParagraphDoesNotLeaveATinyTail() {
        let estimator = KokoroPhonemeEstimator()
        let sentences = (0 ..< 12).map { "This is a measured sentence number \($0) about walking down a hall." }
        let units = [KokoroNaturalnessCorpus.unit(sentences.joined(separator: " "))]
        let utterances = KokoroUtterancePacker.pack(units: units, estimator: estimator)
        XCTAssertGreaterThan(utterances.count, 1)
        let estimates = utterances.map { estimator.estimatePhonemeLength($0.text) }
        if let last = estimates.last, estimates.count >= 2 {
            XCTAssertGreaterThan(last, KokoroPhonemeBudget.shortFragment)
        }
    }

    func testReconstructedTextKeepsAuthorWordsInOrder() {
        let units: [TTSSpeechUnit] = [
            KokoroNaturalnessCorpus.unit("Don't do that."),
            KokoroNaturalnessCorpus.unit("\"No.\""),
            KokoroNaturalnessCorpus.unit("Wait—what?"),
            KokoroNaturalnessCorpus.unit("I... don't know."),
            KokoroNaturalnessCorpus.unit("Dr. Smith walked away."),
            KokoroNaturalnessCorpus.unit("It was 3.14 exactly.")
        ]
        let spoken = KokoroUtterancePacker.reconstructedText(
            from: KokoroUtterancePacker.pack(units: units)
        )
        XCTAssertTrue(spoken.contains("Don't"))
        XCTAssertTrue(spoken.contains("No."))
        XCTAssertTrue(spoken.contains("Wait"))
        XCTAssertTrue(spoken.contains("don't know"))
        XCTAssertTrue(spoken.contains("Dr. Smith"))
        XCTAssertTrue(spoken.contains("3.14"))
    }

    func testPauseAssemblerTrimsEdgeSilenceAndInsertsBoundary() {
        var samples = Array(repeating: Float(0), count: 2400)
        for i in 600 ..< 1800 {
            samples[i] = 0.2 * sin(Float(i) / 10)
        }
        let assembled = KokoroPauseAssembler.assemble(
            samples: samples,
            sampleRate: 24_000,
            pauseAfter: .paragraph
        )
        let pauseSamples = Int((KokoroBoundary.paragraph.pauseSeconds * 24_000).rounded())
        XCTAssertGreaterThan(assembled.count, pauseSamples)
        XCTAssertLessThan(assembled.count, samples.count + pauseSamples)
        XCTAssertEqual(assembled.suffix(pauseSamples).allSatisfy { $0 == 0 }, true)
    }

    func testPronunciationLayersWorkWins() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokoro-pronunciations-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var file = KokoroPronunciationStore.empty
        file.global = ["Kakashi": "global"]
        file.fandoms = ["Naruto": ["Kakashi": "fandom"]]
        file.works = ["work-1": ["Kakashi": "work"]]
        let store = KokoroPronunciationStore(url: url)
        try store.save(file)
        XCTAssertEqual(store.lexicon()["Kakashi"], "global")
        XCTAssertEqual(store.lexicon(fandom: "Naruto")["Kakashi"], "fandom")
        XCTAssertEqual(store.lexicon(fandom: "Naruto", workID: "work-1")["Kakashi"], "work")
    }

    func testPhonemeCacheInvalidatesOnRevision() {
        let cache = KokoroSpeechSessionCache(capacity: 8)
        cache.store(phonemes: "həlˈO", for: "hello", revision: "1")
        XCTAssertEqual(cache.phonemeString(for: "hello", revision: "1"), "həlˈO")
        XCTAssertNil(cache.phonemeString(for: "hello", revision: "2"))
    }

    func testSentenceBaselineProducesMoreUtterancesThanSemanticPacking() {
        let units = [KokoroNaturalnessCorpus.unit(
            "\"No.\" He stepped backward. \"You're lying.\" Rain stitched the windows. She kept walking."
        )]
        let sentences = TTSSpeechUnit.sentenceChunks(from: units)
        let packed = KokoroUtterancePacker.pack(units: units)
        XCTAssertGreaterThan(sentences.count, packed.count)
        XCTAssertGreaterThanOrEqual(packed.count, 1)
    }

    /// Answers the "stacked pauses" question from the improvement plan: `…`
    /// makes the model emit 0.5–1 s of its own silence, and the assembler
    /// then appends a structural pause — so an ellipsis at a paragraph end
    /// was suspected of running ~1.3 s.
    ///
    /// It does not, because `trimEdgeSilence` runs *first* and cuts the
    /// model's trailing silence back to `keepEdgeSeconds`. The pause the
    /// listener hears is the structural one, near enough alone. Pinned as a
    /// test because the ordering is the entire reason, and swapping those two
    /// steps would reintroduce the stack without failing anything else.
    func testAModelPauseIsNotStackedOnTopOfTheStructuralOne() {
        let rate = KokoroPauseAssembler.sampleRate
        let speech = (0 ..< Int(0.10 * rate)).map { index in
            sin(Float(index) * 0.05) * 0.5
        }
        // What an ellipsis leaves at the end of the clip.
        let modelSilence = [Float](repeating: 0, count: Int(0.80 * rate))

        let assembled = KokoroPauseAssembler.assemble(
            samples: speech + modelSilence,
            sampleRate: rate,
            pauseAfter: .paragraph
        )

        let seconds = Double(assembled.count) / rate
        let stacked = 0.10 + 0.80 + KokoroBoundary.paragraph.pauseSeconds
        let expected = 0.10 + KokoroPauseAssembler.keepEdgeSeconds
            + KokoroBoundary.paragraph.pauseSeconds
        XCTAssertLessThan(seconds, stacked - 0.2)
        XCTAssertEqual(seconds, expected, accuracy: 0.05)
    }
}

#endif
