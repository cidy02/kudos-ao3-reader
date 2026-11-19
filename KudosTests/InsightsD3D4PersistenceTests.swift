import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites {
    @MainActor
    @Suite(.serialized)
    struct InsightsD3D4PersistenceTests {
        private func makeContainer() throws -> ModelContainer {
            let schema = Schema([
                SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
                WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
                SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
                ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
            ])
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }

        private func testDefaults() throws -> UserDefaults {
            let name = "InsightsD3D4PersistenceTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defaults.removePersistentDomain(forName: name)
            return defaults
        }

        @Test func backfillComputesChapterCountsFromLocalEPUBWithoutBumpingModifiedAt() async throws {
            let container = try makeContainer()
            let context = ModelContext(container)
            let work = SavedWork(title: "Backfill Target", author: "Writer")
            let data = try EPUBBuilder.archive(
                metadata: EPUBBuilder.Metadata(title: "Backfill Target"),
                chapters: [
                    EPUBBuilder.Chapter(
                        title: "Chapter 1: Heading Excluded",
                        bodyXHTML: "<aside class=\"author-note\"><p>Author note excluded.</p></aside>"
                            + "<p>One two three four five.</p>"
                    ),
                    EPUBBuilder.Chapter(
                        title: "Chapter 2",
                        bodyXHTML: "<p>Six seven eight.</p>"
                    )
                ]
            )
            let dest = work.fileURL
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try data.write(to: dest)
            defer { try? FileManager.default.removeItem(at: dest) }

            let stamped = Date(timeIntervalSince1970: 50_000)
            work.hasEPUB = true
            work.lastModifiedAt = stamped
            work.syncStatus = .synced
            context.insert(work)
            try context.save()

            try await SavedWorkChapterWordCountBackfill(modelContainer: container).run()

            let verify = ModelContext(container)
            let updated = try #require(try verify.fetch(FetchDescriptor<SavedWork>()).first)
            #expect(updated.chapterWordCounts == [5, 3])
            #expect(updated.wordUnitRaw == SavedWork.WordUnit.words.rawValue)
            #expect(updated.lastModifiedAt == stamped)
            #expect(updated.syncStatus == .synced)
        }

        @Test func d3BackupFieldsOmitWhenEmptyRoundTripWhenSetAndSurviveOldPayloads() throws {
            let container = try makeContainer()
            let source = ModelContext(container)
            let untouched = SavedWork(title: "Untouched", author: "A")
            let counted = SavedWork(title: "Counted", author: "B")
            counted.chapterWordCounts = [1_200, 2_300]
            counted.wordUnitRaw = SavedWork.WordUnit.characters.rawValue
            source.insert(untouched)
            source.insert(counted)
            try source.save()

            let contents = try KudosBackupService.makeContents(
                works: [untouched, counted],
                bookmarks: [],
                fonts: [],
                readingQueues: [],
                defaults: try testDefaults()
            )
            let root = try #require(
                JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any]
            )
            let archivedWorks = try #require(root["works"] as? [[String: Any]])
            let archivedUntouched = try #require(archivedWorks.first { $0["title"] as? String == "Untouched" })
            let archivedCounted = try #require(archivedWorks.first { $0["title"] as? String == "Counted" })

            #expect(archivedUntouched["chapterWordCountsJSON"] == nil)
            #expect(archivedUntouched["wordUnitRaw"] == nil)
            #expect(archivedCounted["chapterWordCountsJSON"] as? String == "[1200,2300]")
            #expect(archivedCounted["wordUnitRaw"] as? String == "characters")

            // Restore into a fresh context and verify round-trip.
            let destContainer = try makeContainer()
            let dest = ModelContext(destContainer)
            _ = try KudosBackupService.restore(contents, into: dest, defaults: try testDefaults())
            let restoredCounted = try #require(
                try dest.fetch(FetchDescriptor<SavedWork>()).first { $0.id == counted.id }
            )
            #expect(restoredCounted.chapterWordCounts == [1_200, 2_300])
            #expect(restoredCounted.wordUnitRaw == SavedWork.WordUnit.characters.rawValue)

            // Simulate an older/Android archive missing D3 keys on merge: local stays intact.
            var modifiedRoot = root
            var modifiedWorks = archivedWorks
            for index in modifiedWorks.indices {
                modifiedWorks[index].removeValue(forKey: "chapterWordCountsJSON")
                modifiedWorks[index].removeValue(forKey: "wordUnitRaw")
            }
            modifiedRoot["works"] = modifiedWorks
            let legacyManifest = try KudosBackupContents.decodeManifest(
                JSONSerialization.data(withJSONObject: modifiedRoot)
            )
            _ = try KudosBackupService.restore(
                KudosBackupContents(manifest: legacyManifest),
                into: dest,
                defaults: try testDefaults()
            )

            let afterMerge = try #require(
                try dest.fetch(FetchDescriptor<SavedWork>()).first { $0.id == counted.id }
            )
            #expect(afterMerge.chapterWordCounts == [1_200, 2_300])
            #expect(afterMerge.wordUnitRaw == SavedWork.WordUnit.characters.rawValue)
        }
    }
}
