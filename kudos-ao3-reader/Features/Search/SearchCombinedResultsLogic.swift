import Foundation

/// Pure logic for Search results when on-device matches are combined with AO3 results (Board 11).
enum SearchCombinedResultsLogic {
    /// Maximum number of library work rows to show before offering "See all N".
    static let libraryRowCap = 5

    /// Whether any on-device section (library works, chips, or AO3 fandoms) has items to show.
    static func hasLibrarySections(
        worksCount: Int,
        chipsCount: Int,
        ao3FandomsCount: Int
    ) -> Bool {
        worksCount > 0 || chipsCount > 0 || ao3FandomsCount > 0
    }

    /// Whether to show the "In your library" section.
    static func showInLibrarySection(worksCount: Int) -> Bool {
        worksCount > 0
    }

    /// Number of works to display given whether the section is expanded.
    static func displayedWorksCount(total: Int, isExpanded: Bool) -> Int {
        isExpanded ? total : min(total, libraryRowCap)
    }

    /// Whether the "See all N" row should be displayed.
    static func showsSeeAllRow(total: Int, isExpanded: Bool) -> Bool {
        total > libraryRowCap && !isExpanded
    }

    /// Label for the "See all N" row.
    static func seeAllRowTitle(total: Int) -> String {
        "See all \(total)"
    }

    /// Whether to show the "Your tags, collections, fandoms" chips section.
    static func showChipsSection(chipsCount: Int) -> Bool {
        chipsCount > 0
    }

    /// Header title for the tags/collections/fandoms section.
    static let chipsSectionTitle = "Your tags, collections, fandoms"

    /// Whether to show the "Fandoms on AO3" section.
    static func showAO3FandomsSection(ao3FandomsCount: Int) -> Bool {
        ao3FandomsCount > 0
    }

    /// Header title for the AO3 fandoms section.
    static let ao3FandomsSectionTitle = "Fandoms on AO3"

    /// Header title for the AO3 results section.
    /// When library sections are shown above, reads "On AO3"; otherwise returns the standard title.
    static func ao3HeaderTitle(
        hasLibrarySections: Bool,
        subject: String?,
        query: String?
    ) -> String {
        if hasLibrarySections {
            return "On AO3"
        }
        return AO3ResultListPaging.title(subject: subject, query: query)
    }

    /// Subtitle or count label beside the AO3 header (e.g. "1,284 works").
    static func ao3HeaderCount(total: Int) -> String {
        "\(total.formatted()) \(total == 1 ? "work" : "works")"
    }
}
