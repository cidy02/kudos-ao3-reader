import CryptoKit
import Foundation

/// Persistent Misaki-compatible pronunciation overrides. Empty by default —
/// G2P is used unless an explicit IPA entry exists. UI editing is out of
/// scope; the on-disk shape already supports global / fandom / work layers.
nonisolated struct KokoroPronunciationStore: Sendable {
    struct File: Codable, Equatable, Sendable {
        var version: Int
        var global: [String: String]
        var fandoms: [String: [String: String]]
        var works: [String: [String: String]]
    }

    static let empty = File(version: 1, global: [:], fandoms: [:], works: [:])

    private let url: URL

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.url = support.appendingPathComponent(
                "TTS_Models/kokoro-pronunciations.json",
                isDirectory: false
            )
        }
    }

    func load() -> File {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else {
            return Self.empty
        }
        return file
    }

    func save(_ file: File) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = folder
        try? directory.setResourceValues(values)
        let data = try JSONEncoder().encode(file)
        try data.write(to: url, options: .atomic)
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
