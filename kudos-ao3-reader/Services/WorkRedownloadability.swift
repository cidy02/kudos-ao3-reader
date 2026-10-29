import Foundation

/// Whether Kudos can fetch this work again after the local copy is gone, and
/// why not when it cannot.
///
/// One function so Recently Deleted's orange note, Delete from Library, Delete
/// Permanently, and bulk deletes all name the same reason. Never derived from a
/// network error: `ao3Unavailable` is a durable 404 flag, and a non-AO3 origin
/// is a property of the file we already hold.
nonisolated enum WorkRedownloadability: Equatable, Sendable {
    /// Still on AO3 as far as we know — Kudos can download it again.
    case canRedownload
    /// AO3 answered 404 for this work (`SavedWork.ao3Unavailable`).
    case noLongerOnAO3
    /// A file Kudos did not fetch from AO3. `formatDisplayName` is the import's
    /// format when we know it ("PDF", "HTML"); `origin` is the site
    /// `WorkOrigin` derived from the source URL.
    case imported(formatDisplayName: String?, origin: WorkOrigin)

    var canRedownload: Bool {
        self == .canRedownload
    }

    /// Bold lead-in on the Recently Deleted row, or nil when there is nothing
    /// to warn about.
    var rowTitle: String? {
        switch self {
        case .canRedownload:
            return nil
        case .noLongerOnAO3:
            return "No longer on AO3."
        case .imported(let format, let origin):
            return "Imported \(Self.importedLead(format: format, origin: origin))."
        }
    }

    /// The sentence under the row title.
    var rowBody: String? {
        switch self {
        case .canRedownload:
            return nil
        case .noLongerOnAO3:
            return "The author removed it or made it private, so Kudos can't download it again."
        case .imported:
            return "Kudos can only download from AO3, so this copy is the only one."
        }
    }

    /// "a PDF from FanFiction.net", "FanFiction.net", "a PDF", or "a file".
    var importSourcePhrase: String? {
        switch self {
        case .imported(let format, let origin):
            return Self.importedSourcePhrase(format: format, origin: origin)
        default:
            return nil
        }
    }

    /// Escalates the Library's Confirm-before-deleting setting: a work Kudos
    /// cannot fetch again always asks, even when the setting is off. A work
    /// still on AO3 follows the setting, as today.
    func shouldConfirmDelete(settingOn: Bool) -> Bool {
        settingOn || !canRedownload
    }

    /// The one decision: can this be downloaded again, and why not.
    static func of(
        origin: WorkOrigin,
        ao3Unavailable: Bool,
        importFormatDisplayName: String? = nil
    ) -> WorkRedownloadability {
        if origin.supportsLiveLookup {
            return ao3Unavailable ? .noLongerOnAO3 : .canRedownload
        }
        return .imported(
            formatDisplayName: cleanedFormat(importFormatDisplayName),
            origin: origin
        )
    }

    /// Reads the import's format from disk only for a non-AO3 work: rows and
    /// delete taps call this for every work, and an AO3 work never needs it.
    @MainActor
    static func of(_ work: SavedWork) -> WorkRedownloadability {
        let origin = work.origin
        return of(
            origin: origin,
            ao3Unavailable: work.ao3Unavailable,
            importFormatDisplayName: origin.supportsLiveLookup ? nil : importFormatDisplayName(for: work.id)
        )
    }

    /// The conversion sidecar's format, else a sniff of the preserved original.
    /// Nil when neither is there — the row still names the site.
    static func importFormatDisplayName(for workID: UUID) -> String? {
        let raw: String?
        if let recorded = WorkConversionRecord.read(for: workID)?.format {
            raw = recorded
        } else if let original = Storage.existingOriginalDocumentURL(for: workID) {
            raw = ImportedFileFormat.detect(at: original).rawValue
        } else {
            raw = nil
        }
        guard let raw, let format = ImportedFileFormat(rawValue: raw), format != .unknown else {
            return nil
        }
        return format.displayName
    }

    /// The preserved original, when we still hold it, plus a name the Files
    /// sheet can show. UUID-shaped names (iOS writes those for shared files)
    /// fall back to "Original.<ext>" so the exporter is not a raw id.
    static func originalFile(for workID: UUID) -> (url: URL, suggestedName: String)? {
        guard let url = Storage.existingOriginalDocumentURL(for: workID) else { return nil }
        let recorded = WorkConversionRecord.read(for: workID)?.originalFileName
        let suggested: String
        if let recorded, !recorded.isEmpty, UUID(uuidString: stem(of: recorded)) == nil {
            suggested = (recorded as NSString).lastPathComponent
        } else {
            let ext = url.pathExtension
            suggested = ext.isEmpty ? "Original" : "Original.\(ext)"
        }
        return (url, suggested)
    }

    // MARK: - Phrasing

    private static func cleanedFormat(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func siteName(_ origin: WorkOrigin) -> String? {
        switch origin {
        case .importedFile: nil
        case .unknown: "another site"
        default: origin.displayName
        }
    }

    /// "PDF from FanFiction.net" / "PDF" / "from FanFiction.net" / "file".
    private static func importedLead(format: String?, origin: WorkOrigin) -> String {
        switch (format, siteName(origin)) {
        case (let format?, let site?): "\(format) from \(site)"
        case (let format?, nil): format
        case (nil, let site?): "from \(site)"
        case (nil, nil): "file"
        }
    }

    /// "a PDF from FanFiction.net" / "a PDF" / "FanFiction.net" / "a file".
    private static func importedSourcePhrase(format: String?, origin: WorkOrigin) -> String {
        switch (format, siteName(origin)) {
        case (let format?, let site?): "\(article(format)) from \(site)"
        case (let format?, nil): article(format)
        case (nil, let site?): site
        case (nil, nil): "a file"
        }
    }

    /// "an HTML", "a PDF", "an RTF", "an EPUB": an all-capitals format is said
    /// letter by letter, so its first letter's name decides; a word ("Word
    /// document", "unrecognized file") goes by its first vowel.
    private static func article(_ format: String) -> String {
        guard let first = format.first else { return "a \(format)" }
        let spelledOut = format.allSatisfy { $0.isUppercase || $0.isNumber }
        let an = spelledOut ? "AEFHILMNORSX".contains(first) : "aeiou".contains(first.lowercased())
        return an ? "an \(format)" : "a \(format)"
    }

    private static func stem(of fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }
}
