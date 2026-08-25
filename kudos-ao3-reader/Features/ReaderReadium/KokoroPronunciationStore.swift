import CryptoKit
import Foundation

/// Persistent Misaki-compatible pronunciation overrides. Empty by default —
/// G2P is used unless an explicit IPA entry exists, and entries here are
/// tier 1 of the phonemizer's resolution order, ahead of the Misaki lexicon
/// and the neural fallback.
nonisolated struct KokoroPronunciationStore: Sendable {
    struct File: Codable, Equatable, Sendable {
        var version: Int
        var global: [String: String]
        var fandoms: [String: [String: String]]
        var works: [String: [String: String]]
    }

    static let empty = File(version: 1, global: [:], fandoms: [:], works: [:])

    private let url: URL

    /// Where corrections live now.
    ///
    /// **Not** under `TTS_Models/`. That directory is marked
    /// `isExcludedFromBackup` because it holds the ~180MB model pack, which is
    /// re-downloadable and has no business in a device backup — but the flag
    /// is set on the *directory*, so anything inside inherits it. Corrections
    /// are the opposite kind of data: small, hand-made, and impossible to
    /// reconstruct. They belong where the backup can see them.
    static func defaultURL() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return support.appendingPathComponent("kokoro-pronunciations.json", isDirectory: false)
    }

    /// The pre-move location, read once so corrections made before this change
    /// are not orphaned.
    private static func legacyURL() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return support.appendingPathComponent(
            "TTS_Models/kokoro-pronunciations.json", isDirectory: false
        )
    }

    init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
    }

    func load() -> File {
        if let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            return file
        }
        // Fall back to the pre-move location exactly once, so a reader who
        // made corrections before they were moved out of the backup-excluded
        // model directory does not silently lose them.
        if url == Self.defaultURL(),
           let data = try? Data(contentsOf: Self.legacyURL()),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            try? save(file)
            return file
        }
        return Self.empty
    }

    func save(_ file: File) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Deliberately NOT excluded from backup — see `defaultURL()`.
        let data = try JSONEncoder().encode(file)
        try data.write(to: url, options: .atomic)
    }

    /// Which layer an override belongs to. Work beats fandom beats global,
    /// matching the merge order in ``lexicon(fandom:workID:)``.
    enum Layer: Equatable, Sendable {
        case global
        case fandom(String)
        case work(String)
    }

    /// Overrides in one layer, for display and editing.
    func overrides(in layer: Layer = .global) -> [String: String] {
        let file = load()
        switch layer {
        case .global: return file.global
        case .fandom(let key): return file.fandoms[key] ?? [:]
        case .work(let key): return file.works[key] ?? [:]
        }
    }

    /// Add or replace one override.
    ///
    /// The key keeps the caller's exact spelling: FluidAudio consults a
    /// case-sensitive custom lexicon before the lower-cased one, so `Anna`
    /// and `anna` are deliberately distinct entries rather than folded.
    func setOverride(_ ipa: String, for word: String, in layer: Layer = .global) throws {
        var file = load()
        switch layer {
        case .global: file.global[word] = ipa
        case .fandom(let key): file.fandoms[key, default: [:]][word] = ipa
        case .work(let key): file.works[key, default: [:]][word] = ipa
        }
        try save(file)
    }

    /// Remove one override, and drop the layer's dictionary when it empties
    /// so the file does not accumulate empty objects per work.
    func removeOverride(for word: String, in layer: Layer = .global) throws {
        var file = load()
        switch layer {
        case .global:
            file.global[word] = nil
        case .fandom(let key):
            file.fandoms[key]?[word] = nil
            if file.fandoms[key]?.isEmpty == true { file.fandoms[key] = nil }
        case .work(let key):
            file.works[key]?[word] = nil
            if file.works[key]?.isEmpty == true { file.works[key] = nil }
        }
        try save(file)
    }

    /// Merges layers. Work wins over fandom over global. Exact spelling is
    /// preserved for FluidAudio's case-sensitive custom lexicon.
    func lexicon(fandom: String? = nil, workID: String? = nil) -> [String: String] {
        let file = load()
        var merged = file.global
        if let fandom, let extra = file.fandoms[fandom] {
            extra.forEach { merged[$0.key] = $0.value }
        }
        if let workID, let extra = file.works[workID] {
            extra.forEach { merged[$0.key] = $0.value }
        }
        return merged
    }

    /// The merged lexicon plus the cache token for it, from a single read.
    ///
    /// The token covers keys **and values** across all three layers: hashing
    /// only the global keys let a corrected IPA for a word already in the
    /// lexicon keep serving the old pronunciation out of
    /// `KokoroSpeechSessionCache` forever.
    func resolved(
        fandom: String? = nil,
        workID: String? = nil
    ) -> (lexicon: [String: String], revision: String) {
        let merged = lexicon(fandom: fandom, workID: workID)
        let joined = merged
            .sorted { $0.key < $1.key }
            .map { "\($0.key)\u{1F}\($0.value)" }
            .joined(separator: "\u{1E}")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return (merged, digest.map { String(format: "%02x", $0) }.joined())
    }
}
