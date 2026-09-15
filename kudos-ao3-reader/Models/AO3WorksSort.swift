import Foundation

/// Artboard **1v**'s sort and filter, as AO3's own query parameters.
///
/// Every value here is taken from otwarchive's `WorkSearchForm`, not guessed:
/// `SORT_OPTIONS`, the `faceted`/`collected` rule that trims the list, and
/// `default_sort_direction`. A sort column the Archive does not recognise is
/// silently ignored by the server, which would look like a broken control
/// rather than a bad request — so these are worth pinning to the source.
nonisolated enum AO3WorksSortColumn: String, CaseIterable, Identifiable, Sendable {
    case creator = "authors_to_sort_on"
    case title = "title_to_sort_on"
    case datePosted = "created_at"
    case dateUpdated = "revised_at"
    case wordCount = "word_count"
    case hits
    case kudos = "kudos_count"
    case comments = "comments_count"
    case bookmarks = "bookmarks_count"

    var id: String { rawValue }

    /// AO3's own label for the column, so the sheet reads the way the site does.
    var title: String {
        switch self {
        case .creator: "Creator"
        case .title: "Title"
        case .datePosted: "Date Posted"
        case .dateUpdated: "Date Updated"
        case .wordCount: "Word Count"
        case .hits: "Hits"
        case .kudos: "Kudos"
        case .comments: "Comments"
        case .bookmarks: "Bookmarks"
        }
    }

    /// `WorkSearchForm#default_sort_direction`: the two alphabetical columns
    /// ascend, everything else descends. Getting this backwards would put the
    /// least-read work first on a screen whose whole point is your best ones.
    var defaultDirection: AO3WorksSortDirection {
        switch self {
        case .creator, .title: .ascending
        default: .descending
        }
    }
}

nonisolated enum AO3WorksSortDirection: String, CaseIterable, Identifiable, Sendable {
    case ascending = "asc"
    case descending = "desc"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending: "Ascending"
        case .descending: "Descending"
        }
    }
}

/// 1v's completion chips.
///
/// Sent to AO3 rather than applied to the parsed blurbs, which is a deliberate
/// divergence from 1v's BUILD note ("completion filter is client-side"). AO3
/// accepts `work_search[complete]` on this index, and a client-side filter over
/// a paged list can only narrow the page already loaded — it would quietly omit
/// every matching work on pages 2..n and report a count that means nothing.
nonisolated enum AO3WorksCompletion: String, CaseIterable, Identifiable, Sendable {
    case any = ""
    case complete = "T"
    case incomplete = "F"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "Any"
        case .complete: "Complete"
        case .incomplete: "In progress"
        }
    }
}

/// The whole of 1v's sheet as one value, so the screen has a single thing to
/// bind, compare against the default, and count for the funnel badge.
nonisolated struct AO3WorksSort: Equatable, Sendable {
    var column: AO3WorksSortColumn
    var direction: AO3WorksSortDirection
    var completion: AO3WorksCompletion

    /// `default_sort_column` is `revised_at` for a faceted or collected index,
    /// which a user's works page is. (`_score` / "Best Match" is the default
    /// only for a real search, and is not offered here at all — see `allColumns`.)
    static let `default` = AO3WorksSort(
        column: .dateUpdated,
        direction: .descending,
        completion: .any
    )

    /// Nine, not ten. `WorkSearchForm#sort_options` returns `SORT_OPTIONS[1..-1]`
    /// when the index is faceted or collected, dropping "Best Match" — there is
    /// no relevance to score when nothing was searched for. 1v's own note says
    /// "the nine sort fields", which is the same nine.
    static let allColumns = AO3WorksSortColumn.allCases

    var isDefault: Bool { self == .default }

    /// What the funnel badge counts: how many choices differ from the default.
    var activeCount: Int {
        var count = 0
        if column != Self.default.column { count += 1 }
        if direction != defaultDirectionForColumn { count += 1 }
        if completion != .any { count += 1 }
        return count
    }

    /// Picking a column adopts that column's own default direction, the way
    /// AO3 does when no direction is sent — otherwise switching to Title from
    /// Kudos would leave you on descending and read Z to A.
    var defaultDirectionForColumn: AO3WorksSortDirection {
        column.defaultDirection
    }

    mutating func select(_ newColumn: AO3WorksSortColumn) {
        guard newColumn != column else { return }
        column = newColumn
        direction = newColumn.defaultDirection
    }

    /// Only what differs from AO3's own defaults is sent. An unchanged sheet
    /// produces no query items at all, so the URL stays the plain page URL and
    /// the existing page cache keeps hitting.
    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if column != Self.default.column {
            items.append(URLQueryItem(name: "work_search[sort_column]", value: column.rawValue))
        }
        if direction != defaultDirectionForColumn {
            items.append(URLQueryItem(name: "work_search[sort_direction]", value: direction.rawValue))
        }
        if completion != .any {
            items.append(URLQueryItem(name: "work_search[complete]", value: completion.rawValue))
        }
        return items
    }
}
