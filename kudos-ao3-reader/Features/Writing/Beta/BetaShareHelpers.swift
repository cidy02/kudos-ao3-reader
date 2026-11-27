import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

// MARK: - Platform share / file export helpers for beta reading

nonisolated enum BetaDOCXContentType {
    static let docx = UTType(filenameExtension: "docx") ?? .data
}

nonisolated extension BetaDOCXReader {
    /// Maximum returned `.docx` file size accepted before reading into memory (20 MB).
    static let maxFileBytes = 20 * 1024 * 1024

    /// Tighter ZIP limits than `.epub` (200 MB/entry, 500 MB total, 1100:1) for untrusted
    /// returned beta documents: an AO3 chapter is capped at 510,000 characters.
    static let docxLimits = MiniZip.Limits(
        maxEntryCount: 500,
        maxSingleEntryUncompressedSize: 25 * 1024 * 1024,
        maxTotalUncompressedSize: 50 * 1024 * 1024,
        maxCompressionRatio: 200
    )

    static func read(
        docxData: Data,
        limits: MiniZip.Limits = docxLimits
    ) throws -> BetaDOCXDocument {
        guard docxData.count <= maxFileBytes else {
            throw BetaReadingError.fileTooLarge(maxBytes: maxFileBytes)
        }
        let zip: MiniZip
        do {
            zip = try MiniZip(data: docxData, limits: limits)
        } catch {
            throw BetaReadingError.invalidDOCX(error.localizedDescription)
        }
        guard let documentXML = entryData(named: "word/document.xml", in: zip) else {
            throw BetaReadingError.missingDocumentXML
        }
        let commentsXML = entryData(named: "word/comments.xml", in: zip)
        let commentsExtendedXML = entryData(named: "word/commentsExtended.xml", in: zip)
        return try parse(
            documentXML: documentXML,
            commentsXML: commentsXML,
            commentsExtendedXML: commentsExtendedXML
        )
    }

    private static func entryData(named target: String, in zip: MiniZip) -> Data? {
        if let direct = zip.data(named: target) {
            return direct
        }
        let lower = target.lowercased()
        guard let matched = zip.names.first(where: { $0.lowercased() == lower }) else {
            return nil
        }
        return zip.data(named: matched)
    }

    /// Reads a returned `.docx` file, refusing files above `maxBytes` before reading them.
    static func readFileData(at url: URL, maxBytes: Int = maxFileBytes) throws -> Data {
        if let size = reportedFileSize(at: url), size > UInt64(maxBytes) {
            throw BetaReadingError.fileTooLarge(maxBytes: maxBytes)
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw BetaReadingError.fileReadFailed(error.localizedDescription)
        }
        defer { try? handle.close() }

        var data = Data()
        let chunkSize = 1024 * 1024
        while true {
            let remaining = (maxBytes + 1) - data.count
            guard remaining > 0 else {
                throw BetaReadingError.fileTooLarge(maxBytes: maxBytes)
            }
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: min(chunkSize, remaining))
            } catch {
                throw BetaReadingError.fileReadFailed(error.localizedDescription)
            }
            guard let chunk, !chunk.isEmpty else { break }
            data.append(chunk)
            if data.count > maxBytes {
                throw BetaReadingError.fileTooLarge(maxBytes: maxBytes)
            }
        }
        return data
    }

    private static func reportedFileSize(at url: URL) -> UInt64? {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size >= 0 {
            return UInt64(size)
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let number = attrs[.size] as? NSNumber {
            return number.uint64Value
        }
        return nil
    }
}

nonisolated struct BetaShareFileItem: Identifiable, Sendable {
    let id = UUID()
    let url: URL

    static func cleanUp(_ url: URL) {
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parent)
    }
}

#if os(iOS)
struct BetaShareActivitySheet: UIViewControllerRepresentable {
    let url: URL
    let onComplete: @MainActor @Sendable () -> Void

    final class Coordinator {
        var onComplete: (@MainActor @Sendable () -> Void)?

        init(onComplete: @escaping @MainActor @Sendable () -> Void) {
            self.onComplete = onComplete
        }

        func finish() {
            let action = onComplete
            onComplete = nil
            action?()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        let coordinator = context.coordinator
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in coordinator.finish() }
        }
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}

    static func dismantleUIViewController(_: UIActivityViewController, coordinator: Coordinator) {
        coordinator.finish()
    }
}
#else
nonisolated struct BetaExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [BetaDOCXContentType.docx] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
