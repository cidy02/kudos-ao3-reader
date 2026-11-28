import CoreTransferable
import Foundation
import OSLog
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
        var originalWorkTitle: String? = nil
        var requiresOriginalEntry: String? = nil
    }

    let manifestData: Data
    let assets: [Asset]
    var missingOriginalTitles: [String] = []
}

nonisolated struct KudosBackupArchiveExportResult: Sendable {
    let skippedEntries: [String]
    let omittedOriginalTitles: [String]

    var skippedOtherAssetCount: Int {
        skippedEntries.filter { !$0.hasPrefix("Originals/") || $0.hasSuffix(Storage.conversionRecordSuffix) }.count
    }
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
        // Required, not cosmetic: without a suggested name the item-based
        // `fileExporter` hands `NSFileWrapper` an empty `preferredFilename`,
        // which raises `NSInvalidArgumentException` ("preferredFilename cannot
        // be empty") and kills the app the instant Export Backup is tapped.
        // The `defaultFilename:` argument at the call site does NOT feed this
        // path. The name the user actually sees comes from the exported file's
        // own URL (see `exportBackup()`, which names the temp file for exactly
        // that reason); this value is the fallback that keeps the wrapper legal.
        .suggestedFileName("Kudos Backup.kudosbackup")
    }
}

extension KudosBackupService {
    struct OriginalExportSource {
        let title: String
        let original: URL?
        let record: URL?
    }

    /// A sidecar without its source still tells us which work is missing a file.
    static func originalExportSources(for works: [SavedWork]) -> [OriginalExportSource] {
        guard !works.isEmpty else { return [] }
        let directory = Storage.originalsDirectory
        let originals = Storage.existingOriginalDocumentURLs()
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        var seen = Set<UUID>()
        return works.sorted(by: { $0.id.uuidString < $1.id.uuidString }).compactMap { work in
            guard seen.insert(work.id).inserted else { return nil }
            let original = originals[work.id]
            let recordURL = WorkConversionRecord.url(for: work.id, in: directory)
            let record = names.contains(recordURL.lastPathComponent) ? recordURL : nil
            guard original != nil || record != nil else { return nil }
            return OriginalExportSource(title: work.title, original: original, record: record)
        }
    }

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
        annotations: [ReadingAnnotation] = [],
        savedSearches: [SavedSearch] = [],
        readingSessions: [ReadingSession] = [],
        readingFavorites: [ReadingFavorite] = [],
        fandomReadWatermarks: [FandomReadWatermark] = [],
        followedTags: [FollowedTag] = [],
        tagAliases: [TagAlias] = [],
        tombstones: [SyncTombstone] = [],
        defaults: UserDefaults = .standard
    ) throws -> KudosBackupExportPlan {
        let queueMemberships = readingQueues
            .filter { $0.kind != .smart }
            .flatMap(\.memberships)
            .compactMap(KudosBackupReadingQueueMembership.init)
        let manifest = KudosBackupManifest(
            works: works.map(KudosBackupWork.init),
            bookmarks: bookmarks.map(KudosBackupBookmark.init),
            fonts: fonts.map(KudosBackupFont.init),
            collections: collections.map(KudosBackupCollection.init),
            readingQueues: readingQueues.map(KudosBackupReadingQueue.init),
            readingQueueMemberships: queueMemberships,
            annotations: annotations.compactMap(KudosBackupAnnotation.init),
            savedSearches: savedSearches.map(KudosBackupSavedSearch.init),
            readingSessions: readingSessions.map(KudosBackupReadingSession.init),
            readingFavorites: readingFavorites.map(KudosBackupReadingFavorite.init),
            fandomReadWatermarks: fandomReadWatermarks.map(KudosBackupFandomReadWatermark.init),
            followedTags: followedTags.map(KudosBackupFollowedTag.init),
            tagAliases: tagAliases.map(KudosBackupTagAlias.init),
            settings: .capture(defaults: defaults),
            pronunciations: .capture(),
            tombstones: tombstones.map(KudosBackupTombstone.init)
        )

        var assets: [KudosBackupExportPlan.Asset] = []
        var seenNames = Set<String>()
        let orderedWorks = works.sorted(by: { $0.id.uuidString < $1.id.uuidString })
        for work in orderedWorks where work.hasEPUB {
            let entryName = "Works/\(work.id.uuidString).epub"
            guard seenNames.insert(entryName).inserted else { continue }
            assets.append(.init(entryName: entryName, fileURL: work.fileURL))
        }
        // Fonts a restore would refuse are left out of the archive rather than
        // carried into it. Restore rejects the entire backup over one bad font,
        // so including it trades a decoration for the whole library — and a
        // library already holding such a font, installed back when nothing
        // checked, still exports something that restores.
        //
        // The manifest goes on listing them: restore skips a font whose bytes
        // are absent, and the entry preserves the name so the reader can see
        // what to install again. Dropping it from the manifest instead would
        // drop the `readerFontID` pointing at it.
        var aggregateFontBytes = 0
        for font in fonts.sorted(by: { $0.fileName < $1.fileName }) {
            let name = font.fileName
            let entryName = "Fonts/\(name)"
            guard let data = try? Data(contentsOf: font.fileURL, options: .mappedIfSafe) else {
                Log.library.error("Backup skips unreadable font \(name, privacy: .private).")
                continue
            }
            if let reason = KudosBackupContents.fontRejectionReason(fileName: name, data: data) {
                Log.library.error("Backup skips font \(name, privacy: .private): \(reason, privacy: .private)")
                continue
            }
            // The total cap sinks a backup just as firmly as the per-font one,
            // so eight individually-valid fonts can still cost a library.
            guard aggregateFontBytes <= KudosBackupContents.maxTotalFontBytes - data.count else {
                Log.library.error("Backup skips font \(name, privacy: .private): total reached.")
                continue
            }
            guard seenNames.insert(entryName).inserted else { continue }
            aggregateFontBytes += data.count
            assets.append(.init(entryName: entryName, fileURL: font.fileURL))
        }

        // Imported originals travel with the works they belong to. Streamed
        // from disk like every other asset, so a 200 MB PDF never has to be
        // resident — the reader's `.backup` limits (1 GB per entry, 64 GB
        // total) already cover anything a document import can produce.
        var missingOriginalTitles: [String] = []
        for source in originalExportSources(for: orderedWorks) {
            guard let original = source.original else {
                missingOriginalTitles.append(source.title)
                continue
            }
            let entryName = "Originals/\(original.lastPathComponent)"
            assets.append(.init(entryName: entryName, fileURL: original, originalWorkTitle: source.title))
            if let record = source.record {
                assets.append(.init(
                    entryName: "Originals/\(record.lastPathComponent)", fileURL: record,
                    requiresOriginalEntry: entryName
                ))
            }
        }

        return KudosBackupExportPlan(
            manifestData: try KudosBackupContents(manifest: manifest).manifestData(),
            assets: assets,
            missingOriginalTitles: missingOriginalTitles
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
    ///
    /// Returns skipped entries and the titles of works whose originals were omitted.
    @discardableResult
    nonisolated static func writeArchive(
        _ plan: KudosBackupExportPlan,
        to destination: URL,
        limits: MiniZip.Limits = .backup
    ) throws -> KudosBackupArchiveExportResult {
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
        var skipped = Set<String>()
        var omittedTitles = plan.missingOriginalTitles
        func skip(_ asset: KudosBackupExportPlan.Asset) {
            skipped.insert(asset.entryName)
            if let title = asset.originalWorkTitle { omittedTitles.append(title) }
        }
        var total = UInt64(plan.manifestData.count)
        for asset in plan.assets {
            if let required = asset.requiresOriginalEntry, skipped.contains(required) { continue }
            guard let size = readableArchiveAssetSize(at: asset.fileURL) else {
                skip(asset)
                continue
            }
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
                if let required = asset.requiresOriginalEntry, skipped.contains(required) { continue }
                // Re-probed just before appending: a file that vanished since
                // the preflight is still a skip, not a failed export.
                guard readableArchiveAssetSize(at: asset.fileURL) != nil else {
                    skip(asset)
                    continue
                }
                try writer.append(name: asset.entryName, contentsOf: asset.fileURL)
            }
            try writer.finish()
            try handle.close()
        } catch {
            try? handle.close()
            try? fm.removeItem(at: destination)
            throw error
        }
        return KudosBackupArchiveExportResult(
            skippedEntries: skipped.sorted(), omittedOriginalTitles: omittedTitles.sorted()
        )
    }

    private nonisolated static func readableArchiveAssetSize(at url: URL) -> UInt64? {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let probe = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? probe.close() }
        return try? probe.seekToEnd()
    }
}
