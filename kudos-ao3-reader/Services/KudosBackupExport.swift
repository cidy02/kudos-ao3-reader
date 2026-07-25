import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A fully-resolved plan for streaming a `.kudosbackup` archive to disk: the
/// already-encoded manifest plus the file URL of every asset entry. Built on
/// the main actor (it reads SwiftData models), then consumed off it, where the
/// blocking file I/O belongs — so the archive is produced without ever
/// materializing asset bytes in memory the way `makeContents` does.
nonisolated struct KudosBackupExportPlan: Sendable {
    struct Asset: Sendable {
        let entryName: String
        let fileURL: URL
    }

    let manifestData: Data
    let assets: [Asset]
}

/// Why an export was refused before any archive bytes were written. The
/// writer itself has no ceilings (ZIP64), so these mirror the reader's
/// `.backup` limits at export time — "backup created" must always imply
/// "backup restorable", instead of the size asymmetry surfacing only when a
/// restore fails much later.
nonisolated enum KudosBackupExportError: LocalizedError {
    case tooManyEntries(count: Int, limit: Int)
    case assetTooLarge(name: String, size: UInt64, limit: Int)
    case archiveTooLarge(limit: Int)

    private static func formatted(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    var errorDescription: String? {
        switch self {
        case let .tooManyEntries(count, limit):
            "This backup would contain \(count) files, more than the "
                + "\(limit) a backup can hold."
        case let .assetTooLarge(name, size, limit):
            "\(name) is \(Self.formatted(size)), larger than the "
                + "\(Self.formatted(UInt64(limit))) per-file backup limit."
        case let .archiveTooLarge(limit):
            "This backup would be larger than the "
                + "\(Self.formatted(UInt64(limit))) total backup limit."
        }
    }
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
    /// A stat-only preflight enforces `limits` (the reader's `.backup` caps)
    /// before anything is written, so an unrestorable export fails fast
    /// instead of after streaming gigabytes. An asset that can't be opened is
    /// skipped — the manifest entry stays and restore treats it as
    /// metadata-only, exactly like the in-memory exporter's
    /// `try? Data(contentsOf:)` behavior — but any failure past the preflight
    /// (including a source file changing size mid-stream) aborts and removes
    /// the partial file, so a torn archive is never left behind.
    nonisolated static func writeArchive(
        _ plan: KudosBackupExportPlan,
        to destination: URL,
        limits: MiniZip.Limits = .backup
    ) throws {
        guard plan.assets.count + 1 <= limits.maxEntryCount else {
            throw KudosBackupExportError.tooManyEntries(
                count: plan.assets.count + 1,
                limit: limits.maxEntryCount
            )
        }
        guard plan.manifestData.count <= limits.maxSingleEntryUncompressedSize else {
            throw KudosBackupExportError.assetTooLarge(
                name: "manifest.json",
                size: UInt64(plan.manifestData.count),
                limit: limits.maxSingleEntryUncompressedSize
            )
        }
        var includedAssets: [KudosBackupExportPlan.Asset] = []
        var total = UInt64(plan.manifestData.count)
        for asset in plan.assets {
            guard let probe = try? FileHandle(forReadingFrom: asset.fileURL),
                  let size = try? probe.seekToEnd()
            else { continue }
            try? probe.close()
            guard size <= UInt64(limits.maxSingleEntryUncompressedSize) else {
                throw KudosBackupExportError.assetTooLarge(
                    name: asset.entryName,
                    size: size,
                    limit: limits.maxSingleEntryUncompressedSize
                )
            }
            total += size
            guard total <= UInt64(limits.maxTotalUncompressedSize) else {
                throw KudosBackupExportError.archiveTooLarge(
                    limit: limits.maxTotalUncompressedSize
                )
            }
            includedAssets.append(asset)
        }

        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        guard fm.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let handle = try FileHandle(forWritingTo: destination)
        do {
            let writer = MiniZip.ArchiveWriter { try handle.write(contentsOf: $0) }
            try writer.append(name: "manifest.json", data: plan.manifestData)
            for asset in includedAssets {
                // Re-probed just before appending: a file that vanished since
                // the preflight is still a skip, not a failed export.
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
