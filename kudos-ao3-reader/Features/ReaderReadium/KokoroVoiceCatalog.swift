#if os(iOS)
import Foundation
import ReadiumNavigator
import ReadiumShared

/// The Kokoro voices actually present in the installed pack.
///
/// A voice pack is a flat `[510, 256]` fp32 style-vector blob and is **not**
/// precision-dependent — fp16 vs int8 describes the model weights, not these
/// vectors. So the fp16 Core ML pack can carry exactly the same voice set the
/// int8 Sherpa pack did; it just needs the `.bin` files shipped alongside it
/// (see `Scripts/pack-kokoro-ane-github-release.sh`).
///
/// Reading the directory rather than hard-coding a list means republishing the
/// pack with more voices needs no app change.
nonisolated enum KokoroVoiceCatalog: Sendable {
    /// Kokoro encodes locale and gender in the identifier: first letter is the
    /// language (`a` American, `b` British), second is the gender.
    static func voice(forIdentifier id: String) -> TTSVoice? {
        let parts = id.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].count == 2, !parts[1].isEmpty else { return nil }
        let prefix = Array(parts[0])
        let region: String
        switch prefix[0] {
        case "a": region = "en-US"
        case "b": region = "en-GB"
        default: return nil
        }
        let gender: TTSVoice.Gender
        switch prefix[1] {
        case "f": gender = .female
        case "m": gender = .male
        default: return nil
        }
        return TTSVoice(
            identifier: id,
            language: Language(code: .bcp47(region)),
            name: parts[1].prefix(1).uppercased() + parts[1].dropFirst(),
            gender: gender,
            quality: .higher
        )
    }

    /// Voices found in the installed pack, sorted by identifier so the picker
    /// groups American before British and female before male.
    static func installedVoices(
        in directory: URL = KokoroAneAvailability.packVoicesDirectory
    ) -> [TTSVoice] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.hasSuffix(".bin") }
            .map { String($0.dropLast(".bin".count)) }
            .sorted()
            .compactMap(voice(forIdentifier:))
    }

    /// Preferred default when the pack has it, else the first voice present.
    static func defaultIdentifier(among voices: [TTSVoice]) -> String {
        voices.contains { $0.identifier == "af_heart" }
            ? "af_heart"
            : voices.first?.identifier ?? "af_heart"
    }
}
#endif
