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
        let restored = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first)
        #expect(restored.searchLinks.first?.newResultCount == 0)
        _ = try KudosBackupService.restore(beforeVisit, into: target, defaults: try defaults())
        #expect(restored.searchLinks.first?.newResultCount == 0)
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
}
}
