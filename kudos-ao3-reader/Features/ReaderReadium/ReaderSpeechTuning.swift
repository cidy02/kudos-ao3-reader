import Foundation

/// Runtime-adjustable Read Aloud tuning, for settling by ear what measurement
/// cannot settle.
///
/// Several decisions in this pipeline are defensible but unproven: the `.line`
/// pause is 0.22s because that sits between `.continuation` and `.paragraph`,
/// not because anything says it is right; the packing band targets 175
/// phonemes because upstream's `VOICES.md` calls 100–200 the sweet spot. Those
/// are starting points, and the only way to improve them is to hear the
/// difference.
///
/// **These affect real playback, not just the audition sample.** A knob that
/// only moved the preview would answer a question nobody asked.
///
/// When a change lands is not uniform, and the panel says so rather than
/// implying otherwise. Pauses are read as each clip is assembled, so they
/// reach the next clip not already prefetched — a sentence or two. Chunk
/// sizes and the boundary toggles are consumed when the chapter's utterance
/// plan is built, which happens once before playback, so they apply from the
/// next chapter or after restarting Read Aloud.
///
/// Every value defaults to the shipped constant, so an untouched install
/// behaves exactly as it does today and "reset" is always available.
nonisolated enum ReaderSpeechTuning {
    // MARK: - Keys

    static let continuationPauseKey = "ttsDevContinuationPause"
    static let linePauseKey = "ttsDevLinePause"
    static let paragraphPauseKey = "ttsDevParagraphPause"
    static let scenePauseKey = "ttsDevScenePause"
    static let chapterPauseKey = "ttsDevChapterPause"
    static let packTargetKey = "ttsDevPackTarget"
    static let packMinKey = "ttsDevPackMin"
    static let packMaxKey = "ttsDevPackMax"
    static let splitThresholdKey = "ttsDevSplitThreshold"
    static let dialogueBarrierKey = "ttsDevDialogueBarrier"
    static let lineBreakPausesKey = "ttsDevLineBreakPauses"

    // MARK: - Shipped defaults

    static let defaultContinuationPause = 0.14
    static let defaultLinePause = 0.22
    static let defaultParagraphPause = 0.32
    static let defaultScenePause = 0.85
    static let defaultChapterPause = 1.25
    static let defaultPackTarget = 175
    static let defaultPackMin = 110
    static let defaultPackMax = 220
    static let defaultSplitThreshold = 400

    /// Ranges the UI offers. Deliberately generous at both ends: the point is
    /// to find out whether the shipped value is right, which needs room to be
    /// obviously wrong in both directions.
    static let pauseRange: ClosedRange<Double> = 0 ... 2.0
    static let packRange: ClosedRange<Double> = 40 ... 320
    static let splitRange: ClosedRange<Double> = 200 ... 510

    // MARK: - Snapshot

    /// One read of every value.
    ///
    /// Cached because the packing numbers are consulted once per candidate
    /// grouping — thousands of times per chapter — and a `UserDefaults` lookup
    /// on each would put preference bridging inside the packing loop. The
    /// cache is invalidated explicitly when the panel writes, which is the only
    /// thing that changes them.
    struct Snapshot: Sendable, Equatable {
        var continuationPause: Double
        var linePause: Double
        var paragraphPause: Double
        var scenePause: Double
        var chapterPause: Double
        var packTarget: Int
        var packMin: Int
        var packMax: Int
        var splitThreshold: Int
        var dialogueBarrier: Bool
        var lineBreakPauses: Bool
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var cached: Snapshot?

    static var current: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let snapshot = read()
        cached = snapshot
        return snapshot
    }

    /// Drop the cache so the next read sees new values. Called by the panel.
    static func invalidate() {
        lock.lock()
        cached = nil
        lock.unlock()
    }

    private static func read() -> Snapshot {
        let defaults = UserDefaults.standard
        func double(_ key: String, _ fallback: Double) -> Double {
            defaults.object(forKey: key) as? Double ?? fallback
        }
        func int(_ key: String, _ fallback: Int) -> Int {
            defaults.object(forKey: key) as? Int ?? fallback
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }
        return Snapshot(
            continuationPause: double(continuationPauseKey, defaultContinuationPause),
            linePause: double(linePauseKey, defaultLinePause),
            paragraphPause: double(paragraphPauseKey, defaultParagraphPause),
            scenePause: double(scenePauseKey, defaultScenePause),
            chapterPause: double(chapterPauseKey, defaultChapterPause),
            packTarget: int(packTargetKey, defaultPackTarget),
            packMin: int(packMinKey, defaultPackMin),
            packMax: int(packMaxKey, defaultPackMax),
            splitThreshold: int(splitThresholdKey, defaultSplitThreshold),
            dialogueBarrier: flag(dialogueBarrierKey, true),
            lineBreakPauses: flag(lineBreakPausesKey, true)
        )
    }

    /// Whether anything differs from the shipped defaults — so the panel can
    /// say so, and a listening report can be trusted to describe the build it
    /// claims to.
    static var isModified: Bool {
        current != Snapshot(
            continuationPause: defaultContinuationPause,
            linePause: defaultLinePause,
            paragraphPause: defaultParagraphPause,
            scenePause: defaultScenePause,
            chapterPause: defaultChapterPause,
            packTarget: defaultPackTarget,
            packMin: defaultPackMin,
            packMax: defaultPackMax,
            splitThreshold: defaultSplitThreshold,
            dialogueBarrier: true,
            lineBreakPauses: true
        )
    }

    static func resetAll() {
        let defaults = UserDefaults.standard
        for key in [
            continuationPauseKey, linePauseKey, paragraphPauseKey, scenePauseKey,
            chapterPauseKey, packTargetKey, packMinKey, packMaxKey,
            splitThresholdKey, dialogueBarrierKey, lineBreakPausesKey
        ] {
            defaults.removeObject(forKey: key)
        }
        invalidate()
    }
}
