import Foundation
import SwiftData

/// The one shared answer to "is this local record the same AO3 work?", matched in
/// priority order: AO3 work ID → canonical AO3 work URL → local record UUID.
///
/// Backup/sync restore (`WorkRestoreIndex`), the remote-card context menu,
/// `ReadingQueueService`'s acquisition paths, and `CanonicalWorkMerge` all resolve
/// identity through this index, so a work can't dodge one surface's dedup by
/// matching under a different identity tier somewhere else.
@MainActor
struct WorkIdentityIndex {
    private var worksByID: [UUID: SavedWork] = [:]
    private var worksByAO3WorkID: [Int: SavedWork] = [:]
    private var worksByCanonicalSourceURL: [String: SavedWork] = [:]

    init(_ works: [SavedWork]) {
        for work in works {
            index(work)
        }
    }

    /// Adds a work to the index — e.g. a record just created mid-restore, so later
    /// archive entries can match it.
    mutating func index(_ work: SavedWork) {
        worksByID[work.id] = work
        if let id = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) {
            worksByAO3WorkID[id] = work
        }
        if let canonicalURL = WorkTags.canonicalAO3WorkURL(from: work.sourceURL) {
            worksByCanonicalSourceURL[canonicalURL] = work
        }
    }

    /// Three-tier lookup. Pass whichever identifiers the caller has; the strongest
    /// available tier wins. `recordID` (the local UUID) only matters for
    /// backup/sync payloads, which carry the originating record's UUID.
    func existingWork(ao3WorkID: Int?, sourceURL: String?, recordID: UUID? = nil) -> SavedWork? {
        if let id = ao3WorkID ?? sourceURL.flatMap(WorkTags.ao3WorkID(from:)),
           let work = worksByAO3WorkID[id] {
            return work
        }
        if let canonicalURL = sourceURL.flatMap(WorkTags.canonicalAO3WorkURL(from:)),
           let work = worksByCanonicalSourceURL[canonicalURL] {
            return work
        }
        if let recordID {
            return worksByID[recordID]
        }
        return nil
    }

    /// The local record for a remote AO3 summary, if one exists.
    func existingWork(for summary: AO3WorkSummary) -> SavedWork? {
        existingWork(ao3WorkID: summary.id, sourceURL: summary.workURL.absoluteString)
    }
}
