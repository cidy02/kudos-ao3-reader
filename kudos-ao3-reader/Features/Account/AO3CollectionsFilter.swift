import Foundation

/// Artboard **1bm** — how the collections list is sorted and narrowed.
///
/// The spec's own note explains why this is client-side: *"AO3 sorts collections by
/// title and date only. Recently updated and Works in collection are computed here,
/// so they need the whole list fetched before the first sort."* Every rule below
/// therefore runs over the in-memory list, and none of them costs a request.
nonisolated struct AO3CollectionsFilter: Equatable, Sendable {
    var sort: Sort = .asReturned
    var order: Order = .descending
    var showsOpenOnly = false
    var showsUnrevealedOnly = false
    var showsModeratedOnly = false
    var showsWithWorksOnly = false

    nonisolated enum Sort: String, CaseIterable, Hashable, Sendable {
        /// AO3's own ordering, left alone. The honest default: it is what the
        /// server chose, and re-sorting by something the reader did not ask for is
        /// how a list stops matching the website.
        case asReturned
        case title
        case works
        case bookmarks
        /// Needs `updatedAtText` parsed — see `updatedDate(from:)`, which is a
        /// format assumption rather than a guarantee.
        case recentlyUpdated

        var title: String {
            switch self {
            case .asReturned: "AO3 order"
            case .title: "Title"
            case .works: "Works"
            case .bookmarks: "Bookmarks"
            case .recentlyUpdated: "Recently updated"
            }
        }
    }

    nonisolated enum Order: String, CaseIterable, Hashable, Sendable {
        case ascending
        case descending

        /// Spec 1bm labels these Oldest / Newest, which only reads correctly for a
        /// date sort. The label follows the sort so Title does not offer to show
        /// A–Z as "Newest".
        func title(for sort: Sort) -> String {
            switch sort {
            case .recentlyUpdated:
                return self == .ascending ? "Oldest" : "Newest"
            case .title:
                return self == .ascending ? "A–Z" : "Z–A"
            case .works, .bookmarks:
                return self == .ascending ? "Fewest" : "Most"
            case .asReturned:
                return self == .ascending ? "Ascending" : "Descending"
            }
        }
    }

    var hasActiveFilters: Bool {
        showsOpenOnly || showsUnrevealedOnly || showsModeratedOnly || showsWithWorksOnly
            || sort != .asReturned
    }

    /// Spec 1bm's chips, for the rail above the list. Only non-default settings
    /// appear — the same rule `AO3SearchFilters.summaryLabels` follows.
    var summaryLabels: [String] {
        var labels: [String] = []
        if sort != .asReturned {
            labels.append("\(sort.title) · \(order.title(for: sort))")
        }
        if showsOpenOnly { labels.append("Open to new works") }
        if showsModeratedOnly { labels.append("Moderated") }
        if showsUnrevealedOnly { labels.append("Unrevealed") }
        if showsWithWorksOnly { labels.append("Has works") }
        return labels
    }

    func apply(to collections: [AO3Collection]) -> [AO3Collection] {
        let narrowed = collections.filter { collection in
            if showsOpenOnly, collection.isClosed { return false }
            if showsUnrevealedOnly, !collection.isUnrevealed { return false }
            if showsModeratedOnly, !collection.isModerated { return false }
            if showsWithWorksOnly, (collection.worksCount ?? 0) == 0 { return false }
            return true
        }
        return sorted(narrowed)
    }

    /// Sorts, keeping AO3's order as the tiebreak.
    ///
    /// **Rows the sort cannot rank keep their incoming position rather than being
    /// dropped or bunched at random.** A collection with no works count is not "zero
    /// works", and one whose date will not parse is not "oldest" — both are
    /// unknown, and the least misleading thing to do with unknown is to leave it
    /// where AO3 put it.
    private func sorted(_ collections: [AO3Collection]) -> [AO3Collection] {
        guard sort != .asReturned else { return collections }
        let indexed = collections.enumerated().map { (offset: $0.offset, collection: $0.element) }
        let ranked = indexed.sorted { lhs, rhs in
            // Title is a string sort, so it cannot share the numeric path — an
            // earlier draft folded it in by returning nil and silently turned Title
            // into a no-op.
            if sort == .title {
                let comparison = lhs.collection.title
                    .localizedCaseInsensitiveCompare(rhs.collection.title)
                if comparison != .orderedSame {
                    return order == .ascending
                        ? comparison == .orderedAscending
                        : comparison == .orderedDescending
                }
                return lhs.offset < rhs.offset
            }

            let left = rank(lhs.collection)
            let right = rank(rhs.collection)
            switch (left, right) {
            case let (.some(a), .some(b)) where a != b:
                return order == .ascending ? a < b : a > b
            case (.some, .none):
                return true   // ranked rows above unrankable ones, in both orders
            case (.none, .some):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }
        return ranked.map(\.collection)
    }

    /// A numeric key, or `nil` when this collection cannot be ranked by the current
    /// sort. `.title` never reaches here — see `sorted`.
    private func rank(_ collection: AO3Collection) -> Double? {
        switch sort {
        case .asReturned, .title:
            return nil
        case .works:
            return collection.worksCount.map(Double.init)
        case .bookmarks:
            return collection.bookmarksCount.map(Double.init)
        case .recentlyUpdated:
            return Self.updatedDate(from: collection.updatedAtText)?.timeIntervalSince1970
        }
    }

    /// AO3's `p.datetime` text, parsed if it is in a shape we recognise.
    ///
    /// **This is a format assumption, not a guarantee.** The field is scraped text
    /// and the app has never seen it parsed anywhere else, so a shape that does not
    /// match returns `nil` and its row keeps AO3's own position rather than being
    /// sorted somewhere wrong. If Recently updated ever looks unsorted, this is the
    /// function to check first.
    static func updatedDate(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for formatter in Self.dateFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    /// Fixed `en_US_POSIX` and UTC: these parse *AO3's* output, which is not
    /// localised to the reader, so a device in another locale must not reinterpret
    /// "03/04" by its own conventions.
    private static let dateFormatters: [DateFormatter] = {
        ["d MMM yyyy", "dd MMM yyyy", "yyyy-MM-dd", "d MMMM yyyy"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()
}
