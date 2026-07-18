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
                return "Kudos couldn't confirm the series size. Preserve the entire series only if "
                    + "you are comfortable with a larger AO3 request, paced one work at a time."
            }
            if canUsePreviewForPreservation {
                return "This series has \(knownCount) work\(knownCount == 1 ? "" : "s"). "
                    + "Preserve the entire series?"
            }
            return "This series has at least \(knownCount) work\(knownCount == 1 ? "" : "s") "
                + "and may span multiple pages. Preserve the entire series?"
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
    static func orderedWorks(in queue: ReadingQueue) -> [SavedWork] {
        queue.memberships
            .sorted {
                if $0.sortOrderInQueue != $1.sortOrderInQueue {
                    return $0.sortOrderInQueue < $1.sortOrderInQueue
                }
                return $0.queuedAt > $1.queuedAt
            }
            .compactMap(\.work)
            .filter { !$0.isPendingDeletion }
    }

    static func createQueue(named rawName: String, in context: ModelContext) -> ReadingQueue {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let queue = ReadingQueue(
            name: trimmed.isEmpty ? "Reading Queue" : trimmed,
            kind: .custom,
            sortOrder: nextQueueSortOrder(in: context)
        )
        context.insert(queue)
        context.saveBestEffort(reason: "Saving reading queue failed")
        return queue
    }

    static func normalizeAllQueuedWorks(in context: ModelContext) {
        let memberships = (try? context.fetch(FetchDescriptor<ReadingQueueMembership>())) ?? []
        for membership in memberships where membership.queue == nil || membership.work == nil {
            membership.queue?.memberships.removeAll { $0.id == membership.id }
            membership.work?.queueMemberships.removeAll { $0.id == membership.id }
            context.delete(membership)
        }

        let works = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
        for work in works {
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
        in context: ModelContext
    ) -> ReadingQueueMembership {
        if let existing = work.queueMemberships.first(where: { $0.queue?.id == queue.id }) {
            normalize(work)
            return existing
        }

        let membership = ReadingQueueMembership(
            queue: queue,
            work: work,
            sortOrderInQueue: nextMembershipSortOrder(in: queue)
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

    @discardableResult
    static func addAndPreserve(
        _ work: SavedWork,
        to queue: ReadingQueue,
        in context: ModelContext
    ) async -> ReadingQueueMembership {
        let membership = add(work, to: queue, in: context)
        do {
            try await preserve(work, in: context)
        } catch {
            // User-facing callers keep the queue membership and surface the
            // preservation state on the work instead of throwing out of the UI.
        }
        return membership
    }

    @discardableResult
    static func addToSavedForLater(_ work: SavedWork, in context: ModelContext) async -> ReadingQueueMembership {
        let queue = ensureSavedForLaterQueue(in: context)
        return await addAndPreserve(work, to: queue, in: context)
    }

    static func addToSavedForLater(
        _ summary: AO3WorkSummary,
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
        _ = add(saved, to: queue, in: context)
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
                "Queue preserve failed for \(work.id.uuidString, privacy: .public): \(message, privacy: .public)"
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
        in context: ModelContext,
        preserveWork: SeriesWorkPreserver? = nil,
        pauseNanos: UInt64 = preservationRequestPauseNanos,
        progress: ((SeriesPreservationResult) -> Void)? = nil
    ) async -> SeriesPreservationResult {
        var result = SeriesPreservationResult(total: summaries.count)
        let targetQueues = queues ?? [ensureSavedForLaterQueue(in: context)]
        progress?(result)

        for summary in summaries {
            if Task.isCancelled {
                result.cancelled += max(0, result.total - result.completed)
                progress?(result)
                break
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
                        _ = add(existing, to: queue, in: context)
                    }
                    result.alreadyPreserved += 1
                    progress?(result)
                    continue
                }
            }

            if targetQueues.isEmpty {
                result.skipped += 1
                progress?(result)
                continue
            }

            do {
                try Task.checkCancellation()
                let saved = try await (preserveWork ?? addAndPreserveSummary)(summary, targetQueues, context)
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
            _ = add(saved, to: queue, in: context)
        }
        try context.save()
        try await preserve(saved, in: context)
        return saved
    }

    static func removeFromQueue(_ work: SavedWork, from queue: ReadingQueue, in context: ModelContext) {
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
        work.markModified()
        WorkSearchIndex.reindex(work)
    }

    static func ao3SeriesID(from urlString: String) -> Int? {
        guard let url = URL(string: urlString) else { return nil }
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "series"), index + 1 < parts.count else { return nil }
        return Int(parts[index + 1])
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
    }

    private static func nextQueueSortOrder(in context: ModelContext) -> Int {
        let queues = (try? context.fetch(FetchDescriptor<ReadingQueue>())) ?? []
        return (queues.map(\.sortOrder).max() ?? 0) + 1
    }

    private static func nextMembershipSortOrder(in queue: ReadingQueue) -> Int {
        (queue.memberships.map(\.sortOrderInQueue).max() ?? -1) + 1
    }

    /// Applies a user-dragged reorder of a queue's works. `workIDs` is the full,
    /// unfiltered work list in its new order; each matching membership's
    /// `sortOrderInQueue` is rewritten to its index, so the same ordering survives
    /// relaunch, backup/restore, and sync exactly like the existing sort already does.
    static func reorder(_ workIDs: [UUID], in queue: ReadingQueue, context: ModelContext) {
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
