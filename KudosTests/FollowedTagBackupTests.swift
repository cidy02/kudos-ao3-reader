import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct FollowedTagBackupTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
            ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self,
            QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self,
            FollowedTag.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func testDefaults() throws -> (defaults: UserDefaults, name: String) {
        let name = "FollowedTagBackupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test func backupRoundTripPreservesFieldsAndSwitches() throws {
        let sourceContainer = try makeContainer()
        let source = sourceContainer.mainContext
        let (defaults, name) = try testDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let followedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let checkedAt = Date(timeIntervalSince1970: 1_750_010_000)
        let seenPublishedAt = Date(timeIntervalSince1970: 1_750_009_000)
        let modifiedAt = Date(timeIntervalSince1970: 1_750_020_000)

        let tag = FollowedTag(
            ao3TagID: 27785,
            name: "Doctor Who (2005)",
            tagCategoryRaw: "Fandom",
            tagURLString: "https://archiveofourown.org/tags/Doctor%20Who%20(2005)/works",
            showOnHome: false,
            completeOnly: true,
            hideExplicit: true,
            followedAt: followedAt,
            lastCheckedAt: checkedAt,
            lastSeenWorkID: 9123456,
            lastSeenPublishedAt: seenPublishedAt,
            seenWorkIDs: [9123456, 9123400],
            lastModifiedAt: modifiedAt
        )
        source.insert(tag)
        try source.save()

        let contents = try KudosBackupService.makeContents(
            works: [],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            followedTags: [tag],
            defaults: defaults
        )

        let targetContainer = try makeContainer()
        let target = targetContainer.mainContext
        _ = try KudosBackupService.restore(contents, into: target, defaults: defaults, mode: .reconcile)

        let restored = try target.fetch(FetchDescriptor<FollowedTag>())
        #expect(restored.count == 1)
        let item = try #require(restored.first)
        #expect(item.id == tag.id)
        #expect(item.ao3TagID == 27785)
        #expect(item.name == "Doctor Who (2005)")
        #expect(item.tagCategoryRaw == "Fandom")
        #expect(item.tagURLString == "https://archiveofourown.org/tags/Doctor%20Who%20(2005)/works")
        #expect(!item.showOnHome)
        #expect(item.completeOnly)
        #expect(item.hideExplicit)
        #expect(item.followedAt == followedAt)
        #expect(item.lastCheckedAt == checkedAt)
        #expect(item.lastSeenWorkID == 9123456)
        #expect(item.lastSeenPublishedAt == seenPublishedAt)
        #expect(item.seenWorkIDs == [9123456, 9123400])
        #expect(item.lastModifiedAt == modifiedAt)
    }

    @Test func oldBackupWithoutFollowedTagsKeyImportsCleanlyAndLeavesLocalTagsUntouched() throws {
        let (defaults, name) = try testDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        // Export an archive with 0 followed tags (no "followedTags" key at all), mirroring old backups.
        let emptyExport = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [], defaults: defaults
        )
        let rawRoot = try #require(JSONSerialization.jsonObject(with: emptyExport.manifestData()) as? [String: Any])
        #expect(rawRoot["followedTags"] == nil)

        let manifestData = try emptyExport.manifestData()
        let decodedManifest = try KudosBackupContents.decodeManifest(manifestData)
        let legacyArchive = KudosBackupContents(manifest: decodedManifest)

        let targetContainer = try makeContainer()
        let target = targetContainer.mainContext
        let localTag = FollowedTag(ao3TagID: 42, name: "Sherlock (TV)", tagCategoryRaw: "Fandom")
        target.insert(localTag)
        try target.save()

        for mode in [BackupImportMode.merge, .replaceLibrary, .reconcile] {
            _ = try KudosBackupService.restore(legacyArchive, into: target, defaults: defaults, mode: mode)
            let fetched = try target.fetch(FetchDescriptor<FollowedTag>())
            #expect(fetched.count == 1)
            #expect(fetched[0].ao3TagID == 42)
            #expect(fetched[0].name == "Sherlock (TV)")
        }
    }

    @Test func unrecordedOptionalValuesExportNoneOfTheKeys() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (defaults, name) = try testDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let minimalTag = FollowedTag(ao3TagID: 777, name: "Minimal Tag")
        context.insert(minimalTag)
        try context.save()

        let contents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            followedTags: [minimalTag], defaults: defaults
        )
        let root = try #require(JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any])
        let exportedTag = try #require((root["followedTags"] as? [[String: Any]])?.first)
        #expect(exportedTag["tagCategoryRaw"] == nil)
        #expect(exportedTag["tagURLString"] == nil)
        #expect(exportedTag["lastCheckedAt"] == nil)
        #expect(exportedTag["lastSeenWorkID"] == nil)
        #expect(exportedTag["lastSeenPublishedAt"] == nil)
        #expect(exportedTag["seenWorkIDs"] == nil)
    }

    @Test func unfollowingRecordsTombstoneSoOlderBackupCannotResurrectTag() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (defaults, name) = try testDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let oldTime = Date(timeIntervalSince1970: 1_750_000_000)
        let tag = FollowedTag(
            ao3TagID: 888,
            name: "Unfollowed Tag",
            followedAt: oldTime,
            lastModifiedAt: oldTime
        )
        context.insert(tag)
        try context.save()

        let staleArchive = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            followedTags: [tag], defaults: defaults
        )

        FollowedTagStore.unfollow(tag, in: context, updateStore: nil)
        #expect(try context.fetch(FetchDescriptor<FollowedTag>()).isEmpty)
        let tombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        #expect(tombstones.contains { $0.recordType == .followedTag && $0.recordID == tag.id })

        _ = try KudosBackupService.restore(staleArchive, into: context, defaults: defaults, mode: .reconcile)
        #expect(try context.fetch(FetchDescriptor<FollowedTag>()).isEmpty)
    }
}
}
