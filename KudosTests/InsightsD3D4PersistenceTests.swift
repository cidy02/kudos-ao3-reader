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

        private func sampleEPUB(title: String, body: String) throws -> Data {
            try EPUBBuilder.archive(
                metadata: EPUBBuilder.Metadata(title: title),
                chapters: [EPUBBuilder.Chapter(title: "Chapter 1", bodyXHTML: body)],
                modified: Date(timeIntervalSince1970: 0)
            )
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

        @Test func d3BackupFieldsOmitWhenEmptyRoundTripValidValuesAndSurviveOldPayloads() throws {
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

            let destContainer = try makeContainer()
            let dest = ModelContext(destContainer)
            _ = try KudosBackupService.restore(contents, into: dest, defaults: try testDefaults())
            let restoredCounted = try #require(
                try dest.fetch(FetchDescriptor<SavedWork>()).first { $0.id == counted.id }
            )
            #expect(restoredCounted.chapterWordCounts == [1_200, 2_300])
            #expect(restoredCounted.wordUnitRaw == SavedWork.WordUnit.characters.rawValue)

            // Older/Android payload without D3 keys keeps existing local values intact;
            // malformed D3 values are rejected on merge.
            var modifiedRoot = root
            var modifiedWorks = archivedWorks
            for index in modifiedWorks.indices {
                if modifiedWorks[index]["id"] as? String == counted.id.uuidString {
                    modifiedWorks[index].removeValue(forKey: "chapterWordCountsJSON")
                    modifiedWorks[index].removeValue(forKey: "wordUnitRaw")
                } else {
                    modifiedWorks[index]["chapterWordCountsJSON"] = "[-5, 10]"
                    modifiedWorks[index]["wordUnitRaw"] = "bogus"
                }
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

            let afterMergeCounted = try #require(
                try dest.fetch(FetchDescriptor<SavedWork>()).first { $0.id == counted.id }
            )
            #expect(afterMergeCounted.chapterWordCounts == [1_200, 2_300])
            #expect(afterMergeCounted.wordUnitRaw == SavedWork.WordUnit.characters.rawValue)

            let afterMergeUntouched = try #require(
                try dest.fetch(FetchDescriptor<SavedWork>()).first { $0.id == untouched.id }
            )
            #expect(afterMergeUntouched.chapterWordCountsJSON.isEmpty)
            #expect(afterMergeUntouched.wordUnitRaw.isEmpty)
        }

        @Test func backupReconcileWithNewerEPUBBytesPreservesArchivedD3Fields() throws {
            let container = try makeContainer()
            let target = ModelContext(container)
            let workID = UUID()

            let localWork = SavedWork(id: workID, title: "Updated Work", author: "Author")
            localWork.hasEPUB = true
            localWork.lastModifiedAt = Date(timeIntervalSince1970: 1_000)
            localWork.chapterWordCounts = [100]
            localWork.wordUnitRaw = SavedWork.WordUnit.words.rawValue
            target.insert(localWork)

            let initialEPUB = try sampleEPUB(title: "V1", body: "<p>Initial short text.</p>")
            let epubDest = localWork.fileURL
            try FileManager.default.createDirectory(
                at: epubDest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try initialEPUB.write(to: epubDest)
            let initialDigest = Storage.fileDigest(at: epubDest) ?? ""
            localWork.epubDigest = initialDigest
            try target.save()
            defer { try? FileManager.default.removeItem(at: epubDest) }

            // Incoming newer archive carries updated EPUB bytes AND updated D3 counts.
            let staging = ModelContext(try makeContainer())
            let archivedWork = SavedWork(id: workID, title: "Updated Work", author: "Author")
            archivedWork.hasEPUB = true
            archivedWork.lastModifiedAt = Date(timeIntervalSince1970: 5_000)
            archivedWork.chapterWordCounts = [200, 300]
            archivedWork.wordUnitRaw = SavedWork.WordUnit.characters.rawValue
            staging.insert(archivedWork)
            try staging.save()

            let newerEPUB = try sampleEPUB(title: "V2", body: "<p>Updated chapter prose with new bytes.</p>")
            let manifest = try KudosBackupService.makeContents(
                works: [archivedWork],
                bookmarks: [],
                fonts: [],
                readingQueues: [],
                defaults: try testDefaults()
            ).manifest
            let incoming = KudosBackupContents(manifest: manifest, epubFiles: [workID: newerEPUB])

            _ = try KudosBackupService.restore(incoming, into: target, defaults: try testDefaults())

            let updated = try #require(
                try target.fetch(FetchDescriptor<SavedWork>()).first { $0.id == workID }
            )
            #expect(!initialDigest.isEmpty)
            #expect(updated.epubDigest != initialDigest)
            #expect(updated.chapterWordCounts == [200, 300])
            #expect(updated.wordUnitRaw == SavedWork.WordUnit.characters.rawValue)
        }
    }
}
