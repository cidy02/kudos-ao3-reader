import Foundation
import os

/// Fills in work cards that AO3's own listing left bare.
///
/// The subscriptions page is the case this exists for: AO3 lists nothing there but
/// each work's title, id and author, so `parseSubscriptionsPage` can only build a
/// sparse `AO3WorkSummary` and the cards render with no tags, no stats and no
/// summary while every other list in the app shows all three.
///
/// **One work at a time, on demand, and never as a batch.** Filling a 20-work page
/// eagerly would mean 20 `/works/<id>` fetches before anything could be shown, each
/// taking a `pace()` slot — the list would sit empty for as long as that took, and
/// scrolling past a work you didn't care about would still have cost a request. So
/// rows ask for their own metadata as they appear and the card fills in behind them.
///
/// Results are memoised for the process lifetime: paging back to a list must not
/// re-fetch what it already has. Nothing is written to disk — this is presentation
/// detail for a screen the user is currently looking at, not library data.
actor AO3SparseWorkEnricher {
    static let shared = AO3SparseWorkEnricher()

    /// Successful lookups. Absent means "not fetched yet"; see `failed` for the
    /// difference between that and "asked, and AO3 said no".
    private var enriched: [Int: AO3WorkSummary] = [:]
    /// Work ids whose fetch failed. Kept so a work that 404s (deleted, or locked to
    /// registered users) is not retried on every scroll — the sparse card stands.
    private var failed: Set<Int> = []
    /// In-flight fetches, so two rows appearing at once share one request rather
    /// than racing. `RequestCoalescer` would also merge them at the transport, but
    /// this avoids even queuing the second one behind a `pace()` slot.
    private var inFlight: [Int: Task<AO3WorkSummary?, Never>] = [:]

    /// A fuller version of `work`, or nil if there is nothing to add or the fetch
    /// failed. Returns immediately for a work that already has its metadata.
    func enrich(_ work: AO3WorkSummary) async -> AO3WorkSummary? {
        guard Self.isSparse(work) else { return nil }
        if let cached = enriched[work.id] { return cached }
        if failed.contains(work.id) { return nil }
        // Await someone else's fetch, then fall through to the *same* merge and
        // cache below rather than returning its raw result: the merge restores the
        // listing's title and author, and two rows showing one work must not
        // disagree about them.
        if let running = inFlight[work.id] {
            _ = await running.value
            return enriched[work.id]
        }

        let task = Task<AO3WorkSummary?, Never> {
            do {
                let metadata = try await AO3RequestCoordinator.shared.withSlot {
                    try await AO3Client.shared.workMetadata(workID: work.id)
                }
                return metadata.asWorkSummary
            } catch {
                Log.network.notice(
                    "Sparse work \(work.id, privacy: .public) could not be enriched: \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
        inFlight[work.id] = task
        let result = await task.value
        inFlight[work.id] = nil

        guard let result else {
            failed.insert(work.id)
            return nil
        }
        // AO3's subscriptions listing is the only place the *title* is authoritative
        // for a subscription — the work page's title is the same string, but keeping
        // the listing's avoids a card visibly re-titling itself as it fills in.
        var merged = result
        if merged.title.isEmpty { merged.title = work.title }
        if merged.authors.isEmpty { merged.authors = work.authors }
        enriched[work.id] = merged
        return merged
    }

    /// Whether a summary is missing the fields a card renders.
    ///
    /// Deliberately not "is any field empty": a real work can legitimately have no
    /// fandom listed, or no summary text. What marks a *subscription* blurb is that
    /// AO3 gave the listing no stats block at all, so rating and chapters are both
    /// blank together — a combination a parsed search blurb never produces.
    nonisolated static func isSparse(_ work: AO3WorkSummary) -> Bool {
        work.rating.isEmpty && work.chapters.isEmpty && work.fandoms.isEmpty
    }
}
