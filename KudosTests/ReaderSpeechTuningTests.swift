import Foundation
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

    /// Same for the packing band, which the chunker reads.
    @Test func aChangedBandReachesThePhonemeBudget() {
        withCleanDefaults {
            #expect(KokoroPhonemeBudget.preferredTarget == 175)
            UserDefaults.standard.set(90, forKey: ReaderSpeechTuning.packTargetKey)
            ReaderSpeechTuning.invalidate()
            #expect(KokoroPhonemeBudget.preferredTarget == 90)
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
    @Test func theDialogueBarrierToggleChangesPacking() {
        withCleanDefaults {
            UserDefaults.standard.set(false, forKey: ReaderSpeechTuning.dialogueBarrierKey)
            ReaderSpeechTuning.invalidate()
            #expect(!ReaderSpeechTuning.current.dialogueBarrier)
        }
    }
}
