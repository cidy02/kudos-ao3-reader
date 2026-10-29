import Foundation

/// Sort By's "Ways to Find" (T-473): named searches that are nothing but AO3's own
/// parameters — a hits range, an updated-date window, completion and a sort column —
/// written into `AO3SearchFilters`, so `AO3Client.workSearchQueryItems` sends them
/// and AO3 applies them to every page, not just the one loaded.
///
/// Whether one is on is read back off the filters rather than stored beside them,
/// so the checkmark can never claim a search the filters are not running.
enum SearchWaysToFind: String, CaseIterable, Identifiable {
    case readerFavourites
    case newAndLoved
    case hiddenGems
    case activeWIPs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readerFavourites: "Reader Favourites"
        case .newAndLoved: "New and Loved"
        case .hiddenGems: "Hidden Gems"
        case .activeWIPs: "Active WIPs"
        }
    }

    /// What the search actually asks AO3 for. Two differ from the spec's copy:
    /// AO3's search has no posted-date range (`revised_at` is the only date it
    /// filters on), and "on schedule first" needs each chapter's date, which a
    /// listing does not carry.
    var subtitle: String {
        switch self {
        case .readerFavourites: "Most kudos on AO3, at least 1,000 hits"
        case .newAndLoved: "Updated in the last 6 months, most kudos first"
        case .hiddenGems: "300 to 5,000 hits, most kudos first"
        case .activeWIPs: "In progress, updated in the last 60 days, latest first"
        }
    }

    /// The clause the Load from AO3 by footer names.
    var queryNote: String {
        switch self {
        case .readerFavourites: "hits over 1,000"
        case .newAndLoved: "updated in the last 6 months"
        case .hiddenGems: "hits 300 to 5,000"
        case .activeWIPs: "in progress, updated in the last 60 days"
        }
    }

    static let activeWindowDays = 60

    func isApplied(in filters: AO3SearchFilters) -> Bool {
        switch self {
        case .readerFavourites:
            filters.sort == .kudos && filters.hitsFrom == "1000" && filters.hitsTo.isEmpty
        case .newAndLoved:
            filters.sort == .kudos && filters.updated == .sixMonths
        case .hiddenGems:
            filters.sort == .kudos && filters.hitsFrom == "300" && filters.hitsTo == "5000"
        case .activeWIPs:
            filters.sort == .dateUpdated && filters.completion == .incomplete && filters.dateFrom != nil
        }
    }

    static func applied(in filters: AO3SearchFilters) -> Self? {
        allCases.first { $0.isApplied(in: filters) }
    }

    /// Turns `preset` on (clearing whichever one was on), or off when it already is.
    /// Off puts back the fields it set, and the sort to `defaultSort` — Best Match
    /// on Search, Date Updated on a tag listing, which has no relevance order.
    static func toggle(
        _ preset: Self,
        in filters: inout AO3SearchFilters,
        defaultSort: AO3SearchFilters.Sort = .relevance,
        now: Date = Date()
    ) {
        let wasOn = preset.isApplied(in: filters)
        for applied in allCases where applied.isApplied(in: filters) {
            applied.clear(from: &filters, defaultSort: defaultSort)
        }
        guard !wasOn else { return }
        switch preset {
        case .readerFavourites:
            filters.hitsFrom = "1000"
            filters.hitsTo = ""
            filters.sort = .kudos
        case .newAndLoved:
            filters.updated = .sixMonths
            filters.sort = .kudos
        case .hiddenGems:
            filters.hitsFrom = "300"
            filters.hitsTo = "5000"
            filters.sort = .kudos
        case .activeWIPs:
            filters.completion = .incomplete
            // An absolute `date_from`: AO3's relative windows stop at a week, a
            // month, six months and a year.
            filters.dateFrom = Calendar.current.date(byAdding: .day, value: -activeWindowDays, to: now)
            filters.sort = .dateUpdated
        }
        filters.sortDirection = filters.sort.naturalDirection
    }

    private func clear(from filters: inout AO3SearchFilters, defaultSort: AO3SearchFilters.Sort) {
        switch self {
        case .readerFavourites, .hiddenGems:
            filters.hitsFrom = ""
            filters.hitsTo = ""
        case .newAndLoved:
            filters.updated = .any
        case .activeWIPs:
            filters.completion = .any
            filters.dateFrom = nil
        }
        filters.sort = defaultSort
        filters.sortDirection = defaultSort.naturalDirection
    }

    // MARK: - Leave out works under N hits

    /// The cut-off's choices, as `hitsFrom` values ("" is off). A value set some
    /// other way — the Hits slider — is offered too, so the menu can show it.
    static func minimumHitsOptions(including current: String) -> [String] {
        let options = ["", "100", "300", "500", "1000", "5000"]
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        guard !options.contains(trimmed) else { return options }
        return (options + [trimmed]).sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
    }

    static func minimumHitsTitle(_ value: String) -> String {
        guard let hits = Int(value.trimmingCharacters(in: .whitespaces)) else { return "Off" }
        return "\(hits.formatted()) hits"
    }
}
