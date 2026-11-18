import Foundation
import SwiftData
import SwiftSoup

/// Value-type snapshot of a `SavedSeries` row for background insights and view calculations.
nonisolated struct SavedSeriesSnapshot: Equatable, Sendable {
    var ao3SeriesID: Int
    var title: String
    var partCount: Int
    var isComplete: Bool
    var wordCount: Int
    var partWorkIDs: [Int]
    var checkedAt: Date

    init(
        ao3SeriesID: Int,
        title: String,
        partCount: Int,
        isComplete: Bool,
        wordCount: Int,
        partWorkIDs: [Int] = [],
        checkedAt: Date = Date()
    ) {
        self.ao3SeriesID = ao3SeriesID
        self.title = title
        self.partCount = max(0, partCount)
        self.isComplete = isComplete
        self.wordCount = max(0, wordCount)
        self.partWorkIDs = SavedSeries.normalizedPartWorkIDs(partWorkIDs)
        self.checkedAt = checkedAt
    }

    var effectivePartCount: Int {
        partCount > 0 ? partCount : partWorkIDs.count
    }
}

/// Series metadata parsed from an AO3 series show page (`/series/<id>`).
nonisolated struct AO3ParsedSeries: Equatable, Sendable {
    var ao3SeriesID: Int
    var title: String
    var partCount: Int
    var isComplete: Bool
    var wordCount: Int
    var partWorkIDs: [Int]
    var hasCompleteWorkList: Bool

    init(
        ao3SeriesID: Int,
        title: String,
        partCount: Int,
        isComplete: Bool,
        wordCount: Int,
        partWorkIDs: [Int] = [],
        hasCompleteWorkList: Bool
    ) {
        self.ao3SeriesID = ao3SeriesID
        self.title = title
        self.partCount = max(0, partCount)
        self.isComplete = isComplete
        self.wordCount = max(0, wordCount)
        self.partWorkIDs = SavedSeries.normalizedPartWorkIDs(partWorkIDs)
        self.hasCompleteWorkList = hasCompleteWorkList
    }

    /// The header of `/series/<id>` (otwarchive `app/views/series/show.html.erb`): `h2.heading`, then
    /// `dl.series.meta` whose `dl.stats` holds `dd.words`, `dd.works` and an unclassed
    /// `<dt>Complete:</dt><dd>Yes|No</dd>`. `pageWorkIDs` are the works listed on this page, in series order.
    static func parse(
        html: String,
        ao3SeriesID: Int,
        pageWorkIDs: [Int],
        isWholeList: Bool
    ) -> AO3ParsedSeries? {
        guard ao3SeriesID > 0, let doc = try? SwiftSoup.parse(html),
              let meta = try? doc.select("dl.series.meta").first() else { return nil }
        let labels = (try? meta.select("dl.stats dt").array()) ?? []
        let completeText = labels.first { ((try? $0.text()) ?? "").hasPrefix("Complete") }
            .flatMap { try? $0.nextElementSibling()?.text() }
        return AO3ParsedSeries(
            ao3SeriesID: ao3SeriesID,
            title: (try? doc.select("h2.heading").first()?.text()) ?? "",
            partCount: AO3Client.statInt("works", in: meta) ?? 0,
            isComplete: completeText?.trimmingCharacters(in: .whitespaces) == "Yes",
            wordCount: AO3Client.statInt("words", in: meta) ?? 0,
            partWorkIDs: pageWorkIDs,
            hasCompleteWorkList: isWholeList
        )
    }
}

/// Cached AO3 metadata for a series whose show page the reader has already fetched.
///
/// Every stored property has a default value for lightweight SwiftData migration and
/// additive backup/Folder Sync compatibility.
@Model
final class SavedSeries {
    var id: UUID = UUID()
    var ao3SeriesID: Int = 0
    var title: String = ""
    var partCount: Int = 0
    var isComplete: Bool = false
    var wordCount: Int = 0
    var partWorkIDs: [Int] = []
    var checkedAt: Date = Date()
    var lastModifiedAt: Date = Date()
    /// How often the reader opened this series or one of its works (T-519b: most viewed is checked first).
    var viewCount: Int = 0
    var lastViewedAt: Date?
    /// The series page's Subscribe button said "Unsubscribe" the last time the reader opened it.
    var isSubscribed: Bool = false

    init(
        id: UUID = UUID(),
        ao3SeriesID: Int = 0,
        title: String = "",
        partCount: Int = 0,
        isComplete: Bool = false,
        wordCount: Int = 0,
        partWorkIDs: [Int] = [],
        checkedAt: Date = Date(),
        lastModifiedAt: Date? = nil
    ) {
        self.id = id
        self.ao3SeriesID = ao3SeriesID
        self.title = title
        self.partCount = max(0, partCount)
        self.isComplete = isComplete
        self.wordCount = max(0, wordCount)
        self.partWorkIDs = Self.normalizedPartWorkIDs(partWorkIDs)
        self.checkedAt = checkedAt
        self.lastModifiedAt = lastModifiedAt ?? checkedAt
    }

    var snapshot: SavedSeriesSnapshot {
        SavedSeriesSnapshot(
            ao3SeriesID: ao3SeriesID,
            title: title,
            partCount: partCount,
            isComplete: isComplete,
            wordCount: wordCount,
            partWorkIDs: partWorkIDs,
            checkedAt: checkedAt
        )
    }

    /// Deduplicates work IDs while preserving AO3's series order and dropping invalid IDs.
    nonisolated static func normalizedPartWorkIDs(_ workIDs: [Int]) -> [Int] {
        var seen = Set<Int>()
        var ordered: [Int] = []
        ordered.reserveCapacity(workIDs.count)
        for workID in workIDs where workID > 0 {
            if seen.insert(workID).inserted {
                ordered.append(workID)
            }
        }
        return ordered
    }
}

/// SwiftData persistence helpers for upserting, querying, and deleting `SavedSeries` rows.
@MainActor
enum SavedSeriesStore {
    @discardableResult
    static func upsert(
        _ parsed: AO3ParsedSeries,
        in context: ModelContext,
        now: Date = Date()
    ) -> SavedSeries? {
        let ao3SeriesID = parsed.ao3SeriesID, isComplete = parsed.isComplete
        let hasCompleteWorkList = parsed.hasCompleteWorkList
        guard ao3SeriesID > 0 else { return nil }

        let targetID = ao3SeriesID
        let normalizedTitle = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedPartCount = parsed.partCount
        let clampedWordCount = parsed.wordCount
        let normalizedWorkIDs = parsed.partWorkIDs

        let descriptor = FetchDescriptor<SavedSeries>(
            predicate: #Predicate<SavedSeries> { $0.ao3SeriesID == targetID }
        )
        let matches = (try? context.fetch(descriptor)) ?? []

        if let existing = matches.first {
            for duplicate in matches.dropFirst() {
                context.delete(duplicate)
            }
            if !normalizedTitle.isEmpty {
                existing.title = normalizedTitle
            }
            existing.partCount = clampedPartCount
            existing.isComplete = isComplete
            existing.wordCount = clampedWordCount
            if hasCompleteWorkList {
                existing.partWorkIDs = normalizedWorkIDs
            } else if clampedPartCount > 0, existing.partWorkIDs.count != clampedPartCount {
                // Avoid leaving an outdated or partial partWorkIDs list pretending to be complete
                // when only page 1 of a multi-page series was fetched after a series growth.
                existing.partWorkIDs = []
            }
            existing.checkedAt = now
            existing.lastModifiedAt = now
            return existing
        }

        let created = SavedSeries(
            ao3SeriesID: ao3SeriesID,
            title: normalizedTitle,
            partCount: clampedPartCount,
            isComplete: isComplete,
            wordCount: clampedWordCount,
            partWorkIDs: hasCompleteWorkList ? normalizedWorkIDs : [],
            checkedAt: now,
            lastModifiedAt: now
        )
        context.insert(created)
        return created
    }

    static func series(for ao3SeriesID: Int, in context: ModelContext) -> SavedSeries? {
        guard ao3SeriesID > 0 else { return nil }
        let targetID = ao3SeriesID
        let descriptor = FetchDescriptor<SavedSeries>(
            predicate: #Predicate<SavedSeries> { $0.ao3SeriesID == targetID }
        )
        return (try? context.fetch(descriptor))?.first
    }

    static func snapshots(in context: ModelContext) -> [SavedSeriesSnapshot] {
        let rows = (try? context.fetch(FetchDescriptor<SavedSeries>())) ?? []
        return rows.map(\.snapshot)
    }

}
