import Foundation
import SwiftData

/// Per-chapter lengths for the chapter bars, kept off SwiftData and out of
/// backups. The Caches directory is not in a device backup and is not part of
/// `.kudosbackup` or folder sync. A record is the work's id plus the file's
/// size and modification date; either change drops it, and the next read
/// measures the EPUB again. Missing lengths mean equal bars.
nonisolated enum ChapterLengthCache {
    struct Record: Codable, Equatable {
        var byteCount: Int64
        var modifiedAt: TimeInterval
        /// Readium positions per chapter.
        var weights: [Int]
        /// Words per chapter. Missing in records written before word counts: those measure again.
        var words: [Int]?
    }

    private struct Store: Codable {
        var works: [String: Record]
    }

    private static let lock = NSLock()

    /// Weights still true for this file, or nil when there is no record or the
    /// file has changed. An empty list is a real measurement (no story chapters
    /// were kept); a mismatch is not.
    static func keptWeights(_ record: Record?, byteCount: Int64, modifiedAt: TimeInterval) -> [Int]? {
        guard let record, record.byteCount == byteCount, record.modifiedAt == modifiedAt else { return nil }
        return record.weights
    }

    /// The cached lengths when the file still matches, otherwise a fresh
    /// measurement stored under the file's current stamp. A file that cannot
    /// be measured returns nil and leaves the old record in place, so a
    /// transient read error does not freeze a wrong answer and a changed file
    /// does not keep the previous lengths.
    static func weights(workID: UUID, fileURL: URL, directory: URL = defaultDirectory) -> [Int]? {
        guard let fileStamp = stamp(of: fileURL) else { return nil }
        lock.lock()
        let record = load(directory).works[workID.uuidString]
        lock.unlock()
        if let kept = keptWeights(record, byteCount: fileStamp.bytes, modifiedAt: fileStamp.modified) {
            return kept
        }
        return lengths(workID: workID, fileURL: fileURL, directory: directory)?.positions
    }

    /// Positions and word counts still true for this file, otherwise a fresh measurement
    /// stored under the file's current stamp. A record without word counts measures again.
    static func lengths(workID: UUID, fileURL: URL, directory: URL = defaultDirectory) -> ChapterLengths? {
        guard let fileStamp = stamp(of: fileURL) else { return nil }
        let key = workID.uuidString
        lock.lock()
        let record = load(directory).works[key]
        lock.unlock()
        if let positions = keptWeights(record, byteCount: fileStamp.bytes, modifiedAt: fileStamp.modified),
           let words = record?.words {
            return ChapterLengths(positions: positions, words: words)
        }

        guard let measured = try? EPUBDocument.storyChapterLengths(ofEPUBAt: fileURL) else { return nil }

        lock.lock()
        defer { lock.unlock() }
        guard let current = stamp(of: fileURL) else { return nil }
        var fresh = load(directory)
        fresh.works[key] = Record(
            byteCount: current.bytes, modifiedAt: current.modified,
            weights: measured.positions, words: measured.words
        )
        save(fresh, directory: directory)
        // The file moved while it was being read. Don't hand back a measurement
        // that no longer belongs to it.
        guard current.bytes == fileStamp.bytes, current.modified == fileStamp.modified else { return nil }
        return measured
    }

    /// The `.task(id:)` key for a work's lengths: changes when its file is replaced.
    /// "none" without a download, whose bars stay equal.
    @MainActor static func taskKey(for work: SavedWork?) -> String {
        guard let work, work.hasEPUB else { return "none" }
        let values = try? work.fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? -1
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? -1
        return "\(work.id.uuidString)-\(size)-\(modified)"
    }

    /// A downloaded work's lengths, measured off the main thread (cached after the first
    /// time). Nil without a file, or when the work was deleted while it was measured.
    @MainActor static func lengths(for work: SavedWork) async -> ChapterLengths? {
        guard work.hasEPUB else { return nil }
        let id = work.id
        let url = work.fileURL
        let measured = await Task.detached(priority: .utility) {
            ChapterLengthCache.lengths(workID: id, fileURL: url)
        }.value
        return work.modelContext == nil ? nil : measured
    }

    /// Writes a record for the file's stamp as it is now. Tests use this to
    /// plant a cache entry without building an EPUB.
    static func store(
        workID: UUID, fileURL: URL, weights: [Int], words: [Int]? = nil, directory: URL = defaultDirectory
    ) {
        guard let stamp = stamp(of: fileURL) else { return }
        lock.lock()
        defer { lock.unlock() }
        var store = load(directory)
        store.works[workID.uuidString] = Record(
            byteCount: stamp.bytes, modifiedAt: stamp.modified, weights: weights, words: words
        )
        save(store, directory: directory)
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ChapterLengths", isDirectory: true)
    }

    /// Read from the file system each time: `URL.resourceValues` caches size and
    /// date on the URL instance, so a caller holding one URL across a rewrite of
    /// the file would see the old stamp and get the old lengths back.
    private static func stamp(of url: URL) -> (bytes: Int64, modified: TimeInterval)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = (attributes[.size] as? NSNumber)?.int64Value,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return (bytes, modified.timeIntervalSince1970)
    }

    private static func file(in directory: URL) -> URL {
        directory.appendingPathComponent("lengths.json")
    }

    private static func load(_ directory: URL) -> Store {
        guard let data = try? Data(contentsOf: file(in: directory)),
              let store = try? JSONDecoder().decode(Store.self, from: data)
        else { return Store(works: [:]) }
        return store
    }

    private static func save(_ store: Store, directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: file(in: directory), options: .atomic)
    }
}

/// One downloaded work's chapter lengths, story chapters only, in reading order.
/// `positions` are Readium position weights (reading progress is measured in them);
/// `words` are word counts (the chapter bars' heights).
nonisolated struct ChapterLengths: Equatable, Sendable {
    var positions: [Int]
    var words: [Int]
}
