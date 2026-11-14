import Foundation
import ImageIO

/// One queued scan per file revision. The cache is derived data under Caches, never a library field.
actor GeneratedCoverArtLoader {
    static let shared = GeneratedCoverArtLoader()

    private final class Entry: NSObject {
        let image: CGImage? // nil is a scanned "no art" result.
        init(_ image: CGImage?) { self.image = image }
    }

    private let memory = NSCache<NSString, Entry>()
    private let directory: URL
    private let scan: @Sendable (URL) -> Data?
    private var tail: Task<Void, Never>?
    private var scanning: Set<String> = []
    private var waiters: [String: [UUID: CheckedContinuation<CGImage?, Never>]] = [:]

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
             .appendingPathComponent("GeneratedCoverArt", isDirectory: true),
         scan: @escaping @Sendable (URL) -> Data? = { EmbeddedWorkCoverImage.data(at: $0) }) {
        self.directory = directory
        self.scan = scan
    }

    func image(workID: UUID, fileURL: URL) async -> CGImage? {
        guard let modified = Self.modified(fileURL) else { return nil }
        let revision = String(modified.timeIntervalSince1970.bitPattern)
        let key = fileURL.path + "|" + revision
        if let entry = memory.object(forKey: key as NSString) { return entry.image }
        let basename = workID.uuidString + "-" + revision
        let jpeg = directory.appendingPathComponent(basename + ".jpg")
        let empty = directory.appendingPathComponent(basename + ".empty")
        if let data = try? Data(contentsOf: jpeg) {
            let image = Self.decoded(data)
            memory.setObject(Entry(image), forKey: key as NSString)
            return image
        }
        if FileManager.default.fileExists(atPath: empty.path) {
            memory.setObject(Entry(nil), forKey: key as NSString)
            return nil
        }

        let waiter = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: nil); return }
                waiters[key, default: [:]][waiter] = continuation
                guard scanning.insert(key).inserted else { return }
                let previous = tail
                let scan = self.scan
                tail = Task.detached(priority: .utility) { [self] in
                    await previous?.value
                    let data = EmbeddedWorkCoverImage.downsampledJPEG(scan(fileURL))
                    await finish(key: key, workID: workID, fileURL: fileURL,
                                 revision: revision, data: data)
                }
            }
        } onCancel: {
            Task { await self.cancel(key: key, waiter: waiter) }
        }
    }

    private func cancel(key: String, waiter: UUID) {
        guard var entries = waiters[key], let continuation = entries.removeValue(forKey: waiter) else { return }
        waiters[key] = entries
        continuation.resume(returning: nil)
    }

    private func finish(key: String, workID: UUID, fileURL: URL, revision: String, data: Data?) {
        // A replacement during extraction must not publish an image from the old EPUB.
        let current = Self.modified(fileURL).map { String($0.timeIntervalSince1970.bitPattern) }
        let result = current == revision ? data : nil
        let image = Self.decoded(result)
        if current == revision {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let basename = workID.uuidString + "-" + revision
            let destination = directory.appendingPathComponent(basename + (result == nil ? ".empty" : ".jpg"))
            if let result { try? result.write(to: destination, options: .atomic) }
            else { try? Data().write(to: destination, options: .atomic) }
            for old in (try? FileManager.default.contentsOfDirectory(at: directory,
                         includingPropertiesForKeys: nil)) ?? []
            where old.lastPathComponent.hasPrefix(workID.uuidString + "-") && old != destination {
                try? FileManager.default.removeItem(at: old)
            }
            memory.setObject(Entry(image), forKey: key as NSString)
        }
        scanning.remove(key)
        if let continuations = waiters.removeValue(forKey: key) {
            for continuation in continuations.values { continuation.resume(returning: image) }
        }
    }

    private static func modified(_ file: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    private static func decoded(_ data: Data?) -> CGImage? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
