import Foundation
import OSLog
import SwiftData

@MainActor
// Queue lifecycle rules are centralized here; avoid behavior refactors for lint.
// swiftlint:disable:next type_body_length
enum ReadingQueueService {
    static let savedForLaterName = "Saved for Later"
    nonisolated static let preservationRequestPauseNanos: UInt64 = 2_000_000_000

    struct SeriesPreservationResult: Equatable {
        var total = 0
        var preserved = 0
        var alreadyPreserved = 0
        var skipped = 0
        var failed = 0
        var unavailable = 0
        var cancelled = 0

        var completed: Int {
            preserved + alreadyPreserved + skipped + failed + unavailable + cancelled
        }

        /// The count fragments ("N <verb>", "M already preserved", …) shared by
        /// every series-preservation completion message. Empty when there's
        /// nothing to report. `verb` names what a non-zero `preserved` count did
        /// ("preserved" for Work Detail's own-series preservation, "added" for
        /// Add to Queue's to-other-queues flow) — the one piece of copy that
        /// genuinely differs between call sites.
        func summaryParts(verb: String) -> [String] {
            var parts: [String] = []
            if preserved > 0 { parts.append("\(preserved) \(verb)") }
            if alreadyPreserved > 0 { parts.append("\(alreadyPreserved) already preserved") }
            if unavailable > 0 { parts.append("\(unavailable) unavailable") }
            if failed > 0 { parts.append("\(failed) failed") }
            if skipped > 0 { parts.append("\(skipped) skipped") }
            return parts
        }
    }

    struct SeriesPreservationPrompt: Equatable {
        var preview: AO3SeriesPreview?
        var threshold: Int
        var previewFailed = false

        var knownCount: Int {
            preview?.works.count ?? 0
        }

        var canAutoPreserve: Bool {
            guard let preview else { return false }
            return preview.isComplete && preview.works.count <= threshold
        }

        var canUsePreviewForPreservation: Bool {
            preview?.isComplete == true
        }

        var message: String {
            if previewFailed || preview == nil {
                return "Kudos couldn't check how many works are in this series. Continuing may download many works. "
                    + "Kudos adds them one at a time."
            }
            if canUsePreviewForPreservation {
                return "This series has \(knownCount) work\(knownCount == 1 ? "" : "s"). "
                    + "Download every work in the series?"
            }
            return "This series has at least \(knownCount) work\(knownCount == 1 ? "" : "s") "
                + "and more may be on other pages. Download every work in the series?"
        }

        var autoPreserveLabel: String {
            "Always auto-preserve series under \(threshold) works"
        }
    }

    typealias SeriesWorkPreserver = @MainActor (
        AO3WorkSummary,
        [ReadingQueue],
        ModelContext
    ) async throws -> SavedWork

    static func seriesPrompt(
        for preview: AO3SeriesPreview?,
        threshold: Int,
        previewFailed: Bool = false
    ) -> SeriesPreservationPrompt {
        SeriesPreservationPrompt(
            preview: preview,
            threshold: threshold,
            previewFailed: previewFailed
        )
    }

    @discardableResult
    static func ensureSavedForLaterQueue(in context: ModelContext) -> ReadingQueue {
        let descriptor = FetchDescriptor<ReadingQueue>(
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.dateCreated)
            ]
        )
        let queues = (try? context.fetch(descriptor)) ?? []
        let savedQueues = queues.filter { $0.kind == .savedForLater }
        if let primary = savedQueues.first {
            if primary.isPendingDeletion {
                PreservedWorkService.restore(primary, in: context)
            }
            primary.name = savedForLaterName
            primary.kind = .savedForLater
            primary.sortOrder = min(primary.sortOrder, -1000)
            primary.lastMembershipChangedAt = max(
                primary.lastMembershipChangedAt,
                primary.memberships.map(\.lastModifiedAt).max() ?? primary.dateCreated
            )

            for duplicate in savedQueues.dropFirst() {
                for membership in duplicate.memberships {
                    if let work = membership.work,
                       !primary.memberships.contains(where: { $0.work?.id == work.id }) {
                        membership.queue = primary
                        primary.memberships.append(membership)
                        primary.markMembershipChanged(max(membership.lastModifiedAt, Date()))
                    }
                }
                context.delete(duplicate)
            }
            context.saveBestEffort(reason: "Saving merged Saved for Later queue failed")
            return primary
        }

        let queue = ReadingQueue(
            name: savedForLaterName,
            kind: .savedForLater,
            sortOrder: -1000
        )
        context.insert(queue)
        context.saveBestEffort(reason: "Saving Saved for Later queue failed")
        return queue
    }

    /// The queue's works in display order (explicit sort order, then most
    /// recently queued), excluding soft-deleted works. The single ordering
    /// projection shared by the queue screen and Work Details' queue rows.
    /// Ordered active memberships for a queue (`T-528`), keeping tie-breaks
    /// identical to `orderedWorks(in:)`.
    static func orderedMemberships(in queue: ReadingQueue) -> [ReadingQueueMembership] {
        queue.memberships
            .filter { membership in
                !membership.isPendingDeletion
                    && !(membership.work?.isPendingDeletion ?? true)
            }
            .sorted {
                if $0.sortOrderInQueue != $1.sortOrderInQueue {
                    return $0.sortOrderInQueue < $1.sortOrderInQueue
                }
                return $0.queuedAt > $1.queuedAt
            }
    }

    /// Pre-fetched library slice for evaluating one or more smart queues without
    /// repeating `FetchDescriptor<SavedWork>()` or `TagAliasStore.resolver(in:)`.
    @MainActor
    struct SmartLibrarySnapshot {
        let eligible: [SavedWork]
        let facts: [SmartQueueWorkFacts]
        let byID: [UUID: SavedWork]
        let aliases: TagAliasResolver

        init(works: [SavedWork], aliases: TagAliasResolver = .empty) {
            let filtered = works.filter { !$0.isPendingDeletion && !$0.isQueueOnlyWork }
            eligible = filtered
            facts = filtered.map(SmartQueueWorkFacts.init(work:))
            byID = Dictionary(filtered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.aliases = aliases
        }

        init(in context: ModelContext) {
            let library = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
            self.init(works: library, aliases: TagAliasStore.resolver(in: context))
        }

        /// Evaluates `queue`'s rules against this snapshot. `include`, when given,
        /// runs before `document.limit` so hidden works cannot consume limit slots.
        func matching(
            _ queue: ReadingQueue,
            where include: ((SavedWork) -> Bool)? = nil
        ) -> [SavedWork] {
            guard queue.kind == .smart,
                  let document = SmartQueueRules.decode(queue.smartRulesJSON)
            else { return [] }
            let candidateFacts: [SmartQueueWorkFacts] = if let include {
                zip(eligible, facts).compactMap { work, fact in include(work) ? fact : nil }
            } else {
                facts
            }
            return document.matching(candidateFacts, aliases: aliases).compactMap { byID[$0.id] }
        }
    }

    /// `include` (smart queues only) runs before the rules' limit; pass the Hide
    /// Mature check wherever the result is counted or acted on.
    static func orderedWorks(in queue: ReadingQueue, where include: ((SavedWork) -> Bool)? = nil) -> [SavedWork] {
        if queue.kind == .smart {
            return smartWorks(in: queue, where: include)
        }
        return orderedMemberships(in: queue).compactMap(\.work)
    }

    /// `include` (smart queues only) runs before the rules' limit, so works the
    /// reader cannot see do not use up the limit; pass the Hide Mature check.
    static func orderedWorks(
        in queue: ReadingQueue,
        snapshot: SmartLibrarySnapshot,
        where include: ((SavedWork) -> Bool)? = nil
    ) -> [SavedWork] {
        if queue.kind == .smart {
            return snapshot.matching(queue, where: include)
        }
        return orderedMemberships(in: queue).compactMap(\.work)
    }

    /// Library works that match the queue's rules, in the document's order.
    /// A missing context, a nil document, or JSON this build cannot read
    /// matches nothing and does not rewrite `smartRulesJSON`.
    static func smartWorks(in queue: ReadingQueue, where include: ((SavedWork) -> Bool)? = nil) -> [SavedWork] {
        guard queue.kind == .smart, let context = queue.modelContext else { return [] }
        return SmartLibrarySnapshot(in: context).matching(queue, where: include)
    }

    /// `hue` is 1j's colour swatch: `nil` leaves the queue taking its colour from
    /// its name, which is what every queue did before the swatches existed.
    /// 1j's create step, including its seed: "an empty queue is the one thing you
    /// never actually want".
    ///
    /// Seeding COPIES rather than moves — a work stays in Saved for Later as well
    /// as joining the new queue. Moving would make creating a queue quietly empty
    /// another one, which is not what "start from" says.
    ///
    /// `id` lets New Queue hand over the draft id its preview cover already used;
    /// `nil` mints a fresh `UUID`.
    ///
    /// `keepsWorksOffline` is written as a real choice because the sheet asked:
    /// `nil` on the model means "never asked", and this reader was.
    static func createQueue(
        id: UUID? = nil,
        named rawName: String,
        hue: Double? = nil,
        colorHex: String? = nil,
        keepsWorksOffline: Bool? = nil,
        seededFrom seed: NewQueueSeed = .empty,
        tagNames: [String] = [],
        seedWorkIDs: [UUID] = [],
        smartRulesJSON: String? = nil,
        in context: ModelContext
    ) -> ReadingQueue {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Membership `add` saves as it goes. Hold the commit until the queue
        // and every seeded membership are in, so a failed Create cannot leave a
        // committed prefix that a retry would duplicate.
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }

        let isSmart = smartRulesJSON != nil
        let queue = ReadingQueue(
            id: id ?? UUID(),
            name: trimmed.isEmpty ? "Reading Queue" : trimmed,
            kind: isSmart ? .smart : .custom,
            sortOrder: nextQueueSortOrder(in: context)
        )
        queue.hue = hue
        queue.colorHex = colorHex
        // A smart queue is a list of matches. `nil` would mean "never asked",
        // and a never-asked queue keeps its works (`KeepOffline.queueKeeps`).
        queue.keepsWorksOffline = isSmart ? false : keepsWorksOffline
        queue.smartRulesJSON = smartRulesJSON
        context.insert(queue)
        // 1j's tags, through the same lookup-before-create `QueueTagSheet` uses.
        // Its fetch sees pending inserts, so a tag made for an earlier name is
        // found by a later one.
        for name in tagNames {
            queue.addTag(named: name, in: context)
        }
        // Smart queues have no members to seed. The rules decide the list.
        if !isSmart, seed == .savedForLater {
            seedFromSavedForLater(into: queue, in: context)
        }
        // Works picked in the sheet, after a Saved for Later copy. `append`
        // skips anyone already in the queue, and a queue-only record is not a
        // library work the picker is allowed to add.
        if !isSmart, !seedWorkIDs.isEmpty {
            let library = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
            let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let picked = seedWorkIDs.compactMap { byID[$0] }.filter {
                !$0.isPendingDeletion && !$0.isQueueOnlyWork
            }
            append(
                picked,
                to: queue,
                state: .new,
                origin: ReadingQueueMembershipOrigin(kind: .manual),
                in: context
            )
        }
        guard previousAutosave else { return queue }
        context.autosaveEnabled = previousAutosave
        // One save. On failure the inserts stay pending so the sheet's
        // `saveBestEffort` + `rollback` can drop the whole prefix; an
        // in-method rollback would make that second save a success on an
        // empty context and the sheet would close as if Create worked.
        context.saveBestEffort(reason: "Saving reading queue failed")
        return queue
    }

    /// "Edit Queue": the New queue sheet's fields written onto an existing
    /// queue. A blank name keeps the old one; tags not in `options.tagNames`
    /// come off the queue only (they stay on their works). Offline is written
    /// only when it changes, so a never-asked queue stays never-asked. Returns
    /// true when Keep works offline was turned on, so the caller can fetch the
    /// works still missing their EPUB (`preserveMissingWorks`).
    @discardableResult
    static func updateQueue(
        _ queue: ReadingQueue,
        name rawName: String,
        hue: Double?,
        options: NewQueueOptions,
        in context: ModelContext
    ) -> Bool {
        var changed = false
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != queue.name {
            queue.name = trimmed
            changed = true
        }
        if queue.hue != hue || queue.colorHex != options.colorHex {
            queue.hue = hue
            queue.colorHex = options.colorHex
            changed = true
        }
        let wasKept = KeepOffline.queueKeeps(queue.keepsWorksOffline)
        if queue.kind == .smart {
            // Keep-offline does not apply. A stored `nil` would start keeping.
            if queue.keepsWorksOffline != false {
                queue.keepsWorksOffline = false
                changed = true
            }
            if let json = options.smartRulesJSON, json != queue.smartRulesJSON {
                queue.smartRulesJSON = json
                changed = true
            }
        } else if options.keepsWorksOffline != wasKept {
            queue.keepsWorksOffline = options.keepsWorksOffline
            changed = true
        }
        // `addTag` / `removeTag` stamp the queue themselves.
        for tag in queue.tags where !options.tagNames.contains(tag.name) {
            queue.removeTag(tag)
        }
        for name in options.tagNames {
            queue.addTag(named: name, in: context)
        }
        if queue.kind != .smart, syncSearchLinks(for: queue, searchIDs: options.searchIDs, in: context) {
            changed = true
        }
        if changed { queue.markModified() }
        context.saveBestEffort(reason: "Saving queue changes failed")
        if queue.kind == .smart { return false }
        return options.keepsWorksOffline && !wasKept
    }

    private static func syncSearchLinks(
        for queue: ReadingQueue,
        searchIDs: [UUID],
        in context: ModelContext
    ) -> Bool {
        var sourcesChanged = false
        for link in queue.searchLinks where link.search.map({ !searchIDs.contains($0.id) }) ?? true {
            context.delete(link)
            sourcesChanged = true
        }
        let linkedIDs = Set(queue.searchLinks.compactMap { $0.search?.id })
        if let searches = try? context.fetch(FetchDescriptor<SavedSearch>()) {
            for search in searches where searchIDs.contains(search.id) && !linkedIDs.contains(search.id) {
                if search.lastOpenedAt == nil {
                    search.lastOpenedAt = Date()
                    FolderSyncService.markDirty()
                }
                context.insert(QueueSavedSearchLink(queue: queue, search: search))
                sourcesChanged = true
            }
        }
        if sourcesChanged { queue.searchSourcesModifiedAt = Date() }
        return sourcesChanged
    }

    /// Keep works offline turned on: fetches the works still missing their
    /// EPUB, one at a time through the paced client. Only that tap starts it:
    /// nothing polls.
    static func preserveMissingWorks(in queue: ReadingQueue, context: ModelContext) {
        guard queue.kind != .smart else { return }
        let missing = orderedWorks(in: queue).filter { !$0.hasEPUB && !$0.isPendingDeletion }
        guard !missing.isEmpty else { return }
        Task {
            for work in missing {
                try? await preserve(work, in: context)
            }
        }
    }

    /// How many works `.savedForLater` seeding would actually copy, so 1j's
    /// "Copy all N" can name a number rather than a vague promise.
    ///
    /// Deliberately NOT `ensureSavedForLaterQueue`, which renames the queue,
    /// merges duplicates and can insert one — a sheet previewing a choice must
    /// not write. It unions `orderedWorks` across every `.savedForLater` queue,
    /// which is the set `ensureSavedForLaterQueue` merges into one before
    /// `seedFromSavedForLater` walks it through the same projection. Built on
    /// `orderedWorks` so it agrees with the Saved for Later queue card beside
    /// the sheet, which counts the same way — including dropping a work sitting
    /// in Recently Deleted, whose membership `softDelete` leaves in place.
    static func savedForLaterSeedCount(in context: ModelContext) -> Int {
        let queues = (try? context.fetch(FetchDescriptor<ReadingQueue>())) ?? []
        var seen = Set<UUID>()
        for queue in queues where queue.kind == .savedForLater {
            for work in orderedWorks(in: queue) { seen.insert(work.id) }
        }
        return seen.count
    }

    /// Order is preserved: the new queue reads in the order Saved for Later
    /// *shows*, because it walks the same `orderedWorks` projection the queue
    /// screen draws. It used to sort on `sortOrderInQueue` alone, which left
    /// ties — which `ensureSavedForLaterQueue` creates when it merges a
    /// duplicate queue's memberships in with their old orders — to the
    /// relationship array's unordered fetch, and copied works sitting in
    /// Recently Deleted that the queue screen hides.
    private static func seedFromSavedForLater(into queue: ReadingQueue, in context: ModelContext) {
        for sourceMembership in orderedMemberships(in: ensureSavedForLaterQueue(in: context)) {
            guard let work = sourceMembership.work else { continue }
            _ = add(
                work,
                to: queue,
                state: sourceMembership.state,
                origin: sourceMembership.origin,
                in: context
            )
        }
    }

    static func normalizeAllQueuedWorks(in context: ModelContext) {
        let memberships = (try? context.fetch(FetchDescriptor<ReadingQueueMembership>())) ?? []
        for membership in memberships where membership.queue == nil || membership.work == nil {
            membership.queue?.memberships.removeAll { $0.id == membership.id }
            membership.work?.queueMemberships.removeAll { $0.id == membership.id }
            context.delete(membership)
        }

        // Only walk works that participate in queues (or still claim queue flags).
        // A full-library `fileExists` pass was hitching launch and tab switches on
        // large libraries — non-queued works don't need EPUB preservation reconcile here.
        var seen = Set<UUID>()
        for membership in memberships {
            guard let work = membership.work, seen.insert(work.id).inserted else { continue }
            normalize(work)
        }
        // Catch stale `isQueuedForLater` rows that lost their memberships without a prior
        // normalize (orphaned flag) — still a tiny set vs the whole library.
        let staleDescriptor = FetchDescriptor<SavedWork>(
            predicate: #Predicate { $0.isQueuedForLater }
        )
        let flagged = (try? context.fetch(staleDescriptor)) ?? []
        for work in flagged where seen.insert(work.id).inserted {
            normalize(work)
        }
        context.saveBestEffort(reason: "Saving queue normalization failed")
    }

    static func normalize(_ work: SavedWork) {
        if work.ao3WorkID == nil {
            work.ao3WorkID = WorkTags.ao3WorkID(from: work.sourceURL)
        }
        if work.ao3SeriesID == nil {
            work.ao3SeriesID = ao3SeriesID(from: work.seriesURL)
        }

        let hasMembership = work.queueMemberships.contains { $0.queue != nil }
        work.isQueuedForLater = hasMembership

        let hasFile = FileManager.default.fileExists(atPath: work.fileURL.path)
        if !hasFile {
            work.hasEPUB = false
            if work.epubPreservationStatus == .preserved {
                work.epubPreservationStatus = .missingFile
            }
        }

        if hasMembership {
            if work.hasEPUB, hasFile {
                if work.epubPreservationStatus != .preserving {
                    work.epubPreservationStatus = .preserved
                }
                if work.preservedAt == nil { work.preservedAt = Date() }
            } else if work.epubPreservationStatus == .notPreserved {
                work.epubPreservationStatus = .queued
            }
            if work.metadataSyncStatus == .unknown, work.needsAO3Refresh {
                work.metadataSyncStatus = .pending
            }
        } else if work.epubPreservationStatus != .notPreserved {
            work.epubPreservationStatus = .notPreserved
            work.preservedAt = nil
        }
    }

    @discardableResult
    static func add(
        _ work: SavedWork,
        to queue: ReadingQueue,
        state: ReadingQueueMembershipState = .inLine,
        origin: ReadingQueueMembershipOrigin? = nil,
        in context: ModelContext
    ) -> ReadingQueueMembership {
        if queue.kind == .smart {
            return refusedSmartMembership(work, queue: queue, state: state, origin: origin, in: context)
        }
        if work.knownChapterCount == 0, work.postedChapterCount > 0 {
            work.knownChapterCount = work.postedChapterCount
        }
        if let existing = work.queueMemberships.first(where: { $0.queue?.id == queue.id }) {
            normalize(work)
            return existing
        }

        let membership = ReadingQueueMembership(
            queue: queue,
            work: work,
            sortOrderInQueue: nextMembershipSortOrder(in: queue),
            state: state,
            origin: origin
        )
        context.insert(membership)
        queue.memberships.append(membership)
        work.queueMemberships.append(membership)
        let now = Date()
        queue.markMembershipChanged(now)
        membership.markModified(now)
        work.markModified(now)
        work.isQueuedForLater = true
        normalize(work)
        context.saveBestEffort(reason: "Saving queue membership failed")
        return membership
    }

    /// A smart queue has no memberships. Returning a detached value with nil
    /// endpoints avoids mutating managed inverses or dirtying `ModelContext`.
    private static func refusedSmartMembership(
        _ work: SavedWork,
        queue: ReadingQueue,
        state: ReadingQueueMembershipState,
        origin: ReadingQueueMembershipOrigin?,
        in _: ModelContext
    ) -> ReadingQueueMembership {
        ReadingQueueMembership(
            queue: nil,
            work: nil,
            sortOrderInQueue: 0,
            state: state,
            origin: origin
        )
    }

    /// Moves one or more `New` memberships into `In line` at the end of the
    /// reader's order (`T-528`), bumping sync timestamps so the change replicates.
    static func sortIntoLine(
        _ memberships: [ReadingQueueMembership],
        in queue: ReadingQueue,
        context: ModelContext
    ) {
        guard queue.kind != .smart else { return }
        let candidates = memberships.filter {
            $0.queue?.id == queue.id && !$0.isPendingDeletion && $0.state != .inLine
        }
        guard !candidates.isEmpty else { return }
        let now = Date()
        var nextOrder = nextMembershipSortOrder(in: queue)
        for membership in candidates {
            membership.state = .inLine
            membership.stateWasRecorded = true
            membership.sortOrderInQueue = nextOrder
            nextOrder += 1
            membership.markModified(now)
        }
        queue.markMembershipChanged(now)
        FolderSyncService.markDirty()
        context.saveBestEffort(reason: "Sorting queue items into line failed")
    }

    static func sortIntoLine(
        _ membership: ReadingQueueMembership,
        in queue: ReadingQueue,
        context: ModelContext
    ) {
        sortIntoLine([membership], in: queue, context: context)
    }

    static func move(
        _ works: [SavedWork],
        from source: ReadingQueue,
        to destination: ReadingQueue,
        state: ReadingQueueMembershipState? = nil,
        origin: ReadingQueueMembershipOrigin? = nil,
        in context: ModelContext
    ) {
        guard source.id != destination.id else { return }
        // Moving onto or off a smart queue cannot write or remove memberships.
        guard source.kind != .smart, destination.kind != .smart else { return }
        for work in works {
            let sourceMembership = work.queueMemberships.first { $0.queue?.id == source.id }
            let resolvedState = state ?? sourceMembership?.state ?? .inLine
            let resolvedOrigin = origin ?? sourceMembership?.origin
            add(work, to: destination, state: resolvedState, origin: resolvedOrigin, in: context)
            removeFromQueueAndDeleteIfQueueOnly(work, from: source, in: context)
        }
    }

    /// 1h's library picker offers these: real Library works (queue-only
    /// preservation records excluded, as `CollectionWorkPicker.candidates` does)
    /// not already in `queue`.
    static func appendCandidates(from works: [SavedWork], notIn queue: ReadingQueue) -> [SavedWork] {
        guard queue.kind != .smart else { return [] }
        return works.filter { work in
            !work.isQueueOnlyWork
                && !work.queueMemberships.contains { $0.queue?.id == queue.id }
        }
    }

    /// 1h's "Add N": each work goes on the end of `queue`, in the order given,
    /// through `add` — which skips a work already in the queue. `add`, not
    /// `addAndPreserve`: picking from the Library is a membership change and
    /// must not fetch from AO3. A work whose copy is missing is left `.queued`
    /// for the queue's own offline rules to handle.
    static func append(
        _ works: [SavedWork],
        to queue: ReadingQueue,
        state: ReadingQueueMembershipState = .new,
        origin: ReadingQueueMembershipOrigin? = nil,
        in context: ModelContext
    ) {
        for work in works {
            _ = add(work, to: queue, state: state, origin: origin, in: context)
        }
    }

    @discardableResult
    static func addAndPreserve(
        _ work: SavedWork,
        to queue: ReadingQueue,
        state: ReadingQueueMembershipState = .inLine,
        origin: ReadingQueueMembershipOrigin? = nil,
        in context: ModelContext
    ) async -> ReadingQueueMembership {
        let membership = add(work, to: queue, state: state, origin: origin, in: context)
        // A smart queue never downloads. `add` already refused the membership.
        guard queue.kind != .smart else { return membership }
        // T-276: a queue with Keep downloaded off is just a list; nothing is fetched.
        guard KeepOffline.queueKeeps(queue.keepsWorksOffline) else { return membership }
        do {
            try await preserve(work, in: context)
        } catch {
            // User-facing callers keep the queue membership and surface the
            // preservation state on the work instead of throwing out of the UI.
        }
        return membership
    }

    /// Save for Later on, or off — the one toggle every row and menu shares.
    /// Taking a work off removes a queue-only record with it, as the queue does.
    @MainActor
    static func toggleSavedForLater(
        _ work: SavedWork,
        origin: ReadingQueueMembershipOrigin = ReadingQueueMembershipOrigin(kind: .manual),
        in context: ModelContext
    ) {
        if work.isInSavedForLaterQueue {
            removeFromQueueAndDeleteIfQueueOnly(work, from: ensureSavedForLaterQueue(in: context), in: context)
        } else {
            // Discard membership: Task must not inherit a non-Sendable PersistentModel result.
            Task { @MainActor in
                _ = await addToSavedForLater(work, state: .inLine, origin: origin, in: context)
            }
        }
    }

    @discardableResult
    static func addToSavedForLater(
        _ work: SavedWork,
        state: ReadingQueueMembershipState = .inLine,
        origin: ReadingQueueMembershipOrigin? = nil,
        in context: ModelContext
    ) async -> ReadingQueueMembership {
        let queue = ensureSavedForLaterQueue(in: context)
        return await addAndPreserve(work, to: queue, state: state, origin: origin, in: context)
    }

    static func addToSavedForLater(
        _ summary: AO3WorkSummary,
        state: ReadingQueueMembershipState = .inLine,
        origin: ReadingQueueMembershipOrigin? = nil,
        in context: ModelContext,
        downloadEPUB: ((Int) async throws -> URL)? = nil
    ) async throws -> SavedWork {
        let saved: SavedWork
        let createdNewWork: Bool
        if let existing = existingWork(for: summary, in: context) {
            // Same revival rule as addAndPreserveSummary — never queue a record that
            // stays scheduled for permanent deletion.
            if existing.isPendingDeletion {
                PreservedWorkService.restore(existing, in: context)
            }
            saved = existing
            createdNewWork = false
        } else {
            saved = SavedWork(
                title: summary.title,
                author: summary.authorText,
                summary: summary.summary,
                sourceURL: summary.workURL.absoluteString
            )
            saved.ao3WorkID = summary.id
            saved.knownChapterCount = SavedWork.postedChapterCount(from: summary.chapters)
            context.insert(saved)
            createdNewWork = true
        }

        saved.ao3WorkID = summary.id
        applyRemoteMetadata(summary, to: saved)
        if createdNewWork { saved.isSaved = false }
        let queue = ensureSavedForLaterQueue(in: context)
        _ = add(saved, to: queue, state: state, origin: origin, in: context)
        try context.save()
        try await preserve(saved, in: context, downloadEPUB: downloadEPUB)
        return saved
    }

    static func preserve(
        _ work: SavedWork,
        in context: ModelContext,
        downloadEPUB: ((Int) async throws -> URL)? = nil
    ) async throws {
        normalize(work)
        guard work.isQueuedForLater else { return }

        work.lastPreservationAttemptAt = Date()
        let existingFile = FileManager.default.fileExists(atPath: work.fileURL.path)
        if work.hasEPUB, existingFile {
            work.epubPreservationStatus = .preserved
            work.preservedAt = Date()
            try context.save()
            await syncMetadata(for: work, in: context)
            return
        }

        guard let id = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) else {
            work.epubPreservationStatus = .failed
            work.metadataSyncStatus = .incomplete
            try context.save()
            return
        }

        work.ao3WorkID = id
        work.epubPreservationStatus = .preserving
        try context.save()

        do {
            let temp: URL = if let downloadEPUB {
                try await downloadEPUB(id)
            } else {
                try await AO3Client.shared.downloadEPUB(workID: id)
            }
            try replaceEPUB(for: work, with: temp)
            work.hasEPUB = true
            work.epubPreservationStatus = .preserved
            work.preservedAt = Date()
            work.lastAvailabilityCheck = Date()
            await AO3EPUBChapterWordCounter.populate(for: work, force: true)
            try context.save()
            await WorkTags.backfillFromEPUB(for: work, in: context)
            await syncMetadata(for: work, in: context)
        } catch is CancellationError {
            work.epubPreservationStatus = work.hasEPUB
                && FileManager.default.fileExists(atPath: work.fileURL.path) ? .preserved : .queued
            try context.save()
            throw CancellationError()
        } catch AO3Error.notFound {
            work.ao3Unavailable = true
            work.epubPreservationStatus = .failed
            work.metadataSyncStatus = .failed
            try context.save()
        } catch {
            let message = error.localizedDescription
            Log.library.error(
                "Queue preserve failed for \(work.id.uuidString, privacy: .public): \(message, privacy: .private)"
            )
            work.epubPreservationStatus = .failed
            try context.save()
        }
    }

    static func syncMetadata(for work: SavedWork, in context: ModelContext) async {
        normalize(work)
        guard work.ao3WorkID != nil || WorkTags.ao3WorkID(from: work.sourceURL) != nil else {
            work.metadataSyncStatus = work.workTags.isEmpty ? .incomplete : .complete
            context.saveBestEffort(reason: "Saving queue metadata status failed")
            return
        }
        guard work.needsAO3Refresh else {
            work.metadataSyncStatus = .complete
            context.saveBestEffort(reason: "Saving queue metadata completion failed")
            return
        }

        work.metadataSyncStatus = .syncing
        context.saveBestEffort(reason: "Saving queue metadata sync start failed")
        await WorkTags.refreshFromAO3(for: work, in: context)
        if work.needsAO3Refresh {
            work.metadataSyncStatus = work.ao3Unavailable ? .failed : .incomplete
        } else {
            work.metadataSyncStatus = .complete
        }
        context.saveBestEffort(reason: "Saving queue metadata sync result failed")
    }

    static func preserveSeries(
        anchoredAt anchor: SavedWork,
        to queues: [ReadingQueue]? = nil,
        state: ReadingQueueMembershipState = .new,
        origin: ReadingQueueMembershipOrigin? = nil,
        in context: ModelContext,
        pauseNanos: UInt64 = preservationRequestPauseNanos,
        progress: ((SeriesPreservationResult) -> Void)? = nil
    ) async -> SeriesPreservationResult {
        guard let url = URL(string: anchor.seriesURL), !anchor.seriesURL.isEmpty else {
            return SeriesPreservationResult()
        }

        do {
            let summaries = try await AO3Client.shared.seriesWorks(seriesURL: url)
            return await preserveSeries(
                summaries,
                to: queues,
                state: state,
                origin: origin,
                in: context,
                pauseNanos: pauseNanos,
                progress: progress
            )
        } catch is CancellationError {
            return SeriesPreservationResult(cancelled: 1)
        } catch {
            Log.library.error(
                "Couldn't load series for queue preservation: \(error.localizedDescription, privacy: .public)"
            )
            return SeriesPreservationResult(failed: 1)
        }
    }

    // Series preservation keeps its accounting in one place for safety.
    // swiftlint:disable:next cyclomatic_complexity
    static func preserveSeries(
        _ summaries: [AO3WorkSummary],
        to queues: [ReadingQueue]? = nil,
        state: ReadingQueueMembershipState = .new,
        origin: ReadingQueueMembershipOrigin? = nil,
        in context: ModelContext,
        preserveWork: SeriesWorkPreserver? = nil,
        pauseNanos: UInt64 = preservationRequestPauseNanos,
        progress: ((SeriesPreservationResult) -> Void)? = nil
    ) async -> SeriesPreservationResult {
        var result = SeriesPreservationResult(total: summaries.count)
        let targetQueues = (queues ?? [ensureSavedForLaterQueue(in: context)]).filter { $0.kind != .smart }
        progress?(result)

        for summary in summaries {
            if Task.isCancelled {
                result.cancelled += max(0, result.total - result.completed)
                progress?(result)
                break
            }

            if targetQueues.isEmpty {
                result.skipped += 1
                progress?(result)
                continue
            }

            if let existing = existingWork(for: summary, in: context) {
                // Revive before any branch below can `continue` — a series preserve
                // that touches a Recently Deleted record must never leave it
                // scheduled for permanent deletion.
                if existing.isPendingDeletion {
                    PreservedWorkService.restore(existing, in: context)
                }
                if existing.ao3Unavailable {
                    result.unavailable += 1
                    progress?(result)
                    continue
                }
                if existing.epubPreservationStatus == .preserved,
                   targetQueues.allSatisfy({ queue in
                       existing.queueMemberships.contains { $0.queue?.id == queue.id }
                   }) {
                    result.alreadyPreserved += 1
                    progress?(result)
                    continue
                }
                if existing.epubPreservationStatus == .preserved {
                    for queue in targetQueues {
                        _ = add(existing, to: queue, state: state, origin: origin, in: context)
                    }
                    result.alreadyPreserved += 1
                    progress?(result)
                    continue
                }
            }

            do {
                try Task.checkCancellation()
                let saved: SavedWork = if let preserveWork {
                    try await preserveWork(summary, targetQueues, context)
                } else {
                    try await addAndPreserveSummary(
                        summary,
                        to: targetQueues,
                        state: state,
                        origin: origin,
                        in: context
                    )
                }
                if saved.ao3Unavailable {
                    result.unavailable += 1
                } else if saved.epubPreservationStatus == .preserved {
                    result.preserved += 1
                } else {
                    result.failed += 1
                }
            } catch is CancellationError {
                result.cancelled += max(1, result.total - result.completed)
                progress?(result)
                break
            } catch AO3Error.notFound {
                result.unavailable += 1
            } catch {
                result.failed += 1
            }
            progress?(result)

            guard result.completed < result.total else { continue }
            do {
                if pauseNanos > 0 {
                    try await Task.sleep(nanoseconds: pauseNanos)
                }
            } catch {
                result.cancelled += max(0, result.total - result.completed)
                progress?(result)
                break
            }
        }

        return result
    }

    @discardableResult
    private static func addAndPreserveSummary(
        _ summary: AO3WorkSummary,
        to queues: [ReadingQueue],
        state: ReadingQueueMembershipState = .new,
        origin: ReadingQueueMembershipOrigin? = nil,
        in context: ModelContext
    ) async throws -> SavedWork {
        let saved: SavedWork
        let createdNewWork: Bool
        if let existing = existingWork(for: summary, in: context) {
            // Queueing a work that's sitting in Recently Deleted revives it — a
            // pending-deletion record would otherwise be queued invisibly and then
            // swept for good when its recovery window lapses.
            if existing.isPendingDeletion {
                PreservedWorkService.restore(existing, in: context)
            }
            saved = existing
            createdNewWork = false
        } else {
            saved = SavedWork(
                title: summary.title,
                author: summary.authorText,
                summary: summary.summary,
                sourceURL: summary.workURL.absoluteString
            )
            saved.ao3WorkID = summary.id
            saved.knownChapterCount = SavedWork.postedChapterCount(from: summary.chapters)
            context.insert(saved)
            createdNewWork = true
        }

        saved.ao3WorkID = summary.id
        applyRemoteMetadata(summary, to: saved)
        if createdNewWork { saved.isSaved = false }
        for queue in queues {
            _ = add(saved, to: queue, state: state, origin: origin, in: context)
        }
        try context.save()
        try await preserve(saved, in: context)
        return saved
    }

    static func removeFromQueue(_ work: SavedWork, from queue: ReadingQueue, in context: ModelContext) {
        guard queue.kind != .smart else { return }
        let matches = work.queueMemberships.filter { $0.queue?.id == queue.id }
        for membership in matches {
            SyncTombstones.recordDeletion(of: membership, in: context)
            work.queueMemberships.removeAll { $0.id == membership.id }
            queue.memberships.removeAll { $0.id == membership.id }
            context.delete(membership)
        }
        let now = Date()
        queue.markMembershipChanged(now)
        work.markModified(now)
        work.isQueuedForLater = !work.queueMemberships.isEmpty
        normalize(work)
        context.saveBestEffort(reason: "Saving queue removal failed")
    }

    static func removeFromQueueAndDeleteIfQueueOnly(
        _ work: SavedWork,
        from queue: ReadingQueue,
        in context: ModelContext
    ) {
        let wasQueueOnly = work.isQueueOnlyWork
        removeFromQueue(work, from: queue, in: context)
        if wasQueueOnly, !work.isQueuedForLater, !work.isSaved, !work.isFavorite {
            PreservedWorkService.softDelete(work, in: context)
        }
    }

    static func removeFromAllQueues(_ work: SavedWork, in context: ModelContext) {
        let queues = work.queueMemberships.compactMap(\.queue)
        for queue in queues {
            removeFromQueue(work, from: queue, in: context)
        }
    }

    static func removeFromAllQueuesAndDeleteIfQueueOnly(_ work: SavedWork, in context: ModelContext) {
        let wasQueueOnly = work.isQueueOnlyWork
        removeFromAllQueues(work, in: context)
        if wasQueueOnly, !work.isQueuedForLater, !work.isSaved, !work.isFavorite {
            PreservedWorkService.softDelete(work, in: context)
        }
    }

    static func existingWork(for summary: AO3WorkSummary, in context: ModelContext) -> SavedWork? {
        let works = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
        return WorkIdentityIndex(works).existingWork(for: summary)
    }

    /// Instant local row for remote-card actions that should not wait on an EPUB
    /// download (Add to Queue / Collection sheets, Save flag flips, etc.).
    ///
    /// Reuses an existing match (reviving Recently Deleted when needed); otherwise
    /// inserts a metadata-only `SavedWork` (`hasEPUB = false`) from the search-page
    /// summary. EPUB download still happens later via `preserve` / Read / explicit
    /// download — never as a gate on presenting UI.
    ///
    /// Android parity: `WorkImporter.saveMetadataOnly`.
    @discardableResult
    static func ensureLocalMetadata(
        for summary: AO3WorkSummary,
        in context: ModelContext
    ) throws -> SavedWork {
        if let existing = existingWork(for: summary, in: context) {
            if existing.isPendingDeletion {
                PreservedWorkService.restore(existing, in: context)
            }
            applyRemoteMetadata(summary, to: existing)
            try context.save()
            return existing
        }

        let saved = SavedWork(
            title: summary.title,
            author: summary.authorText,
            summary: summary.summary,
            sourceURL: summary.workURL.absoluteString
        )
        saved.ao3WorkID = summary.id
        saved.knownChapterCount = SavedWork.postedChapterCount(from: summary.chapters)
        // No package on disk yet — preserve/Read will fetch later.
        saved.hasEPUB = false
        saved.isSaved = false
        applyRemoteMetadata(summary, to: saved)
        context.insert(saved)
        try context.save()
        return saved
    }

    /// Drops a metadata-only stub that never became a real library item: no EPUB,
    /// no queue/collection membership, not saved/favorited, never opened. Used when
    /// the user dismisses Add to Queue without picking anything so search → queue
    /// doesn't leave History ghosts.
    static func discardUnattachedMetadataIfNeeded(_ work: SavedWork, in context: ModelContext) {
        guard !work.isSaved,
              !work.isFavorite,
              !work.isFinished,
              !work.hasEPUB,
              work.queueMemberships.isEmpty,
              work.collections.isEmpty,
              work.lastReadDate == nil,
              work.readiumLocator.isEmpty,
              work.lastSpineIndex == 0,
              work.lastScrollFraction == 0
        else { return }
        context.delete(work)
        context.saveBestEffort(reason: "Discarding unattached metadata stub failed")
    }

    static func resolveLocalWork(for summary: AO3WorkSummary, in context: ModelContext) async throws -> SavedWork {
        if let existing = existingWork(for: summary, in: context) {
            // Acting on a remote card whose local twin sits in Recently Deleted
            // revives it — otherwise the action would mutate a hidden record still
            // scheduled for permanent deletion.
            if existing.isPendingDeletion {
                PreservedWorkService.restore(existing, in: context)
            }
            return existing
        }

        let temp = try await AO3Client.shared.downloadEPUB(workID: summary.id)
        let saved = try await importEPUB(
            temp,
            source: summary.workURL,
            isComplete: summary.isComplete ?? false,
            seriesURL: summary.seriesURL ?? "",
            knownChapterCount: SavedWork.postedChapterCount(from: summary.chapters),
            into: context
        )
        applyRemoteMetadata(summary, to: saved)
        if saved.coverRecipeJSON == nil || GeneratedCoverRecipe.isAutomaticPin(in: saved.coverRecipeJSON) {
            saved.pinCover(salt: 0, automatic: saved.workFandoms.isEmpty || saved.wordCount == 0)
        }
        try? context.save()
        return saved
    }

    // Metadata merge is a field-by-field guard sequence by design.
    // swiftlint:disable:next cyclomatic_complexity
    static func applyRemoteMetadata(_ summary: AO3WorkSummary, to work: SavedWork) {
        work.ao3WorkID = summary.id
        if work.author.isEmpty { work.author = summary.authorText }
        if !summary.authorIdentities.isEmpty {
            work.verifiedAuthorIdentities = summary.authorIdentities
        }
        if work.workFandoms.isEmpty { work.workFandoms = summary.fandoms }
        if work.rating.isEmpty { work.rating = summary.rating }
        if work.workWarnings.isEmpty { work.workWarnings = summary.warnings }
        if work.workCategories.isEmpty { work.workCategories = summary.categories }
        if work.workRelationships.isEmpty { work.workRelationships = summary.relationships }
        if work.workCharacters.isEmpty { work.workCharacters = summary.characters }
        if work.workFreeforms.isEmpty { work.workFreeforms = additionalTags(from: summary) }
        work.workTags = TagMerge.merged(
            work.workTags,
            work.workFandoms + work.workRelationships + work.workCharacters + work.workFreeforms
        )
        if work.kudos == 0, let kudos = summary.kudos { work.kudos = kudos }
        if work.comments == 0, let comments = summary.comments { work.comments = comments }
        if work.bookmarks == 0, let bookmarks = summary.bookmarks { work.bookmarks = bookmarks }
        if work.hits == 0, let hits = summary.hits { work.hits = hits }
        if work.wordCount == 0, let words = summary.words { work.wordCount = words }
        if work.chapters.isEmpty { work.chapters = summary.chapters }
        if work.language.isEmpty { work.language = summary.language }
        if work.dateUpdated.isEmpty { work.dateUpdated = summary.dateUpdated }
        if let complete = summary.isComplete { work.isComplete = complete }
        if work.seriesTitle.isEmpty { work.seriesTitle = summary.seriesTitle ?? "" }
        if work.seriesURL.isEmpty { work.seriesURL = summary.seriesURL ?? "" }
        if work.seriesPosition == 0 { work.seriesPosition = summary.seriesPosition ?? 0 }
        if work.ao3SeriesID == nil { work.ao3SeriesID = ao3SeriesID(from: work.seriesURL) }
        if work.coverRecipeJSON == nil { work.pinCover(salt: 0, automatic: true) }
        work.refreshCoverIfNeeded()
        work.markModified()
        WorkSearchIndex.reindex(work)
    }

    static func ao3SeriesID(from urlString: String) -> Int? {
        guard let url = URL(string: urlString, relativeTo: URL(string: "https://archiveofourown.org")),
              urlString.hasPrefix("/") || url.scheme != nil else { return nil }
        guard case let .series(id) = AO3Link(url.absoluteURL).kind else { return nil }
        return id
    }

    private static func additionalTags(from summary: AO3WorkSummary) -> [String] {
        let categorized = Set(
            (summary.fandoms + summary.warnings + summary.categories
                + summary.relationships + summary.characters)
                .map(TagMerge.key)
        )
        return summary.tags.filter { !categorized.contains(TagMerge.key($0)) }
    }

    static func replaceEPUB(for work: SavedWork, with temp: URL) throws {
        let destination = work.fileURL
        _ = try EPUBDocument.inspectPackage(ofEPUBAt: temp)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        #if os(iOS)
        NotificationCenter.default.post(name: .kudosWorkEPUBWillChange, object: work.id)
        #endif
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(
                destination,
                withItemAt: temp,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try FileManager.default.moveItem(at: temp, to: destination)
        }
        // The one place an EPUB is written, so the one place the cached content
        // identity can be kept honest. Every other caller — download, import,
        // reconversion, restore, sync — comes through here.
        let previousDigest = work.epubDigest
        let newDigest = Storage.fileDigest(at: destination) ?? ""
        work.epubDigest = newDigest
        if !previousDigest.isEmpty && !newDigest.isEmpty && newDigest != previousDigest {
            work.chapterWordCountsJSON = ""
            work.wordUnitRaw = ""
        }
        // The bytes arrived, so nothing is outstanding any more.
        work.remoteEPUBPending = false
    }

    private static func nextQueueSortOrder(in context: ModelContext) -> Int {
        let queues = (try? context.fetch(FetchDescriptor<ReadingQueue>())) ?? []
        return (queues.map(\.sortOrder).max() ?? 0) + 1
    }

    private static func nextMembershipSortOrder(in queue: ReadingQueue) -> Int {
        (queue.memberships.map(\.sortOrderInQueue).max() ?? -1) + 1
    }

    /// Pure index arithmetic for a single-step reorder (`ReadingQueueDetailView.moveWork(_:toIndex:)`,
    /// the compact grid's VoiceOver Move Up/Down/to Top/to Bottom actions) — extracted so the
    /// math is directly unit-testable without a `ModelContext`/SwiftUI. Mirrors
    /// `WorkReorderDropDelegate.dropEntered`'s direction convention: `toOffset` gets `+1` only
    /// when moving forward, matching `Array.move(fromOffsets:toOffset:)`'s contract that
    /// `toOffset` names a position in the array as it stood *before* the move. Returns `nil`
    /// when `requestedIndex` clamps to `currentIndex` (already at that boundary) — the safe
    /// no-op every accessibility action relies on to be attachable unconditionally.
    static func moveOffsets(currentIndex: Int, requestedIndex: Int, count: Int) -> (from: IndexSet, to: Int)? {
        guard count > 0 else { return nil }
        let clamped = max(0, min(requestedIndex, count - 1))
        guard clamped != currentIndex else { return nil }
        return (IndexSet(integer: currentIndex), clamped > currentIndex ? clamped + 1 : clamped)
    }

    /// Pure index arithmetic for the compact grid's live drag-over reorder
    /// (`WorkReorderDropDelegate.dropEntered`) — extracted for the same reason as
    /// `moveOffsets` above: directly unit-testable without a `ModelContext`/SwiftUI
    /// drag session, which simulator automation cannot reliably drive (A6-F1).
    /// `base` is the order the drag started from, or the accumulated preview from an
    /// earlier crossing in the same still-live gesture. Returns `base` unchanged when
    /// either id is absent from it, or when the drag is hovering its own source card
    /// (`draggedID == targetID`) — both safe no-ops callable unconditionally. Otherwise
    /// replicates `RangeReplaceableCollection.move(fromOffsets:toOffset:)`'s single-
    /// element semantics by hand — that SwiftUI extension isn't available here, and
    /// this file deliberately doesn't import SwiftUI (a service layer, not a view).
    /// `toOffset` gets `+1` only when moving forward, same convention `moveOffsets` uses;
    /// removing the dragged element first shifts every later index down by one, so the
    /// insert position is `toOffset - 1` whenever the move is forward (`toOffset` sits
    /// past the removed element), else `toOffset` unchanged.
    static func reorderedIDs(base: [UUID], moving draggedID: UUID, over targetID: UUID) -> [UUID] {
        guard draggedID != targetID,
              let fromIndex = base.firstIndex(of: draggedID),
              let toIndex = base.firstIndex(of: targetID)
        else { return base }
        let toOffset = toIndex > fromIndex ? toIndex + 1 : toIndex
        var ids = base
        let dragged = ids.remove(at: fromIndex)
        ids.insert(dragged, at: toOffset > fromIndex ? toOffset - 1 : toOffset)
        return ids
    }

    /// Applies a user-dragged reorder of a queue's works. `workIDs` is the full,
    /// unfiltered work list in its new order; each matching membership's
    /// `sortOrderInQueue` is rewritten to its index, so the same ordering survives
    /// relaunch, backup/restore, and sync exactly like the existing sort already does.
    static func reorder(_ workIDs: [UUID], in queue: ReadingQueue, context: ModelContext) {
        guard queue.kind != .smart else { return }
        let membershipsByWorkID = Dictionary(
            queue.memberships.compactMap { membership in
                membership.work.map { ($0.id, membership) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        for (index, workID) in workIDs.enumerated() {
            guard let membership = membershipsByWorkID[workID] else { continue }
            membership.sortOrderInQueue = index
            // Each reordered membership is its own sync record — flip it to .pending
            // too, not just the queue's own timestamp, so the new order actually syncs.
            membership.markModified()
        }
        queue.markMembershipChanged()
        context.saveBestEffort(reason: "Saving queue reorder failed")
    }
}
