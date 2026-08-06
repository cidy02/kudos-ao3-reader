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

    init(name: String, filters: AO3SearchFilters) {
        id = UUID()
        self.name = name
        self.filters = filters
        dateAdded = Date()
    }
}
