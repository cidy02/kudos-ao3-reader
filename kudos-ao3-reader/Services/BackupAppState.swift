import Foundation
import os

/// Unpublished writing the editor saved for crash recovery, carried in a backup and through
/// the sync folder (T-541; owner, 2026-11-16: backups and the sync folder are a complete
/// snapshot, "writing drafts too").
///
/// Each copy keeps the file name `WritingTextRecovery` gave it: a digest of account, target
/// and field, then the editing session. Names carry no account name, and a name that is not
/// that shape is refused, so an archive cannot write outside the recovery folder.
nonisolated struct KudosBackupRecoveryCopy: Codable, Equatable, Sendable {
    let fileName: String
    let entry: WritingTextRecovery.Entry

    static func capture(directory: URL = WritingTextRecovery.defaultDirectory) -> [Self] {
        let store = WritingTextRecovery(directory: directory)
        return store.allCopyURLs()
            .filter { isValidName($0.lastPathComponent) }
            .compactMap { url in
                (try? store.load(from: url)).flatMap { $0 }.map { Self(fileName: url.lastPathComponent, entry: $0) }
            }
            .sorted { $0.fileName < $1.fileName }
    }

    /// Adds every copy this device does not have and replaces one only with a newer save of
    /// the same session. Nothing is ever removed: losing typed text is the worse outcome, and
    /// the editor's own pruning keeps the folder small.
    static func apply(_ copies: [Self], directory: URL = WritingTextRecovery.defaultDirectory) {
        let store = WritingTextRecovery(directory: directory)
        let now = Date()
        for copy in copies where isValidName(copy.fileName) {
            let url = directory.appendingPathComponent(copy.fileName)
            let savedAt = KudosBackupContents.clampedArchiveDate(copy.entry.savedAt, now: now)
            if let local = (try? store.load(from: url)) ?? nil, local.savedAt >= savedAt { continue }
            var entry = copy.entry
            entry.savedAt = savedAt
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(entry).write(to: url, options: .atomic)
                // The editor lists a field's copies newest first by modification date.
                try FileManager.default.setAttributes([.modificationDate: savedAt], ofItemAtPath: url.path)
            } catch {
                Log.library.notice("A writing recovery copy from the backup could not be written.")
            }
        }
    }

    /// `<64 hex>.json` or `<64 hex>.<session>.json`.
    static func isValidName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.last == "json", parts.count == 2 || parts.count == 3 else { return false }
        let digest = parts[0]
        guard digest.count == 64, digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return false }
        guard parts.count == 3 else { return true }
        let session = parts[1]
        return (1...80).contains(session.count)
            && session.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

/// App data kept in files outside SwiftData, carried whole (T-541): the mail updates list with
/// the reader's Save / Not for me choices, and each account's subscription scan. Both were
/// once documented as derived and device-local; the owner's complete-snapshot rule brings them
/// in. The mail position (`cursor.json`) stays: it belongs with the mail sign-in.
nonisolated struct KudosBackupDocument: Codable, Equatable, Sendable {
    let name: String
    let data: Data
    let modifiedAt: Date

    /// Largest file carried. The mail list is capped by its store; a scan is one account's
    /// subscriptions.
    static let maximumBytes = 20 * 1024 * 1024

    static func capture(root: URL = URL.applicationSupportDirectory) -> [Self] {
        var found: [Self] = []
        func add(_ name: String) {
            guard let url = location(for: name, root: root),
                  let data = try? Data(contentsOf: url), data.count <= maximumBytes else { return }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            found.append(Self(name: name, data: data, modifiedAt: date))
        }
        add("mail/updates.json")
        let scans = root.appendingPathComponent("KudosSubscriptionScan", isDirectory: true)
        for url in (try? FileManager.default.contentsOfDirectory(at: scans, includingPropertiesForKeys: nil)) ?? [] {
            add("subscriptionScan/" + url.lastPathComponent)
        }
        return found.sorted { $0.name < $1.name }
    }

    /// Writes a file when this device has none or the incoming one is newer. Each store
    /// validates what it reads (a scan for another account is ignored), so this checks only
    /// that the name is one it knows and the bytes are JSON.
    static func apply(_ documents: [Self], root: URL = URL.applicationSupportDirectory) {
        let now = Date()
        for document in documents where document.data.count <= maximumBytes {
            guard let url = location(for: document.name, root: root),
                  (try? JSONSerialization.jsonObject(with: document.data)) != nil else { continue }
            let incomingDate = KudosBackupContents.clampedArchiveDate(document.modifiedAt, now: now)
            if let localDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate, localDate >= incomingDate { continue }
            do {
                let folder = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // Both folders stay out of the device's own iCloud backup, as their stores set them.
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var mutableFolder = folder
                try? mutableFolder.setResourceValues(values)
                try document.data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.modificationDate: incomingDate], ofItemAtPath: url.path)
            } catch {
                Log.library.notice("A data file from the backup could not be written.")
            }
        }
    }

    /// The only names carried, and where each lives. Anything else is refused.
    static func location(for name: String, root: URL) -> URL? {
        if name == "mail/updates.json" {
            return root.appendingPathComponent("KudosMail", isDirectory: true).appendingPathComponent("updates.json")
        }
        let prefix = "subscriptionScan/"
        guard name.hasPrefix(prefix) else { return nil }
        let file = String(name.dropFirst(prefix.count))
        guard file.hasSuffix(".json"), (6...220).contains(file.count), !file.hasPrefix("."),
              file.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "%._-".contains($0)) })
        else { return nil }
        return root.appendingPathComponent("KudosSubscriptionScan", isDirectory: true).appendingPathComponent(file)
    }
}
