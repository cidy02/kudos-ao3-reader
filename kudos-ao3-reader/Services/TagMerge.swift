import Foundation

/// Shared tag-list merge/normalization used everywhere a work's tags are unioned
/// with a freshly fetched AO3 list (`WorkTags`, `WorkMetadataRefresh`, and the
/// `ReadingQueueService` series-preservation path) — trims whitespace, dedupes
/// case-insensitively, and preserves first-seen casing/order.
enum TagMerge {
    static func merged(_ existing: [String], _ incoming: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in existing + incoming {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(key(value)).inserted else { continue }
            result.append(value)
        }
        return result
    }

    static func key(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
