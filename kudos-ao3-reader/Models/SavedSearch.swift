import Foundation
import SwiftData

/// A named, saved AO3 search: the full `AO3SearchFilters` (query + every facet), so
/// re-running reproduces the exact search. Listed on the Search tab's idle screen;
/// tapping one re-runs it.
///
/// **Not persisted through `AO3SearchFilters`'s `Codable` conformance**, despite
/// that conformance being what SwiftData *requires* of a composite attribute.
/// SwiftData reflects over stored properties and writes one SQLite column each —
/// `Language` has a custom `encode(to:)` emitting a single bare string, and a real
/// store still carries two columns for it, one per stored property. So adding a
/// field here is a schema change, not a serialization change: additive optionals
/// (`dateFrom`/`dateTo` → nullable `TIMESTAMP`) are a lightweight migration, while
/// *restructuring* a property is not. `aSavedSearchSurvivesARealSwiftDataRoundTrip`
/// covers the mechanism actually used; the `Codable` tests next to it cover a path
/// with no production consumer.
@Model final class SavedSearch {
    var id: UUID = UUID()
    var name: String = ""
    var dateAdded: Date = Date()
    var filters: AO3SearchFilters = AO3SearchFilters()
    var lastOpenedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \QueueSavedSearchLink.search)
    var queueLinks: [QueueSavedSearchLink] = []

    init(name: String, filters: AO3SearchFilters) {
        id = UUID()
        self.name = name
        self.filters = filters
        dateAdded = Date()
    }
}

/// One queue source (saved search, author, series, tag, or an unknown kind kept
/// for round-trip compatibility). The row owns its count and cooldown; deleting
/// either a saved search or a queue removes the join without deleting the other.
///
/// All non-search fields are optional plain primitives for lightweight SwiftData
/// migration (no composite attributes). Existing rows have `sourceKindRaw == nil`,
/// which resolves to `.savedSearch`.
@Model final class QueueSavedSearchLink {
    var id: UUID = UUID()
    var queue: ReadingQueue?
    var search: SavedSearch?
    var lastCheckedAt: Date?
    var newResultCount: Int?
    /// Raw source kind (`nil` or `"savedSearch"`, `"author"`, `"series"`, `"tag"`,
    /// or an unknown string from a newer build kept verbatim).
    var sourceKindRaw: String?
    /// Normalized per-kind identity key for deduplication and backup restore.
    var targetKey: String?
    var displayName: String?
    var subtitle: String?
    var authorUsername: String?
    var authorPseud: String?
    var ao3SeriesID: Int?
    var tagName: String?
    var tagCategoryRaw: String?
    var urlString: String?
    /// Last-opened stamp for non-search sources (saved searches keep `SavedSearch.lastOpenedAt`).
    var lastOpenedAt: Date?
    var dateAdded: Date?
    /// Passthrough JSON object of any extra keys from a newer build's backup entry.
    var unknownPayloadJSON: String?

    init(queue: ReadingQueue, search: SavedSearch) {
        self.queue = queue
        self.search = search
    }

    init(
        id: UUID = UUID(),
        queue: ReadingQueue,
        kindRaw: String,
        targetKey: String,
        displayName: String? = nil,
        subtitle: String? = nil,
        authorUsername: String? = nil,
        authorPseud: String? = nil,
        ao3SeriesID: Int? = nil,
        tagName: String? = nil,
        tagCategoryRaw: String? = nil,
        urlString: String? = nil,
        lastOpenedAt: Date? = nil,
        lastCheckedAt: Date? = nil,
        newResultCount: Int? = nil,
        dateAdded: Date? = nil,
        unknownPayloadJSON: String? = nil
    ) {
        self.id = id
        self.queue = queue
        self.search = nil
        self.sourceKindRaw = kindRaw
        self.targetKey = targetKey
        self.displayName = displayName
        self.subtitle = subtitle
        self.authorUsername = authorUsername
        self.authorPseud = authorPseud
        self.ao3SeriesID = ao3SeriesID
        self.tagName = tagName
        self.tagCategoryRaw = tagCategoryRaw
        self.urlString = urlString
        self.lastOpenedAt = lastOpenedAt
        self.lastCheckedAt = lastCheckedAt
        self.newResultCount = newResultCount
        self.dateAdded = dateAdded
        self.unknownPayloadJSON = unknownPayloadJSON
    }
}
