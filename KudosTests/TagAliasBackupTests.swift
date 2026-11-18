import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites {
    @Suite(.serialized)
    @MainActor
    struct TagAliasBackupTests {
        private func makeContainer() throws -> ModelContainer {
            let schema = Schema([
                SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
                ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self,
                QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
                ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self,
                FollowedTag.self, TagAlias.self
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        }

        private func testDefaults() throws -> (defaults: UserDefaults, name: String) {
            let name = "TagAliasBackupTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defaults.removePersistentDomain(forName: name)
            return (defaults, name)
        }

        @Test func roundTripRestoresAliasesAndParentFandoms() throws {
            let source = try makeContainer()
            let (defaults, name) = try testDefaults()
            defer { defaults.removePersistentDomain(forName: name) }

            let learnedAt = Date(timeIntervalSince1970: 1_750_000_000)
            let modifiedAt = Date(timeIntervalSince1970: 1_750_000_500)
            let alias = TagAlias(
                name: "Spider-Verse",
                canonicalName: "Spider-Man: Into the Spider-Verse",
                kind: .fandom,
                parentFandoms: ["Spider-Man - All Media Types"],
                learnedAt: learnedAt,
                lastModifiedAt: modifiedAt
            )
            source.mainContext.insert(alias)
            try source.mainContext.save()

            let contents = try KudosBackupService.makeContents(
                works: [],
                bookmarks: [],
                fonts: [],
                readingQueues: [],
                tagAliases: [alias],
                defaults: defaults
            )
            let zipBytes = try contents.zipData()
            let decodedContents = try KudosBackupContents(zipData: zipBytes)

            let target = try makeContainer()
            _ = try KudosBackupService.restore(
                decodedContents,
                into: target.mainContext,
                defaults: defaults,
                mode: .reconcile
            )

            let restored = try target.mainContext.fetch(FetchDescriptor<TagAlias>())
            #expect(restored.count == 1)
            let item = try #require(restored.first)
            #expect(item.id == alias.id)
            #expect(item.name == "Spider-Verse")
            #expect(item.canonicalName == "Spider-Man: Into the Spider-Verse")
            #expect(item.kind == .fandom)
            #expect(item.parentFandoms == ["Spider-Man - All Media Types"])
            #expect(item.learnedAt == learnedAt)
            #expect(item.lastModifiedAt == modifiedAt)
        }

        @Test func emptyArrayAndEmptyParentsOmitJSONKeysAndKeepV8() throws {
            let (defaults, name) = try testDefaults()
            defer { defaults.removePersistentDomain(forName: name) }

            // Empty tagAliases omits key completely and preserves v8 manifest compatibility.
            let emptyExport = try KudosBackupService.makeContents(
                works: [],
                bookmarks: [],
                fonts: [],
                readingQueues: [],
                defaults: defaults
            )
            #expect(emptyExport.manifest.version == KudosBackupManifest.currentVersion)
            let emptyRoot = try #require(
                JSONSerialization.jsonObject(with: emptyExport.manifestData()) as? [String: Any]
            )
            #expect(emptyRoot["tagAliases"] == nil)

            // Alias without parents omits "parentFandoms" key in JSON.
            let minimalAlias = TagAlias(
                name: "h/c",
                canonicalName: "Hurt/Comfort",
                kind: .freeform,
                parentFandoms: []
            )
            let withAlias = try KudosBackupService.makeContents(
                works: [],
                bookmarks: [],
                fonts: [],
                readingQueues: [],
                tagAliases: [minimalAlias],
                defaults: defaults
            )
            let root = try #require(
                JSONSerialization.jsonObject(with: withAlias.manifestData()) as? [String: Any]
            )
            let exportedAlias = try #require((root["tagAliases"] as? [[String: Any]])?.first)
            #expect(exportedAlias["name"] as? String == "h/c")
            #expect(exportedAlias["canonicalName"] as? String == "Hurt/Comfort")
            #expect(exportedAlias["parentFandoms"] == nil)
        }

        @Test func legacyManifestWithoutTagAliasesLeavesLocalAliasesUntouched() throws {
            let (defaults, name) = try testDefaults()
            defer { defaults.removePersistentDomain(forName: name) }

            let emptyExport = try KudosBackupService.makeContents(
                works: [], bookmarks: [], fonts: [], readingQueues: [], defaults: defaults
            )
            let legacyManifest = try KudosBackupContents.decodeManifest(emptyExport.manifestData())
            let legacyArchive = KudosBackupContents(manifest: legacyManifest)

            let target = try makeContainer()
            let existing = TagAlias(name: "BNHA", canonicalName: "Boku no Hero Academia", kind: .fandom)
            target.mainContext.insert(existing)
            try target.mainContext.save()

            for mode in [BackupImportMode.merge, .reconcile, .replaceLibrary] {
                _ = try KudosBackupService.restore(
                    legacyArchive,
                    into: target.mainContext,
                    defaults: defaults,
                    mode: mode
                )
                let fetched = try target.mainContext.fetch(FetchDescriptor<TagAlias>())
                #expect(fetched.count == 1)
                #expect(fetched.first?.name == "BNHA")
            }
        }

        @Test func deleteMintsTombstoneAndBlocksStaleResurrectionAcrossDevices() throws {
            let (defaults, name) = try testDefaults()
            defer { defaults.removePersistentDomain(forName: name) }

            let container = try makeContainer()
            let context = container.mainContext
            let t0 = Date(timeIntervalSince1970: 1_750_000_000)

            let alias = try #require(TagAliasStore.upsert(
                name: "DW",
                canonicalName: "Doctor Who",
                kind: .fandom,
                in: context,
                now: t0
            ))
            let staleArchive = try KudosBackupService.makeContents(
                works: [],
                bookmarks: [],
                fonts: [],
                readingQueues: [],
                tagAliases: [alias],
                defaults: defaults
            )

            // Deleting records a .tagAlias tombstone.
            TagAliasStore.delete(alias, in: context)
            let tombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
            #expect(tombstones.contains { $0.recordType == .tagAlias && $0.recordID == alias.id })

            // Stale archive containing deleted alias must NOT resurrect it.
            _ = try KudosBackupService.restore(
                staleArchive,
                into: context,
                defaults: defaults,
                mode: .reconcile
            )
            #expect(try context.fetch(FetchDescriptor<TagAlias>()).isEmpty)

            // Peer device still holding the stale copy and importing our empty-alias
            // tombstone manifest should delete its stale copy too (even when nil tagAliases).
            let peer = try makeContainer()
            peer.mainContext.insert(TagAlias(
                id: alias.id,
                name: "DW",
                canonicalName: "Doctor Who",
                kind: .fandom,
                learnedAt: t0,
                lastModifiedAt: t0
            ))
            try peer.mainContext.save()

            let deletionManifest = try KudosBackupService.makeContents(
                works: [],
                bookmarks: [],
                fonts: [],
                readingQueues: [],
                tagAliases: [],
                tombstones: tombstones,
                defaults: defaults
            )
            _ = try KudosBackupService.restore(
                deletionManifest,
                into: peer.mainContext,
                defaults: defaults,
                mode: .reconcile
            )
            #expect(try peer.mainContext.fetch(FetchDescriptor<TagAlias>()).isEmpty)
        }

        @Test func replaceModeOmissionMintsTagAliasTombstone() throws {
            let (defaults, name) = try testDefaults()
            defer { defaults.removePersistentDomain(forName: name) }

            let container = try makeContainer()
            let context = container.mainContext
            let t0 = Date(timeIntervalSince1970: 1_750_000_000)

            let keepAlias = TagAlias(
                name: "A",
                canonicalName: "Canon A",
                kind: .freeform,
                learnedAt: t0,
                lastModifiedAt: t0
            )
            let dropAlias = TagAlias(
                name: "B",
                canonicalName: "Canon B",
                kind: .freeform,
                learnedAt: t0,
                lastModifiedAt: t0
            )
            context.insert(keepAlias)
            context.insert(dropAlias)
            try context.save()

            let archiveKeepingOnlyA = try KudosBackupService.makeContents(
                works: [],
                bookmarks: [],
                fonts: [],
                readingQueues: [],
                tagAliases: [keepAlias],
                defaults: defaults
            )

            _ = try KudosBackupService.restore(
                archiveKeepingOnlyA,
                into: context,
                defaults: defaults,
                mode: .replaceLibrary
            )

            let surviving = try context.fetch(FetchDescriptor<TagAlias>())
            #expect(surviving.map(\.id) == [keepAlias.id])
            let tombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
            #expect(tombstones.contains { $0.recordType == .tagAlias && $0.recordID == dropAlias.id })
        }

        @Test func folderSyncRoundTripsTagAlias() async throws {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("TagAliasFolderSync-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }

            let (publisherDefaults, pubSuite) = try testDefaults()
            defer { publisherDefaults.removePersistentDomain(forName: pubSuite) }
            let (receiverDefaults, recSuite) = try testDefaults()
            defer { receiverDefaults.removePersistentDomain(forName: recSuite) }

            let publisher = try makeContainer()
            let t0 = Date(timeIntervalSince1970: 1_750_000_000)
            let alias = try #require(TagAliasStore.upsert(
                name: "SPN",
                canonicalName: "Supernatural",
                kind: .fandom,
                in: publisher.mainContext,
                now: t0
            ))
            try FolderSyncService.connect(to: folder, defaults: publisherDefaults)
            _ = try await FolderSyncService.syncUp(
                in: publisher.mainContext,
                defaults: publisherDefaults
            )

            let receiver = try makeContainer()
            try FolderSyncService.connect(to: folder, defaults: receiverDefaults)
            _ = try await FolderSyncService.syncDown(
                in: receiver.mainContext,
                defaults: receiverDefaults
            )

            let synced = try receiver.mainContext.fetch(FetchDescriptor<TagAlias>())
            #expect(synced.count == 1)
            #expect(synced.first?.name == "SPN")
            #expect(synced.first?.canonicalName == "Supernatural")
            #expect(synced.first?.kind == .fandom)

            // Deleting on publisher syncs the deletion down via .tagAlias tombstone.
            TagAliasStore.delete(alias, in: publisher.mainContext)
            _ = try await FolderSyncService.syncUp(
                in: publisher.mainContext,
                defaults: publisherDefaults
            )
            _ = try await FolderSyncService.syncDown(
                in: receiver.mainContext,
                defaults: receiverDefaults
            )
            #expect(try receiver.mainContext.fetch(FetchDescriptor<TagAlias>()).isEmpty)
        }
    }
}
