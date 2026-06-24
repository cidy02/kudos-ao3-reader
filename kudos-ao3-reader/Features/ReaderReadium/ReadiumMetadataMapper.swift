import Foundation
#if os(iOS)
import ReadiumShared
#endif

/// The subset of EPUB metadata the library importer needs, decoupled from any
/// particular parser. This mirrors the fields the old `EPUBMetadata` exposed so
/// the importer's mapping into `SavedWork` stays unchanged.
///
/// Two producers feed it: `ReadiumMetadataMapper.map(_:)` (the new Readium path,
/// iOS) and the legacy bridge below (the old `EPUBMetadata`, used on macOS until
/// Readium gains macOS support). When `EPUB.swift` is eventually removed, only
/// the legacy bridge goes with it.
struct ImportedWorkMetadata {
    var title: String
    var author: String
    var summary: String
    /// Raw `dc:language` / BCP 47 code (e.g. "en"); the importer humanizes it.
    var language: String
    var subjects: [String]
    /// AO3 rating recovered from the subject list (e.g. "Mature"); "" if absent.
    var rating: String
    var seriesTitle: String
    var seriesIndex: Int?
}

extension ImportedWorkMetadata {
    /// The AO3 ratings, in the exact spelling AO3 writes into EPUB subjects.
    /// Kept here (rather than reused from `EPUBMetadata`) so the Readium path is
    /// self-contained and survives the removal of the old parser.
    private static let ao3Ratings: Set<String> = [
        "General Audiences", "Teen And Up Audiences", "Mature", "Explicit", "Not Rated",
    ]

    /// Picks the AO3 rating out of a subject list, if present.
    static func rating(in subjects: [String]) -> String {
        subjects.first { ao3Ratings.contains($0) } ?? ""
    }
}

#if os(iOS)
/// Maps a Readium `Publication`'s metadata onto `ImportedWorkMetadata`.
///
/// This is the Readium replacement for reading `EPUBMetadata` out of the custom
/// `OPFParser`. Readium has already parsed the OPF Dublin Core metadata and
/// calibre extensions (it reads `calibre:series`/`series_index` into
/// `belongsToSeries`), so we only need to translate field shapes.
enum ReadiumMetadataMapper {
    static func map(_ publication: Publication) -> ImportedWorkMetadata {
        let metadata = publication.metadata
        // Readium models subjects/authors/series as rich value types; flatten
        // them to the plain strings the library expects.
        let subjects = metadata.subjects.map(\.name)
        let series = metadata.belongsToSeries.first

        return ImportedWorkMetadata(
            title: metadata.title ?? "",
            // AO3 EPUBs have a single creator, but join defensively for co-authors.
            author: metadata.authors.map(\.name).joined(separator: ", "),
            summary: metadata.description ?? "",
            language: metadata.languages.first ?? "",
            subjects: subjects,
            rating: ImportedWorkMetadata.rating(in: subjects),
            seriesTitle: series?.name ?? "",
            // Readium stores the series position as a Double; AO3 uses integers.
            seriesIndex: series?.position.map { Int($0) }
        )
    }
}
#endif

// MARK: - Legacy bridge (macOS / fallback)

extension ImportedWorkMetadata {
    /// Adapts the old custom-parser `EPUBMetadata` to the shared shape. Used on
    /// macOS (where Readium can't link yet). Temporary — remove with `EPUB.swift`.
    init(legacy meta: EPUBMetadata) {
        self.init(
            title: meta.title,
            author: meta.author,
            summary: meta.summary,
            language: meta.language,
            subjects: meta.subjects,
            rating: meta.rating,
            seriesTitle: meta.seriesTitle,
            seriesIndex: meta.seriesIndex
        )
    }
}
