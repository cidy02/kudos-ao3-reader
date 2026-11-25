import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct QueueSourceBackupTests {
    private func context() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
            ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self,
            QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func defaults() throws -> UserDefaults {
        let name = "QueueSourceBackupTests.\(UUID().uuidString)"
        let value = try #require(UserDefaults(suiteName: name))
        value.removePersistentDomain(forName: name)
        return value
    }

    @Test func sourceFieldsRoundTripAndLegacyKeysPreserveStoredValues() throws {
        let source = try context()
        let queue = ReadingQueue(name: "Queue")
        let search = SavedSearch(name: "Search", filters: AO3SearchFilters())
        search.lastOpenedAt = Date(timeIntervalSince1970: 1_000)
        let link = QueueSavedSearchLink(queue: queue, search: search)
        link.lastCheckedAt = Date(timeIntervalSince1970: 2_000)
        link.newResultCount = 3
        source.insert(queue)
        source.insert(search)
        source.insert(link)
        try source.save()
        let contents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [queue],
            savedSearches: [search], defaults: try defaults()
        )
        let target = try context()
        _ = try KudosBackupService.restore(contents, into: target, defaults: try defaults())
        let restoredQueue = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first {
            $0.id == queue.id
        })
        let restoredSearch = try #require(try target.fetch(FetchDescriptor<SavedSearch>()).first {
            $0.id == search.id
        })
        #expect(restoredSearch.lastOpenedAt == search.lastOpenedAt)
        #expect(restoredQueue.searchLinks.first?.lastCheckedAt == link.lastCheckedAt)
        #expect(restoredQueue.searchLinks.first?.newResultCount == 3)

        var root = try #require(JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any])
        var queues = try #require(root["readingQueues"] as? [[String: Any]])
        var searches = try #require(root["savedSearches"] as? [[String: Any]])
        queues[0].removeValue(forKey: "searchSources")
        queues[0].removeValue(forKey: "searchSourcesModifiedAt")
        searches[0].removeValue(forKey: "lastOpenedAt")
        root["readingQueues"] = queues
        root["savedSearches"] = searches
        let old = try KudosBackupContents.decodeManifest(JSONSerialization.data(withJSONObject: root))
        _ = try KudosBackupService.restore(
            KudosBackupContents(manifest: old), into: target, defaults: try defaults()
        )
        #expect(restoredSearch.lastOpenedAt == search.lastOpenedAt)
        #expect(restoredQueue.searchLinks.first?.lastCheckedAt == link.lastCheckedAt)
        #expect(restoredQueue.searchLinks.first?.newResultCount == 3)
    }

    @Test func unrecordedValuesExportNoKeysAndDeletingSearchOnlyDetaches() throws {
        let context = try context()
        let queue = ReadingQueue(name: "Queue")
        let search = SavedSearch(name: "Search", filters: AO3SearchFilters())
        context.insert(queue)
        context.insert(search)
        try context.save()
        let contents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [queue],
            savedSearches: [search], defaults: try defaults()
        )
        let root = try #require(JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any])
        let exportedQueue = try #require((root["readingQueues"] as? [[String: Any]])?.first)
        let exportedSearch = try #require((root["savedSearches"] as? [[String: Any]])?.first)
        #expect(exportedQueue["searchSources"] == nil)
        #expect(exportedQueue["searchSourcesModifiedAt"] == nil)
        #expect(exportedSearch["lastOpenedAt"] == nil)
        let link = QueueSavedSearchLink(queue: queue, search: search)
        context.insert(link)
        try context.save()
        context.delete(search)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<ReadingQueue>()).contains { $0.id == queue.id })
        #expect(try context.fetch(FetchDescriptor<QueueSavedSearchLink>()).isEmpty)
    }

    @Test func openingSearchClearsBadgeAcrossRestoreAndOlderCountCannotReviveIt() throws {
        let source = try context()
        let queue = ReadingQueue(name: "Queue")
        let search = SavedSearch(name: "Search", filters: AO3SearchFilters())
        let link = QueueSavedSearchLink(queue: queue, search: search)
        link.lastCheckedAt = Date(timeIntervalSince1970: 1_000)
        link.newResultCount = 3
        source.insert(queue)
        source.insert(search)
        source.insert(link)
        try source.save()
        let beforeVisit = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [queue],
            savedSearches: [search], defaults: try defaults()
        )
        search.lastOpenedAt = Date(timeIntervalSince1970: 2_000)
        link.newResultCount = 0
        try source.save()
        let afterVisit = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [queue],
            savedSearches: [search], defaults: try defaults()
        )
        let target = try context()
        _ = try KudosBackupService.restore(beforeVisit, into: target, defaults: try defaults())
        _ = try KudosBackupService.restore(afterVisit, into: target, defaults: try defaults())
        // A restore also adds the system Saved for Later queue, so pick ours by id.
        let restored = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first {
            $0.id == queue.id
        })
        #expect(restored.searchLinks.first?.newResultCount == 0)
        _ = try KudosBackupService.restore(beforeVisit, into: target, defaults: try defaults())
        #expect(restored.searchLinks.first?.newResultCount == 0)
    }

    @Test func replaceLibraryRestoresOlderSourceStamps() throws {
        let source = try context()
        let queue = ReadingQueue(name: "Queue")
        let search = SavedSearch(name: "Search", filters: AO3SearchFilters())
        search.lastOpenedAt = Date(timeIntervalSince1970: 1_000)
        queue.searchSourcesModifiedAt = Date(timeIntervalSince1970: 1_000)
        let link = QueueSavedSearchLink(queue: queue, search: search)
        link.lastCheckedAt = Date(timeIntervalSince1970: 1_000)
        link.newResultCount = 3
        source.insert(queue)
        source.insert(search)
        source.insert(link)
        try source.save()
        let snapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [queue],
            savedSearches: [search], defaults: try defaults()
        )
        let target = try context()
        _ = try KudosBackupService.restore(snapshot, into: target, defaults: try defaults())
        let restoredQueue = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first {
            $0.id == queue.id
        })
        let restoredSearch = try #require(try target.fetch(FetchDescriptor<SavedSearch>()).first {
            $0.id == search.id
        })
        restoredSearch.lastOpenedAt = Date(timeIntervalSince1970: 2_000)
        restoredQueue.searchSourcesModifiedAt = Date(timeIntervalSince1970: 2_000)
        restoredQueue.searchLinks.first?.lastCheckedAt = Date(timeIntervalSince1970: 2_000)
        restoredQueue.searchLinks.first?.newResultCount = 0
        try target.save()
        _ = try KudosBackupService.restore(
            snapshot, into: target, defaults: try defaults(), mode: .merge
        )
        #expect(restoredSearch.lastOpenedAt == Date(timeIntervalSince1970: 2_000))
        #expect(restoredQueue.searchSourcesModifiedAt == Date(timeIntervalSince1970: 2_000))
        #expect(restoredQueue.searchLinks.first?.lastCheckedAt == Date(timeIntervalSince1970: 2_000))
        #expect(restoredQueue.searchLinks.first?.newResultCount == 0)
        _ = try KudosBackupService.restore(
            snapshot, into: target, defaults: try defaults(), mode: .replaceLibrary
        )
        #expect(restoredSearch.lastOpenedAt == Date(timeIntervalSince1970: 1_000))
        #expect(restoredQueue.searchSourcesModifiedAt == Date(timeIntervalSince1970: 1_000))
        #expect(restoredQueue.searchLinks.first?.lastCheckedAt == Date(timeIntervalSince1970: 1_000))
        #expect(restoredQueue.searchLinks.first?.newResultCount == 3)
    }

    @Test func clearingSourcesTravelsAsAnEmptyRecordedList() throws {
        let source = try context()
        let queue = ReadingQueue(name: "Queue")
        let search = SavedSearch(name: "Search", filters: AO3SearchFilters())
        queue.searchSourcesModifiedAt = Date(timeIntervalSince1970: 1_000)
        source.insert(queue)
        source.insert(search)
        source.insert(QueueSavedSearchLink(queue: queue, search: search))
        try source.save()
        let first = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [queue],
            savedSearches: [search], defaults: try defaults()
        )
        let target = try context()
        _ = try KudosBackupService.restore(first, into: target, defaults: try defaults())
        let targetQueue = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first {
            $0.id == queue.id
        })
        #expect(targetQueue.searchLinks.count == 1)
        for link in queue.searchLinks { source.delete(link) }
        queue.searchSourcesModifiedAt = Date(timeIntervalSince1970: 2_000)
        try source.save()
        let cleared = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [queue],
            savedSearches: [search], defaults: try defaults()
        )
        let root = try #require(JSONSerialization.jsonObject(with: cleared.manifestData()) as? [String: Any])
        let archivedQueue = try #require((root["readingQueues"] as? [[String: Any]])?.first)
        #expect((archivedQueue["searchSources"] as? [Any])?.isEmpty == true)
        _ = try KudosBackupService.restore(cleared, into: target, defaults: try defaults())
        #expect(targetQueue.searchLinks.isEmpty)
    }

    @Test func allFourKindsAndUnknownKindsRoundTripWithoutBumpingVersion() throws {
        let source = try context()
        let queue = ReadingQueue(name: "Multi-Source Queue")
        let search = SavedSearch(name: "Search One", filters: AO3SearchFilters())
        search.lastOpenedAt = Date(timeIntervalSince1970: 1_000)
        let searchLink = QueueSavedSearchLink(queue: queue, search: search)
        searchLink.lastCheckedAt = Date(timeIntervalSince1970: 2_000)
        searchLink.newResultCount = 2

        let author = QueueSavedSearchLink(
            queue: queue,
            kindRaw: QueueSourceKind.author.rawValue,
            targetKey: QueueSourceDraft.authorTargetKey(username: "kestrel", pseud: "alt"),
            displayName: "alt (kestrel)",
            subtitle: "Pseud of kestrel",
            authorUsername: "kestrel",
            authorPseud: "alt",
            urlString: "https://archiveofourown.org/users/kestrel/pseuds/alt/works",
            lastOpenedAt: Date(timeIntervalSince1970: 1_100),
            lastCheckedAt: Date(timeIntervalSince1970: 2_100),
            newResultCount: 4,
            dateAdded: Date(timeIntervalSince1970: 900)
        )
        let series = QueueSavedSearchLink(
            queue: queue,
            kindRaw: QueueSourceKind.series.rawValue,
            targetKey: QueueSourceDraft.seriesTargetKey(id: 9876),
            displayName: "Starfall Arc",
            subtitle: "Series",
            ao3SeriesID: 9876,
            urlString: "https://archiveofourown.org/series/9876",
            lastOpenedAt: Date(timeIntervalSince1970: 1_200),
            lastCheckedAt: Date(timeIntervalSince1970: 2_200),
            newResultCount: 1,
            dateAdded: Date(timeIntervalSince1970: 910)
        )
        let tag = QueueSavedSearchLink(
            queue: queue,
            kindRaw: QueueSourceKind.tag.rawValue,
            targetKey: QueueSourceDraft.tagTargetKey(name: "Found Family"),
            displayName: "Found Family",
            subtitle: "Freeform",
            tagName: "Found Family",
            tagCategoryRaw: "Freeform",
            urlString: "https://archiveofourown.org/tags/Found%20Family/works",
            lastOpenedAt: Date(timeIntervalSince1970: 1_300),
            lastCheckedAt: Date(timeIntervalSince1970: 2_300),
            newResultCount: 20,
            dateAdded: Date(timeIntervalSince1970: 920)
        )
        queue.searchSourcesModifiedAt = Date(timeIntervalSince1970: 1_500)
        queue.sourcesModifiedAt = Date(timeIntervalSince1970: 1_600)

        source.insert(queue)
        source.insert(search)
        source.insert(searchLink)
        source.insert(author)
        source.insert(series)
        source.insert(tag)
        try source.save()

        let exported = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [queue],
            savedSearches: [search], defaults: try defaults()
        )
        #expect(exported.manifest.version == 8)

        // Inject a future unknown source kind with extra keys into the JSON payload.
        var root = try #require(
            JSONSerialization.jsonObject(with: exported.manifestData()) as? [String: Any]
        )
        var queues = try #require(root["readingQueues"] as? [[String: Any]])
        var sourcesArray = try #require(queues[0]["sources"] as? [[String: Any]])
        let unknownID = UUID()
        sourcesArray.append([
            "id": unknownID.uuidString,
            "kindRaw": "collection",
            "targetKey": "collection:yuletide2026",
            "displayName": "Yuletide 2026",
            "urlString": "https://archiveofourown.org/collections/yuletide2026",
            "collectionSlug": "yuletide2026",
            "extraFlag": true
        ])
        queues[0]["sources"] = sourcesArray
        root["readingQueues"] = queues
        let futureManifest = try KudosBackupContents.decodeManifest(
            JSONSerialization.data(withJSONObject: root)
        )

        let target = try context()
        _ = try KudosBackupService.restore(
            KudosBackupContents(manifest: futureManifest),
            into: target,
            defaults: try defaults()
        )
        let restoredQueue = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first {
            $0.id == queue.id
        })
        #expect(restoredQueue.savedSearchLinks.count == 1)
        #expect(restoredQueue.visibleNonSearchSources.count == 3)
        #expect(restoredQueue.nonSearchSources.count == 4)

        let restoredAuthor = try #require(
            restoredQueue.visibleNonSearchSources.first { $0.knownSourceKind == .author }
        )
        #expect(restoredAuthor.authorUsername == "kestrel")
        #expect(restoredAuthor.authorPseud == "alt")
        #expect(restoredAuthor.newResultCount == 4)
        #expect(restoredAuthor.lastOpenedAt == author.lastOpenedAt)

        let restoredSeries = try #require(
            restoredQueue.visibleNonSearchSources.first { $0.knownSourceKind == .series }
        )
        #expect(restoredSeries.ao3SeriesID == 9876)
        #expect(restoredSeries.newResultCount == 1)

        let restoredTag = try #require(
            restoredQueue.visibleNonSearchSources.first { $0.knownSourceKind == .tag }
        )
        #expect(restoredTag.tagName == "Found Family")
        #expect(restoredTag.tagCategoryRaw == "Freeform")
        #expect(restoredTag.newResultCount == 20)

        let restoredUnknown = try #require(
            restoredQueue.nonSearchSources.first { $0.sourceKindRaw == "collection" }
        )
        #expect(!restoredUnknown.isKnownSource)
        #expect(!restoredUnknown.countsNewResults)
        #expect(restoredUnknown.listingURL == nil)

        // Editing known sources keeps unknown kinds intact.
        let keepOnlyAuthor = [try #require(restoredAuthor.sourceDraft)]
        ReadingQueueService.syncNonSearchSources(for: restoredQueue, drafts: keepOnlyAuthor, in: target)
        try target.save()
        #expect(restoredQueue.nonSearchSources.contains { $0.sourceKindRaw == "collection" })

        // Re-export carries the unknown kind and its extra keys verbatim.
        let reexported = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [restoredQueue],
            savedSearches: try target.fetch(FetchDescriptor<SavedSearch>()),
            defaults: try defaults()
        )
        let reRoot = try #require(
            JSONSerialization.jsonObject(with: reexported.manifestData()) as? [String: Any]
        )
        let reQueues = try #require(reRoot["readingQueues"] as? [[String: Any]])
        let reQueue = try #require(reQueues.first {
            ($0["id"] as? String)?.lowercased() == queue.id.uuidString.lowercased()
        })
        let reSources = try #require(reQueue["sources"] as? [[String: Any]])
        let reUnknown = try #require(reSources.first { $0["kindRaw"] as? String == "collection" })
        #expect(reUnknown["targetKey"] as? String == "collection:yuletide2026")
        #expect(reUnknown["displayName"] as? String == "Yuletide 2026")
        #expect(reUnknown["collectionSlug"] as? String == "yuletide2026")
        #expect(reUnknown["extraFlag"] as? Bool == true)
    }

    @Test func absentSourcesKeyPreservesLocalAndUnrecordedOmitsKeysAndClearingTravels() throws {
        let source = try context()
        let queue = ReadingQueue(name: "Plain")
        source.insert(queue)
        try source.save()

        let emptyExport = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [queue], defaults: try defaults()
        )
        let emptyRoot = try #require(
            JSONSerialization.jsonObject(with: emptyExport.manifestData()) as? [String: Any]
        )
        let emptyQueue = try #require((emptyRoot["readingQueues"] as? [[String: Any]])?.first)
        #expect(emptyQueue["sources"] == nil)
        #expect(emptyQueue["sourcesModifiedAt"] == nil)

        let draft = try #require(QueueSourceDraft.tag(name: "Time Loop", category: "Freeform"))
        #expect(ReadingQueueService.addSource(draft, to: queue, in: source))
        queue.sourcesModifiedAt = Date(timeIntervalSince1970: 1_000)
        try source.save()

        let withSource = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [queue], defaults: try defaults()
        )
        let target = try context()
        _ = try KudosBackupService.restore(withSource, into: target, defaults: try defaults())
        let targetQueue = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first {
            $0.id == queue.id
        })
        #expect(targetQueue.visibleNonSearchSources.count == 1)

        // Legacy/Android archive omitting `sources` leaves local sources untouched even on Replace.
        var legacyRoot = try #require(
            JSONSerialization.jsonObject(with: withSource.manifestData()) as? [String: Any]
        )
        var legacyQueues = try #require(legacyRoot["readingQueues"] as? [[String: Any]])
        legacyQueues[0].removeValue(forKey: "sources")
        legacyQueues[0].removeValue(forKey: "sourcesModifiedAt")
        legacyRoot["readingQueues"] = legacyQueues
        let legacyManifest = try KudosBackupContents.decodeManifest(
            JSONSerialization.data(withJSONObject: legacyRoot)
        )
        _ = try KudosBackupService.restore(
            KudosBackupContents(manifest: legacyManifest),
            into: target,
            defaults: try defaults(),
            mode: .replaceLibrary
        )
        #expect(targetQueue.visibleNonSearchSources.count == 1)

        // Clearing non-search sources exports `sources: []` and propagates.
        ReadingQueueService.syncNonSearchSources(for: queue, drafts: [], in: source)
        queue.sourcesModifiedAt = Date(timeIntervalSince1970: 2_000)
        try source.save()
        let cleared = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [queue], defaults: try defaults()
        )
        let clearedRoot = try #require(
            JSONSerialization.jsonObject(with: cleared.manifestData()) as? [String: Any]
        )
        let clearedQueue = try #require((clearedRoot["readingQueues"] as? [[String: Any]])?.first)
        #expect((clearedQueue["sources"] as? [Any])?.isEmpty == true)
        _ = try KudosBackupService.restore(cleared, into: target, defaults: try defaults())
        #expect(targetQueue.nonSearchSources.isEmpty)
    }

    @Test func deletingSavedSearchLeavesOtherSourcesAndSmartQueuesSkipSources() throws {
        let context = try self.context()
        let queue = ReadingQueue(name: "Mixed")
        let search = SavedSearch(name: "S", filters: AO3SearchFilters())
        let searchLink = QueueSavedSearchLink(queue: queue, search: search)
        context.insert(queue)
        context.insert(search)
        context.insert(searchLink)
        let author = try #require(QueueSourceDraft.author(username: "writer"))
        #expect(ReadingQueueService.addSource(author, to: queue, in: context))
        try context.save()

        context.delete(search)
        try context.save()
        #expect(queue.savedSearchLinks.isEmpty)
        #expect(queue.visibleNonSearchSources.count == 1)
        #expect(queue.visibleNonSearchSources.first?.authorUsername == "writer")

        // Smart queues never import or export `sources`.
        let smart = ReadingQueue(name: "Smart", kind: .smart)
        context.insert(smart)
        try context.save()
        let smartExport = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [smart], defaults: try defaults()
        )
        var root = try #require(
            JSONSerialization.jsonObject(with: smartExport.manifestData()) as? [String: Any]
        )
        var queues = try #require(root["readingQueues"] as? [[String: Any]])
        let idx = try #require(queues.firstIndex { $0["kindRaw"] as? String == "smart" })
        queues[idx]["sources"] = [[
            "id": UUID().uuidString,
            "kindRaw": "author",
            "targetKey": "user:writer",
            "authorUsername": "writer"
        ]]
        queues[idx]["sourcesModifiedAt"] = "2026-11-20T00:00:00.000Z"
        root["readingQueues"] = queues
        let tainted = try KudosBackupContents.decodeManifest(JSONSerialization.data(withJSONObject: root))
        let target = try self.context()
        _ = try KudosBackupService.restore(
            KudosBackupContents(manifest: tainted), into: target, defaults: try defaults()
        )
        let restoredSmart = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first {
            $0.id == smart.id
        })
        #expect(restoredSmart.searchLinks.isEmpty)
    }
}
}
