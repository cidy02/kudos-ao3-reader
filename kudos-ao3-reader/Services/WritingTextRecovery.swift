import CryptoKit
import Foundation

/// Device-local crash recovery, separate from AO3 drafts and library backups.
/// Store text only: no cookies, form tokens, or account names in filenames.
///
/// The editor writes through `WritingRecoveryWriter`, off the main thread and
/// once per checkpoint rather than per keystroke. File layout, keys and pruning
/// are specified in docs/WRITING_EDITOR_ARCHITECTURE.md §8.3–8.5, which Android
/// follows too.
nonisolated struct WritingTextRecovery {
    struct Entry: Codable, Equatable {
        var text: String
        var originalDigest: String
        var savedAt: Date
        var accountDigest: String?
    }

    struct Copy: Identifiable {
        var url: URL
        var entry: Entry
        var id: URL { url }
    }

    private static let keyRegistryLock = NSLock()
    nonisolated(unsafe) private static var accountDigestByKeyDigest: [String: String] = [:]
    nonisolated(unsafe) private static var usernameByKeyDigest: [String: String] = [:]

    /// The field's readable copies, newest first. A copy that won't decode is
    /// skipped on its own: it used to make this throw, which hid every other
    /// copy of the field from the recovery prompt and stopped pruning for good.
    func copies(for key: URL) throws -> [Copy] {
        try copyFileURLs(withPrefix: Self.copyPrefix(forKey: key))
            .compactMap { url in
                guard let entry = try? load(from: url) else { return nil }
                return Copy(url: url, entry: entry)
            }
            .sorted { $0.entry.savedAt > $1.entry.savedAt }
    }

    static let defaultDirectory: URL = URL.applicationSupportDirectory
        .appendingPathComponent("WritingTextRecovery", isDirectory: true)

    var directory: URL = Self.defaultDirectory

    func hasLocalDrafts(for username: String?) -> Bool {
        guard let normalized = Self.normalizedAccount(username) else { return false }
        let targetDigest = Self.digest(normalized)
        let newWorkKeys = Set(["content", "summary", "notes", "endnotes"].map { field in
            Self.keyDigest(normalizedAccount: normalized, target: "work:new", field: field)
        })
        for url in allCopyURLs() {
            guard let keyDigest = Self.keyDigestPrefix(for: url) else { continue }
            if let entry = try? load(from: url) {
                if let entryAccountDigest = entry.accountDigest {
                    if entryAccountDigest == targetDigest { return true }
                    continue
                }
            }
            if Self.registeredAccountDigest(forKeyDigest: keyDigest) == targetDigest
                || newWorkKeys.contains(keyDigest) {
                return true
            }
        }
        return false
    }

    func fileURL(account: String, target: String, field: String) -> URL {
        // Length-delimited components prevent ambiguous account/target pairs.
        let normalized = account.lowercased()
        let keyDigest = Self.keyDigest(normalizedAccount: normalized, target: target, field: field)
        if let trimmed = Self.normalizedAccount(account) {
            Self.registerKeyDigest(keyDigest, normalizedAccount: trimmed)
        }
        return directory.appendingPathComponent(keyDigest).appendingPathExtension("json")
    }

    func load(from url: URL) throws -> Entry? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Entry.self, from: Data(contentsOf: url))
    }

    /// Copies kept per field. A recovery list is for "the app died, give me back
    /// what I typed", and the useful answer is the last few attempts — not every
    /// session ever opened. Without a ceiling these are full copies of a chapter
    /// that accumulate for the life of the install, because each editor session
    /// writes under a fresh UUID and nothing else removes them.
    static let copyLimit = 5

    func save(text: String, original: String, to url: URL) throws {
        try save(text: text, originalDigest: Self.digest(original), to: url)
    }

    /// The form `WritingRecoveryWriter` uses: the digest of the field's original
    /// text is computed once per editor session, not once per save.
    func save(text: String, originalDigest: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keyDigest = Self.keyDigestPrefix(for: url)
        let accountDigest = keyDigest.flatMap { Self.registeredAccountDigest(forKeyDigest: $0) }
        let entry = Entry(
            text: text,
            originalDigest: originalDigest,
            savedAt: Date(),
            accountDigest: accountDigest
        )
        try JSONEncoder().encode(entry).write(to: url, options: .atomic)
        try? prune(around: url)
        if directory == Self.defaultDirectory,
           let username = keyDigest.flatMap({ Self.registeredUsername(forKeyDigest: $0) }) {
            WritingTabEvents.notifyDraftSaved(username: username)
        }
    }

    /// Keeps `url` and the newest `copyLimit - 1` other copies of the same
    /// field, by file modification date, and deletes the rest. Nothing is
    /// decoded: this used to read every copy in full on every save, and one
    /// unreadable copy stopped it working altogether. Best-effort: a copy that
    /// will not delete is left alone rather than failing the save that just
    /// succeeded.
    func prune(around url: URL) throws {
        let name = url.lastPathComponent
        guard let digest = name.split(separator: ".", maxSplits: 1).first else { return }
        let others = try copyFileURLs(withPrefix: String(digest) + ".")
            .filter { $0.lastPathComponent != name }
        for surplus in others.dropFirst(Self.copyLimit - 1) {
            try? FileManager.default.removeItem(at: surplus)
        }
    }

    /// Everything this store holds, for the Privacy screen's measured figure and
    /// its clear action. Unpublished writing is exactly what that screen must not
    /// omit.
    func allCopyURLs() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedAccount(_ username: String?) -> String? {
        guard let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty,
              trimmed != "signed-out"
        else { return nil }
        return trimmed
    }

    private static func keyDigest(normalizedAccount: String, target: String, field: String) -> String {
        let key = [normalizedAccount, target, field].map { "\($0.utf8.count):\($0)" }.joined()
        return digest(key)
    }

    private static func keyDigestPrefix(for url: URL) -> String? {
        guard let prefix = url.lastPathComponent.split(separator: ".", maxSplits: 1).first,
              !prefix.isEmpty
        else { return nil }
        return String(prefix)
    }

    private static func registerKeyDigest(_ keyDigest: String, normalizedAccount: String) {
        let accountDigest = digest(normalizedAccount)
        keyRegistryLock.lock()
        accountDigestByKeyDigest[keyDigest] = accountDigest
        usernameByKeyDigest[keyDigest] = normalizedAccount
        keyRegistryLock.unlock()
    }

    private static func registeredAccountDigest(forKeyDigest keyDigest: String) -> String? {
        keyRegistryLock.lock()
        defer { keyRegistryLock.unlock() }
        return accountDigestByKeyDigest[keyDigest]
    }

    private static func registeredUsername(forKeyDigest keyDigest: String) -> String? {
        keyRegistryLock.lock()
        defer { keyRegistryLock.unlock() }
        return usernameByKeyDigest[keyDigest]
    }

    /// `<digest>.` for a key made by `fileURL(account:target:field:)`, which
    /// matches every session's `<digest>.<session>.json`.
    private static func copyPrefix(forKey key: URL) -> String {
        key.deletingPathExtension().lastPathComponent + "."
    }

    /// Copy files whose names start with `prefix`, newest first by modification
    /// date (then by name, so ties sort the same way every time). Reads
    /// directory metadata only.
    private func copyFileURLs(withPrefix prefix: String) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let dated: [(url: URL, date: Date)] = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                return (url: url, date: date ?? .distantPast)
            }
        return dated
            .sorted { lhs, rhs in
                lhs.date != rhs.date ? lhs.date > rhs.date : lhs.url.lastPathComponent > rhs.url.lastPathComponent
            }
            .map { $0.url }
    }
}
