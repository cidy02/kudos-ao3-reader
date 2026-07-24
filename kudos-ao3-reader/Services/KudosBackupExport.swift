import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A fully-resolved plan for streaming a `.kudosbackup` archive to disk: the
/// already-encoded manifest plus the file URL of every asset entry. Built on
/// the main actor (it reads SwiftData models), then consumed off it, where the
/// blocking file I/O belongs — so the archive is produced without ever
/// materializing asset bytes in memory the way `makeDocument` does.
nonisolated struct KudosBackupExportPlan: Sendable {
    struct Asset: Sendable {
        let entryName: String
        let fileURL: URL
    }

    let manifestData: Data
    let assets: [Asset]
}

/// Wraps a pre-built archive file for the item-based `fileExporter`, which
/// copies it from disk instead of round-tripping the bytes through memory the
/// way a `FileDocument` would.
nonisolated struct KudosBackupArchiveFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .kudosBackup) {
            SentTransferredFile($0.url, allowAccessingOriginalFile: true)
        }
    }
}

extension KudosBackupService {
    /// Snapshots the manifest and the asset list for an export. Entry order
    /// matches `KudosBackupContents.zipData()` — manifest first, then assets
    /// sorted by name — so streamed and in-memory exports of identical
    /// contents produce identical archives.
    static func makeExportPlan(
        works: [SavedWork],
        bookmarks: [Bookmark],
        fonts: [CustomFont],
        collections: [WorkCollection] = [],
        readingQueues: [ReadingQueue],
        tombstones: [SyncTombstone] = [],
        defaults: UserDefaults = .standard
    ) throws -> KudosBackupExportPlan {
        let queueMemberships = readingQueues.flatMap(\.memberships)
            .compactMap(KudosBackupReadingQueueMembership.init)
        let manifest = KudosBackupManifest(
            works: works.map(KudosBackupWork.init),
            bookmarks: bookmarks.map(KudosBackupBookmark.init),
            fonts: fonts.map(KudosBackupFont.init),
            collections: collections.map(KudosBackupCollection.init),
            readingQueues: readingQueues.map(KudosBackupReadingQueue.init),
            readingQueueMemberships: queueMemberships,
            settings: .capture(defaults: defaults),
            tombstones: tombstones.map(KudosBackupTombstone.init)
        )

        var assets: [KudosBackupExportPlan.Asset] = []
        var seenNames = Set<String>()
        for work in works.sorted(by: { $0.id.uuidString < $1.id.uuidString }) where work.hasEPUB {
            let entryName = "Works/\(work.id.uuidString).epub"
            guard seenNames.insert(entryName).inserted else { continue }
            assets.append(.init(entryName: entryName, fileURL: work.fileURL))
        }
        for font in fonts.sorted(by: { $0.fileName < $1.fileName })
        where KudosBackupContents.isSafeFileName(font.fileName) {
            let entryName = "Fonts/\(font.fileName)"
            guard seenNames.insert(entryName).inserted else { continue }
            assets.append(.init(entryName: entryName, fileURL: font.fileURL))
        }

        return KudosBackupExportPlan(
            manifestData: try KudosBackupContents(manifest: manifest).manifestData(),
            assets: assets
        )
    }

    /// Streams the planned archive to `destination` with the ZIP64-capable
    /// `MiniZip.ArchiveWriter`: constant memory regardless of library size.
    /// An asset that can't be opened is skipped — the manifest entry stays and
    /// restore treats it as metadata-only, exactly like the in-memory
    /// exporter's `try? Data(contentsOf:)` behavior — but any failure past
    /// that point (including a source file changing size mid-stream) aborts
    /// and removes the partial file, so a torn archive is never left behind.
    nonisolated static func writeArchive(
        _ plan: KudosBackupExportPlan,
        to destination: URL
    ) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        guard fm.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let handle = try FileHandle(forWritingTo: destination)
        do {
            let writer = MiniZip.ArchiveWriter { try handle.write(contentsOf: $0) }
            try writer.append(name: "manifest.json", data: plan.manifestData)
            for asset in plan.assets {
                guard let probe = try? FileHandle(forReadingFrom: asset.fileURL) else { continue }
                try? probe.close()
                try writer.append(name: asset.entryName, contentsOf: asset.fileURL)
            }
            try writer.finish()
            try handle.close()
        } catch {
            try? handle.close()
            try? fm.removeItem(at: destination)
            throw error
        }
    }
}
