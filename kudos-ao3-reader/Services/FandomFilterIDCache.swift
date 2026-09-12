import Foundation

/// Fandom name → AO3's numeric filter id, for the life of the process.
///
/// Deliberately **no TTL**: a canonical tag's id does not change (a renamed tag
/// keeps its id; a merged one redirects), so the only reason to forget an entry
/// is memory. Bounded at the same 128 entries `FandomFamilyExactCountCache` and
/// `AO3AuthorPageCache` use — the networking policy names that ceiling — because
/// a long browse through a category with thousands of families would otherwise
/// grow a dictionary and never give it back.
actor FandomFilterIDCache {
    static let shared = FandomFilterIDCache()
    static let entryLimit = 128

    private var ids: [String: Int] = [:]
    /// Insertion order, oldest first, so eviction drops the least recently stored.
    private var order: [String] = []

    func id(for fandomName: String) -> Int? { ids[fandomName] }

    func store(_ id: Int, for fandomName: String) {
        if ids.updateValue(id, forKey: fandomName) == nil {
            order.append(fandomName)
        }
        while order.count > Self.entryLimit, let oldest = order.first {
            order.removeFirst()
            ids.removeValue(forKey: oldest)
        }
    }
}
