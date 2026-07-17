import Foundation
import OSLog
import SwiftData

/// Builds and queries `SavedWork.searchText` — a derived, normalized (lowercased,
/// diacritic-folded) concatenation of a work's searchable fields, computed once per
/// content change instead of per keystroke over the whole library.
///
/// The index is never source of truth: it's excluded from `.kudosbackup` exports,
/// and any record can be rebuilt from the real fields (`rebuildIfNeeded` sweeps
/// records whose `searchIndexVersion` doesn't match `currentVersion` at launch,
/// which also covers records created by pre-index builds or backup restores that
/// somehow missed their explicit reindex). Building the index never triggers a
/// network request — it reads only what's already stored locally.
@MainActor
enum WorkSearchIndex {
    /// Bump when `indexText(for:)`'s composition changes so existing records
    /// rebuild on next launch. 0 is reserved for "never indexed".
    /// v2: added the series title and the user's own tags (`SavedWork.tags`).
    static let currentVersion = 2

    /// Summary text beyond this contributes noise, memory, and store size, not
    /// recall — AO3 blurbs are typically well under it.
    private static let summaryLimit = 600

    /// Yield to the run loop every N records so a large stale library doesn't
    /// freeze the UI for the whole launch-time rebuild.
    private static let yieldInterval = 200

    // MARK: Normalization

    /// One shared normalization for both indexed text and queries: lowercased and
    /// diacritic-insensitive ("Héroïne" matches "heroine"), with a fixed locale so
    /// text indexed under one device locale matches queries typed under another.
    nonisolated static func normalize(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    /// A query split into normalized terms. Matching is AND-across-terms, so
    /// "granger fluff" finds a work whose title has one word and tags the other —
    /// a single-term query behaves exactly like the old substring match.
    nonisolated static func terms(from query: String) -> [String] {
        normalize(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    // MARK: Indexing

    /// The normalized searchable text for a work's current fields.
    static func indexText(for work: SavedWork) -> String {
        var parts: [String] = [work.title, work.author]
        // Series title, so a work is findable by the series it belongs to.
        parts.append(work.seriesTitle)
        // The user's own organizational tags. Every mutation site must reindex:
        // WorkDetailView's add/remove, and KudosBackup's restore (which links
        // archived user tags and must therefore reindex *after* linking them).
        parts.append(contentsOf: work.tags.map(\.name))
        parts.append(contentsOf: work.workFandoms)
        parts.append(contentsOf: work.workRelationships)
        parts.append(contentsOf: work.workCharacters)
        parts.append(contentsOf: work.workFreeforms)
        parts.append(contentsOf: work.workWarnings)
        parts.append(contentsOf: work.workCategories)
        // Flat tags cover works not yet enriched with categorized AO3 tags (e.g.
        // fresh EPUB imports) without duplicating every categorized entry above —
        // duplicates are harmless for matching but waste store space.
        let categorized = Set(
            (work.workFandoms + work.workRelationships + work.workCharacters
                + work.workFreeforms + work.workWarnings + work.workCategories)
                .map(normalize)
        )
        parts.append(contentsOf: work.workTags.filter { !categorized.contains(normalize($0)) })
        parts.append(work.rating)
        parts.append(work.language)
        parts.append(work.isComplete ? "complete" : "wip in progress")
        if !work.summary.isEmpty {
            parts.append(String(work.summary.strippingHTML().prefix(summaryLimit)))
        }
        return normalize(parts.filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    /// Recomputes a work's derived search fields. Deliberately does **not** call
    /// `markModified()` — the index is derived state, and bumping the sync
    /// timestamp for it would make every reindex look like a user edit to the
    /// backup/folder-sync merge rules. Callers save the context themselves.
    static func reindex(_ work: SavedWork) {
        work.searchText = indexText(for: work)
        work.searchIndexVersion = currentVersion
    }

    /// Whether a work matches every normalized term (see `terms(from:)`). An empty
    /// term list matches everything, mirroring "no query".
    static func matches(_ work: SavedWork, terms: [String]) -> Bool {
        terms.allSatisfy { work.searchText.contains($0) }
    }

    // MARK: Rebuild

    /// Reindexes every record whose stamp doesn't match `currentVersion` — new
    /// installs' pre-index libraries, records restored from backups, and records
    /// indexed under an older schema. Cheap no-op when everything is current.
    @discardableResult
    static func rebuildIfNeeded(in context: ModelContext) async -> Int {
        let version = currentVersion
        let stale = (try? context.fetch(
            FetchDescriptor<SavedWork>(predicate: #Predicate { $0.searchIndexVersion != version })
        )) ?? []
        guard !stale.isEmpty else { return 0 }
        var processed = 0
        for work in stale {
            // The yields below let other main-actor work interleave — including a
            // user deleting one of the fetched works. Touching an invalidated model
            // asserts, so re-check liveness (same guard as the migration service).
            guard work.modelContext != nil else { continue }
            reindex(work)
            processed += 1
            if processed.isMultiple(of: yieldInterval) { await Task.yield() }
        }
        try? context.save()
        Log.library.info("Search index rebuilt for \(stale.count, privacy: .public) work(s)")
        return stale.count
    }
}
