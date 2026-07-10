import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
@Suite(.serialized)
struct WorkSearchIndexTests {
    @Test func normalizeFoldsCaseAndDiacritics() {
        #expect(WorkSearchIndex.normalize("HÉROÏNE Café") == "heroine cafe")
        #expect(WorkSearchIndex.terms(from: "  Café  NOIR ") == ["cafe", "noir"])
    }

    @Test func reindexPopulatesNormalizedSearchTextFromAllFields() throws {
        let context = try makeContext()
        let work = SavedWork(
            title: "Über Story",
            author: "Ém Writer",
            summary: "<p>A <b>café</b> adventure.</p>",
            sourceURL: "https://archiveofourown.org/works/8101"
        )
        work.workFandoms = ["Tëst Fandom"]
        work.workRelationships = ["A/B"]
        work.workCharacters = ["Chárlie"]
        work.workFreeforms = ["Fluff"]
        work.rating = "Teen And Up Audiences"
        work.language = "Français"
        work.isComplete = true
        context.insert(work)

        WorkSearchIndex.reindex(work)

        #expect(work.searchIndexVersion == WorkSearchIndex.currentVersion)
        for expected in [
            "uber story", "em writer", "test fandom", "a/b", "charlie",
            "fluff", "teen and up", "francais", "complete", "cafe adventure"
        ] {
            #expect(work.searchText.contains(expected), "missing: \(expected)")
        }
        // HTML markup from the summary must not leak into the index.
        #expect(!work.searchText.contains("<p>"))
    }

    @Test func matchesRequiresEveryTermAcrossFields() throws {
        let context = try makeContext()
        let work = SavedWork(title: "The Long Watch", author: "Writer", sourceURL: "")
        work.workFreeforms = ["Angst"]
        context.insert(work)
        WorkSearchIndex.reindex(work)

        // Terms spanning different fields (title word + tag) both match.
        #expect(WorkSearchIndex.matches(work, terms: WorkSearchIndex.terms(from: "watch angst")))
        #expect(WorkSearchIndex.matches(work, terms: WorkSearchIndex.terms(from: "LONG")))
        #expect(!WorkSearchIndex.matches(work, terms: WorkSearchIndex.terms(from: "watch fluff")))
        // Empty query matches everything, mirroring "no query typed".
        #expect(WorkSearchIndex.matches(work, terms: []))
    }

    @Test func applyRemoteMetadataReindexes() throws {
        let context = try makeContext()
        let work = SavedWork(title: "Old Title", author: "", sourceURL: "https://archiveofourown.org/works/8102")
        context.insert(work)
        WorkSearchIndex.reindex(work)
        #expect(!work.searchText.contains("remotia"))

        // applyRemoteMetadata is fill-only for most fields — assert on one it
        // actually fills (fandoms on a work that has none).
        ReadingQueueService.applyRemoteMetadata(
            summary(8102, title: "Ignored", fandoms: ["Remotia Chronicles"]),
            to: work
        )

        #expect(work.searchText.contains("remotia chronicles"))
    }

    @Test func rebuildIfNeededIndexesStaleRecordsOnceAndOnlyOnce() async throws {
        let context = try makeContext()
        let work = SavedWork(title: "Unindexed Résumé", author: "Writer", sourceURL: "")
        context.insert(work)
        try context.save()
        #expect(work.searchIndexVersion == 0)

        #expect(await WorkSearchIndex.rebuildIfNeeded(in: context) == 1)
        #expect(work.searchText.contains("unindexed resume"))
        // Everything current now — the sweep is a no-op.
        #expect(await WorkSearchIndex.rebuildIfNeeded(in: context) == 0)
    }

    @Test func backupRestoreRebuildsSearchTextWithoutCarryingIt() throws {
        let sourceContext = try makeContext()
        let work = SavedWork(
            title: "Backup Héroïne",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/8103"
        )
        work.ao3WorkID = 8103
        work.workFreeforms = ["Hurt/Comfort"]
        sourceContext.insert(work)
        WorkSearchIndex.reindex(work)
        try sourceContext.save()

        let document = try KudosBackupService.makeDocument(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: testDefaults()
        )
        // The derived index never travels in the manifest — only real fields do.
        let manifestJSON = try #require(
            try document.contents.fileWrapper().fileWrappers?["manifest.json"]?.regularFileContents
        )
        #expect(manifestJSON.range(of: Data("searchText".utf8)) == nil)

        let targetContext = try makeContext()
        _ = try KudosBackupService.restore(document.contents, into: targetContext, defaults: testDefaults())

        let restored = try #require(try targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.searchIndexVersion == WorkSearchIndex.currentVersion)
        #expect(WorkSearchIndex.matches(restored, terms: WorkSearchIndex.terms(from: "heroine comfort")))
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func testDefaults() -> UserDefaults {
        let name = "WorkSearchIndexTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func summary(_ id: Int, title: String, fandoms: [String] = ["Fandom"]) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: title,
            authors: ["Writer"],
            fandoms: fandoms,
            rating: "Teen And Up Audiences",
            warnings: ["No Archive Warnings Apply"],
            categories: [],
            isComplete: true,
            dateUpdated: "2026-06-30",
            tags: ["Freeform"],
            summary: "Summary \(id)",
            language: "English",
            words: 1_000,
            chapters: "1/1",
            comments: nil,
            kudos: nil,
            hits: nil,
            seriesTitle: nil,
            seriesURL: nil,
            seriesPosition: nil
        )
    }
}
