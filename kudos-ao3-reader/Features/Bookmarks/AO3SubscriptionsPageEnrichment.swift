import Foundation

/// Chapter counts for one loaded subscriptions page.
///
/// Updated and Mark All as Seen read `enrichedSubscriptionSummaries`. A row
/// used to store its summary only from its own `.task`, and that task runs
/// only once the row has been rendered. The Updated pill filters before any
/// row exists, so a page that had not drawn a row had nothing left to enrich.
///
/// This asks `AO3SparseWorkEnricher` for every sparse row after the page is
/// already on screen. `enrich` detaches the network task, so cancelling here
/// does not stop a fetch that has already been handed over. `maxInFlight` is
/// `AO3RequestCoordinator`'s width: at most that many stay in flight, and the
/// rest are not started. Each one still goes through `withSlot` and `pace()`.
/// A result is recorded only while the generation that loaded the page is
/// still the one on screen.
enum AO3SubscriptionsPageEnrichment {
    /// How many work-page fetches may be handed to the enricher before one
    /// of them finishes. Matches `AO3RequestCoordinator`'s default limit.
    /// Wider than that would queue fetches the coordinator will run anyway,
    /// and those cannot be cancelled once `enrich` has detached them.
    static let maxInFlight = 3

    /// Sparse rows on this page, in page order, one entry per work id.
    /// A summary that already names rating, chapters, and fandoms is not
    /// sparse and is not fetched again.
    nonisolated static func sparseWorks(in works: [AO3WorkSummary]) -> [AO3WorkSummary] {
        var seen = Set<Int>()
        return works.filter { work in
            AO3SparseWorkEnricher.isSparse(work) && seen.insert(work.id).inserted
        }
    }

    /// `fetch` defaults to the shared enricher. Tests pass their own.
    static func enrichPage(
        _ works: [AO3WorkSummary],
        generation: Int,
        sessionGeneration: @escaping @MainActor () -> Int,
        note: @escaping @MainActor (AO3WorkSummary) -> Void,
        fetch: @escaping @MainActor (AO3WorkSummary) async -> AO3WorkSummary? = { work in
            await AO3SparseWorkEnricher.shared.enrich(work)
        }
    ) async {
        let pending = sparseWorks(in: works)
        guard !pending.isEmpty else { return }
        await withTaskGroup(of: AO3WorkSummary?.self) { group in
            var next = 0
            func startNext() {
                guard next < pending.count, !Task.isCancelled else { return }
                let work = pending[next]
                next += 1
                group.addTask {
                    if Task.isCancelled { return nil }
                    return await fetch(work)
                }
            }
            for _ in 0..<min(maxInFlight, pending.count) {
                startNext()
            }
            while let enriched = await group.next() {
                if let enriched,
                   AO3AccountWorksSessionReload.shouldApplyCapturedGeneration(
                       generation,
                       sessionGeneration: sessionGeneration()
                   ) {
                    note(enriched)
                }
                if Task.isCancelled {
                    group.cancelAll()
                    continue
                }
                startNext()
            }
        }
    }
}
