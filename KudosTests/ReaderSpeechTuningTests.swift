import Foundation
import ReadiumShared
import Testing
@testable import Kudos

/// The tuning panel exists to settle by ear what measurement cannot. These
/// cover the part that must not go wrong: an untouched install has to behave
/// exactly as the shipped constants did, and a change has to actually reach
/// the playback path rather than only the preview.
@Suite("Reader speech tuning", .serialized)
struct ReaderSpeechTuningTests {
    /// Clears every key and the cache, so one case cannot leak into the next
    /// through `UserDefaults` — these read process-wide state.
    private func withCleanDefaults(_ body: () throws -> Void) rethrows {
        ReaderSpeechTuning.resetAll()
        defer { ReaderSpeechTuning.resetAll() }
        try body()
    }

    /// The property that matters most: nothing set means nothing changed.
    @Test func defaultsMatchTheShippedConstants() {
        withCleanDefaults {
            let tuning = ReaderSpeechTuning.current
            #expect(tuning.continuationPause == 0.14)
            #expect(tuning.linePause == 0.22)
            #expect(tuning.paragraphPause == 0.32)
            #expect(tuning.scenePause == 0.85)
            #expect(tuning.chapterPause == 1.25)
            #expect(tuning.packTarget == 175)
            #expect(tuning.packMin == 110)
            #expect(tuning.packMax == 220)
            #expect(tuning.splitThreshold == 400)
            #expect(tuning.dialogueBarrier)
            #expect(tuning.lineBreakPauses)
            #expect(!ReaderSpeechTuning.isModified)
        }
    }

    /// The boundary enum is what the pause assembler consults, so a value that
    /// stopped here would move the panel and not the audio.
    @Test func aChangedPauseReachesTheBoundaryEnum() {
        withCleanDefaults {
            #expect(KokoroBoundary.line.pauseSeconds == 0.22)
            UserDefaults.standard.set(0.75, forKey: ReaderSpeechTuning.linePauseKey)
            ReaderSpeechTuning.invalidate()
            #expect(KokoroBoundary.line.pauseSeconds == 0.75)
        }
    }

    /// Deliberately `preferredMax`, not `preferredTarget`. Review established
    /// that packing consumes only `preferredMax` (grouping) and `preferredMin`
    /// (the orphan-tail merge) — `preferredTarget` is read by nothing, which is
    /// why the panel no longer offers it. Asserting through it would have
    /// tested a number with no consumer.
    @Test func aChangedBandReachesThePhonemeBudget() {
        withCleanDefaults {
            #expect(KokoroPhonemeBudget.preferredMax == 220)
            UserDefaults.standard.set(90, forKey: ReaderSpeechTuning.packMaxKey)
            ReaderSpeechTuning.invalidate()
            #expect(KokoroPhonemeBudget.preferredMax == 90)
        }
    }

    /// The cache is the reason the packing loop is not doing preference
    /// bridging thousands of times a chapter — but a stale cache would mean a
    /// setting that appears to do nothing, which is worse than a slow one.
    @Test func theCacheIsInvalidatedOnChange() {
        withCleanDefaults {
            _ = ReaderSpeechTuning.current
            UserDefaults.standard.set(1.5, forKey: ReaderSpeechTuning.scenePauseKey)
            // Deliberately not invalidated yet: the cached value should stand.
            #expect(ReaderSpeechTuning.current.scenePause == 0.85)
            ReaderSpeechTuning.invalidate()
            #expect(ReaderSpeechTuning.current.scenePause == 1.5)
        }
    }

    @Test func modifiedIsReportedHonestly() {
        withCleanDefaults {
            #expect(!ReaderSpeechTuning.isModified)
            UserDefaults.standard.set(0.5, forKey: ReaderSpeechTuning.linePauseKey)
            ReaderSpeechTuning.invalidate()
            #expect(ReaderSpeechTuning.isModified)
        }
    }

    /// Reset has to restore the shipped behaviour exactly, or a listening
    /// session can never be returned to a known baseline.
    @Test func resetRestoresEveryDefault() {
        ReaderSpeechTuning.resetAll()
        for key in [
            ReaderSpeechTuning.linePauseKey,
            ReaderSpeechTuning.packTargetKey,
            ReaderSpeechTuning.dialogueBarrierKey
        ] {
            UserDefaults.standard.set(key == ReaderSpeechTuning.dialogueBarrierKey ? false : 7,
                                      forKey: key)
        }
        ReaderSpeechTuning.invalidate()
        #expect(ReaderSpeechTuning.isModified)
        ReaderSpeechTuning.resetAll()
        #expect(!ReaderSpeechTuning.isModified)
        #expect(ReaderSpeechTuning.current.dialogueBarrier)
    }

    /// Turning the barrier off must actually restore the older merging
    /// behaviour, or the comparison the panel promises is not real.
    ///
    /// This asserted only the stored flag until review pointed out it never
    /// packed anything — it would have passed with the whole feature reverted.
    /// It now runs the packer and compares utterance counts.
    @Test func theDialogueBarrierToggleChangesPacking() {
        let units = [
            // No terminal punctuation: `endsUtterance` would otherwise block
            // the join on its own and the barrier would look inert.
            unit("He hesitated at the door", "html > body > p:nth-child(1)"),
            unit("\u{201C}Don't.\u{201D}", "html > body > p:nth-child(2)")
        ]
        withCleanDefaults {
            let withBarrier = KokoroUtterancePacker.pack(units: units)
            UserDefaults.standard.set(false, forKey: ReaderSpeechTuning.dialogueBarrierKey)
            ReaderSpeechTuning.invalidate()
            let without = KokoroUtterancePacker.pack(units: units)
            let detail = "got \(withBarrier.count) vs \(without.count)"
            #expect(withBarrier.count > without.count,
                    "the barrier should keep dialogue separate; \(detail)")
        }
    }

    /// Same for line-break pauses: the flag has to change what the packer
    /// produces, not merely what the panel stored.
    @Test func theLineBreakToggleChangesPacking() {
        let units = [
            unit("hey", "html > body > p:nth-child(1)"),
            unit("are you there", "html > body > p:nth-child(1)")
        ]
        withCleanDefaults {
            let withPauses = KokoroUtterancePacker.pack(units: units)
            #expect(withPauses.contains { $0.pauseAfter == .line })
            UserDefaults.standard.set(false, forKey: ReaderSpeechTuning.lineBreakPausesKey)
            ReaderSpeechTuning.invalidate()
            let without = KokoroUtterancePacker.pack(units: units)
            #expect(!without.contains { $0.pauseAfter == .line })
        }
    }

    /// The maximum is what grouping actually consumes, so a smaller one must
    /// produce more utterances from the same text.
    @Test func aSmallerMaximumProducesMoreUtterances() {
        // Several sentences: `preferredMax` bounds how many are grouped into
        // one utterance, so a single sentence can never demonstrate it — the
        // first version of this test used one and passed either way.
        let text = "She walked to the window. The rain had not stopped. "
            + "She turned back. He said nothing. The clock ticked on."
        let units = [unit(text, "html > body > p:nth-child(1)")]
        withCleanDefaults {
            let wide = KokoroUtterancePacker.pack(units: units)
            UserDefaults.standard.set(60, forKey: ReaderSpeechTuning.packMaxKey)
            ReaderSpeechTuning.invalidate()
            let narrow = KokoroUtterancePacker.pack(units: units)
            let detail = "got \(narrow.count) vs \(wide.count)"
            #expect(narrow.count > wide.count, "a tighter maximum should split more; \(detail)")
        }
    }

    private func unit(_ text: String, _ selector: String) -> TTSSpeechUnit {
        TTSSpeechUnit(
            text: text,
            locator: Locator(
                href: AnyURL(string: "chapter.xhtml")!,
                mediaType: .xhtml,
                locations: .init(otherLocations: ["cssSelector": .string(selector)])
            )
        )
    }
}
