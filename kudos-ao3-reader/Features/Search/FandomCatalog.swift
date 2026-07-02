import SwiftUI

/// Local-first cache of each media category's full fandom list — the same data the
/// category detail page (`FandomListView`) loads from AO3's `/media/<name>/fandoms`
/// index. The Browse cards use it for real fandom/work counts and to map the user's
/// saved/recently-read works to a category.
///
/// Backed by an on-disk cache (`FandomCatalogCache`) so the counts show **instantly**
/// on relaunch instead of re-scraping ~thousands of fandoms per category every time.
/// Stale-while-revalidate: cached lists are shown immediately, then any
/// missing/stale category is refreshed in the background, bounded + polite via
/// `AO3RequestCoordinator`. A shared instance so the lists survive the Browse view
/// being rebuilt when the user runs a search and returns to the idle state.
@MainActor @Observable
final class FandomCatalog {
    static let shared = FandomCatalog()

    /// Fandom lists keyed by category id (= name), shown by the cards. May hold a
    /// stale cached list while a fresh copy is being fetched.
    private(set) var fandomsByCategory: [String: [AO3Fandom]] = [:]

    private let cache: FandomCatalogCache
    /// Cache entries (with fetch dates) backing `fandomsByCategory`; drives staleness.
    private var entries: [String: FandomCatalogCache.Entry] = [:]
    private var inFlight: Set<String> = []
    private var didLoadCache = false

    private init() {
        self.cache = FandomCatalogCache()
    }

    /// The cached fandom list for a category, or nil while it's still loading.
    func fandoms(for category: AO3MediaCategory) -> [AO3Fandom]? {
        fandomsByCategory[category.id]
    }

    /// Clears the cached fandom catalog (disk + memory) — the Privacy & Local Data
    /// "Clear Browse cache" action. It rebuilds the next time Browse is opened.
    func clearCache() {
        cache.clear()
        fandomsByCategory = [:]
        entries = [:]
        didLoadCache = false
    }

    /// Loads the on-disk fandom cache into memory **without any network**, so other
    /// surfaces (e.g. Global Search) can match the cached AO3 catalog instantly. The
    /// cached counts are kept fresh by the browser's stale-while-revalidate refresh;
    /// running a real search corrects any drift.
    func warmCache() async {
        await loadCacheIfNeeded()
    }

    /// Cached AO3 fandoms (across all categories) whose name contains `query` —
    /// matched on-device, so typing feels live without scraping AO3 per keystroke.
    /// Prefix matches first, then by work count. Deduped by name.
    func cachedFandoms(matching query: String, limit: Int = 12) -> [AO3Fandom] {
        let normalizedQuery = query.lowercased()
        guard !normalizedQuery.isEmpty else { return [] }
        var seen = Set<String>()
        var matches: [AO3Fandom] = []
        for list in fandomsByCategory.values {
            for fandom in list where fandom.name.lowercased().contains(normalizedQuery) {
                if seen.insert(fandom.name.lowercased()).inserted { matches.append(fandom) }
            }
        }
        return matches.sorted { lhs, rhs in
            let leftHasPrefix = lhs.name.lowercased().hasPrefix(normalizedQuery)
            let rightHasPrefix = rhs.name.lowercased().hasPrefix(normalizedQuery)
            if leftHasPrefix != rightHasPrefix { return leftHasPrefix }
            return (lhs.workCount ?? 0) > (rhs.workCount ?? 0)
        }
        .prefix(limit)
        .map { $0 }
    }

    /// Shows any disk-cached lists immediately, then fetches the categories that are
    /// missing or stale — **concurrently but bounded** (a few at a time, polite) so
    /// the cards fill in together rather than one slow row at a time. Fresh results
    /// update the cards and the on-disk cache. Safe to call repeatedly (in-flight /
    /// fresh categories are skipped) and cancellable (leaving the screen stops the
    /// remaining fetches).
    func loadMissing(for categories: [AO3MediaCategory]) async {
        await loadCacheIfNeeded()

        let pending = categories.filter {
            FandomCatalogCache.isStale(entries[$0.id])
                && !inFlight.contains($0.id)
                && !$0.fandomsURL.isEmpty
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
            var changed = false
            for await (key, list) in group {
                if let list {
                    fandomsByCategory[key] = list
                    entries[key] = FandomCatalogCache.Entry(fandoms: list, fetchedAt: Date())
                    changed = true
                }
                inFlight.remove(key)
                if Task.isCancelled { group.cancelAll() }
            }
            if changed { persist() }
        }
    }

    /// User-triggered refresh for the categories currently on screen. Unlike
    /// `loadMissing`, this bypasses staleness so pull-to-refresh really updates the
    /// visible counts, but failures keep the previous cached lists in place.
    func refresh(_ categories: [AO3MediaCategory]) async {
        await loadCacheIfNeeded()

        let pending = categories.filter {
            !inFlight.contains($0.id) && !$0.fandomsURL.isEmpty
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
            var changed = false
            for await (key, list) in group {
                if let list {
                    fandomsByCategory[key] = list
                    entries[key] = FandomCatalogCache.Entry(fandoms: list, fetchedAt: Date())
                    changed = true
                }
                inFlight.remove(key)
                if Task.isCancelled { group.cancelAll() }
            }
            if changed { persist() }
        }
    }

    /// Loads the disk cache once (off the main actor) and shows cached lists so the
    /// cards aren't blank on relaunch.
    private func loadCacheIfNeeded() async {
        guard !didLoadCache else { return }
        didLoadCache = true
        let cache = self.cache
        let loaded = await Task.detached(priority: .utility) { cache.load() }.value
        for (key, entry) in loaded {
            entries[key] = entry
            if fandomsByCategory[key] == nil { fandomsByCategory[key] = entry.fandoms }
        }
    }

    /// Writes the cache off the main actor (the payload can be a few MB).
    private func persist() {
        let snapshot = entries
        let cache = self.cache
        Task.detached(priority: .utility) { cache.save(snapshot) }
    }
}
