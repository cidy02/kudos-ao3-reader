import Foundation

/// What Share offers for a saved work. The same order the reader's fan uses:
/// the AO3 page, then an http(s) source page, then the EPUB when it is on disk.
enum WorkShareLink {
    static func url(
        ao3WorkID: Int?,
        sourceURL: String,
        epubFileURL: URL,
        hasReadableEPUB: Bool
    ) -> URL? {
        if let ao3WorkID { return AO3AuthService.workURL(ao3WorkID) }
        if let source = URL(string: sourceURL), source.scheme?.hasPrefix("http") == true {
            return source
        }
        return hasReadableEPUB ? epubFileURL : nil
    }

    @MainActor
    static func url(for work: SavedWork) -> URL? {
        url(
            ao3WorkID: work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL),
            sourceURL: work.sourceURL,
            epubFileURL: work.fileURL,
            hasReadableEPUB: WorkReaderPreparation.hasReadableEPUB(for: work)
        )
    }
}
