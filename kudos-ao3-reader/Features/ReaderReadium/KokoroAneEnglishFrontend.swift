#if os(iOS) && canImport(FluidAudio)
import FluidAudio
import Foundation

/// Thin Kudos-side entry to FluidAudio's English frontend.
///
/// `KudosTests` cannot link FluidAudio (the test bundle also builds for
/// macOS, where the package is `platformFilter = ios`), so tests phonemize
/// through this wrapper with a stand-in lexicon. Playback still goes
/// through `KokoroAneManager`; this exists only so the recovery rules in
/// `KokoroAneEnglishPhonemizer.resolveWord` have a reachable test seam.
enum KokoroAneEnglishFrontend {
    static func phonemize(
        _ text: String,
        wordToPhonemes: [String: [String]],
        caseSensitiveWordToPhonemes: [String: [String]] = [:],
        allowedPunctuation: Set<Character> = [],
        fallback: @escaping (String) async throws -> [String]? = { _ in nil }
    ) async throws -> String {
        let phonemizer = KokoroAneEnglishPhonemizer(
            wordToPhonemes: wordToPhonemes,
            caseSensitiveWordToPhonemes: caseSensitiveWordToPhonemes,
            allowedPunctuation: allowedPunctuation
        )
        return try await phonemizer.phonemize(text, fallback: fallback)
    }
}
#endif
