import SwiftUI

/// Session cache of each media category's full fandom list — the same data the
/// category detail page (`FandomListView`) loads from AO3's `/media/<name>/fandoms`
/// index. The Browse cards use it for real fandom/work counts and to map the
/// user's saved/recently-read works to a category.
///
/// A shared (per-launch) instance so the lists survive the Browse view being torn
/// down and rebuilt when the user runs a search and returns to the idle state.
@MainActor @Observable
final class FandomCatalog {
    static let shared = FandomCatalog()

    /// Fetched fandom lists keyed by category id (= name). Absent = not loaded yet.
    private(set) var fandomsByCategory: [String: [AO3Fandom]] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    /// The cached fandom list for a category, or nil while it's still loading.
    func fandoms(for category: AO3MediaCategory) -> [AO3Fandom]? {
        fandomsByCategory[category.id]
    }

    /// Lazily fetches any not-yet-cached categories, **sequentially** (the AO3
    /// client serializes requests to stay polite). Cards fill in as each lands.
    /// Safe to call repeatedly — already-loaded / in-flight categories are skipped.
    func loadMissing(for categories: [AO3MediaCategory]) async {
        for category in categories {
            let key = category.id
            guard fandomsByCategory[key] == nil,
                  !inFlight.contains(key),
                  !category.fandomsURL.isEmpty else { continue }
            inFlight.insert(key)
            if let list = try? await AO3Client.shared.fandoms(atPath: category.fandomsURL) {
                fandomsByCategory[key] = list
            }
            inFlight.remove(key)
            if Task.isCancelled { return }
        }
    }
}
