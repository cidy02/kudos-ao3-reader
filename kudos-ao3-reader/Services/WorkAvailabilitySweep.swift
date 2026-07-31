import Foundation
import OSLog
import SwiftData

/// Checks a whole library for works their site has deleted, so the **Last Copy** badge
/// reflects reality rather than only what an import happened to touch.
///
/// ## Manual on purpose
///
/// This never runs by itself. Asking AO3 hundreds of questions to learn that nothing
/// changed is not a polite thing for an app to do on a timer, and Kudos has no way to
/// ask "what changed since yesterday?" — AO3 exposes no such feed, so the only
/// available implementation is one request per work. Until there is a cheaper signal,
/// the user decides when that cost is worth paying.
///
/// `AO3RequestCoordinator` bounds *concurrency* (3 at once) but does not rate-limit, so
/// a sweep left to its own devices would fire a sustained burst. This runs **serially
/// with a deliberate gap** instead: availability is maintenance, not something anyone is
/// waiting on, so there is nothing to gain from speed and a great deal to lose from
/// looking like a scraper.
///
/// Politeness measures, all of them deliberate:
/// - one request at a time, `requestSpacing` apart (≈0.7/second);
/// - works checked within `recheckInterval` are skipped, so a second run does not
///   re-ask the same questions;
/// - oldest-checked first, so repeat runs cover the library over time instead of
///   re-walking the same prefix;
/// - a per-run `limit`, with whatever it did not reach **reported** rather than
///   silently dropped;
/// - cancellable between requests, and cancellation keeps the work already done.
@MainActor
enum WorkAvailabilitySweep {
    /// Don't re-ask about a work checked more recently than this. A week: deletions are
    /// rare, and a user who runs the sweep twice in an afternoon should send no traffic
    /// the second time.
    static let recheckInterval: TimeInterval = 7 * 24 * 3600

    /// Gap between requests. 1.5s is slower than a person clicking through pages, which
    /// is the bar this should stay under.
    static let requestSpacing: Duration = .milliseconds(1500)

    /// Ceiling for one run, so a 2,000-work library cannot turn into a 50-minute
    /// session by accident. What is left over is reported and picked up next time.
    static let defaultLimit = 150

    struct Summary: Equatable {
        var checked = 0
        var stillAvailable = 0
        var nowUnavailable = 0
        /// Skipped because they were checked within `recheckInterval`.
        var skippedRecent = 0
        /// In scope but beyond this run's limit, or not reached before cancellation.
        var remaining = 0
        var cancelled = false

        /// Works that can never be checked: no AO3 identity, so no site to ask. Counted
        /// so the summary can say why a number is smaller than the library.
        var unverifiable = 0
    }

    /// Works this sweep would actually contact AO3 about, oldest check first.
    static func pending(in context: ModelContext, now: Date = Date()) -> [SavedWork] {
        allAO3Works(in: context)
            .filter { work in
                guard let last = work.lastAvailabilityCheck else { return true }
                return now.timeIntervalSince(last) >= recheckInterval
            }
            // nil (never checked) sorts first: those are the works we know least about.
            .sorted { ($0.lastAvailabilityCheck ?? .distantPast) < ($1.lastAvailabilityCheck ?? .distantPast) }
    }

    /// Every work with an AO3 identity. The rest cannot be checked at all — there is no
    /// native path to fanfiction.net or Wattpad — and are counted, not contacted.
    private static func allAO3Works(in context: ModelContext) -> [SavedWork] {
        ((try? context.fetch(FetchDescriptor<SavedWork>())) ?? [])
            .filter { !$0.isPendingDeletion && $0.origin.supportsLiveLookup }
    }

    /// Runs the sweep. Never throws: a work that cannot be checked is left as it was.
    ///
    /// `verify` is injectable so tests exercise the pacing, limit and summary logic
    /// without a network — the same seam `WorkAvailability` and
    /// `ReadingQueueService.preserve` use.
    static func run(
        in context: ModelContext,
        limit: Int = defaultLimit,
        spacing: Duration = requestSpacing,
        now: Date = Date(),
        progress: (_ completed: Int, _ total: Int) -> Void = { _, _ in },
        verify: (SavedWork) async -> Void = { await WorkAvailability.verify($0, in: $0.modelContext!) }
    ) async -> Summary {
        var summary = Summary()
        let all = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
        summary.unverifiable = all.filter { !$0.isPendingDeletion && !$0.origin.supportsLiveLookup }.count

        let queue = pending(in: context, now: now)
        summary.skippedRecent = allAO3Works(in: context).count - queue.count

        let batch = queue.prefix(limit)
        summary.remaining = queue.count - batch.count

        for (index, work) in batch.enumerated() {
            if Task.isCancelled {
                summary.cancelled = true
                summary.remaining += batch.count - index
                break
            }
            // Spacing goes *before* each request after the first, so a cancelled sweep
            // never leaves a pointless trailing sleep, and the first check feels
            // immediate.
            if index > 0 {
                do {
                    try await Task.sleep(for: spacing)
                } catch {
                    summary.cancelled = true
                    summary.remaining += batch.count - index
                    break
                }
            }

            let wasUnavailable = work.ao3Unavailable
            await verify(work)
            summary.checked += 1
            // Read the flag rather than trusting the call: an inconclusive check (a
            // timeout) deliberately records nothing, and must not be counted either way.
            if work.lastAvailabilityCheck != nil || wasUnavailable != work.ao3Unavailable {
                if work.ao3Unavailable {
                    summary.nowUnavailable += 1
                } else {
                    summary.stillAvailable += 1
                }
            }
            progress(index + 1, batch.count)
        }

        let checked = summary.checked
        let gone = summary.nowUnavailable
        let left = summary.remaining
        Log.library.info("Availability sweep: checked \(checked), gone \(gone), remaining \(left)")
        return summary
    }
}
