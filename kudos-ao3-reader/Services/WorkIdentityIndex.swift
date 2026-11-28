import Foundation
import os
import SwiftData

/// The one shared answer to "is this local record the same AO3 work?", matched in
/// priority order: AO3 work ID → canonical AO3 work URL → local record UUID.
///
/// Backup/sync restore (`WorkRestoreIndex`), the import funnels (`WorkImporter`),
/// the remote-card context menu, `ReadingQueueService`'s acquisition paths, and
/// `CanonicalWorkMerge` all resolve identity through this index, so a work can't
/// dodge one surface's dedup by matching under a different identity tier
/// somewhere else.
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

    fileprivate mutating func setAO3Match(_ work: SavedWork?, for id: Int) {
        worksByAO3WorkID[id] = work
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

    /// Same id-then-canonical-URL lookup as `existingWork`, for a mail work id.
    /// A value that does not fit in `Int` cannot be a stored AO3 work id.
    func containsAO3Work(_ workID: UInt64) -> Bool {
        guard let id = Int(exactly: workID) else { return false }
        return existingWork(
            ao3WorkID: id,
            sourceURL: "https://archiveofourown.org/works/\(id)"
        ) != nil
    }
}

/// An acquisition batch can suspend between items. Keep the index across its
/// own writes, and reload it if an intervening edit can change a match.
@MainActor
final class WorkIdentityBatch {
    private struct Identity: Equatable {
        let recordID: UUID
        let ao3WorkID: Int?
        let sourceURL: String

        init(_ work: SavedWork) {
            recordID = work.id
            ao3WorkID = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL)
            sourceURL = work.sourceURL
        }
    }

    private let context: ModelContext
    private var index: WorkIdentityIndex?
    private var identities: [ObjectIdentifier: Identity] = [:]
    private var fetchOrder: [ObjectIdentifier: Int] = [:]
    private var ao3Candidates: [Int: [SavedWork]] = [:]
    private var exactSources: [String: SavedWork] = [:]
    private var fetchedWithPendingChanges = false
    private var observers: [any NSObjectProtocol] = []
    private let otherContextSavedWork = OSAllocatedUnfairLock(initialState: false)

    init(in context: ModelContext) {
        self.context = context
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ModelContext.willSave, object: context, queue: nil) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.invalidateForPendingChanges() }
        })
        let contextID = ObjectIdentifier(context)
        let workEntity = Schema.entityName(for: SavedWork.self)
        let invalidation = otherContextSavedWork
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { notice in
            guard let sender = notice.object, ObjectIdentifier(sender as AnyObject) != contextID else { return }
            if WorkIdentityBatch.save(notice, affects: [workEntity]) {
                invalidation.withLock { $0 = true }
            }
        })
    }

    func stopTrackingChanges() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    func existingWork(ao3WorkID: Int?, sourceURL: String?, recordID: UUID? = nil) -> SavedWork? {
        resolve {
            index?.existingWork(ao3WorkID: ao3WorkID, sourceURL: sourceURL, recordID: recordID)
        }
    }

    func existingWork(forSource source: URL) -> SavedWork? {
        let target = source.absoluteString
        return resolve {
            index?.existingWork(ao3WorkID: nil, sourceURL: target) ?? exactSources[target]
        }
    }

    func invalidate() {
        index = nil
    }

    private func resolve(_ lookup: () -> SavedWork?) -> SavedWork? {
        refreshIfNeeded()
        guard let work = lookup() else { return nil }
        // A rollback can detach an unsaved insert without a save notification.
        if work.modelContext === context, !work.isDeleted, identities[ObjectIdentifier(work)] == Identity(work) {
            return work
        }
        invalidate()
        refreshIfNeeded()
        return lookup()
    }

    /// Called before saving an acquisition, including inserts whose SwiftData
    /// persistent identifier will change on that save.
    func record(_ work: SavedWork) {
        guard index != nil else { return }
        let objectID = ObjectIdentifier(work)
        let identity = Identity(work)
        if let prior = identities[objectID] {
            guard prior.recordID == identity.recordID, prior.sourceURL == identity.sourceURL else {
                index = nil
                return
            }
            if prior.ao3WorkID != identity.ao3WorkID {
                // A URL match can backfill or correct the explicit ID on a legacy
                // row. Keep the original fetch precedence at both affected keys.
                identities[objectID] = identity
                if let oldID = prior.ao3WorkID {
                    ao3Candidates[oldID]?.removeAll { $0 === work }
                    updateAO3Match(for: oldID)
                }
                if let newID = identity.ao3WorkID {
                    ao3Candidates[newID, default: []].append(work)
                    updateAO3Match(for: newID)
                }
            }
        } else {
            identities[objectID] = identity
            fetchOrder[objectID] = fetchOrder.count
            if let id = identity.ao3WorkID { ao3Candidates[id, default: []].append(work) }
            index?.index(work)
            if exactSources[identity.sourceURL] == nil { exactSources[identity.sourceURL] = work }
        }
    }

    private func updateAO3Match(for id: Int) {
        let match = ao3Candidates[id]?.max {
            (fetchOrder[ObjectIdentifier($0)] ?? -1) < (fetchOrder[ObjectIdentifier($1)] ?? -1)
        }
        index?.setAO3Match(match, for: id)
    }

    private func invalidateForPendingChanges() {
        guard index != nil else { return }
        let changed = context.insertedModelsArray + context.changedModelsArray
        if changed.contains(where: { model in
            guard let work = model as? SavedWork else { return false }
            return identities[ObjectIdentifier(work)] != Identity(work)
        }) || context.deletedModelsArray.contains(where: { identities[ObjectIdentifier($0 as AnyObject)] != nil }) {
            index = nil
        }
    }

    private func refreshIfNeeded() {
        let externallyChanged = otherContextSavedWork.withLock { dirty in
            let wasDirty = dirty
            dirty = false
            return wasDirty
        }
        if externallyChanged || fetchedWithPendingChanges { invalidate() }
        invalidateForPendingChanges()
        guard index == nil else { return }
        identities.removeAll(keepingCapacity: true)
        fetchOrder.removeAll(keepingCapacity: true)
        ao3Candidates.removeAll(keepingCapacity: true)
        exactSources.removeAll(keepingCapacity: true)
        guard let works = try? context.fetch(FetchDescriptor<SavedWork>()) else { return }
        index = WorkIdentityIndex([])
        for work in works { record(work) }
        let pending = context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray
        fetchedWithPendingChanges = pending.contains { $0 is SavedWork }
    }

    nonisolated static func save(_ notice: Notification, affects entityNames: Set<String>) -> Bool {
        let info = notice.userInfo ?? [:]
        let keys: [ModelContext.NotificationKey] = [
            .insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers, .invalidatedAllIdentifiers
        ]
        let ids = keys.compactMap { key -> [PersistentIdentifier]? in
            let value = info[key] ?? info[key.rawValue]
            if let list = value as? [PersistentIdentifier] { return list }
            if let set = value as? Set<PersistentIdentifier> { return Array(set) }
            return nil
        }
        return ids.isEmpty || ids.contains { $0.contains { entityNames.contains($0.entityName) } }
    }
}
