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

        /// Review 3 P2 #2: editing one exclusion list writes only that key so backup/sync
        /// omits the other 8 keys and never clobbers another device's untouched toggles or lists.
        @Test func singleExclusionEditOmitsOtherEightKeysAndPreservesOtherDeviceOnMerge() throws {
            let context = try makeContext()
            let deviceADefaults = try testDefaults()
            let deviceAOptions = InsightsOptions(
                discreetMode: true,
                hideReadingTime: true,
                countRereads: false,
                countReadAloud: false,
                askAboutUntouched: false,
                untouchedDays: 14,
                excludedFandoms: ["Sherlock"],
                excludedTags: ["Slow Burn"],
                excludedWorkIDs: []
            )
            deviceAOptions.save(to: deviceADefaults, notifySync: false)

            let deviceBDefaults = try testDefaults()
            let excludedWorkID = UUID().uuidString.lowercased()
            InsightsOptions.saveExcludedWorkIDs([excludedWorkID], to: deviceBDefaults, notifySync: false)

            let deviceBContents = try KudosBackupService.makeContents(
                works: [], bookmarks: [], fonts: [], readingQueues: [],
                defaults: deviceBDefaults
            )
            let root = try #require(
                try JSONSerialization.jsonObject(with: deviceBContents.manifestData()) as? [String: Any]
            )
            let settings = try #require(root["settings"] as? [String: Any])
            #expect(settings["excludedWorkIDs"] as? [String] == [excludedWorkID])
            for untouchedKey in [
                "discreetMode", "hideReadingTime", "countRereads", "countReadAloud",
                "askAboutUntouched", "untouchedDays", "excludedFandoms", "excludedTags"
            ] {
                #expect(settings[untouchedKey] == nil)
            }

            // Merging Device B's backup into Device A applies `excludedWorkIDs` without clobbering.
            _ = try KudosBackupService.restore(
                deviceBContents, into: context, defaults: deviceADefaults, mode: .merge
            )
            let merged = InsightsOptions.load(from: deviceADefaults)
            #expect(merged.discreetMode == true)
            #expect(merged.hideReadingTime == true)
            #expect(merged.countRereads == false)
            #expect(merged.countReadAloud == false)
            #expect(merged.askAboutUntouched == false)
            #expect(merged.untouchedDays == 14)
            #expect(merged.excludedFandoms == ["Sherlock"])
            #expect(merged.excludedTags == ["Slow Burn"])
            #expect(merged.excludedWorkIDs == [excludedWorkID])

            // Clear All on Device B clears only keys present on Device B, leaving others absent.
            InsightsOptions.clearAllExclusions(in: deviceBDefaults, notifySync: false)
            let clearedContents = try KudosBackupService.makeContents(
                works: [], bookmarks: [], fonts: [], readingQueues: [],
                defaults: deviceBDefaults
            )
            let clearedRoot = try #require(
                try JSONSerialization.jsonObject(with: clearedContents.manifestData()) as? [String: Any]
            )
            let clearedSettings = try #require(clearedRoot["settings"] as? [String: Any])
            #expect(clearedSettings["excludedWorkIDs"] as? [String] == [])
            #expect(clearedSettings["excludedFandoms"] == nil)
            #expect(clearedSettings["excludedTags"] == nil)
        }

        /// Review 3 P3 #13: resetting the log while a detached Read Aloud session is open
        /// rotates its `recordID` and zeros pre-reset seconds so ending it later does not
        /// re-insert a tombstoned row with pre-reset duration.
        @Test func resetReadingLogRotatesOpenDetachedSessionRecordIDAndResetsDuration() throws {
            ReadingLogService.resetOpenSessionsForTests()
            let context = try makeContext()
            let work = SavedWork(title: "Detached Audio", author: "Author A")
            work.wordCount = 10_000
            context.insert(work)
            try context.save()

            let t0 = Date(timeIntervalSince1970: 500_000)
            ReadingLogService.handleDetachedSpeech(.playing, for: work, playbackRate: 1.0, now: t0)
            ReadingLogService.handleDetachedSpeech(
                .paused, for: work, playbackRate: 1.0, now: t0.addingTimeInterval(60)
            )
            let beforeReset = try context.fetch(FetchDescriptor<ReadingSession>())
            let oldRecordID = try #require(beforeReset.first?.id)
            #expect(beforeReset.count == 1)

            let resetTime = t0.addingTimeInterval(100)
            let deleted = try InsightsExportService.resetReadingLog(in: context, now: resetTime)
            #expect(deleted == 1)
            #expect(try context.fetch(FetchDescriptor<ReadingSession>()).isEmpty)

            // Resuming and stopping after reset must write a fresh non-tombstoned row with only post-reset time.
            ReadingLogService.handleDetachedSpeech(
                .playing, for: work, playbackRate: 1.0, now: resetTime.addingTimeInterval(10)
            )
            ReadingLogService.handleDetachedSpeech(
                .stopped, for: work, playbackRate: 1.0, now: resetTime.addingTimeInterval(35)
            )
            let afterReset = try context.fetch(FetchDescriptor<ReadingSession>())
            #expect(afterReset.count == 1)
            let fresh = try #require(afterReset.first)
            #expect(fresh.id != oldRecordID)
            #expect(fresh.durationSeconds == 25)
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
