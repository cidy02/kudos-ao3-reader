import CryptoKit
import Foundation

/// Device-local crash recovery, separate from AO3 drafts and library backups.
/// Store text only: no cookies, form tokens, or account names in filenames.
nonisolated struct WritingTextRecovery {
    struct Entry: Codable, Equatable {
        var text: String
        var originalDigest: String
        var savedAt: Date
    }

    struct Copy: Identifiable {
        var url: URL
        var entry: Entry
        var id: URL { url }
    }

    func copies(for key: URL) throws -> [Copy] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let prefix = key.deletingPathExtension().lastPathComponent + "."
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
            .compactMap { url in try load(from: url).map { Copy(url: url, entry: $0) } }
            .sorted { $0.entry.savedAt > $1.entry.savedAt }
    }

    var directory: URL = URL.applicationSupportDirectory
        .appendingPathComponent("WritingTextRecovery", isDirectory: true)

    func fileURL(account: String, target: String, field: String) -> URL {
        // Length-delimited components prevent ambiguous account/target pairs.
        let key = [account.lowercased(), target, field].map { "\($0.utf8.count):\($0)" }.joined()
        return directory.appendingPathComponent(Self.digest(key)).appendingPathExtension("json")
    }

    func load(from url: URL) throws -> Entry? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Entry.self, from: Data(contentsOf: url))
    }

    func save(text: String, original: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = Entry(text: text, originalDigest: Self.digest(original), savedAt: Date())
        try JSONEncoder().encode(entry).write(to: url, options: .atomic)
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
