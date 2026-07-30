#if os(iOS)
import AVFoundation
import Foundation
import ReadiumNavigator
import ReadiumShared

/// Persisted read-aloud preferences and pure helpers for voice selection / text
/// cleanup. Phase 1 keeps Apple's `AVSpeechSynthesizer` (via Readium) and aims
/// for more natural speech by preferring Enhanced/Premium voices, letting the
/// user set rate/pitch, and lightly cleaning utterance text.
///
/// Personal Voice is intentionally excluded — fanfic read in the listener's own
/// voice is a product choice we don't offer.
enum ReaderSpeechPreferences {
    static let voiceIDKey = "readerSpeechVoiceID"
    static let rateKey = "readerSpeechRate"
    static let pitchKey = "readerSpeechPitch"

    /// Multiplier on `AVSpeechUtteranceDefaultSpeechRate`. 1.0 = system default.
    static let rateRange: ClosedRange<Double> = 0.5 ... 1.5
    static let defaultRate: Double = 1.0

    /// `AVSpeechUtterance.pitchMultiplier` range we expose (Apple allows 0.5…2.0).
    static let pitchRange: ClosedRange<Double> = 0.75 ... 1.25
    static let defaultPitch: Double = 1.0

    /// Short breath between sentences so back-to-back utterances don't run on.
    static let sentencePause: TimeInterval = 0.22

    static var voiceIdentifier: String {
        get { UserDefaults.standard.string(forKey: voiceIDKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: voiceIDKey) }
    }

    static var rateMultiplier: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: rateKey) as? Double
            return clamp(stored ?? defaultRate, to: rateRange)
        }
        set { UserDefaults.standard.set(clamp(newValue, to: rateRange), forKey: rateKey) }
    }

    static var pitchMultiplier: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: pitchKey) as? Double
            return clamp(stored ?? defaultPitch, to: pitchRange)
        }
        set { UserDefaults.standard.set(clamp(newValue, to: pitchRange), forKey: pitchKey) }
    }

    /// Maps the user-facing rate multiplier onto AVFoundation's absolute rate.
    static var avSpeechRate: Float {
        let def = Double(AVSpeechUtteranceDefaultSpeechRate)
        let minR = Double(AVSpeechUtteranceMinimumSpeechRate)
        let maxR = Double(AVSpeechUtteranceMaximumSpeechRate)
        return Float(clamp(def * rateMultiplier, to: minR ... maxR))
    }

    static var avPitch: Float {
        Float(pitchMultiplier)
    }

    // MARK: Voice catalog

    /// Voices safe to offer for long-form reading. Mirrors Readium's
    /// `AVTTSEngine` filter: drops novelty, Personal Voice, Eloquence, and the
    /// ancient `com.apple.speech.synthesis.voice.*` set.
    static func catalogVoices() -> [TTSVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                if voice.voiceTraits.contains(.isNoveltyVoice)
                    || voice.voiceTraits.contains(.isPersonalVoice)
                {
                    return false
                }
                return !voice.identifier.contains(".eloquence.")
                    && !voice.identifier.starts(with: "com.apple.speech.synthesis.voice.")
            }
            .compactMap { voice -> TTSVoice? in
                guard let quality = quality(for: voice) else { return nil }
                return TTSVoice(
                    identifier: voice.identifier,
                    language: Language(code: .bcp47(voice.language)),
                    name: voice.name,
                    gender: gender(for: voice),
                    quality: quality
                )
            }
    }

    /// Resolves the stored preference to a concrete voice id. Empty preference
    /// → best-quality voice for `language` (or the device language).
    static func resolvedVoiceIdentifier(
        preferredID: String = voiceIdentifier,
        language: Language? = nil,
        voices: [TTSVoice] = catalogVoices()
    ) -> String? {
        if !preferredID.isEmpty, voices.contains(where: { $0.identifier == preferredID }) {
            return preferredID
        }
        return bestVoice(for: language, from: voices)?.identifier
    }

    /// Highest-quality voice for `language`, using Readium's region/quality sort.
    static func bestVoice(for language: Language?, from voices: [TTSVoice]) -> TTSVoice? {
        let pool: [TTSVoice]
        if let language {
            let matched = voices.filterByLanguage(language.removingRegion())
            pool = matched.isEmpty ? voices : matched
        } else {
            let device = Language(code: .bcp47(Locale.current.identifier))
            let matched = voices.filterByLanguage(device.removingRegion())
            pool = matched.isEmpty ? voices : matched
        }
        return pool.sorted().first
    }

    static func qualityLabel(for quality: TTSVoice.Quality?) -> String {
        switch quality {
        case .higher: "Premium"
        case .high: "Enhanced"
        case .medium: "Standard"
        case .low: "Compact"
        case .lower: "Super Compact"
        case nil: "Standard"
        }
    }

    static func displayName(for voice: TTSVoice) -> String {
        let quality = qualityLabel(for: voice.quality)
        let region = voice.language.region?.code
        if let region, !region.isEmpty {
            return "\(voice.name) · \(quality) · \(region)"
        }
        return "\(voice.name) · \(quality)"
    }

    // MARK: Text cleanup

    /// Light normalisation before synthesis. Keeps letter content intact so
    /// Readium locators still roughly align; we only tidy whitespace / common
    /// EPUB leftovers that make the voice stumble.
    static func cleanUtteranceText(_ text: String) -> String {
        var s = text
        // Non-breaking / narrow spaces → regular space.
        s = s
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{2007}", with: " ")
        // Soft hyphen: don't read as a pause.
        s = s.replacingOccurrences(of: "\u{00AD}", with: "")
        // Collapse runs of whitespace (incl. newlines from block elements).
        if let regex = try? NSRegularExpression(pattern: "\\s+") {
            let range = NSRange(s.startIndex ..< s.endIndex, in: s)
            s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Private

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private static func gender(for voice: AVSpeechSynthesisVoice) -> TTSVoice.Gender {
        switch voice.gender {
        case .male: .male
        case .female: .female
        default: .unspecified
        }
    }

    private static func quality(for voice: AVSpeechSynthesisVoice) -> TTSVoice.Quality? {
        switch voice.quality {
        case .premium:
            return TTSVoice.Quality.higher
        case .enhanced:
            return TTSVoice.Quality.high
        case .default:
            if voice.identifier.contains(".compact.") { return .low }
            if voice.identifier.contains(".super-compact.") { return .lower }
            return .medium
        @unknown default:
            return .medium
        }
    }
}
#endif
