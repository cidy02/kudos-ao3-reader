import Foundation

/// What the reader had already seen the last time they looked at their AO3
/// subscriptions — the store behind artboard **1p**'s "X New" badge.
///
/// **Keyed on the chapter count, not on AO3's date string.** `AO3WorkSummary`
/// carries `dateUpdated` as prose ("Updated 3 Sep 2026"), which would have to be
/// parsed back into a date in AO3's locale before it could be compared. The posted
/// chapter count is an integer that already arrives parsed, it is what the reader
/// actually cares about ("two new chapters", not "touched on Tuesday"), and it is
/// the same signal `SavedWork.knownChapterCount` already uses for update detection
/// elsewhere in the app.
///
/// **`UserDefaults`, not SwiftData, and that is a deliberate trade.** A new `@Model`
/// means a schema change, a `PersistenceSync` entry, a preview-container entry and
/// three `KudosBackup` sites — none of which can be exercised from the container this
/// branch is built in, and `T-211` forbids the manifest bump that would normally
/// carry it. What is stored here is a per-device convenience: losing it re-baselines
/// the badges and loses nothing a reader authored. If it should survive a restore, it
/// moves to a model later and this becomes its migration source.
nonisolated struct SubscriptionWatermark: Codable, Equatable, Sendable {
    /// Posted chapters as of the last time this subscription was seen.
    var postedChapterCount: Int
    var seenAt: Date
}

@MainActor
enum SubscriptionWatermarks {
    private static let defaultsKey = "ao3.subscriptions.watermarks"

    /// Matching the ceiling `AO3_NETWORKING_POLICY` names for the other caches.
    /// Someone with more subscriptions than this loses the badge on the ones they
    /// looked at longest ago, which is the right thing to drop.
    static let entryLimit = 512

    static func load(from defaults: UserDefaults = .standard) -> [Int: SubscriptionWatermark] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: SubscriptionWatermark].self, from: data)
        else { return [:] }
        return Dictionary(
            decoded.compactMap { key, value in Int(key).map { ($0, value) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func save(
        _ watermarks: [Int: SubscriptionWatermark],
        to defaults: UserDefaults = .standard
    ) {
        let bounded = bound(watermarks)
        let encodable = Dictionary(
            bounded.map { (String($0.key), $0.value) }, uniquingKeysWith: { first, _ in first }
        )
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    /// Drops the least recently seen entries past `entryLimit`.
    static func bound(_ watermarks: [Int: SubscriptionWatermark]) -> [Int: SubscriptionWatermark] {
        guard watermarks.count > entryLimit else { return watermarks }
        let kept = watermarks
            .sorted { $0.value.seenAt > $1.value.seenAt }
            .prefix(entryLimit)
        return Dictionary(kept.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// New chapters on this work since it was last seen.
    ///
    /// **A work with no watermark is not new.** Otherwise a reader opening this
    /// screen for the first time would meet three hundred badges, every one of them
    /// technically true and collectively meaningless. First sight baselines instead
    /// — see `baseline`.
    ///
    /// Only ever counts up: AO3 chapter counts can fall when a chapter is deleted,
    /// and "−2 new chapters" is not a thing.
    static func newChapterCount(
        for work: AO3WorkSummary,
        watermarks: [Int: SubscriptionWatermark]
    ) -> Int {
        guard let seen = watermarks[work.id] else { return 0 }
        let posted = SavedWork.postedChapterCount(from: work.chapters)
        return max(0, posted - seen.postedChapterCount)
    }

    /// Records a first sight for any work not already watermarked, leaving works
    /// that **are** watermarked alone so their badges survive the page load that
    /// displayed them.
    ///
    /// Returns the updated map, or `nil` when nothing changed — so a caller can skip
    /// the write on the overwhelmingly common repeat visit.
    static func baseline(
        _ works: [AO3WorkSummary],
        into watermarks: [Int: SubscriptionWatermark],
        now: Date = Date()
    ) -> [Int: SubscriptionWatermark]? {
        var updated = watermarks
        var changed = false
        for work in works where updated[work.id] == nil {
            updated[work.id] = SubscriptionWatermark(
                postedChapterCount: SavedWork.postedChapterCount(from: work.chapters),
                seenAt: now
            )
            changed = true
        }
        return changed ? updated : nil
    }

    /// Marks every given work as seen at its current chapter count, clearing badges.
    static func markSeen(
        _ works: [AO3WorkSummary],
        in watermarks: [Int: SubscriptionWatermark],
        now: Date = Date()
    ) -> [Int: SubscriptionWatermark] {
        var updated = watermarks
        for work in works {
            updated[work.id] = SubscriptionWatermark(
                postedChapterCount: SavedWork.postedChapterCount(from: work.chapters),
                seenAt: now
            )
        }
        return updated
    }
}
