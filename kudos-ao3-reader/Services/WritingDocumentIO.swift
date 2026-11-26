import Foundation

/// On-disk layout of `Writing/`. A leftover `*.tmp` is an interrupted write and is
/// never read as the document it was saving.
enum WritingDocumentPaths {
    static let recentlyDeletedDirectoryName = "Recently Deleted"
    static let temporarySuffix = ".tmp"
    static let deviceIDFileName = "device-id"

    static func workDirectory(root: URL, id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func deletedWorkDirectory(root: URL, id: UUID) -> URL {
        recentlyDeleted(root).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func deletedChapterDirectory(root: URL, id: UUID) -> URL {
        recentlyDeleted(root)
            .appendingPathComponent("chapters", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func recentlyDeleted(_ root: URL) -> URL {
        root.appendingPathComponent(recentlyDeletedDirectoryName, isDirectory: true)
    }

    static func workFile(_ directory: URL) -> URL {
        directory.appendingPathComponent("work.json")
    }

    static func storyNotes(_ directory: URL) -> URL {
        directory.appendingPathComponent("storyNotes.json")
    }

    static func annotations(_ directory: URL) -> URL {
        directory.appendingPathComponent("annotations.json")
    }

    static func deletionMarker(_ directory: URL) -> URL {
        directory.appendingPathComponent("deletion.json")
    }

    static func chapters(_ directory: URL) -> URL {
        directory.appendingPathComponent("chapters", isDirectory: true)
    }

    static func chapterDirectory(_ workDirectory: URL, id: UUID) -> URL {
        chapters(workDirectory).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func chapterFile(_ directory: URL) -> URL {
        directory.appendingPathComponent("chapter.json")
    }

    static func bodyFile(_ directory: URL) -> URL {
        directory.appendingPathComponent("body.html")
    }

    static func versions(_ chapterDirectory: URL) -> URL {
        chapterDirectory.appendingPathComponent("versions", isDirectory: true)
    }

    static func versionFile(_ chapterDirectory: URL, id: UUID, pathExtension: String) -> URL {
        versions(chapterDirectory)
            .appendingPathComponent(id.uuidString)
            .appendingPathExtension(pathExtension)
    }

    static func deviceID(_ root: URL) -> URL {
        root.appendingPathComponent(deviceIDFileName)
    }

    static func temporaryFile(for url: URL) -> URL {
        URL(fileURLWithPath: url.path + temporarySuffix)
    }
}

/// JSON and text writes for the writing folder. Dates are fractional-second
/// ISO-8601, and a whole-second value still decodes. The encoder is locked
/// because two stores (two tests) may encode at once; `JSONEncoder` is a class.
enum WritingDocumentIO {
    private static let codingLock = NSLock()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSecondFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter.string(from: date))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractionalFormatter.date(from: string) { return date }
            if let date = wholeSecondFormatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date."
            )
        }
        return decoder
    }()

    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Same shape as WritingTextRecovery.save: `Data.write(options: .atomic)`
        // fills a temporary file, then we rename it over the real one. A crash
        // before the rename leaves `url` + ".tmp" and the previous file intact.
        let temporary = WritingDocumentPaths.temporaryFile(for: url)
        try data.write(to: temporary, options: .atomic)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try write(encode(value), to: url)
    }

    static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        do {
            return try decode(type, from: data)
        } catch {
            throw WritingDocumentError.corrupt(url.lastPathComponent)
        }
    }

    static func writeText(_ text: String, to url: URL) throws {
        try write(Data(text.utf8), to: url)
    }

    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw WritingDocumentError.corrupt(url.lastPathComponent)
        }
        return text
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try locked { try encoder.encode(value) }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try locked { try decoder.decode(type, from: data) }
    }

    private static func locked<T>(_ body: () throws -> T) rethrows -> T {
        codingLock.lock()
        defer { codingLock.unlock() }
        return try body()
    }
}
