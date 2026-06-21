import Foundation
import Testing
@testable import Kudos

/// Covers the local-first fandom-catalog cache: entries round-trip through disk,
/// a missing file reads as empty, and staleness honors the max age.
struct FandomCatalogCacheTests {

    private func tempCache() -> FandomCatalogCache {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fandom-cache-\(UUID().uuidString).json")
        return FandomCatalogCache(fileURL: url)
    }

    @Test func roundTripsEntriesThroughDisk() {
        let cache = tempCache()
        let entries: [String: FandomCatalogCache.Entry] = [
            "Anime & Manga": .init(
                fandoms: [AO3Fandom(name: "Naruto", workCount: 1200), AO3Fandom(name: "Bleach")],
                fetchedAt: Date(timeIntervalSince1970: 1_000_000)
            )
        ]
        cache.save(entries)

        let loaded = cache.load()
        #expect(loaded.count == 1)
        let anime = loaded["Anime & Manga"]
        #expect(anime?.fandoms.count == 2)
        #expect(anime?.fandoms.first?.name == "Naruto")
        #expect(anime?.fandoms.first?.workCount == 1200)
        #expect(anime?.fandoms.last?.workCount == nil)
    }

    @Test func loadReturnsEmptyWhenFileAbsent() {
        #expect(tempCache().load().isEmpty)
    }

    @Test func stalenessHonorsMaxAge() {
        let now = Date()
        let fresh = FandomCatalogCache.Entry(fandoms: [], fetchedAt: now)
        let old = FandomCatalogCache.Entry(
            fandoms: [],
            fetchedAt: now.addingTimeInterval(-FandomCatalogCache.maxAge - 60)
        )
        #expect(FandomCatalogCache.isStale(fresh, now: now) == false)
        #expect(FandomCatalogCache.isStale(old, now: now) == true)
        #expect(FandomCatalogCache.isStale(nil, now: now) == true)
    }
}
