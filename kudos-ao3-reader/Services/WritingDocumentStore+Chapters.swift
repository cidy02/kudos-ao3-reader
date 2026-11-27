import Foundation

extension WritingDocumentStore {
    func listChapters(workID: UUID) throws -> [WritingChapter] {
        let directory = try liveWorkDirectory(workID)
        var work = try readWork(at: directory)
        try settleChapters(in: directory, work: &work)
        return try work.chapterOrder.map { id in
            try readChapter(at: WritingDocumentPaths.chapterDirectory(directory, id: id))
        }
    }

    func addChapter(workID: UUID, title: String = "") throws -> WritingChapter {
        let directory = try liveWorkDirectory(workID)
        var work = try readWork(at: directory)
        try settleChapters(in: directory, work: &work)
        let stamp = now()
        let author = try deviceID()
        let chapter = WritingChapter(
            id: UUID(),
            title: title,
            summary: "",
            notesBefore: "",
            notesAfter: "",
            ao3ChapterID: nil,
            status: .local,
            wordCount: 0,
            bodySavedAt: stamp,
            updatedAt: stamp,
            updatedBy: author
        )
        let folder = WritingDocumentPaths.chapterDirectory(directory, id: chapter.id)
        try WritingDocumentIO.writeJSON(chapter, to: WritingDocumentPaths.chapterFile(folder))
        try WritingDocumentIO.writeText("", to: WritingDocumentPaths.bodyFile(folder))
        work.chapterOrder.append(chapter.id)
        work.updatedAt = stamp
        work.updatedBy = author
        try WritingDocumentIO.writeJSON(work, to: WritingDocumentPaths.workFile(directory))
        return chapter
    }

    func reorderChapters(workID: UUID, order: [UUID]) throws -> WritingWork {
        let directory = try liveWorkDirectory(workID)
        var work = try readWork(at: directory)
        try settleChapters(in: directory, work: &work)
        guard order.count == work.chapterOrder.count, Set(order) == Set(work.chapterOrder) else {
            throw WritingDocumentError.chapterOrderMismatch
        }
        guard order != work.chapterOrder else { return work }
        work.chapterOrder = order
        work.updatedAt = now()
        work.updatedBy = try deviceID()
        try WritingDocumentIO.writeJSON(work, to: WritingDocumentPaths.workFile(directory))
        return work
    }

    func deleteChapter(workID: UUID, chapterID: UUID) throws {
        let directory = try liveWorkDirectory(workID)
        var work = try readWork(at: directory)
        try settleChapters(in: directory, work: &work)
        guard let index = work.chapterOrder.firstIndex(of: chapterID) else {
            throw WritingDocumentError.chapterNotFound(chapterID)
        }
        let folder = WritingDocumentPaths.chapterDirectory(directory, id: chapterID)
        guard fileExists(WritingDocumentPaths.chapterFile(folder)) else {
            throw WritingDocumentError.chapterNotFound(chapterID)
        }
        try writeDeletionMarker(in: folder, workID: workID, chapterIndex: index)
        let marker = WritingDocumentPaths.deletionMarker(folder)
        do {
            try moveWithoutOverwrite(
                from: folder,
                to: WritingDocumentPaths.deletedChapterDirectory(root: root, id: chapterID)
            )
        } catch {
            try? FileManager.default.removeItem(at: marker)
            throw error
        }
        work.chapterOrder.remove(at: index)
        work.updatedAt = now()
        work.updatedBy = try deviceID()
        try WritingDocumentIO.writeJSON(work, to: WritingDocumentPaths.workFile(directory))
    }

    func restoreChapter(_ id: UUID) throws -> WritingChapter {
        let source = WritingDocumentPaths.deletedChapterDirectory(root: root, id: id)
        guard fileExists(WritingDocumentPaths.chapterFile(source)) else {
            throw WritingDocumentError.notInRecentlyDeleted(id)
        }
        guard let marker = try readDeletionMarker(in: source), let workID = marker.workID else {
            throw WritingDocumentError.corrupt("deletion.json")
        }
        let workDirectory = try directoryContainingWork(workID)
        let destination = WritingDocumentPaths.chapterDirectory(workDirectory, id: id)
        guard !fileExists(destination) else { throw WritingDocumentError.corrupt(id.uuidString) }
        // Move first, marker and all. Removing the marker before the move would
        // strand the chapter if the move failed: restore reads the marker to know
        // which work it belongs to.
        try moveWithoutOverwrite(from: source, to: destination)
        try FileManager.default.removeItem(at: WritingDocumentPaths.deletionMarker(destination))
        var work = try readWork(at: workDirectory)
        if !work.chapterOrder.contains(id) {
            let index = min(max(0, marker.chapterIndex ?? work.chapterOrder.count), work.chapterOrder.count)
            work.chapterOrder.insert(id, at: index)
        }
        work.updatedAt = now()
        work.updatedBy = try deviceID()
        try WritingDocumentIO.writeJSON(work, to: WritingDocumentPaths.workFile(workDirectory))
        return try readChapter(at: destination)
    }

    func loadChapter(workID: UUID, chapterID: UUID) throws -> WritingChapterDocument {
        let folder = try chapterDirectory(workID: workID, chapterID: chapterID)
        return WritingChapterDocument(
            chapter: try readChapter(at: folder),
            bodyHTML: try readBody(at: folder)
        )
    }

    /// Saves fields and body. The previous body is copied into `versions/` when the
    /// text changes and either `kind` is destructive or the last text save was at
    /// least ten minutes ago. Field-only saves do not start that clock.
    func saveChapter(
        workID: UUID,
        chapter: WritingChapter,
        bodyHTML: String,
        kind: WritingChapterSaveKind = .edit
    ) throws -> WritingChapterDocument {
        let folder = try chapterDirectory(workID: workID, chapterID: chapter.id)
        let existing = try readChapter(at: folder)
        let previousBody = try readBody(at: folder)
        let stamp = now()
        let author = try deviceID()
        let bodyChanged = previousBody != bodyHTML
        if bodyChanged, shouldSnapshot(existing: existing, kind: kind, now: stamp) {
            let cause: WritingVersionCause = kind == .destructive ? .destructive : .automatic
            try writeSnapshot(previousBody, cause: cause, in: folder, at: stamp, by: author)
        }
        var saved = chapter
        saved.id = existing.id
        saved.wordCount = WritingWordCount.count(bodyHTML)
        saved.updatedAt = stamp
        saved.updatedBy = author
        saved.bodySavedAt = bodyChanged ? stamp : existing.bodySavedAt
        guard bodyChanged || fieldsChanged(existing, saved) else {
            return WritingChapterDocument(chapter: existing, bodyHTML: previousBody)
        }
        if bodyChanged {
            try WritingDocumentIO.writeText(bodyHTML, to: WritingDocumentPaths.bodyFile(folder))
        }
        try WritingDocumentIO.writeJSON(saved, to: WritingDocumentPaths.chapterFile(folder))
        return WritingChapterDocument(chapter: saved, bodyHTML: bodyHTML)
    }

    func listVersions(workID: UUID, chapterID: UUID) throws -> [WritingChapterVersion] {
        let folder = try chapterDirectory(workID: workID, chapterID: chapterID)
        return try readVersions(in: folder)
    }

    func versionBody(workID: UUID, chapterID: UUID, versionID: UUID) throws -> String {
        let folder = try chapterDirectory(workID: workID, chapterID: chapterID)
        let html = WritingDocumentPaths.versionFile(folder, id: versionID, pathExtension: "html")
        let meta = WritingDocumentPaths.versionFile(folder, id: versionID, pathExtension: "json")
        guard fileExists(html), fileExists(meta) else {
            throw WritingDocumentError.versionNotFound(versionID)
        }
        return try WritingDocumentIO.readText(html)
    }

    /// Puts an older body back. The text being replaced is kept as a destructive snapshot.
    func restoreVersion(
        workID: UUID,
        chapterID: UUID,
        versionID: UUID
    ) throws -> WritingChapterDocument {
        let body = try versionBody(workID: workID, chapterID: chapterID, versionID: versionID)
        let current = try loadChapter(workID: workID, chapterID: chapterID)
        return try saveChapter(
            workID: workID,
            chapter: current.chapter,
            bodyHTML: body,
            kind: .destructive
        )
    }

    /// Snapshots the chapter right now as a `.destructive` version, even when the body
    /// matches what is already on disk (used before accepting beta edits).
    @discardableResult
    func snapshotChapterVersion(
        workID: UUID,
        chapterID: UUID,
        bodyHTML: String? = nil
    ) throws -> WritingChapterVersion {
        let folder = try chapterDirectory(workID: workID, chapterID: chapterID)
        let body = try bodyHTML ?? readBody(at: folder)
        return try writeSnapshot(body, cause: .destructive, in: folder, at: now(), by: try deviceID())
    }

    func readChapter(at directory: URL) throws -> WritingChapter {
        try WritingDocumentIO.readJSON(WritingChapter.self, from: WritingDocumentPaths.chapterFile(directory))
    }

    func readBody(at directory: URL) throws -> String {
        let url = WritingDocumentPaths.bodyFile(directory)
        guard fileExists(url) else { throw WritingDocumentError.corrupt("body.html") }
        return try WritingDocumentIO.readText(url)
    }

    /// Finishes a delete that crashed after the marker was written, and puts back a
    /// chapter folder whose `work.json` order never got the id (a crashed add).
    func settleChapters(in workDirectory: URL, work: inout WritingWork) throws {
        let folders = try uuidDirectories(in: WritingDocumentPaths.chapters(workDirectory))
        var live: [UUID] = []
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            if fileExists(WritingDocumentPaths.deletionMarker(folder)) {
                try finishChapterDeletion(folder, id: id)
            } else {
                live.append(id)
            }
        }
        let liveIDs = Set(live)
        var healed = work.chapterOrder.filter { liveIDs.contains($0) }
        for id in live where !healed.contains(id) {
            healed.append(id)
        }
        guard healed != work.chapterOrder else { return }
        work.chapterOrder = healed
        work.updatedAt = now()
        work.updatedBy = try deviceID()
        try WritingDocumentIO.writeJSON(work, to: WritingDocumentPaths.workFile(workDirectory))
    }

    func chapterDirectory(workID: UUID, chapterID: UUID) throws -> URL {
        let workDirectory = try liveWorkDirectory(workID)
        var work = try readWork(at: workDirectory)
        try settleChapters(in: workDirectory, work: &work)
        let folder = WritingDocumentPaths.chapterDirectory(workDirectory, id: chapterID)
        guard work.chapterOrder.contains(chapterID),
              fileExists(WritingDocumentPaths.chapterFile(folder)) else {
            throw WritingDocumentError.chapterNotFound(chapterID)
        }
        return folder
    }

    private func finishChapterDeletion(_ folder: URL, id: UUID) throws {
        let destination = WritingDocumentPaths.deletedChapterDirectory(root: root, id: id)
        guard !fileExists(destination) else { return }
        try moveWithoutOverwrite(from: folder, to: destination)
    }

    private func shouldSnapshot(
        existing: WritingChapter,
        kind: WritingChapterSaveKind,
        now: Date
    ) -> Bool {
        if kind == .destructive { return true }
        return now.timeIntervalSince(existing.bodySavedAt) >= Self.automaticVersionGap
    }

    private func fieldsChanged(_ existing: WritingChapter, _ saved: WritingChapter) -> Bool {
        existing.title != saved.title
            || existing.summary != saved.summary
            || existing.notesBefore != saved.notesBefore
            || existing.notesAfter != saved.notesAfter
            || existing.ao3ChapterID != saved.ao3ChapterID
            || existing.status != saved.status
            || existing.wordCount != saved.wordCount
    }

    /// HTML first, then the JSON record. The JSON is the commit: a body without it
    /// is an interrupted snapshot and is not listed.
    @discardableResult
    private func writeSnapshot(
        _ body: String,
        cause: WritingVersionCause,
        in chapterDirectory: URL,
        at stamp: Date,
        by author: String
    ) throws -> WritingChapterVersion {
        let version = WritingChapterVersion(id: UUID(), cause: cause, updatedAt: stamp, updatedBy: author)
        try WritingDocumentIO.writeText(
            body,
            to: WritingDocumentPaths.versionFile(chapterDirectory, id: version.id, pathExtension: "html")
        )
        try WritingDocumentIO.writeJSON(
            version,
            to: WritingDocumentPaths.versionFile(chapterDirectory, id: version.id, pathExtension: "json")
        )
        try pruneVersions(in: chapterDirectory, now: stamp)
        return version
    }

    func pruneLiveVersions(now: Date) throws {
        for directory in try uuidDirectories(in: root) {
            guard fileExists(WritingDocumentPaths.workFile(directory)),
                  !fileExists(WritingDocumentPaths.deletionMarker(directory)) else { continue }
            for folder in try uuidDirectories(in: WritingDocumentPaths.chapters(directory)) {
                try pruneVersions(in: folder, now: now)
            }
        }
    }

    private func pruneVersions(in chapterDirectory: URL, now: Date) throws {
        let versions = try readVersions(in: chapterDirectory)
        let automatic = versions
            .filter { $0.cause == .automatic }
            .sorted { $0.updatedAt > $1.updatedAt }
        var dropping = Array(automatic.dropFirst(Self.retainedAutomaticVersions))
        dropping.append(contentsOf: versions.filter { version in
            version.cause == .destructive && isExpired(version.updatedAt, now: now)
        })
        for version in dropping {
            let html = WritingDocumentPaths.versionFile(chapterDirectory, id: version.id, pathExtension: "html")
            let meta = WritingDocumentPaths.versionFile(chapterDirectory, id: version.id, pathExtension: "json")
            try? FileManager.default.removeItem(at: html)
            try? FileManager.default.removeItem(at: meta)
        }
    }

    private func readVersions(in chapterDirectory: URL) throws -> [WritingChapterVersion] {
        let directory = WritingDocumentPaths.versions(chapterDirectory)
        guard fileExists(directory) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var versions: [WritingChapterVersion] = []
        for file in files where file.pathExtension == "json" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            let html = WritingDocumentPaths.versionFile(chapterDirectory, id: id, pathExtension: "html")
            guard fileExists(html) else { continue }
            guard let version = try? WritingDocumentIO.readJSON(WritingChapterVersion.self, from: file),
                  version.id == id else { continue }
            versions.append(version)
        }
        return versions.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
