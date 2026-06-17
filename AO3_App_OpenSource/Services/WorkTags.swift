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
            work.workFandoms = groups.fandoms
            work.workRelationships = groups.relationships
            work.workCharacters = groups.characters
            work.workFreeforms = groups.freeforms
            work.workTags = groups.flattened   // flat union for the Library filter
            work.workWarnings = groups.warnings
            work.workCategories = groups.categories
            if !groups.language.isEmpty { work.language = groups.language }
            if let words = groups.words { work.wordCount = words }
            work.workTagsFetched = true
            try? context.save()
        } catch {
            // Network or parse failure: keep the EPUB-derived tags and retry next time.
        }
    }

    /// Extracts the numeric AO3 work id from a `…/works/<id>` source URL.
    static func ao3WorkID(from urlString: String) -> Int? {
        guard let url = URL(string: urlString) else { return nil }
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "works"), index + 1 < parts.count else { return nil }
        return Int(parts[index + 1])
    }
}
