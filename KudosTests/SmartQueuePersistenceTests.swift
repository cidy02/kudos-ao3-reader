import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct SmartQueuePersistenceTests {
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
        let name = "SmartQueuePersistenceTests.\(UUID().uuidString)"
        let value = try #require(UserDefaults(suiteName: name))
        value.removePersistentDomain(forName: name)
        return value
    }

    private func work(_ title: String, words: Int) -> SavedWork {
        let work = SavedWork(title: title, author: "Author")
        work.wordCount = words
        work.isComplete = true
        return work
    }

    private func rulesJSON(words: Int = 20_000) -> String {
        let rule = SmartQueueDocument.Rule(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
            kind: .length,
            lengthComparison: .under,
            words: words
        )
        let document = SmartQueueDocument(match: .all, rules: [rule], sort: .title, limit: 25)
        return SmartQueueRules.encode(document)!
    }

    @Test func addAppendAndMoveWriteNoMembership() async throws {
        let context = try context()
        let queue = ReadingQueueService.createQueue(
            named: "Smart",
            keepsWorksOffline: true,
            seededFrom: .savedForLater,
            seedWorkIDs: [UUID()],
            smartRulesJSON: rulesJSON(),
            in: context
        )
        let story = work("Story", words: 1_000)
        let other = work("Other", words: 1_000)
        context.insert(story)
        context.insert(other)
        let manual = ReadingQueueService.createQueue(named: "Manual", in: context)
        _ = ReadingQueueService.add(story, to: manual, in: context)
        _ = ReadingQueueService.add(story, to: queue, in: context)
        ReadingQueueService.append([story, other], to: queue, in: context)
        ReadingQueueService.move([story], from: manual, to: queue, in: context)
        _ = await ReadingQueueService.addAndPreserve(story, to: queue, in: context)
        try context.save()

        let memberships = try context.fetch(FetchDescriptor<ReadingQueueMembership>())
        #expect(memberships.count == 1)
        #expect(memberships.first?.queue?.id == manual.id)
        #expect(queue.memberships.isEmpty)
        #expect(manual.memberships.contains { $0.work?.id == story.id })
        #expect(queue.kind == .smart)
        #expect(queue.keepsWorksOffline == false)
        #expect(ReadingQueueService.orderedWorks(in: queue).map(\.title).sorted() == ["Other", "Story"])
    }

    @Test func aWorkLeavesTheComputedListWhenItStopsMatching() throws {
        let context = try context()
        let queue = ReadingQueueService.createQueue(named: "Smart", smartRulesJSON: rulesJSON(), in: context)
        let story = work("Story", words: 12_000)
        let novel = work("Novel", words: 80_000)
        context.insert(story)
        context.insert(novel)
        try context.save()
        #expect(ReadingQueueService.orderedWorks(in: queue).map(\.id) == [story.id])
        story.wordCount = 40_000
        #expect(ReadingQueueService.orderedWorks(in: queue).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ReadingQueueMembership>()).isEmpty)
    }

    @Test func backupRoundTripKeepsKindAndRulesAndAnOlderArchiveDoesNotClearThem() throws {
        let source = try context()
        let json = rulesJSON()
        let queue = ReadingQueueService.createQueue(named: "Short and finished", smartRulesJSON: json, in: context)
        let story = work("Story", words: 4_000)
        source.insert(story)
        let plain = ReadingQueue(name: "Plain")
        source.insert(plain)
        try source.save()

        let contents = try KudosBackupService.makeContents(
            works: [story], bookmarks: [], fonts: [], readingQueues: [queue, plain],
            defaults: try defaults()
        )
        let root = try #require(JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any])
        let exported = try #require(root["readingQueues"] as? [[String: Any]])
        let smartExport = try #require(exported.first { $0["kindRaw"] as? String == "smart" })
        let plainExport = try #require(exported.first { $0["name"] as? String == "Plain" })
        #expect(smartExport["smartRulesJSON"] as? String == json)
        #expect(smartExport["kindRaw"] as? String == "smart")
        #expect(plainExport["smartRulesJSON"] == nil)
        let memberships = root["readingQueueMemberships"] as? [[String: Any]] ?? []
        #expect(memberships.isEmpty)

        let target = try context()
        _ = try KudosBackupService.restore(contents, into: target, defaults: try defaults(), mode: .replaceLibrary)
        let restored = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first { $0.kindRaw == "smart" })
        #expect(restored.smartRulesJSON == json)
        #expect(restored.memberships.isEmpty)
        #expect(ReadingQueueService.orderedWorks(in: restored).map(\.title) == ["Story"])

        var strippedRoot = root
        var strippedQueues = exported
        let index = try #require(strippedQueues.firstIndex { $0["kindRaw"] as? String == "smart" })
        strippedQueues[index].removeValue(forKey: "smartRulesJSON")
        strippedRoot["readingQueues"] = strippedQueues
        let older = try KudosBackupContents.decodeManifest(
            JSONSerialization.data(withJSONObject: strippedRoot)
        )
        _ = try KudosBackupService.restore(
            KudosBackupContents(manifest: older),
            into: target,
            defaults: try defaults(),
            mode: .replaceLibrary
        )
        let kept = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first { $0.id == queue.id })
        #expect(kept.smartRulesJSON == json)
        #expect(kept.kindRaw == "smart")
    }

    @Test func anUnknownKindAndItsRulesPassThroughAndAreNotEvaluated() throws {
        let source = try context()
        let queue = ReadingQueue(name: "Later", kind: .custom)
        queue.kindRaw = "futureKind"
        queue.smartRulesJSON = rulesJSON()
        let story = work("Story", words: 1_000)
        source.insert(queue)
        source.insert(story)
        try source.save()
        #expect(queue.kind == .custom)
        #expect(ReadingQueueService.orderedWorks(in: queue).isEmpty)

        let contents = try KudosBackupService.makeContents(
            works: [story], bookmarks: [], fonts: [], readingQueues: [queue],
            defaults: try defaults()
        )
        let target = try context()
        _ = try KudosBackupService.restore(contents, into: target, defaults: try defaults(), mode: .replaceLibrary)
        let restored = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first)
        #expect(restored.kindRaw == "futureKind")
        #expect(restored.smartRulesJSON == queue.smartRulesJSON)
        #expect(restored.kind == .custom)
        #expect(ReadingQueueService.orderedWorks(in: restored).isEmpty)
        #expect(restored.memberships.isEmpty)
    }

    @Test func updateWritesRulesAndNeverTurnsKeepOfflineOn() throws {
        let context = try context()
        let queue = ReadingQueueService.createQueue(named: "Smart", smartRulesJSON: rulesJSON(), in: context)
        var options = NewQueueOptions()
        options.isSmart = true
        options.keepsWorksOffline = true
        options.smartRulesJSON = rulesJSON(words: 5_000)
        let turnedOn = ReadingQueueService.updateQueue(queue, name: "Renamed", hue: nil, options: options, in: context)
        #expect(!turnedOn)
        #expect(queue.keepsWorksOffline == false)
        #expect(queue.name == "Renamed")
        #expect(queue.smartRulesJSON == options.smartRulesJSON)
    }
}
}
