#if os(iOS)
import Foundation
import os
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
/// `nonisolated` like every sibling helper here: the module builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so without it the whole-chapter
/// NER pass and the guessed-word file write would both run on the main actor
/// and freeze the sheet for seconds on a long chapter.
nonisolated enum KokoroCastPreflight {
    /// Whether a scan can run at all.
    ///
    /// Everything playback consults before it speaks through Core ML: a safe
    /// OS line, the pack installed, synthesis not already abandoned on this
    /// device — and the engine the reader actually chose. Checking only the
    /// pack offered the button where the engine is never used.
    static var isAvailable: Bool {
        #if canImport(FluidAudio)
        guard KokoroAnePlayback.supportsCoreML(),
              KokoroAneAvailability.isUsableForPlayback,
              !KokoroAneHealth.hasAbandonedCoreML
        else { return false }
        // Capability is not the same as selection: a reader who has chosen
        // Apple in Settings keeps that engine even with the pack installed, and
        // a scan would then describe a pronunciation they never hear. The pack
        // is already established above, so `modelDownloaded: true`.
        return ReaderTTSEngineKind.effective(
            requestedRawValue: ReaderSpeechPreferences.engineIdentifier,
            modelDownloaded: true
        ) == .kokoro
        #else
        false
        #endif
    }

    enum ScanError: Error, Equatable {
        /// Playback owns the fallback observer while it runs, and there is
        /// exactly one. Scanning mid-playback would silently redirect the
        /// engine's own guesses into the scan and lose them. Paused counts:
        /// the session still owns it.
        case playbackActive
        /// Core ML Kokoro is not the engine that will speak.
        case unavailable
        /// The chapter walk produced nothing to phonemise.
        case noText
        /// The engine exists but would not start — a pack that failed to seed,
        /// a cache directory that could not be made, a chain that would not
        /// initialize. Carries the underlying reason, because "could not scan"
        /// on its own is unactionable.
        case engineFailed(String)
    }

    struct ScanResult: Equatable, Sendable {
        /// Distinct words this scan had to guess at.
        ///
        /// Not "newly recorded": a rescan of the same chapter guesses at the
        /// same words and reports the same number. Naming it otherwise made
        /// the message claim a discovery it had not made.
        var newWords: Int
        /// Names on-device NER found in the same text.
        ///
        /// Carried back rather than stored, because this is the third ranking
        /// source and nothing else in the app has the chapter text to compute
        /// it from. It is a *prior*: it cannot add a word to the list, only
        /// move one the engine actually guessed at further up. That is what
        /// surfaces an OC — the most-spoken name in many works, and the one
        /// AO3 tags never carry.
        var recognisedNames: Set<String>
    }

    /// Phonemises `texts` and records every word the frontend had to guess at.
    @discardableResult
    static func scan(texts: [String], isPlaying: Bool) async throws -> ScanResult {
        guard !isPlaying else { throw ScanError.playbackActive }
        guard isAvailable else { throw ScanError.unavailable }

        #if canImport(FluidAudio)
        // Wrapped so the caller can say *why*. `readyManager` throws from four
        // separate places (seeding the cache, making the directory, compiling
        // the chain, writing the marker) and swallowing them all into one
        // "could not scan" told the reader nothing they could act on.
        let manager: KokoroAneManager
        do {
            manager = try await CoreMLKokoroPackInstaller.shared.readyManager()
        } catch {
            Log.tts.error(
                "Pre-flight could not ready the Kokoro manager: \(error.localizedDescription, privacy: .public)"
            )
            throw ScanError.engineFailed(error.localizedDescription)
        }
        let collector = Collector()
        await manager.setNeuralFallbackObserver { word in collector.add(word) }

        for text in texts {
            if Task.isCancelled { break }
            // Failure is per-chunk and deliberately not fatal: one unphonemisable
            // paragraph must not cost the rest of the chapter's findings.
            _ = try? await manager.phonemes(for: text)
        }
        // Same text, one pass, while we have it in hand.
        let result = ScanResult(
            newWords: collector.flush(),
            recognisedNames: KokoroCastDiscovery.recognisedNames(
                in: texts.joined(separator: " ")
            )
        )
        // Cleared inline, deliberately not in a `defer`.
        //
        // Swift has no async `defer`, so doing this as
        // `defer { Task { await ...(nil) } }` hands the clear to an
        // unstructured task that can run *after* a later `speak()` has
        // installed playback's own observer — wiping it, and silently costing
        // every guessed word for that session. That is exactly the clobbering
        // the `.playbackActive` guard above prevents, arriving from the other
        // side.
        //
        // Nothing between the install and here throws (the loop swallows with
        // `try?`), so this is reached on every path, cancellation included. Any
        // future `try` added above must clear before it propagates.
        await manager.setNeuralFallbackObserver(nil)
        return result
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
