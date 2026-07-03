import Foundation
import SwiftData

/// A named, saved AO3 search: the full `AO3SearchFilters` (query + every facet), so
/// re-running reproduces the exact search. Listed on the Search tab's idle screen;
/// tapping one re-runs it. Persisted via `AO3SearchFilters`'s `Codable` conformance.
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
