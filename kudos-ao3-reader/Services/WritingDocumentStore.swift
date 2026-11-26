import Foundation

/// File store for local manuscripts. Disk work runs on this actor, off the main thread.
///
/// Layout, under `root` (Application Support `Writing/` by default):
/// `<work id>/work.json`, `storyNotes.json`, `annotations.json`, and
/// `chapters/<chapter id>/chapter.json`, `body.html`, `versions/`.
/// Deleting a work or chapter moves that folder to `Recently Deleted/` for 30 days.
/// Only `deleteNow` or `emptyRecentlyDeleted` removes it. A `*.tmp` beside a file is
/// an interrupted write and is never promoted over the real file.
///
/// This store does not talk to AO3. Annotations have no posting path.
actor WritingDocumentStore {
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Writing", isDirectory: true)
    }

    /// First text save after a quiet stretch of this long keeps the previous body.
    static let automaticVersionGap: TimeInterval = 10 * 60
    static let retainedAutomaticVersions = 20
    /// Recently Deleted entries, and destructive version snapshots, older than this go.
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    let root: URL
    let deviceIDOverride: String?
    let now: @Sendable () -> Date
    var resolvedDeviceID: String?

    init(root: URL, deviceID: String? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.root = root
        self.deviceIDOverride = deviceID
        self.now = now
    }

    // MARK: Works

    func listWorks() throws -> [WritingWork] {
        try settleDeletedWorks()
        var works: [WritingWork] = []
        for directory in try uuidDirectories(in: root) {
            guard fileExists(WritingDocumentPaths.workFile(directory)) else { continue }
            works.append(try readWork(at: directory))
        }
        return works.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func createWork(title: String, ao3WorkID: Int? = nil) throws -> WritingWork {
        let stamp = now()
        let author = try deviceID()
        let work = WritingWork(
            id: UUID(),
            title: title,
            ao3WorkID: ao3WorkID,
            createdAt: stamp,
            updatedAt: stamp,
            updatedBy: author,
            chapterOrder: []
        )
        let directory = WritingDocumentPaths.workDirectory(root: root, id: work.id)
        try WritingDocumentIO.writeJSON(work, to: WritingDocumentPaths.workFile(directory))
        try WritingDocumentIO.writeJSON(
            WritingStoryNotesFile(notes: []),
            to: WritingDocumentPaths.storyNotes(directory)
        )
        try WritingDocumentIO.writeJSON(
            WritingAnnotationsFile(annotations: []),
            to: WritingDocumentPaths.annotations(directory)
        )
        try FileManager.default.createDirectory(
            at: WritingDocumentPaths.chapters(directory),
            withIntermediateDirectories: true
        )
        return work
    }

    func openWork(_ id: UUID) throws -> WritingWork {
        let directory = try liveWorkDirectory(id)
        var work = try readWork(at: directory)
        try settleChapters(in: directory, work: &work)
        return work
    }

    func renameWork(_ id: UUID, title: String) throws -> WritingWork {
        let directory = try liveWorkDirectory(id)
        var work = try readWork(at: directory)
        guard work.title != title else { return work }
        work.title = title
        work.updatedAt = now()
        work.updatedBy = try deviceID()
        try WritingDocumentIO.writeJSON(work, to: WritingDocumentPaths.workFile(directory))
        return work
    }

    func deleteWork(_ id: UUID) throws {
        let directory = try liveWorkDirectory(id)
        let marker = WritingDocumentPaths.deletionMarker(directory)
        try writeDeletionMarker(in: directory, workID: nil, chapterIndex: nil)
        do {
            try moveWithoutOverwrite(
                from: directory,
                to: WritingDocumentPaths.deletedWorkDirectory(root: root, id: id)
            )
        } catch {
            try? FileManager.default.removeItem(at: marker)
            throw error
        }
    }

    func restoreWork(_ id: UUID) throws -> WritingWork {
        let source = WritingDocumentPaths.deletedWorkDirectory(root: root, id: id)
        guard fileExists(WritingDocumentPaths.workFile(source)) else {
            throw WritingDocumentError.notInRecentlyDeleted(id)
        }
        let destination = WritingDocumentPaths.workDirectory(root: root, id: id)
        guard !fileExists(destination) else {
            throw WritingDocumentError.corrupt(id.uuidString)
        }
        let marker = WritingDocumentPaths.deletionMarker(source)
        if fileExists(marker) {
            try FileManager.default.removeItem(at: marker)
        }
        try moveWithoutOverwrite(from: source, to: destination)
        var work = try readWork(at: destination)
        work.updatedAt = now()
        work.updatedBy = try deviceID()
        try WritingDocumentIO.writeJSON(work, to: WritingDocumentPaths.workFile(destination))
        return work
    }

    // MARK: Recently Deleted

    func listRecentlyDeleted() throws -> [WritingDeletedItem] {
        try settleDeletedWorks()
        var items: [WritingDeletedItem] = []
        items.append(contentsOf: try deletedWorks())
        items.append(contentsOf: try deletedChapters())
        return items.sorted { lhs, rhs in
            if lhs.deletedAt != rhs.deletedAt { return lhs.deletedAt > rhs.deletedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Removes one Recently Deleted work or chapter. A live id is left where it is.
    func deleteNow(_ id: UUID) throws {
        let work = WritingDocumentPaths.deletedWorkDirectory(root: root, id: id)
        if fileExists(WritingDocumentPaths.workFile(work)) {
            try FileManager.default.removeItem(at: work)
            return
        }
        let chapter = WritingDocumentPaths.deletedChapterDirectory(root: root, id: id)
        if fileExists(WritingDocumentPaths.chapterFile(chapter)) {
            try FileManager.default.removeItem(at: chapter)
            return
        }
        throw WritingDocumentError.notInRecentlyDeleted(id)
    }

    /// Removes Recently Deleted entries older than 30 days, and destructive version
    /// snapshots older than 30 days. Automatic snapshots are capped at 20 on save,
    /// not by age. Returns what the bin dropped.
    func emptyRecentlyDeleted() throws -> [WritingDeletedItem] {
        let stamp = now()
        var removed: [WritingDeletedItem] = []
        for item in try listRecentlyDeleted() where isExpired(item.deletedAt, now: stamp) {
            guard deletionWasRecorded(item.id) else { continue }
            try deleteNow(item.id)
            removed.append(item)
        }
        try pruneLiveVersions(now: stamp)
        return removed
    }

    // MARK: Shared file helpers

    func deviceID() throws -> String {
        if let deviceIDOverride { return deviceIDOverride }
        if let resolvedDeviceID { return resolvedDeviceID }
        let url = WritingDocumentPaths.deviceID(root)
        if fileExists(url),
           let text = try? WritingDocumentIO.readText(url) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                resolvedDeviceID = trimmed
                return trimmed
            }
        }
        let created = UUID().uuidString
        try WritingDocumentIO.writeText(created, to: url)
        resolvedDeviceID = created
        return created
    }

    func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func readWork(at directory: URL) throws -> WritingWork {
        try WritingDocumentIO.readJSON(WritingWork.self, from: WritingDocumentPaths.workFile(directory))
    }

    func liveWorkDirectory(_ id: UUID) throws -> URL {
        try settleDeletedWorks()
        let directory = WritingDocumentPaths.workDirectory(root: root, id: id)
        guard fileExists(WritingDocumentPaths.workFile(directory)) else {
            throw WritingDocumentError.workNotFound(id)
        }
        return directory
    }

    /// The work folder, still in the bin or live. Used when a deleted chapter is put back.
    func directoryContainingWork(_ id: UUID) throws -> URL {
        try settleDeletedWorks()
        let live = WritingDocumentPaths.workDirectory(root: root, id: id)
        if fileExists(WritingDocumentPaths.workFile(live)) { return live }
        let deleted = WritingDocumentPaths.deletedWorkDirectory(root: root, id: id)
        if fileExists(WritingDocumentPaths.workFile(deleted)) { return deleted }
        throw WritingDocumentError.workNotFound(id)
    }

    func isExpired(_ date: Date, now: Date) -> Bool {
        date.addingTimeInterval(Self.retention) < now
    }

    private func settleDeletedWorks() throws {
        for directory in try uuidDirectories(in: root) {
            guard fileExists(WritingDocumentPaths.deletionMarker(directory)),
                  let id = UUID(uuidString: directory.lastPathComponent) else { continue }
            try finishWorkDeletion(directory, id: id)
        }
    }

    private func finishWorkDeletion(_ directory: URL, id: UUID) throws {
        let destination = WritingDocumentPaths.deletedWorkDirectory(root: root, id: id)
        guard !fileExists(destination) else { return }
        try moveWithoutOverwrite(from: directory, to: destination)
    }

    private func deletedWorks() throws -> [WritingDeletedItem] {
        var items: [WritingDeletedItem] = []
        for directory in try uuidDirectories(in: WritingDocumentPaths.recentlyDeleted(root)) {
            guard fileExists(WritingDocumentPaths.workFile(directory)),
                  let id = UUID(uuidString: directory.lastPathComponent) else { continue }
            let work = try readWork(at: directory)
            items.append(WritingDeletedItem(
                id: id,
                kind: .work,
                title: work.title,
                deletedAt: try recordedDeletionDate(in: directory)
            ))
        }
        return items
    }

    private func deletedChapters() throws -> [WritingDeletedItem] {
        let folder = WritingDocumentPaths.recentlyDeleted(root)
            .appendingPathComponent("chapters", isDirectory: true)
        var items: [WritingDeletedItem] = []
        for directory in try uuidDirectories(in: folder) {
            guard fileExists(WritingDocumentPaths.chapterFile(directory)),
                  let id = UUID(uuidString: directory.lastPathComponent) else { continue }
            let chapter = try readChapter(at: directory)
            let marker = try readDeletionMarker(in: directory)
            items.append(WritingDeletedItem(
                id: id,
                kind: .chapter(workID: marker?.workID),
                title: chapter.title,
                deletedAt: marker?.deletedAt ?? .distantFuture
            ))
        }
        return items
    }

    /// Missing marker: keep the folder. A date we invented must not sweep it.
    private func recordedDeletionDate(in directory: URL) throws -> Date {
        try readDeletionMarker(in: directory)?.deletedAt ?? .distantFuture
    }

    private func deletionWasRecorded(_ id: UUID) -> Bool {
        let work = WritingDocumentPaths.deletedWorkDirectory(root: root, id: id)
        if fileExists(WritingDocumentPaths.deletionMarker(work)) { return true }
        let chapter = WritingDocumentPaths.deletedChapterDirectory(root: root, id: id)
        return fileExists(WritingDocumentPaths.deletionMarker(chapter))
    }

    func readDeletionMarker(in directory: URL) throws -> WritingDeletionMarker? {
        let url = WritingDocumentPaths.deletionMarker(directory)
        guard fileExists(url) else { return nil }
        return try WritingDocumentIO.readJSON(WritingDeletionMarker.self, from: url)
    }

    func writeDeletionMarker(in directory: URL, workID: UUID?, chapterIndex: Int?) throws {
        let stamp = now()
        let marker = WritingDeletionMarker(
            deletedAt: stamp,
            updatedAt: stamp,
            updatedBy: try deviceID(),
            workID: workID,
            chapterIndex: chapterIndex
        )
        try WritingDocumentIO.writeJSON(marker, to: WritingDocumentPaths.deletionMarker(directory))
    }

    func uuidDirectories(in directory: URL) throws -> [URL] {
        guard fileExists(directory) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            return UUID(uuidString: url.lastPathComponent) != nil
        }
    }

    func moveWithoutOverwrite(from source: URL, to destination: URL) throws {
        guard !fileExists(destination) else {
            throw WritingDocumentError.corrupt(destination.lastPathComponent)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)
    }
}
