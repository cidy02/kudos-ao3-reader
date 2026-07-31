import Foundation
import OSLog

/// What a converted import was made from, and by which version of the converter.
///
/// Written beside the preserved original, as `Originals/<work-uuid>.conversion.json`.
/// Deliberately a sidecar file rather than a `SavedWork` field: the record is only
/// ever useful when the original file is present, so the two belong together — and it
/// keeps this out of `Models.swift`/`KudosBackup.swift`, which T-155 owns.
///
/// The point is re-conversion. This session improved the PDF converter four times;
/// each improvement left already-imported works stale, and the only remedy was to
/// delete a work and import the file again. With the original archived and the version
/// recorded, a stale work can be rebuilt in place from the bytes we already hold.
nonisolated struct WorkConversionRecord: Codable, Equatable, Sendable {
    var converterVersion: Int
    /// `ImportedFileFormat.rawValue` the work was converted from.
    var format: String
    var originalFileName: String
    var convertedAt: Date

    init(
        converterVersion: Int = ImportedDocumentConverter.converterVersion,
        format: String,
        originalFileName: String,
        convertedAt: Date = Date()
    ) {
        self.converterVersion = converterVersion
        self.format = format
        self.originalFileName = originalFileName
        self.convertedAt = convertedAt
    }

    var isStale: Bool {
        converterVersion < ImportedDocumentConverter.converterVersion
    }

    // MARK: - Storage

    static func url(for workID: UUID) -> URL {
        Storage.originalsDirectory
            .appendingPathComponent(workID.uuidString + Storage.conversionRecordSuffix)
    }

    static func read(for workID: UUID) -> Self? {
        guard let data = try? Data(contentsOf: url(for: workID)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    /// Best-effort: a conversion that reads perfectly should not fail because its
    /// bookkeeping could not be written. A missing record only costs the ability to
    /// detect staleness later.
    func write(for workID: UUID) {
        do {
            let data = try JSONEncoder().encode(self)
            try data.write(to: Self.url(for: workID), options: .atomic)
        } catch {
            Log.library.error(
                "Couldn't record the conversion version: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    static func delete(for workID: UUID) {
        try? FileManager.default.removeItem(at: url(for: workID))
    }
}
