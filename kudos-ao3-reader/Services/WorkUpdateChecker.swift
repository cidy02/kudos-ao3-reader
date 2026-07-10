import Foundation
import OSLog
import SwiftData

/// Polls AO3 for new chapters on the user's in-progress works, feeding Home's
/// "Recently Updated". Polite by design: only **WIP** works (complete works can't
/// gain chapters), serial (through the already-serialized `AO3Client`), and
/// throttled so opening Home re-checks each work at most every few hours.
@MainActor
enum WorkUpdateChecker {
    /// Don't re-poll a work more often than this.
    private static let minInterval: TimeInterval = 6 * 3600

    /// Re-checks the live AO3 chapter count for each eligible work, updating its
    /// stored `chapters` (so `hasUpdate` reflects reality) and baselining
    /// `knownChapterCount` on first sight. Failures are kept silent and retried.
    static func checkForUpdates(among works: [SavedWork], in context: ModelContext) async {
        let due = works.filter(shouldCheck)
        guard !due.isEmpty else { return }
        Log.network.info("Checking \(due.count) work(s) for AO3 updates")

        for work in due {
            guard let id = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) else { continue }
            do {
                let groups = try await AO3Client.shared.workTags(workID: id)
                guard !groups.isEmpty, !groups.chapters.isEmpty else { continue }
                work.chapters = groups.chapters
                // Baseline on first sight (native imports seed this at download time).
                if work.knownChapterCount == 0 {
                    work.knownChapterCount = work.postedChapterCount
                }
                work.lastUpdateCheck = Date()
                try? context.save()
            } catch {
                // Network / parse / locked page — keep what we have, but still stamp
                // the check so a failing work waits out `minInterval` instead of
                // being retried on every Home visit.
                work.lastUpdateCheck = Date()
                try? context.save()
            }
        }
    }

    private static func shouldCheck(_ work: SavedWork) -> Bool {
        guard !work.isQueueOnlyWork, !work.isComplete,
              work.ao3WorkID != nil || WorkTags.ao3WorkID(from: work.sourceURL) != nil
        else { return false }
        if let last = work.lastUpdateCheck, Date().timeIntervalSince(last) < minInterval {
            return false
        }
        return true
    }
}
