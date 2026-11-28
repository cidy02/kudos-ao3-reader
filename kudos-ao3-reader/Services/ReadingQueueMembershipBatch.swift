import Foundation
import SwiftData

extension ReadingQueueService {
    struct MembershipAddition {
        let work: SavedWork
        let state: ReadingQueueMembershipState
        let origin: ReadingQueueMembershipOrigin?
    }

    /// Append local works in picker order. Missing EPUBs stay queued for the
    /// queue's offline rules to handle.
    static func append(
        _ works: [SavedWork],
        to queue: ReadingQueue,
        state: ReadingQueueMembershipState = .new,
        origin: ReadingQueueMembershipOrigin? = nil,
        in context: ModelContext
    ) {
        let additions = works.map { MembershipAddition(work: $0, state: state, origin: origin) }
        if appendMemberships(additions, to: queue, in: context) {
            context.saveBestEffort(reason: "Saving queue memberships failed")
        }
    }

    /// Stages additions for the caller's single save, which can also include
    /// creating the destination or removing memberships from a source queue.
    @discardableResult
    static func appendMemberships(
        _ additions: [MembershipAddition],
        to queue: ReadingQueue,
        in context: ModelContext
    ) -> Bool {
        guard queue.kind != .smart else { return false }
        var seen = Set<ObjectIdentifier>()
        var pending: [MembershipAddition] = []
        for addition in additions where seen.insert(ObjectIdentifier(addition.work)).inserted {
            let work = addition.work
            backfillKnownChapterCount(for: work)
            if work.queueMemberships.contains(where: { $0.queue?.id == queue.id }) {
                normalize(work)
            } else {
                pending.append(addition)
            }
        }
        guard !pending.isEmpty else { return false }

        var memberships = queue.memberships
        var lastOrder = memberships.lazy.map(\.sortOrderInQueue).max() ?? -1
        var lastChange = queue.lastMembershipChangedAt
        for addition in pending {
            let work = addition.work
            lastOrder += 1
            let membership = ReadingQueueMembership(
                queue: nil,
                work: work,
                sortOrderInQueue: lastOrder,
                state: addition.state,
                origin: addition.origin
            )
            context.insert(membership)
            if !work.queueMemberships.contains(where: { $0 === membership }) {
                work.queueMemberships.append(membership)
            }
            memberships.append(membership)
            let now = Date()
            lastChange = now
            membership.markModified(now)
            work.markModified(now)
        }
        // Setting the inverse in one assignment (as in the scale fixture)
        // avoids mutating the growing SwiftData relationship for each member.
        queue.memberships = memberships
        queue.markMembershipChanged(lastChange)
        for addition in pending {
            normalize(addition.work)
        }
        return true
    }

    static func move(
        _ works: [SavedWork],
        from source: ReadingQueue,
        to destination: ReadingQueue,
        state: ReadingQueueMembershipState? = nil,
        origin: ReadingQueueMembershipOrigin? = nil,
        in context: ModelContext
    ) {
        guard source.id != destination.id, source.kind != .smart, destination.kind != .smart else { return }
        let additions = works.map { work in
            let membership = work.queueMemberships.first { $0.queue?.id == source.id }
            return MembershipAddition(
                work: work,
                state: state ?? membership?.state ?? .inLine,
                origin: origin ?? membership?.origin
            )
        }
        appendMemberships(additions, to: destination, in: context)
        // Each work now belongs to the destination, so leaving the source
        // cannot make it a queue-only work with no memberships.
        removeFromQueue(works, from: source, in: context)
    }

    static func removeFromQueue(_ works: [SavedWork], from queue: ReadingQueue, in context: ModelContext) {
        guard queue.kind != .smart, !works.isEmpty else { return }
        var seen = Set<ObjectIdentifier>()
        let uniqueWorks = works.filter { seen.insert(ObjectIdentifier($0)).inserted }
        var removed: [ReadingQueueMembership] = []
        var removedIDs = Set<UUID>()
        for work in uniqueWorks {
            let memberships = work.queueMemberships
            let matches = memberships.filter { $0.queue?.id == queue.id }
            guard !matches.isEmpty else { continue }
            let matchIDs = Set(matches.map(\.id))
            for membership in matches {
                SyncTombstones.recordDeletion(of: membership, in: context)
            }
            work.queueMemberships = memberships.filter { !matchIDs.contains($0.id) }
            removed.append(contentsOf: matches)
            removedIDs.formUnion(matchIDs)
        }
        if !removedIDs.isEmpty {
            queue.memberships.removeAll { removedIDs.contains($0.id) }
            for membership in removed {
                context.delete(membership)
            }
        }
        let now = Date()
        queue.markMembershipChanged(now)
        for work in uniqueWorks {
            work.markModified(now)
            normalize(work)
        }
        context.saveBestEffort(reason: "Saving queue removals failed")
    }

    static func mergeSavedForLaterDuplicates(
        _ duplicates: ArraySlice<ReadingQueue>,
        into primary: ReadingQueue,
        in context: ModelContext
    ) {
        guard !duplicates.isEmpty else { return }
        var memberships = primary.memberships
        var workIDs = Set(memberships.compactMap { $0.work?.id })
        var links = primary.searchLinks
        var sourceKeys = Set(links.map(\.dedupKey))
        let originalSourceCount = links.count
        var lastChange: Date?

        for duplicate in duplicates {
            let duplicateMemberships = duplicate.memberships
            let remainingMemberships = duplicateMemberships.filter { membership in
                guard let id = membership.work?.id, workIDs.insert(id).inserted else { return true }
                memberships.append(membership)
                lastChange = max(membership.lastModifiedAt, Date())
                return false
            }
            if remainingMemberships.count != duplicateMemberships.count {
                duplicate.memberships = remainingMemberships
            }

            let duplicateLinks = duplicate.searchLinks
            let remainingLinks = duplicateLinks.filter { link in
                guard sourceKeys.insert(link.dedupKey).inserted else { return true }
                links.append(link)
                return false
            }
            if remainingLinks.count != duplicateLinks.count {
                duplicate.searchLinks = remainingLinks
            }
        }

        // Attach the retained rows before deleting the source queues, whose
        // cascade should only delete their remaining duplicate rows.
        if let lastChange {
            primary.memberships = memberships
            primary.markMembershipChanged(lastChange)
        }
        if links.count != originalSourceCount { primary.searchLinks = links }
        for duplicate in duplicates {
            context.delete(duplicate)
        }
    }
}
