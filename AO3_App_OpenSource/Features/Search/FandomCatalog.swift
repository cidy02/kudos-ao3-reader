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

    /// Lazily fetches any not-yet-cached categories **concurrently but bounded** via
    /// `AO3RequestCoordinator` (a few at a time — polite, not a flood), so the cards
    /// fill in together instead of one slow row at a time. Each result is applied as
    /// it lands. Safe to call repeatedly — already-loaded / in-flight categories are
    /// skipped — and cancellable (leaving the screen stops the remaining fetches).
    func loadMissing(for categories: [AO3MediaCategory]) async {
        let pending = categories.filter {
            fandomsByCategory[$0.id] == nil && !inFlight.contains($0.id) && !$0.fandomsURL.isEmpty
        }
        guard !pending.isEmpty else { return }
        for category in pending { inFlight.insert(category.id) }

        await withTaskGroup(of: (String, [AO3Fandom]?).self) { group in
            for category in pending {
                let key = category.id
                let path = category.fandomsURL
                group.addTask {
                    let list = try? await AO3RequestCoordinator.shared.withSlot {
                        try await AO3Client.shared.fandoms(atPath: path)
                    }
                    return (key, list)
                }
            }
            for await (key, list) in group {
                if let list { fandomsByCategory[key] = list }
                inFlight.remove(key)
                if Task.isCancelled { group.cancelAll() }
            }
        }
    }
}
