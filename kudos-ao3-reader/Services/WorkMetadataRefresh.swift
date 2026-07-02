import Foundation
import OSLog
import SwiftData

/// Explicit, user-triggered AO3 metadata refresh. This is intentionally separate
/// from background backfill/update checks because pull-to-refresh must never become
/// a sync-delete path: AO3 404/private/rate-limit/network/parse failures leave the
/// local work exactly as-is.
@MainActor
enum WorkMetadataRefresh {
    struct Summary: Equatable {
        var refreshed = 0
        var failed = 0
        var skipped = 0

        var attempted: Int { refreshed + failed + skipped }
        var hasFailures: Bool { failed > 0 }
    }

    enum RefreshError: LocalizedError {
        case missingAO3ID

        var errorDescription: String? {
            switch self {
            case .missingAO3ID:
                "This work does not have an AO3 source URL to refresh."
            }
        }
    }

    static func refresh(_ works: [SavedWork], in context: ModelContext) async -> Summary {
        var seen = Set<UUID>()
        var summary = Summary()
        for work in works where seen.insert(work.id).inserted {
            // Check *before* starting the next fetch — a cancelled URLSession request
            // throws URLError(.cancelled), not CancellationError, so relying solely on
            // the catch clause below to stop the loop is unreliable. This keeps a pull
            // that was abandoned (view dismissed, refresh re-triggered) from walking
            // through every remaining work in the list.
            if Task.isCancelled {
                summary.failed += 1
                break
            }
            do {
                try await refresh(work, in: context)
                summary.refreshed += 1
            } catch RefreshError.missingAO3ID {
                summary.skipped += 1
            } catch is CancellationError {
                summary.failed += 1
                break
            } catch let urlError as URLError where urlError.code == .cancelled {
                summary.failed += 1
                break
            } catch {
                summary.failed += 1
                let id = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) ?? -1
                Log.network.notice(
                    "Metadata refresh failed for work \(id, privacy: .public): \(message(for: error), privacy: .public)"
                )
            }
        }
        return summary
    }

    static func refresh(_ work: SavedWork, in context: ModelContext) async throws {
        guard let id = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) else {
            throw RefreshError.missingAO3ID
        }

        let metadata = try await AO3RequestCoordinator.shared.withSlot {
            try await AO3Client.shared.workMetadata(workID: id)
        }

        // Safety rule: all network/parse failures throw before this point. From here
        // onward we merge a fully parsed value and never delete/unlink local records.
        apply(metadata, to: work)
        try context.save()
    }

    static func remoteSummary(workID: Int) async throws -> AO3WorkSummary {
        let metadata = try await AO3RequestCoordinator.shared.withSlot {
            try await AO3Client.shared.workMetadata(workID: workID)
        }
        return metadata.summaryValue
    }

    static func message(for error: Error) -> String {
        if let ao3 = error as? AO3Error, let description = ao3.errorDescription {
            return description
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private static func apply(_ metadata: AO3WorkMetadata, to work: SavedWork) {
        work.ao3WorkID = metadata.id
        work.ao3Unavailable = false

        if !metadata.title.isEmpty { work.title = metadata.title }
        if !metadata.authors.isEmpty { work.author = metadata.authorText }
        if !metadata.summary.isEmpty { work.summary = metadata.summary }
        if !metadata.rating.isEmpty { work.rating = metadata.rating }

        work.workFandoms = TagMerge.merged(work.workFandoms, metadata.fandoms)
        work.workRelationships = TagMerge.merged(work.workRelationships, metadata.relationships)
        work.workCharacters = TagMerge.merged(work.workCharacters, metadata.characters)
        work.workFreeforms = TagMerge.merged(work.workFreeforms, metadata.freeforms)
        work.workWarnings = TagMerge.merged(work.workWarnings, metadata.warnings)
        work.workCategories = TagMerge.merged(work.workCategories, metadata.categories)

        let categorized = work.workFandoms + work.workRelationships + work.workCharacters
            + work.workWarnings + work.workCategories
        let categorizedKeys = Set(categorized.map(TagMerge.key))
        work.workFreeforms.removeAll { categorizedKeys.contains(TagMerge.key($0)) }
        work.workTags = TagMerge.merged(
            work.workTags,
            work.workFandoms + work.workRelationships + work.workCharacters + work.workFreeforms
        )

        if !metadata.language.isEmpty { work.language = metadata.language }
        if let words = metadata.words { work.wordCount = words }
        if !metadata.chapters.isEmpty { work.chapters = metadata.chapters }
        if let kudos = metadata.kudos { work.kudos = kudos }
        if let comments = metadata.comments { work.comments = comments }
        if let hits = metadata.hits { work.hits = hits }
        if !metadata.datePublished.isEmpty { work.datePublished = metadata.datePublished }
        if !metadata.dateUpdated.isEmpty { work.dateUpdated = metadata.dateUpdated }
        if let complete = metadata.isComplete { work.isComplete = complete }
        if let title = metadata.seriesTitle, !title.isEmpty { work.seriesTitle = title }
        if let url = metadata.seriesURL, !url.isEmpty {
            work.seriesURL = url
            work.ao3SeriesID = ReadingQueueService.ao3SeriesID(from: url)
        }
        if let position = metadata.seriesPosition, position > 0 { work.seriesPosition = position }
        if !metadata.tagGroups.isEmpty { work.workTagsFetched = true }
        work.lastUpdateCheck = Date()
    }
}
