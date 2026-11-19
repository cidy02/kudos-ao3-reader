import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites {
    @MainActor
    @Suite(.serialized)
    struct InsightsD5D6PersistenceTests {
        private func schema() -> Schema {
            Schema([
                SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
                WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
                SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self,
                ReadingAnnotation.self, ReadingSession.self, ReadingFavorite.self,
                FandomReadWatermark.self, TagAlias.self
            ])
        }

        private func makeContext() throws -> ModelContext {
            let modelSchema = schema()
            let container = try ModelContainer(
                for: modelSchema,
                configurations: [ModelConfiguration(schema: modelSchema, isStoredInMemoryOnly: true)]
            )
            return ModelContext(container)
        }

        private func testDefaults() throws -> UserDefaults {
            let name = "InsightsD5D6PersistenceTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defaults.removePersistentDomain(forName: name)
            return defaults
        }

        @Test func insightsOptionsOmitWhenUnsetRoundTripWhenSetAndAbsentLeavesLocal() throws {
            let context = try makeContext()
            let untouchedDefaults = try testDefaults()

            let untouchedContents = try KudosBackupService.makeContents(
                works: [], bookmarks: [], fonts: [], readingQueues: [],
                defaults: untouchedDefaults
            )
            let untouchedRoot = try #require(
                try JSONSerialization.jsonObject(with: untouchedContents.manifestData()) as? [String: Any]
            )
            let untouchedSettings = try #require(untouchedRoot["settings"] as? [String: Any])
            for key in [
                "discreetMode", "hideReadingTime", "countRereads", "countReadAloud",
                "askAboutUntouched", "untouchedDays",
                "excludedFandoms", "excludedTags", "excludedWorkIDs"
            ] {
                #expect(untouchedSettings[key] == nil)
            }

            let sourceDefaults = try testDefaults()
            let excludedWorkID = UUID()
            let custom = InsightsOptions(
                discreetMode: true,
                hideReadingTime: true,
                countRereads: false,
                countReadAloud: false,
                askAboutUntouched: false,
                untouchedDays: 14,
                excludedFandoms: ["Sherlock", "Arcane"],
                excludedTags: ["Slow Burn"],
                excludedWorkIDs: [excludedWorkID.uuidString]
            )
            custom.save(to: sourceDefaults, notifySync: false)

            let configuredContents = try KudosBackupService.makeContents(
                works: [], bookmarks: [], fonts: [], readingQueues: [],
                defaults: sourceDefaults
            )
            let targetDefaults = try testDefaults()
            _ = try KudosBackupService.restore(
                configuredContents, into: context, defaults: targetDefaults, mode: .merge
            )
            let restored = InsightsOptions.load(from: targetDefaults)
            #expect(restored == custom)

            // Absent keys in an incoming archive must leave local preferences unchanged.
            let localDefaults = try testDefaults()
            let localCustom = InsightsOptions(
                discreetMode: true,
                hideReadingTime: false,
                countRereads: false,
                countReadAloud: true,
                askAboutUntouched: false,
                untouchedDays: 35,
                excludedFandoms: ["Local Fandom"],
                excludedTags: ["Local Tag"],
                excludedWorkIDs: [UUID().uuidString]
            )
            localCustom.save(to: localDefaults, notifySync: false)

            _ = try KudosBackupService.restore(
                untouchedContents, into: context, defaults: localDefaults, mode: .merge
            )
            #expect(InsightsOptions.load(from: localDefaults) == localCustom)
        }

        @Test func resetReadingLogMintsTombstonesAndFolderSyncMergeDoesNotResurrect() throws {
            let context = try makeContext()
            let defaults = try testDefaults()

            let work = SavedWork(title: "Sync Survivor", author: "Author A")
            work.lastSpineIndex = 3
            work.lastScrollFraction = 0.75
            work.readiumLocator = "{\"href\":\"ch4.xhtml\"}"
            work.setReadingStatus(.stopped, at: Date(timeIntervalSince1970: 2_000))
            work.stoppedAt = Date(timeIntervalSince1970: 2_000)
            work.stopReasonRaw = "tooLong"
            work.stopTag = "Epic"
            work.stopNote = "Stopped midway"

            let s1 = ReadingSession(
                workID: work.id,
                workTitle: work.title,
                startedAt: Date(timeIntervalSince1970: 1_000),
                endedAt: Date(timeIntervalSince1970: 1_500),
                durationSeconds: 500,
                startProgress: 0,
                endingProgress: 0.4,
                wordCount: 20_000
            )
            let s2 = ReadingSession(
                workID: work.id,
                workTitle: work.title,
                startedAt: Date(timeIntervalSince1970: 1_600),
                endedAt: Date(timeIntervalSince1970: 1_900),
                durationSeconds: 300,
                startProgress: 0.4,
                endingProgress: 0.75,
                wordCount: 20_000
            )
            context.insert(work)
            context.insert(s1)
            context.insert(s2)
            try context.save()

            let staleRemoteSnapshot = try KudosBackupService.makeContents(
                works: [work],
                bookmarks: [],
                fonts: [],
                readingQueues: [],
                readingSessions: [s1, s2],
                defaults: try testDefaults()
            )

            let deletedCount = try InsightsExportService.resetReadingLog(in: context)
            #expect(deletedCount == 2)
            #expect(try context.fetch(FetchDescriptor<ReadingSession>()).isEmpty)

            // Simulate Folder Sync merge bringing an older snapshot that still carries s1 and s2.
            _ = try KudosBackupService.restore(
                staleRemoteSnapshot,
                into: context,
                defaults: defaults,
                mode: .merge
            )

            #expect(try context.fetch(FetchDescriptor<ReadingSession>()).isEmpty)
            let works = try context.fetch(FetchDescriptor<SavedWork>())
            let survivor = try #require(works.first { $0.id == work.id })
            #expect(survivor.lastSpineIndex == 3)
            #expect(survivor.lastScrollFraction == 0.75)
            #expect(survivor.readiumLocator == "{\"href\":\"ch4.xhtml\"}")
            #expect(survivor.readingStatusRaw == "stopped")
            #expect(survivor.stopReasonRaw == "tooLong")
            #expect(survivor.stopTag == "Epic")
            #expect(survivor.stopNote == "Stopped midway")
        }
    }
}
