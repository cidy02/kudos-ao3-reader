import Foundation
import OSLog
import SwiftData

/// Imports a user-selected file of *any* supported format by converting it to an
/// EPUB and handing that to `importUserEPUB`.
///
/// The conversion seam lives here, at the very edge of the app, on purpose.
/// Everything past this point — both readers, preservation, reading queues, the
/// search index, `.kudosbackup`, folder sync — is EPUB-only by contract
/// (`Storage.safeEPUBAssetIdentifier` rejects any other asset identifier), so
/// teaching the app new formats would mean touching all of it. Converting at the
/// door means none of it changes.
@MainActor
enum UserDocumentImport {
    /// Imports the file at `url`, converting first when it is not already an EPUB.
    ///
    /// Returns the same outcome type as a plain EPUB import so callers show one
    /// set of messages, plus the format the file came from so the UI can say what
    /// it did ("Converted from HTML").
    static func perform(
        _ url: URL,
        into context: ModelContext
    ) async throws -> (outcome: UserEPUBImportOutcome, convertedFrom: ImportedFileFormat?) {
        guard url.isFileURL else { throw UserEPUBImportError.notLocalFile }
        // A picked iCloud Drive file may still be a placeholder; reading it before
        // it materializes fails with an opaque error instead of waiting.
        try await waitForUbiquitousDownload(of: url)

        // Sniffing, unzipping and re-serializing a whole work is heavy, so it runs
        // off the main actor — the same reason `importEPUB` detaches its metadata
        // read. Only SwiftData work happens back here.
        let conversion = try await Task.detached(priority: .userInitiated) {
            try ImportedDocumentConverter.convert(fileAt: url)
        }.value

        switch conversion {
        case .alreadyEPUB:
            return (try await importUserEPUB(url, into: context), nil)
        case let .converted(data, format):
            let outcome = try await importConverted(data, from: url, format: format, into: context)
            return (outcome, format)
        }
    }

    /// Writes converted EPUB bytes to a temp file, imports that, then preserves
    /// the original alongside the work.
    private static func importConverted(
        _ epub: Data,
        from source: URL,
        format: ImportedFileFormat,
        into context: ModelContext
    ) async throws -> UserEPUBImportOutcome {
        let staged = Storage.tempDownloadURL(suggestedName: "\(UUID().uuidString).epub")
        try epub.write(to: staged, options: .atomic)
        defer { try? FileManager.default.removeItem(at: staged) }

        let outcome = try await importUserEPUB(staged, into: context)
        preserveOriginal(at: source, for: outcome.work, format: format)
        Log.library.info(
            "Imported “\(outcome.work.title)” converted from \(format.rawValue, privacy: .public)"
        )
        return outcome
    }

    /// Keeps the exact bytes the user handed us next to the work.
    ///
    /// Best-effort by design: a converted work that reads correctly should not
    /// fail to import because its archival copy could not be written (a full disk,
    /// a revoked sandbox URL). The EPUB is what the reader needs; the original is
    /// insurance, so a failure is logged and swallowed rather than thrown.
    private static func preserveOriginal(at source: URL, for work: SavedWork, format: ImportedFileFormat) {
        let fileExtension = source.pathExtension.isEmpty ? format.rawValue : source.pathExtension
        let destination = Storage.originalDocumentURL(for: work.id, fileExtension: fileExtension)
        do {
            // Replace rather than skip: re-importing a corrected copy of the same
            // work should update the archived original too.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            Log.library.error(
                "Couldn't preserve the original import: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
