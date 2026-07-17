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

    /// Monotonic stamp bumped on every catalog content change (cache load, a
    /// category fetch landing, clear). Global Search keys its debounced match
    /// snapshot off this, so results computed before the disk cache finished
    /// loading refresh once it lands instead of staying empty until the next
    /// keystroke.
    private(set) var revision = 0

    private let cache: FandomCatalogCache
    /// Cache entries (with fetch dates) backing `fandomsByCategory`; drives staleness.
    private var entries: [String: FandomCatalogCache.Entry] = [:]
    private var inFlight: Set<String> = []
    private var didLoadCache = false

    /// Flattened, deduplicated index over every cached fandom — normalized names
    /// precomputed and entries pre-sorted by work count — so a query is one
    /// allocation-free scan. Rebuilt lazily on first use after a catalog change:
    /// the catalog holds tens of thousands of names, and re-normalizing (or worse,
    /// re-sorting) them per keystroke is exactly the main-thread stall this
    /// index exists to prevent.
    private var searchEntries: [SearchEntry] = []
    private var searchIndexStale = true

    /// One entry of the flattened catalog search index: a fandom plus its
    /// normalized (`WorkSearchIndex.normalize`) name. Internal so tests can build
    /// and query the pure index helpers directly.
    struct SearchEntry: Sendable {
        let normalizedName: String
        let fandom: AO3Fandom
    }

    private init() {
        cache = FandomCatalogCache()
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
        catalogDidChange()
    }

    /// Records a catalog content change: the flattened search index is stale and
    /// any observer keying off `revision` (Global Search) recomputes.
    private func catalogDidChange() {
        searchIndexStale = true
        revision += 1
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
    /// Prefix matches first, then by work count; deduped by normalized name.
    /// Matching is case- and diacritic-insensitive (`WorkSearchIndex.normalize`,
    /// the same folding Library/Search matching uses), so "pokemon" finds
    /// "Pokémon". Cost per call is one scan of the precomputed index — no string
    /// normalization or sorting happens per query.
    func cachedFandoms(matching query: String, limit: Int = 12) -> [AO3Fandom] {
        let normalizedQuery = WorkSearchIndex.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }
        if searchIndexStale {
            searchIndexStale = false
            searchEntries = Self.searchIndex(over: fandomsByCategory.values)
        }
        return Self.rankedMatches(in: searchEntries, normalizedQuery: normalizedQuery, limit: limit)
    }

    /// Builds the flattened index: names normalized once, deduplicated across
    /// categories (a fandom can be listed under several media types — the copy
    /// with the highest work count wins, deterministically, where the old
    /// per-query dedup kept whichever category happened to iterate first), and
    /// sorted by work count descending (name ascending as a stable tiebreaker)
    /// so `rankedMatches` never sorts per query.
    nonisolated static func searchIndex(over lists: some Collection<[AO3Fandom]>) -> [SearchEntry] {
        var bestByName: [String: AO3Fandom] = [:]
        bestByName.reserveCapacity(lists.reduce(0) { $0 + $1.count })
        for list in lists {
            for fandom in list {
                let key = WorkSearchIndex.normalize(fandom.name)
                if let existing = bestByName[key], (existing.workCount ?? 0) >= (fandom.workCount ?? 0) {
                    continue
                }
                bestByName[key] = fandom
            }
        }
        return bestByName
            .map { SearchEntry(normalizedName: $0.key, fandom: $0.value) }
            .sorted { lhs, rhs in
                let left = lhs.fandom.workCount ?? 0
                let right = rhs.fandom.workCount ?? 0
                if left != right { return left > right }
                return lhs.normalizedName < rhs.normalizedName
            }
    }

    /// Scans the pre-ranked index once: prefix matches outrank substring matches,
    /// and within each bucket the index's own work-count order stands. The scan
    /// stops early once `limit` prefix matches exist — nothing later can outrank
    /// them — and the substring bucket never grows past `limit` either, so a
    /// one-letter query over tens of thousands of entries stays allocation-light.
    nonisolated static func rankedMatches(
        in entries: [SearchEntry],
        normalizedQuery: String,
        limit: Int
    ) -> [AO3Fandom] {
        var prefixMatches: [AO3Fandom] = []
        var substringMatches: [AO3Fandom] = []
        for entry in entries {
            if entry.normalizedName.hasPrefix(normalizedQuery) {
                prefixMatches.append(entry.fandom)
                if prefixMatches.count >= limit { break }
            } else if substringMatches.count < limit, entry.normalizedName.contains(normalizedQuery) {
                substringMatches.append(entry.fandom)
            }
        }
        return Array((prefixMatches + substringMatches).prefix(limit))
    }

    /// Shows any disk-cached lists immediately, then fetches only the categories
    /// that are missing or stale. See `fetch(_:onlyStale:)` for the mechanics.
    func loadMissing(for categories: [AO3MediaCategory]) async {
        await fetch(categories, onlyStale: true)
    }

    /// User-triggered refresh for the categories currently on screen. Unlike
    /// `loadMissing`, this bypasses staleness so pull-to-refresh really updates the
    /// visible counts, but failures keep the previous cached lists in place.
    func refresh(_ categories: [AO3MediaCategory]) async {
        await fetch(categories, onlyStale: false)
    }

    /// Shared fetch behind `loadMissing`/`refresh`: shows any disk-cached lists
    /// immediately, then fetches the categories that are missing/stale (or, for
    /// a user-triggered refresh, every candidate regardless of staleness) —
    /// **concurrently but bounded** (a few at a time, polite) so the cards fill
    /// in together rather than one slow row at a time. Fresh results update the
    /// cards and the on-disk cache. Safe to call repeatedly (in-flight / fresh
    /// categories are skipped) and cancellable (leaving the screen stops the
    /// remaining fetches).
    private func fetch(_ categories: [AO3MediaCategory], onlyStale: Bool) async {
        await loadCacheIfNeeded()

        let pending = categories.filter {
            (!onlyStale || FandomCatalogCache.isStale(entries[$0.id]))
                && !inFlight.contains($0.id)
                && !$0.fandomsURL.isEmpty
        }
        guard !pending.isEmpty else { return }
        for category in pending {
            inFlight.insert(category.id)
        }

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
                if let list {
                    fandomsByCategory[key] = list
                    catalogDidChange()
                    entries[key] = FandomCatalogCache.Entry(fandoms: list, fetchedAt: Date())
                    // Persist per landing, not once after the whole group: if the
                    // process dies mid-load (the exact jetsam scenario BUG-5 chased),
                    // a single end-of-group persist loses every fetched list and the
                    // next Browse open repeats the full burst — a kill loop.
                    persist()
                }
                inFlight.remove(key)
                if Task.isCancelled { group.cancelAll() }
            }
        }
    }

    /// Loads the disk cache once (off the main actor) and shows cached lists so the
    /// cards aren't blank on relaunch.
    private func loadCacheIfNeeded() async {
        guard !didLoadCache else { return }
        didLoadCache = true
        let cache = cache
        let loaded = await Task.detached(priority: .utility) { cache.load() }.value
        for (key, entry) in loaded {
            entries[key] = entry
            if fandomsByCategory[key] == nil { fandomsByCategory[key] = entry.fandoms }
        }
        if !loaded.isEmpty { catalogDidChange() }
    }

    /// Writes the cache off the main actor (the payload can be a few MB).
    private func persist() {
        let snapshot = entries
        let cache = cache
        Task.detached(priority: .utility) { cache.save(snapshot) }
    }
}
