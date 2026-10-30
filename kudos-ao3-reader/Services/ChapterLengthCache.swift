import Foundation

/// Per-chapter lengths for the chapter bars, kept off SwiftData and out of
/// backups. The Caches directory is not in a device backup and is not part of
/// `.kudosbackup` or folder sync. A record is the work's id plus the file's
/// size and modification date; either change drops it, and the next read
/// measures the EPUB again. Missing lengths mean equal bars.
nonisolated enum ChapterLengthCache {
    struct Record: Codable, Equatable {
        var byteCount: Int64
        var modifiedAt: TimeInterval
        var weights: [Int]
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
        let key = workID.uuidString
        lock.lock()
        let store = load(directory)
        if let kept = keptWeights(store.works[key], byteCount: fileStamp.bytes, modifiedAt: fileStamp.modified) {
            lock.unlock()
            return kept
        }
        lock.unlock()

        guard let measured = try? EPUBDocument.storyChapterPositionWeights(ofEPUBAt: fileURL) else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }
        guard let current = stamp(of: fileURL) else { return nil }
        var fresh = load(directory)
        fresh.works[key] = Record(
            byteCount: current.bytes, modifiedAt: current.modified, weights: measured
        )
        save(fresh, directory: directory)
        // The file moved while it was being read. Don't hand back a measurement
        // that no longer belongs to it.
        guard current.bytes == fileStamp.bytes, current.modified == fileStamp.modified else { return nil }
        return measured
    }

    /// Writes a record for the file's stamp as it is now. Tests use this to
    /// plant a cache entry without building an EPUB.
    static func store(
        workID: UUID, fileURL: URL, weights: [Int], directory: URL = defaultDirectory
    ) {
        guard let stamp = stamp(of: fileURL) else { return }
        lock.lock()
        defer { lock.unlock() }
        var store = load(directory)
        store.works[workID.uuidString] = Record(
            byteCount: stamp.bytes, modifiedAt: stamp.modified, weights: weights
        )
        save(store, directory: directory)
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ChapterLengths", isDirectory: true)
    }

    private static func stamp(of url: URL) -> (bytes: Int64, modified: TimeInterval)? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let bytes = values?.fileSize, let modified = values?.contentModificationDate else { return nil }
        return (Int64(bytes), modified.timeIntervalSince1970)
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
