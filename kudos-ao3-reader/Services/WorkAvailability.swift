import Foundation
import OSLog
import SwiftData

/// Confirms whether a work still exists at its source.
///
/// The point is the Library's **Last Copy** badge. That badge reads
/// `SavedWork.ao3Unavailable`, which before this only got set when a *tag refresh*
/// happened to touch the work — and the tag refresh is skipped whenever a work
/// already has its metadata. So the works most likely to be irreplaceable, the ones
/// imported complete with tags from someone else's export, were exactly the ones
/// never checked. Import now asks the question directly.
///
/// Only AO3 can be asked. There is no native path to fanfiction.net or Wattpad (see
/// `WorkOrigin.supportsLiveLookup`), so for those this records nothing rather than
/// guessing — an unchecked work must not look like a confirmed-present one.
@MainActor
enum WorkAvailability {
    /// Fetches a work's page to prove it exists. Injectable so tests can exercise the
    /// state transitions without a network — the same seam
    /// `ReadingQueueService.preserve` uses for its EPUB download.
    typealias MetadataFetch = @Sendable (Int) async throws -> AO3WorkMetadata

    private static let liveFetch: MetadataFetch = { workID in
        try await AO3Client.shared.workMetadata(workID: workID)
    }

    /// Checks the work and records the answer. Never throws: a work that could not be
    /// checked is left exactly as it was.
    ///
    /// Costs at most one request. When a tag refresh is due it delegates, because that
    /// refresh already fetches this very page and already handles 404 — fetching twice
    /// per import would be rude to AO3 for no new information.
    static func verify(
        _ work: SavedWork,
        in context: ModelContext,
        fetchMetadata: MetadataFetch? = nil
    ) async {
        // The caller fires this as a detached task, so the work can be deleted (or its
        // container torn down in tests) before it runs. Same liveness guard the tag
        // refresh uses.
        guard work.modelContext != nil else { return }
        guard let id = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) else {
            // No AO3 identity: nothing to ask, and nothing recorded. A community copy
            // from another site stays "unknown", which is the honest answer.
            return
        }
        work.ao3WorkID = id

        if fetchMetadata == nil, work.needsAO3Refresh {
            await WorkTags.refreshFromAO3(for: work, in: context)
            return
        }

        do {
            _ = try await (fetchMetadata ?? liveFetch)(id)
            guard work.modelContext != nil else { return }
            record(.present, on: work, in: context)
        } catch AO3Error.notFound {
            guard work.modelContext != nil else { return }
            Log.library.info("AO3 no longer has work \(id); marking the local copy as the last one")
            record(.deleted, on: work, in: context)
        } catch {
            // A timeout or a parse failure says nothing about whether the work exists,
            // so nothing is recorded — including the timestamp, so a later pass still
            // treats this work as unchecked rather than as verified-present.
            let reason = error.localizedDescription
            Log.library.notice("Availability check for work \(id) was inconclusive: \(reason, privacy: .public)")
        }
    }

    enum Outcome {
        case present
        case deleted
    }

    /// Applies an outcome. Kept separate so the reverse transition is impossible to
    /// forget: a work that reappears on AO3 (an author un-hiding it, a temporary
    /// admin block lifted) must lose the flag, or `needsAO3Refresh` keeps returning
    /// false and the work is stuck as "deleted" forever — a one-way trap this had.
    static func record(_ outcome: Outcome, on work: SavedWork, in context: ModelContext) {
        let wasUnavailable = work.ao3Unavailable
        work.ao3Unavailable = outcome == .deleted
        work.lastAvailabilityCheck = Date()
        if wasUnavailable != work.ao3Unavailable {
            work.markModified()
            if outcome == .present {
                Log.library.info("Work \(work.ao3WorkID ?? 0) is back on AO3; clearing the last-copy flag")
            }
        }
        context.saveBestEffort(reason: "Saving the availability check failed")
    }
}
