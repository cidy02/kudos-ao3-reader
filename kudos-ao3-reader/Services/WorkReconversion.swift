import Foundation
import OSLog
import SwiftData

/// Rebuilds a converted work from the original file it was imported from.
///
/// Exists because the converter keeps improving. Every fix in this series — paragraphs
/// rebuilt from geometry, a title no longer duplicated, front matter no longer dropped
/// — left previously-imported works stale, and before this the only remedy was to
/// delete the work and import the file again, losing its reading progress, tags,
/// collections and queue memberships along with it.
///
/// The archived original plus a recorded converter version make that unnecessary: the
/// EPUB is regenerated in place and everything *about* the work is untouched.
@MainActor
enum WorkReconversion {
    /// A work that can be rebuilt, and whether doing so would change anything.
    struct Candidate {
        let work: SavedWork
        let record: WorkConversionRecord
        let originalURL: URL

        var isStale: Bool { record.isStale }
    }

    /// Nil when the work has no archived original — the file is what makes a rebuild
    /// possible, so without it there is nothing honest to offer.
    ///
    /// A work whose original exists but has **no record** is treated as version 0, i.e.
    /// stale. That is not an edge case: every work imported before conversion
    /// versioning existed is in exactly that state, and those are the works most in need
    /// of a rebuild. Requiring a record first made the feature invisible to all of them.
    static func candidate(for work: SavedWork) -> Candidate? {
        guard let original = Storage.existingOriginalDocumentURL(for: work.id),
              FileManager.default.fileExists(atPath: original.path)
        else { return nil }
        let record = WorkConversionRecord.read(for: work.id)
            ?? WorkConversionRecord(
                converterVersion: 0,
                format: ImportedFileFormat.detect(at: original).rawValue,
                originalFileName: original.lastPathComponent,
                convertedAt: work.dateAdded
            )
        return Candidate(work: work, record: record, originalURL: original)
    }

    /// Every work in the library whose EPUB an improved converter would now produce
    /// differently.
    static func staleWorks(in context: ModelContext) -> [Candidate] {
        let works = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
        return works.compactMap(candidate).filter(\.isStale)
    }

    enum ReconversionError: LocalizedError {
        case noOriginalAvailable

        var errorDescription: String? {
            switch self {
            case .noOriginalAvailable:
                "The original file this work was converted from is no longer stored, so it "
                    + "can't be rebuilt. Import the file again instead."
            }
        }
    }

    /// Re-runs conversion and swaps in the new EPUB.
    ///
    /// Reading progress is deliberately **kept**. A Readium locator can drift when the
    /// underlying document changes — that is the same risk the reader already carries
    /// when an author edits a posted chapter — and keeping an approximate position is
    /// plainly better than resetting a long work to page one. Chapter *count* changes
    /// (a recovered Preface, say) shift positions by a chapter at most.
    @discardableResult
    static func reconvert(_ work: SavedWork, in context: ModelContext) async throws -> WorkConversionRecord {
        guard let candidate = candidate(for: work) else { throw ReconversionError.noOriginalAvailable }
        let url = candidate.originalURL

        // Conversion unzips and re-serializes a whole work, so it stays off the main
        // actor exactly as it does during import.
        let outcome = try await Task.detached(priority: .userInitiated) {
            try ImportedDocumentConverter.convert(fileAt: url)
        }.value

        let epub: Data
        switch outcome {
        case .alreadyEPUB:
            // The original was an EPUB, so there is nothing for a new converter to do
            // differently. Record the version and stop rather than rewriting the file.
            let updated = WorkConversionRecord(
                format: candidate.record.format,
                originalFileName: candidate.record.originalFileName
            )
            updated.write(for: work.id)
            return updated
        case let .converted(data, _):
            epub = data
        }

        let staged = Storage.tempDownloadURL(suggestedName: "\(UUID().uuidString).epub")
        try epub.write(to: staged, options: .atomic)
        defer { try? FileManager.default.removeItem(at: staged) }

        // Same atomic replace the importer uses, so a failure here leaves the previous
        // EPUB intact rather than destroying the only readable copy.
        try ReadingQueueService.replaceEPUB(for: work, with: staged)
        work.hasEPUB = true
        work.markModified()
        WorkSearchIndex.reindex(work)
        context.saveBestEffort(reason: "Saving the re-converted work failed")

        // The rebuilt EPUB usually knows *more* than the old one — a recovered source
        // URL, a rating, a word count, real fandoms — so its metadata is applied too.
        // Without this a rebuild swapped the text and left every field as it was, and
        // the work still claimed its origin was unknown.
        await applyStoredEPUBMetadata(to: work, in: context)

        let updated = WorkConversionRecord(
            format: candidate.record.format,
            originalFileName: candidate.record.originalFileName
        )
        updated.write(for: work.id)
        Log.library.info(
            "Rebuilt “\(work.title)” with converter v\(ImportedDocumentConverter.converterVersion)"
        )
        return updated
    }
}
