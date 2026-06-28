import Foundation
import SwiftData

/// Keeps a saved work's Work Tags in sync with AO3's canonical work page. Imports
/// seed `workTags` from the EPUB immediately; this then refreshes them from AO3 in
/// the background so the list matches the live work (and works even when the EPUB's
/// metadata is sparse). Failures are silent and leave the EPUB tags in place.
enum WorkTags {
    /// Replaces `workTags` with AO3's tags for the work, once. No-ops if already
    /// fetched, if there's no AO3 work id, or if AO3 returns nothing — staying
    /// un-flagged in those last cases so a later attempt can still succeed.
    @MainActor
    static func refreshFromAO3(for work: SavedWork, in context: ModelContext) async {
        guard let id = ao3WorkID(from: work.sourceURL) else { return }
        // Fetch when never fetched, when fetched before categorized tags existed, or
        // when the newer filter metadata (warnings/categories/language/word count) is
        // still absent — so works saved by an older build gain all of it.
        guard work.needsAO3Refresh else { return }
        do {
            let groups = try await AO3Client.shared.workTags(workID: id)
            guard !groups.isEmpty else { return }   // locked/empty page — keep EPUB tags, retry later
            work.workFandoms = merged(work.workFandoms, groups.fandoms)
            work.workRelationships = merged(work.workRelationships, groups.relationships)
            work.workCharacters = merged(work.workCharacters, groups.characters)
            work.workFreeforms = merged(work.workFreeforms, groups.freeforms)
            work.workWarnings = merged(work.workWarnings, groups.warnings)
            work.workCategories = merged(work.workCategories, groups.categories)
            let categorized = work.workFandoms + work.workRelationships + work.workCharacters
                + work.workWarnings + work.workCategories
            let categorizedKeys = Set(categorized.map(tagKey))
            work.workFreeforms.removeAll {
                categorizedKeys.contains(tagKey($0))
            }
            // Flat union for the Library filter. Warnings/categories stay in their
            // dedicated fields and are not duplicated into Additional Tags.
            work.workTags = merged([], work.workFandoms + work.workRelationships
                + work.workCharacters + work.workFreeforms)
            if !groups.language.isEmpty { work.language = groups.language }
            if let words = groups.words { work.wordCount = words }
            work.chapters = groups.chapters
            if let kudos = groups.kudos { work.kudos = kudos }
            if let comments = groups.comments { work.comments = comments }
            if let hits = groups.hits { work.hits = hits }
            work.workTagsFetched = true
            try? context.save()
        } catch AO3Error.notFound {
            // 404 — the work has been deleted from AO3. Stop re-fetching it and keep
            // whatever tags it already has (EPUB-derived or a prior AO3 fetch).
            work.ao3Unavailable = true
            try? context.save()
        } catch {
            // Other network or parse failure: keep the EPUB-derived tags and retry next time.
        }
    }

    /// Seeds `workTags` from the on-disk EPUB for a downloaded work that has none yet
    /// (imported before Work Tags existed, or whose tags were never populated). Pure
    /// local — no network — so a downloaded work always keeps the tags its EPUB carries,
    /// even when AO3 is unreachable or the work has been deleted there. No-ops once tags
    /// exist or when the work has no EPUB on disk.
    @MainActor
    static func backfillFromEPUB(for work: SavedWork, in context: ModelContext) async {
        guard work.workTags.isEmpty, work.hasEPUB else { return }
        // Reading the EPUB pulls the whole file into memory + unzips it — do it off the
        // main actor, then apply the result back on the main actor.
        let url = work.fileURL
        let meta = await Task.detached(priority: .utility) {
            try? EPUBDocument.metadata(ofEPUBAt: url)
        }.value
        guard let meta else { return }
        let tags = SavedWork.normalizedWorkTags(meta.subjects, excludingRating: meta.rating)
        guard !tags.isEmpty else { return }
        work.workTags = tags
        if work.rating.isEmpty { work.rating = meta.rating }
        try? context.save()
    }

    /// Extracts the numeric AO3 work id from a `…/works/<id>` source URL.
    static func ao3WorkID(from urlString: String) -> Int? {
        guard let url = URL(string: urlString) else { return nil }
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "works"), index + 1 < parts.count else { return nil }
        return Int(parts[index + 1])
    }

    private static func merged(_ existing: [String], _ incoming: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in existing + incoming {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = value.lowercased()
            guard !value.isEmpty, seen.insert(key).inserted else { continue }
            result.append(value)
        }
        return result
    }

    private static func tagKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
