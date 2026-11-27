import Foundation

/// Persists chapter beta-reading copies (`betas.json`) inside each chapter folder in
/// `WritingDocumentStore`. Kept strictly device-local; never sent to AO3.
extension WritingDocumentStore {
    private static let betasFileName = "betas.json"

    func listBetaCopies(workID: UUID, chapterID: UUID) throws -> [BetaCopyRecord] {
        let folder = try chapterDirectory(workID: workID, chapterID: chapterID)
        return try readBetaCopies(in: folder)
            .sorted { lhs, rhs in
                if lhs.sentAt != rhs.sentAt { return lhs.sentAt > rhs.sentAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    @discardableResult
    func recordBetaCopy(
        workID: UUID,
        chapterID: UUID,
        betaName: String,
        format: BetaCopyFormat,
        sentHTML: String
    ) throws -> BetaCopyRecord {
        let folder = try chapterDirectory(workID: workID, chapterID: chapterID)
        var copies = try readBetaCopies(in: folder)
        let stamp = now()
        let record = BetaCopyRecord(
            id: UUID(),
            betaName: betaName.trimmingCharacters(in: .whitespacesAndNewlines),
            format: format,
            sentAt: stamp,
            sentHTML: sentHTML,
            returnedAt: nil,
            status: .waiting,
            hasSnapshottedBeforeAccept: false,
            suggestions: [],
            comments: [],
            updatedAt: stamp,
            updatedBy: try deviceID()
        )
        copies.append(record)
        try writeBetaCopies(copies, in: folder)
        return record
    }

    @discardableResult
    func updateBetaCopy(
        workID: UUID,
        chapterID: UUID,
        copy: BetaCopyRecord
    ) throws -> BetaCopyRecord {
        let folder = try chapterDirectory(workID: workID, chapterID: chapterID)
        var copies = try readBetaCopies(in: folder)
        guard let index = copies.firstIndex(where: { $0.id == copy.id }) else {
            throw WritingDocumentError.corrupt("Beta copy \(copy.id.uuidString) not found")
        }
        var updated = copy
        updated.updatedAt = now()
        updated.updatedBy = try deviceID()
        copies[index] = updated
        try writeBetaCopies(copies, in: folder)
        return updated
    }

    func deleteBetaCopy(workID: UUID, chapterID: UUID, copyID: UUID) throws {
        let folder = try chapterDirectory(workID: workID, chapterID: chapterID)
        var copies = try readBetaCopies(in: folder)
        copies.removeAll { $0.id == copyID }
        try writeBetaCopies(copies, in: folder)
    }

    /// Distinct beta names previously used across live works (current work's chapters
    /// prioritized by recency), ordered most-recently-sent first.
    func recentBetaNames(preferringWorkID workID: UUID? = nil) throws -> [String] {
        var entries: [(name: String, sentAt: Date, sameWork: Bool)] = []
        let workDirectories = try uuidDirectories(in: root)
        for workDir in workDirectories {
            guard fileExists(WritingDocumentPaths.workFile(workDir)),
                  !fileExists(WritingDocumentPaths.deletionMarker(workDir))
            else { continue }
            let isPreferred = workID.map { workDir.lastPathComponent == $0.uuidString } ?? false
            let chaptersDir = WritingDocumentPaths.chapters(workDir)
            for chapterDir in try uuidDirectories(in: chaptersDir) {
                guard !fileExists(WritingDocumentPaths.deletionMarker(chapterDir)) else { continue }
                let copies = (try? readBetaCopies(in: chapterDir)) ?? []
                for copy in copies {
                    let trimmed = copy.betaName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    entries.append((name: trimmed, sentAt: copy.sentAt, sameWork: isPreferred))
                }
            }
        }
        entries.sort { lhs, rhs in
            if lhs.sentAt != rhs.sentAt { return lhs.sentAt > rhs.sentAt }
            if lhs.sameWork != rhs.sameWork { return lhs.sameWork && !rhs.sameWork }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        var seen: Set<String> = []
        var names: [String] = []
        for entry in entries {
            let key = entry.name.lowercased()
            if seen.insert(key).inserted {
                names.append(entry.name)
            }
        }
        return names
    }

    // MARK: - Helpers

    private func betasFileURL(in chapterDirectory: URL) -> URL {
        chapterDirectory.appendingPathComponent(Self.betasFileName)
    }

    private func readBetaCopies(in chapterDirectory: URL) throws -> [BetaCopyRecord] {
        let url = betasFileURL(in: chapterDirectory)
        guard fileExists(url) else { return [] }
        return try WritingDocumentIO.readJSON(WritingChapterBetasFile.self, from: url).copies
    }

    private func writeBetaCopies(_ copies: [BetaCopyRecord], in chapterDirectory: URL) throws {
        try WritingDocumentIO.writeJSON(
            WritingChapterBetasFile(copies: copies),
            to: betasFileURL(in: chapterDirectory)
        )
    }
}
