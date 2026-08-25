#if os(iOS)
import Foundation
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Finds the words a chapter *would* be guessed at, before it is spoken.
///
/// The pronunciation list has always been retrospective: `KokoroGuessedWordStore`
/// only learns a word after synthesis has already fallen back on it, so the
/// reader hears the name mangled once and corrects it afterwards. For a name
/// repeated every third paragraph that is the wrong way round.
///
/// G2P is separable from synthesis, which is what makes the pre-flight
/// possible at all: `KokoroAneManager.phonemes(for:)` runs the frontend and
/// nothing else, and the fallback observer fires from the same path — upstream
/// documents it as existing so a frontend can offer "words I guessed at" for
/// correction. Phonemising a chapter is a fraction of the cost of speaking it.
///
/// **Core ML only.** sherpa-onnx takes text and returns audio with no exposed
/// frontend, so on iOS 26 there is nothing to ask. `isAvailable` says so rather
/// than offering a button that cannot work.
enum KokoroCastPreflight {
    /// Whether a scan can run at all.
    ///
    /// The same three conditions playback uses to pick Core ML — a safe OS
    /// line, the pack installed, and synthesis not already abandoned on this
    /// device — because the scan runs the same frontend. Checking only for the
    /// pack would offer a button on a device where the engine is not used.
    static var isAvailable: Bool {
        #if canImport(FluidAudio)
        KokoroAnePlayback.supportsCoreML()
            && KokoroAneAvailability.isUsableForPlayback
            && !KokoroAneHealth.hasAbandonedCoreML
        #else
        false
        #endif
    }

    enum ScanError: Error, Equatable {
        /// Playback owns the fallback observer while it runs, and there is
        /// exactly one. Scanning mid-playback would silently redirect the
        /// engine's own guesses into the scan and lose them.
        case playbackActive
        case unavailable
    }

    /// Phonemises `texts` and records every word the frontend had to guess at.
    ///
    /// - Returns: how many distinct words were newly recorded.
    @discardableResult
    static func scan(texts: [String], isPlaying: Bool) async throws -> Int {
        guard !isPlaying else { throw ScanError.playbackActive }
        guard isAvailable else { throw ScanError.unavailable }

        #if canImport(FluidAudio)
        let manager = try await CoreMLKokoroPackInstaller.shared.readyManager()
        let collector = Collector()
        await manager.setNeuralFallbackObserver { word in collector.add(word) }
        // Always cleared: leaving a scan's observer installed would send the
        // next playback's guesses into a collector nobody reads.
        defer { Task { await manager.setNeuralFallbackObserver(nil) } }

        for text in texts {
            if Task.isCancelled { break }
            // Failure is per-chunk and deliberately not fatal: one unphonemisable
            // paragraph must not cost the rest of the chapter's findings.
            _ = try? await manager.phonemes(for: text)
        }
        return collector.flush()
        #else
        throw ScanError.unavailable
        #endif
    }

    /// Buffers the observer's words and writes them once.
    ///
    /// Mirrors `CoreMLKokoroTTSService.GuessedWordCollector`: the observer is
    /// `@Sendable` and synchronous, called from inside the frontend, so it
    /// cannot await. The lock is held only to append.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [String] = []
        private let store = KokoroGuessedWordStore()

        func add(_ word: String) {
            lock.lock()
            pending.append(word)
            lock.unlock()
        }

        /// - Returns: the number of distinct words written.
        func flush() -> Int {
            lock.lock()
            let batch = pending
            pending.removeAll(keepingCapacity: true)
            lock.unlock()
            guard !batch.isEmpty else { return 0 }
            try? store.record(batch)
            return Set(batch).count
        }
    }
}
#endif
