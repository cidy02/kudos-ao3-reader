import Foundation
import OSLog
import SwiftData

@MainActor
enum ReadingQueueService {
    static let savedForLaterName = "Saved for Later"

    struct SeriesPreservationResult: Equatable {
        var total = 0
        var preserved = 0
        var skipped = 0
        var failed = 0
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
            primary.sortOrder = min(primary.sortOrder, -1_000)

            for duplicate in savedQueues.dropFirst() {
                for membership in duplicate.memberships {
                    if let work = membership.work,
                       !primary.memberships.contains(where: { $0.work?.id == work.id }) {
                        membership.queue = primary
                        primary.memberships.append(membership)
                    }
                }
                context.delete(duplicate)
            }
            try? context.save()
            return primary
        }

        let queue = ReadingQueue(
            name: savedForLaterName,
            kind: .savedForLater,
            sortOrder: -1_000
        )
        context.insert(queue)
        try? context.save()
        return queue
    }

    static func createQueue(named rawName: String, in context: ModelContext) -> ReadingQueue {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let queue = ReadingQueue(
            name: trimmed.isEmpty ? "Reading Queue" : trimmed,
            kind: .custom,
            sortOrder: nextQueueSortOrder(in: context)
        )
        context.insert(queue)
        try? context.save()
        return queue
    }

    static func normalizeAllQueuedWorks(in context: ModelContext) {
        let savedForLater = ensureSavedForLaterQueue(in: context)
        let works = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
        for work in works {
            if work.isQueuedForLater && work.queueMemberships.isEmpty {
                add(work, to: savedForLater, in: context)
            } else {
                normalize(work)
            }
        }
        try? context.save()
    }

    static func normalize(_ work: SavedWork) {
        if work.ao3WorkID == nil {
            work.ao3WorkID = WorkTags.ao3WorkID(from: work.sourceURL)
        }
        if work.ao3SeriesID == nil {
            work.ao3SeriesID = ao3SeriesID(from: work.seriesURL)
        }

        let hasFile = FileManager.default.fileExists(atPath: work.fileURL.path)
        if work.hasEPUB && !hasFile {
            work.hasEPUB = false
            if work.isQueuedForLater {
                work.epubPreservationStatus = .missingFile
            }
        }

        let hasMembership = !work.queueMemberships.isEmpty
        work.isQueuedForLater = hasMembership || work.isQueuedForLater
        if work.isQueuedForLater {
            if work.hasEPUB && hasFile {
                if work.epubPreservationStatus != .preserving {
                    work.epubPreservationStatus = .preserved
                }
                if work.preservedAt == nil { work.preservedAt = Date() }
            } else if work.epubPreservationStatus == .notPreserved {
                work.epubPreservationStatus = .queued
            }
            if work.metadataSyncStatus == .unknown && work.needsAO3Refresh {
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
        queue.dateUpdated = Date()
        work.isQueuedForLater = true
        normalize(work)
        try? context.save()
        return membership
    }

    @discardableResult
    static func addAndPreserve(
        _ work: SavedWork,
        to queue: ReadingQueue,
        in context: ModelContext
    ) async -> ReadingQueueMembership {
        let membership = add(work, to: queue, in: context)
        await preserve(work, in: context)
        return membership
    }

    @discardableResult
    static func addToSavedForLater(_ work: SavedWork, in context: ModelContext) async -> ReadingQueueMembership {
        let queue = ensureSavedForLaterQueue(in: context)
        return await addAndPreserve(work, to: queue, in: context)
    }

    static func addToSavedForLater(
        _ summary: AO3WorkSummary,
        in context: ModelContext
    ) async throws -> SavedWork {
        if let existing = existingWork(for: summary, in: context) {
            applyRemoteMetadata(summary, to: existing)
            existing.ao3WorkID = summary.id
            if existing.seriesURL.isEmpty { existing.seriesURL = summary.seriesURL ?? "" }
            if existing.ao3SeriesID == nil { existing.ao3SeriesID = ao3SeriesID(from: existing.seriesURL) }
            _ = await addToSavedForLater(existing, in: context)
            return existing
        }

        let temp = try await AO3Client.shared.downloadEPUB(workID: summary.id)
        let saved = try await importEPUB(
            temp,
            source: summary.workURL,
            isComplete: summary.isComplete ?? false,
            seriesURL: summary.seriesURL ?? "",
            knownChapterCount: postedChapterCount(from: summary.chapters),
            into: context
        )
        saved.ao3WorkID = summary.id
        saved.ao3SeriesID = ao3SeriesID(from: saved.seriesURL)
        applyRemoteMetadata(summary, to: saved)
        saved.isSaved = false
        let queue = ensureSavedForLaterQueue(in: context)
        add(saved, to: queue, in: context)
        saved.epubPreservationStatus = .preserved
        saved.preservedAt = Date()
        try? context.save()
        await syncMetadata(for: saved, in: context)
        return saved
    }

    static func preserve(_ work: SavedWork, in context: ModelContext) async {
        normalize(work)
        guard work.isQueuedForLater else { return }

        work.lastPreservationAttemptAt = Date()
        let existingFile = FileManager.default.fileExists(atPath: work.fileURL.path)
        if work.hasEPUB && existingFile {
            work.epubPreservationStatus = .preserved
            work.preservedAt = Date()
            try? context.save()
            await syncMetadata(for: work, in: context)
            return
        }

        guard let id = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) else {
            work.epubPreservationStatus = .failed
            work.metadataSyncStatus = .incomplete
            try? context.save()
            return
        }

        work.ao3WorkID = id
        work.epubPreservationStatus = .preserving
        try? context.save()

        do {
            let temp = try await AO3Client.shared.downloadEPUB(workID: id)
            try replaceEPUB(for: work, with: temp)
            work.hasEPUB = true
            work.epubPreservationStatus = .preserved
            work.preservedAt = Date()
            work.lastAvailabilityCheck = Date()
            try? context.save()
            await WorkTags.backfillFromEPUB(for: work, in: context)
            await syncMetadata(for: work, in: context)
        } catch AO3Error.notFound {
            work.ao3Unavailable = true
            work.epubPreservationStatus = .failed
            work.metadataSyncStatus = .failed
            try? context.save()
        } catch {
            Log.library.error(
                "Couldn't preserve queued work \(work.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            work.epubPreservationStatus = .failed
            try? context.save()
        }
    }

    static func syncMetadata(for work: SavedWork, in context: ModelContext) async {
        normalize(work)
        guard work.ao3WorkID != nil || WorkTags.ao3WorkID(from: work.sourceURL) != nil else {
            work.metadataSyncStatus = work.workTags.isEmpty ? .incomplete : .complete
            try? context.save()
            return
        }
        guard work.needsAO3Refresh else {
            work.metadataSyncStatus = .complete
            try? context.save()
            return
        }

        work.metadataSyncStatus = .syncing
        try? context.save()
        await WorkTags.refreshFromAO3(for: work, in: context)
        if work.needsAO3Refresh {
            work.metadataSyncStatus = work.ao3Unavailable ? .failed : .incomplete
        } else {
            work.metadataSyncStatus = .complete
        }
        try? context.save()
    }

    static func preserveSeries(
        anchoredAt anchor: SavedWork,
        in context: ModelContext
    ) async -> SeriesPreservationResult {
        guard let url = URL(string: anchor.seriesURL), !anchor.seriesURL.isEmpty else {
            return SeriesPreservationResult()
        }

        do {
            let summaries = try await AO3Client.shared.seriesWorks(seriesURL: url)
            var result = SeriesPreservationResult(total: summaries.count)
            for summary in summaries {
                if let existing = existingWork(for: summary, in: context),
                   existing.isInSavedForLaterQueue,
                   existing.epubPreservationStatus == .preserved {
                    result.skipped += 1
                    continue
                }
                do {
                    _ = try await addToSavedForLater(summary, in: context)
                    result.preserved += 1
                } catch {
                    result.failed += 1
                }
            }
            return result
        } catch {
            Log.library.error(
                "Couldn't load series for queue preservation: \(error.localizedDescription, privacy: .public)"
            )
            return SeriesPreservationResult(failed: 1)
        }
    }

    static func remove(_ work: SavedWork, from queue: ReadingQueue, in context: ModelContext) {
        let matches = work.queueMemberships.filter { $0.queue?.id == queue.id }
        for membership in matches {
            work.queueMemberships.removeAll { $0.id == membership.id }
            queue.memberships.removeAll { $0.id == membership.id }
            context.delete(membership)
        }
        queue.dateUpdated = Date()
        work.isQueuedForLater = !work.queueMemberships.isEmpty
        normalize(work)
        WorkLifecycle.freeEPUBIfFinished(work, in: context)
        try? context.save()
    }

    static func existingWork(for summary: AO3WorkSummary, in context: ModelContext) -> SavedWork? {
        let works = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
        return works.first { work in
            work.ao3WorkID == summary.id
                || WorkTags.ao3WorkID(from: work.sourceURL) == summary.id
                || work.sourceURL == summary.workURL.absoluteString
        }
    }

    static func applyRemoteMetadata(_ summary: AO3WorkSummary, to work: SavedWork) {
        work.ao3WorkID = summary.id
        if work.author.isEmpty { work.author = summary.authorText }
        if work.workFandoms.isEmpty { work.workFandoms = summary.fandoms }
        if work.rating.isEmpty { work.rating = summary.rating }
        if work.workWarnings.isEmpty { work.workWarnings = summary.warnings }
        if work.workCategories.isEmpty { work.workCategories = summary.categories }
        if work.workRelationships.isEmpty { work.workRelationships = summary.relationships }
        if work.workCharacters.isEmpty { work.workCharacters = summary.characters }
        if work.workFreeforms.isEmpty { work.workFreeforms = additionalTags(from: summary) }
        work.workTags = merged(
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
                .map(normalizedTag)
        )
        return summary.tags.filter { !categorized.contains(normalizedTag($0)) }
    }

    private static func replaceEPUB(for work: SavedWork, with temp: URL) throws {
        let destination = work.fileURL
        _ = try EPUBDocument.inspectPackage(ofEPUBAt: temp)
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

    private static func postedChapterCount(from chapters: String) -> Int {
        Int(chapters.split(separator: "/").first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
    }

    private static func merged(_ existing: [String], _ incoming: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in existing + incoming {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(normalizedTag(trimmed)).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func normalizedTag(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
