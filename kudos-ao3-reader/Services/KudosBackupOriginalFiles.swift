import Foundation
import OSLog

/// The source document and optional conversion record for one archived work.
nonisolated struct KudosBackupOriginalFiles {
    var documents: [String] = []
    var record: String?

    static func grouped(_ names: [String]) -> [UUID: Self] {
        var groups: [UUID: Self] = [:]
        for name in Set(names).sorted() where KudosBackupContents.isSafeFileName(name) {
            guard let id = UUID(uuidString: String(name.prefix(36))) else { continue }
            let suffix = name.dropFirst(36)
            if suffix == Storage.conversionRecordSuffix {
                if groups[id]?.record == nil { groups[id, default: Self()].record = name }
            } else if (suffix.hasPrefix(".") || suffix.hasPrefix("-")),
                      !(name as NSString).pathExtension.isEmpty {
                groups[id, default: Self()].documents.append(name)
            }
        }
        return groups
    }

    func documentName(for id: UUID, record: WorkConversionRecord?) -> String? {
        if documents.count == 1 { return documents.first }
        guard let record else { return nil }
        let expected = Storage.originalDocumentURL(
            for: id, fileExtension: record.originalPathExtension,
            in: URL(fileURLWithPath: "/", isDirectory: true)
        ).lastPathComponent
        return documents.first { $0.caseInsensitiveCompare(expected) == .orderedSame }
    }

    static func exportWarning(for titles: [String]) -> String? {
        guard !titles.isEmpty else { return nil }
        let subject = titles.count == 1 ? "original file" : "original files"
        return "\(titles.count.formatted()) \(subject) couldn't be included.\n"
            + titles.map { "• \($0)" }.joined(separator: "\n")
    }

    static func install(
        _ data: Data,
        at destination: URL,
        replacing previous: URL?,
        previousData: Data?,
        record: (url: URL, data: Data)?
    ) throws {
        let replacesInPlace = previous?.path == destination.path
        try data.write(to: destination, options: .atomic)
        do {
            if let record { try record.data.write(to: record.url, options: .atomic) }
        } catch {
            // Keep the previous pair readable if committing the sidecar fails.
            do {
                if replacesInPlace, let previousData {
                    try previousData.write(to: destination, options: .atomic)
                } else if previous != nil, !replacesInPlace {
                    try FileManager.default.removeItem(at: destination)
                }
            } catch {
                Log.library.error("Couldn't roll back an original after its conversion record failed to write.")
            }
            throw error
        }
        if let previous, !replacesInPlace {
            try FileManager.default.removeItem(at: previous)
        }
    }
}

extension KudosBackupService {
    /// Resolve archive IDs after the library merge. Install the source before
    /// advancing its conversion record, so a failed write can be retried.
    static func restoreOriginalFiles(
        from contents: KudosBackupContents,
        workIDsByArchivedID: [UUID: UUID],
        fromSync: Bool
    ) -> (restored: Int, failures: Set<UUID>) {
        let groups = KudosBackupOriginalFiles.grouped(contents.originalFileNames)
        guard !groups.isEmpty else { return (0, []) }
        let directory = Storage.originalsDirectory
        var localOriginals = Storage.existingOriginalDocumentURLs()
        var restored = 0
        var failures: Set<UUID> = []
        for (archivedID, files) in groups.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard let workID = workIDsByArchivedID[archivedID] else { continue }
            do {
                if let installed = try restoreOriginal(
                    files, archivedID: archivedID, workID: workID, from: contents,
                    local: localOriginals[workID], directory: directory, fromSync: fromSync
                ) {
                    localOriginals[workID] = installed
                    restored += 1
                }
            } catch {
                failures.insert(archivedID)
                Log.library.notice("An imported original in this backup could not be restored.")
            }
        }
        return (restored, failures)
    }

    private static func restoreOriginal(
        _ files: KudosBackupOriginalFiles,
        archivedID: UUID,
        workID: UUID,
        from contents: KudosBackupContents,
        local: URL?,
        directory: URL,
        fromSync: Bool
    ) throws -> URL? {
        // A directory at the destination is a write failure waiting to happen,
        // rather than a local copy that can satisfy the restore.
        let local = local.flatMap { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? nil : url
        }
        let recordURL = WorkConversionRecord.url(for: workID, in: directory)
        let hasLocalRecord = FileManager.default.fileExists(atPath: recordURL.path)
        if local != nil, !fromSync, hasLocalRecord { return nil }

        let recordData = files.record.flatMap { contents.originalData(named: $0) }
        let incomingRecord = recordData.flatMap { try? JSONDecoder().decode(WorkConversionRecord.self, from: $0) }

        guard let name = files.documentName(for: archivedID, record: incomingRecord) else {
            if !files.documents.isEmpty { throw KudosBackupError.invalidPackage }
            if !fromSync, !hasLocalRecord, let recordData {
                try recordData.write(to: recordURL, options: .atomic)
            }
            return nil
        }
        let localRecord = WorkConversionRecord.read(for: workID)
        let incomingIsNewer = if let incomingRecord, let localRecord {
            incomingRecord.convertedAt > localRecord.convertedAt
        } else {
            false
        }
        if let local, fromSync, let localRecord, let incomingRecord,
           localRecord.convertedAt > incomingRecord.convertedAt {
            if archivedID != workID, (try? Data(contentsOf: local, options: .mappedIfSafe)) == nil {
                throw CocoaError(.fileReadNoPermission)
            }
            return nil
        }
        guard let data = contents.originalData(named: name) else { throw KudosBackupError.invalidPackage }

        let previousData = local.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
        if local != nil {
            if previousData == data {
                if let recordData, !hasLocalRecord || (fromSync && incomingRecord != nil
                    && (localRecord == nil || incomingIsNewer)) {
                    try recordData.write(to: recordURL, options: .atomic)
                }
                return nil
            }
            guard fromSync, incomingIsNewer else {
                // Publishing the merged work under a different ID would orphan
                // the archive's only copy of a source we can't safely order.
                if fromSync, archivedID != workID { throw KudosBackupError.invalidPackage }
                return nil
            }
        }

        let canonical = Storage.originalDocumentURL(
            for: workID, fileExtension: (name as NSString).pathExtension, in: directory
        )
        let destination = if let local,
                             local.lastPathComponent.caseInsensitiveCompare(canonical.lastPathComponent) == .orderedSame {
            local
        } else {
            canonical
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try KudosBackupOriginalFiles.install(
            data, at: destination, replacing: local, previousData: previousData,
            record: recordData.map { (url: recordURL, data: $0) }
        )
        return destination
    }
}
