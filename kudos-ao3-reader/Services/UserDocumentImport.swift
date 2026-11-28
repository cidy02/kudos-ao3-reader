import Darwin
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
    /// Reads dates while the caller still holds access to the original picked
    /// URL. Nothing here copies or mutates the file.
    static func detectDownloadDate(
        of url: URL,
        now: Date = Date()
    ) async throws -> DownloadDateDetection {
        try await waitForUbiquitousDownload(of: url)
        return await Task.detached(priority: .userInitiated) {
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let generatedAt: Date?
            if url.pathExtension.localizedCaseInsensitiveCompare("epub") == .orderedSame {
                generatedAt = try? EPUBDocument.metadata(ofEPUBAt: url).generatedAt
            } else {
                generatedAt = nil
            }
            return DownloadDateDetector.detect(
                fileCreated: values?.creationDate,
                fileModified: values?.contentModificationDate,
                epubGeneratedAt: generatedAt,
                now: now
            )
        }.value
    }

    /// Imports the file at `url`, converting first when it is not already an EPUB.
    ///
    /// Returns the same outcome type as a plain EPUB import so callers show one
    /// set of messages, plus the format the file came from so the UI can say what
    /// it did ("Converted from HTML").
    static func perform(
        _ url: URL,
        downloadedAt: Date = Date(),
        importSource: WorkImportSource = .fileImport,
        originalsDirectory: URL? = nil,
        verifyAvailability: Bool = true,
        into context: ModelContext
    ) async throws -> (outcome: UserEPUBImportOutcome, convertedFrom: ImportedFileFormat?) {
        guard url.isFileURL else { throw UserEPUBImportError.notLocalFile }
        // A picked iCloud Drive file may still be a placeholder; reading it before
        // it materializes fails with an opaque error instead of waiting.
        try await waitForUbiquitousDownload(of: url)

        let format = await Task.detached(priority: .userInitiated) {
            ImportedFileFormat.detect(at: url)
        }.value
        if format == .epub {
            let outcome = try await importUserEPUB(
                url, downloadedAt: downloadedAt, importSource: importSource,
                verifyAvailability: verifyAvailability, into: context
            )
            return (outcome, nil)
        }
        guard format.isConvertible else { throw ImportedDocumentConverter.ConversionError.notYetSupported(format) }

        let directory = originalsDirectory ?? Storage.originalsDirectory
        let stagedSource = try await Task.detached(priority: .userInitiated) {
            try StagedOriginal.copySource(url, into: directory)
        }.value
        let stagingDirectory = stagedSource.deletingLastPathComponent().deletingLastPathComponent()
        let original = StagedOriginal(source: stagedSource, stagingDirectory: stagingDirectory, directory: directory)
        defer { original.discardStaging() }

        // Convert the archived bytes so that an edit to the picked file cannot
        // leave the reader's EPUB and the original representing different inputs.
        let conversion = try await Task.detached(priority: .userInitiated) {
            try ImportedDocumentConverter.convert(fileAt: stagedSource)
        }.value

        switch conversion {
        case .alreadyEPUB:
            let imported = try await importUserEPUB(
                stagedSource, downloadedAt: downloadedAt, importSource: importSource,
                verifyAvailability: verifyAvailability, into: context
            )
            return (imported, nil)
        case let .converted(data, format):
            let stagedEPUB = Storage.tempDownloadURL(suggestedName: "\(UUID().uuidString).epub")
            defer { try? FileManager.default.removeItem(at: stagedEPUB) }
            try data.write(to: stagedEPUB, options: .atomic)
            let outcome = try await importUserEPUB(
                stagedEPUB, downloadedAt: downloadedAt, importSource: importSource,
                original: (original, format), verifyAvailability: verifyAvailability, into: context
            )
            Log.library.info(
                "Imported “\(outcome.work.title)” converted from \(format.rawValue, privacy: .public)"
            )
            return (outcome, format)
        }
    }

    /// An import owns one hidden staging directory on the Originals volume.
    /// The final names are installed synchronously before any model is changed.
    @MainActor
    final class StagedOriginal {
        let source: URL
        let stagingDirectory: URL
        let directory: URL
        private var needsRecovery = false

        init(source: URL, stagingDirectory: URL, directory: URL) {
            self.source = source
            self.stagingDirectory = stagingDirectory
            self.directory = directory
        }

        nonisolated static func copySource(_ source: URL, into directory: URL) throws -> URL {
            let manager = FileManager.default
            let staging = directory.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
            let sourceDirectory = staging.appendingPathComponent("Source", isDirectory: true)
            let copy = sourceDirectory.appendingPathComponent(source.lastPathComponent)
            do {
                try manager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
                try manager.copyItem(at: source.resolvingSymlinksInPath(), to: copy)
                return copy
            } catch {
                try? manager.removeItem(at: staging)
                throw Self.preservationError(error)
            }
        }

        func discardStaging() {
            if !needsRecovery { try? FileManager.default.removeItem(at: stagingDirectory) }
        }

        func install(
            for workID: UUID,
            format: ImportedFileFormat,
            replacesEPUB: Bool,
            save: () throws -> UserEPUBImportOutcome
        ) throws -> UserEPUBImportOutcome {
            let manager = FileManager.default
            let fileExtension = source.pathExtension.isEmpty ? format.rawValue : source.pathExtension
            let destination = Storage.originalDocumentURL(for: workID, fileExtension: fileExtension, in: directory)
            let sidecar = WorkConversionRecord.url(for: workID, in: directory)
            let previousOriginals = Storage.originalDocuments(for: workID, in: directory)
            let record = WorkConversionRecord(
                converterVersion: replacesEPUB ? ImportedDocumentConverter.converterVersion : 0,
                format: format.rawValue,
                originalFileName: source.lastPathComponent
            )

            var undo: [() throws -> Void] = []
            var saved = false
            defer {
                if !saved {
                    for restore in undo.reversed() {
                        do { try restore() } catch {
                            needsRecovery = true
                            Log.library.error(
                                "Couldn't roll back original import: \(error.localizedDescription, privacy: .private)"
                            )
                        }
                    }
                }
            }
            do {
                let stagedRecord = stagingDirectory.appendingPathComponent("record")
                try JSONEncoder().encode(record).write(to: stagedRecord)
                try installFile(source, at: destination, backupName: "original-backup", undo: &undo)
                try installFile(stagedRecord, at: sidecar, backupName: "record-backup", undo: &undo)
                for (index, previous) in previousOriginals.enumerated() {
                    guard previous.lastPathComponent.caseInsensitiveCompare(destination.lastPathComponent)
                        != .orderedSame else { continue }
                    let backup = stagingDirectory.appendingPathComponent("original-backup-\(index)")
                    try manager.moveItem(at: previous, to: backup)
                    undo.append { try Self.rename(backup, to: previous) }
                }
            } catch {
                throw Self.preservationError(error)
            }
            let outcome = try save()
            saved = true
            return outcome
        }

        private func installFile(
            _ staged: URL, at destination: URL, backupName: String, undo: inout [() throws -> Void]
        ) throws {
            let manager = FileManager.default
            let backup = stagingDirectory.appendingPathComponent(backupName)
            let existed = manager.fileExists(atPath: destination.path)
            // Keep the previous file reachable until the atomic rename succeeds,
            // and retain a link to its bytes until SwiftData commits.
            if existed { try manager.linkItem(at: destination, to: backup) }
            try Self.rename(staged, to: destination)
            undo.append {
                if existed {
                    try Self.rename(backup, to: destination)
                } else {
                    try manager.removeItem(at: destination)
                }
            }
        }

        private static func rename(_ source: URL, to destination: URL) throws {
            guard Darwin.rename(source.path, destination.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        }

        private nonisolated static func preservationError(_ error: Error) -> UserEPUBImportError {
            Log.library.error(
                "Couldn't preserve the original import: \(error.localizedDescription, privacy: .private)"
            )
            return .couldNotKeepOriginal
        }
    }
}
