import Foundation
import SwiftData

/// One time Kudos saw a saved work's posted chapter count go up (Insights D10, "New
/// Chapters" and the Letting Chapters Stack trigger).
///
/// Written only by the update checks the app already makes (`ChapterUpdateRecorder`), so it
/// costs no AO3 request. Keyed by `SavedWork.id` plus `ao3WorkID`, never a relationship, so
/// deleting the work leaves the event (the reading log works the same way). Every stored
/// property has a default for lightweight migration and additive backup decoding.
@Model final class ChapterUpdateEvent {
    var id: UUID = UUID()
    /// `SavedWork.id`. Remapped on restore when a merge kept the local copy's id.
    var workID: UUID = UUID()
    var ao3WorkID: Int?
    /// Posted chapters after the rise, and before it. One event can cover several chapters
    /// (3 -> 6 is chapters 4...6, all detected at once); none is dropped when unread.
    var chapterCount: Int = 0
    var previousChapterCount: Int = 0
    var detectedAt: Date = Date()
    /// AO3's day for the update (`SavedWork.dateUpdated` as printed), or empty when the
    /// check had none: the delay then counts from `detectedAt`.
    var postedDate: String = ""
    /// The work's rating when the event was written, so Hide Mature still applies after
    /// the work is deleted (the same snapshot `ReadingSession.rating` keeps).
    var rating: String = ""
    var lastModifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        workID: UUID,
        ao3WorkID: Int? = nil,
        chapterCount: Int,
        previousChapterCount: Int,
        detectedAt: Date = Date(),
        postedDate: String = "",
        rating: String = "",
        lastModifiedAt: Date? = nil
    ) {
        self.id = id
        self.workID = workID
        self.ao3WorkID = ao3WorkID
        self.chapterCount = chapterCount
        self.previousChapterCount = previousChapterCount
        self.detectedAt = detectedAt
        self.postedDate = postedDate
        self.rating = rating
        self.lastModifiedAt = lastModifiedAt ?? detectedAt
    }

    /// First chapter this event added (1-based).
    var firstNewChapter: Int { previousChapterCount + 1 }

    /// When AO3 says the chapters went up: its day when it printed one, else the check.
    var postedAt: Date {
        WorkStat.date(from: postedDate).map { min($0, detectedAt) } ?? detectedAt
    }
}

/// Writes `ChapterUpdateEvent` rows from the checks that already read a work's chapter count.
@MainActor
enum ChapterUpdateRecorder {
    /// Largest chapter count an event may carry. AO3 caps a work far below this; an imported
    /// number above it is damage, not data, and would only feed arithmetic in the figures.
    nonisolated static let maximumChapterCount = 10_000

    /// The earlier of two AO3 posting days (either may be empty): merging must not depend on the
    /// order two devices' archives arrive in. Days that do not parse fall back to the non-empty one.
    nonisolated static func earlierPostingDay(_ first: String, _ second: String) -> String {
        if first.isEmpty { return second }
        if second.isEmpty { return first }
        switch (WorkStat.date(from: first), WorkStat.date(from: second)) {
        case let (one?, two?): return two < one ? second : first
        case (nil, _?): return second
        default: return first
        }
    }

    /// Of two ratings for one observation, the adult one (Hide Mature evidence is never lost),
    /// else the non-empty one, else the first.
    nonisolated static func strongerRating(_ first: String, _ second: String) -> String {
        if MatureContentRating.isAdult(first), !first.isEmpty { return first }
        if MatureContentRating.isAdult(second), !second.isEmpty { return second }
        return first.isEmpty ? second : first
    }

    /// The events Insights and exports may use. Sync never erases an event on the strength of a
    /// deletion record (the tombstone signature does not cover its reason, and a soft delete
    /// looks the same as a permanent one): it only **hides** the events of a work that is absent
    /// here while a signed work tombstone at least as new as the sighting covers it, by id or by
    /// AO3 id. A work still here (even in Recently Deleted) keeps its events visible, so
    /// Restore finds them; only `WorkLifecycle.hardDelete` on this device removes them.
    nonisolated static func visible(
        _ events: [ChapterUpdateEvent],
        localWorkIDs: Set<UUID>,
        localAO3IDs: Set<Int> = [],
        workTombstones: [(recordID: UUID, ao3WorkID: Int?, modifiedAt: Date)]
    ) -> [ChapterUpdateEvent] {
        guard !workTombstones.isEmpty else { return events }
        return events.filter { event in
            // The same AO3 work counts as here whatever local UUID it was restored under.
            guard !localWorkIDs.contains(event.workID),
                  !(event.ao3WorkID.map(localAO3IDs.contains) ?? false) else { return true }
            return !workTombstones.contains { tombstone in
                tombstone.modifiedAt >= event.detectedAt
                    && (tombstone.recordID == event.workID
                        || (event.ao3WorkID != nil && tombstone.ao3WorkID == event.ao3WorkID))
            }
        }
    }

    /// `visible` from the stores: every work row (Recently Deleted included) and the work tombstones.
    static func visible(_ events: [ChapterUpdateEvent], in context: ModelContext) -> [ChapterUpdateEvent] {
        let works = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
        let tombstones = (try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? []
        return visible(
            events,
            localWorkIDs: Set(works.map(\.id)),
            localAO3IDs: Set(works.compactMap { $0.ao3WorkID ?? WorkTags.ao3WorkID(from: $0.sourceURL) }),
            workTombstones: workTombstonePairs(tombstones)
        )
    }

    nonisolated static func workTombstonePairs(
        _ tombstones: [SyncTombstone]
    ) -> [(recordID: UUID, ao3WorkID: Int?, modifiedAt: Date)] {
        tombstones.filter { $0.recordTypeRaw == SyncTombstoneRecordType.savedWork.rawValue }
            .map { ($0.recordID, $0.ao3WorkID, $0.lastModifiedAt) }
    }

    /// A store built without this model (a unit-test schema) has nowhere to put events.
    static func isStored(in context: ModelContext) -> Bool {
        context.container.schema.entities.contains(where: { $0.name == "ChapterUpdateEvent" })
    }

    /// Records a rise in the posted chapter count. Nothing is written for a work that had no
    /// count before (the first sight is a baseline, not an update), for a count that did not
    /// rise, or for a rise an event already covers (two checks seeing the same chapters).
    @discardableResult
    static func recordRise(
        for work: SavedWork,
        previousPosted: Int,
        newPosted: Int,
        postedDate: String = "",
        at now: Date = Date(),
        in context: ModelContext
    ) -> ChapterUpdateEvent? {
        guard previousPosted > 0, newPosted <= maximumChapterCount,
              work.modelContext != nil, isStored(in: context)
        else { return nil }
        let workID = work.id
        let existing = (try? context.fetch(FetchDescriptor<ChapterUpdateEvent>(
            predicate: #Predicate { $0.workID == workID }
        ))) ?? []
        guard newPosted > previousPosted else {
            // A recheck that finds the same count: no new chapters, but AO3's day for the last
            // one, if this page has it and the event for that chapter did not, is new.
            let day = postedDate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !day.isEmpty,
               let last = existing.first(where: { $0.chapterCount == newPosted && $0.postedDate.isEmpty }) {
                last.postedDate = day
                last.lastModifiedAt = now
            }
            return nil
        }
        if let covering = existing.first(where: { $0.chapterCount >= newPosted && $0.previousChapterCount < newPosted }) {
            // The same chapters seen again: only AO3's posting day, if this sighting has it
            // and the first did not, is new.
            let day = postedDate.trimmingCharacters(in: .whitespacesAndNewlines)
            if covering.postedDate.isEmpty, !day.isEmpty {
                covering.postedDate = day
                covering.lastModifiedAt = now
            }
            return nil
        }
        guard !existing.contains(where: { $0.chapterCount >= newPosted }) else { return nil }
        // A rise another event already started (3 -> 5, then 3 -> 6) only adds the new tail.
        let covered = existing.map(\.chapterCount).max() ?? 0
        let event = ChapterUpdateEvent(
            workID: workID,
            ao3WorkID: work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL),
            chapterCount: newPosted,
            previousChapterCount: max(previousPosted, covered),
            detectedAt: now,
            postedDate: postedDate.trimmingCharacters(in: .whitespacesAndNewlines),
            rating: work.rating
        )
        context.insert(event)
        FolderSyncService.markDirty()
        return event
    }
}
