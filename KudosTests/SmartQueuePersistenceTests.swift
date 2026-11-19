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
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self,
            FollowedTag.self, TagAlias.self
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
        // A queued-but-unsaved work is queue-only and is not part of the library
        // a smart queue reads.
        work.isSaved = true
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

    private func remoteSummary(_ id: Int) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: "Series Work \(id)",
            authors: ["Writer"],
            fandoms: ["Fandom"],
            rating: "General Audiences",
            warnings: ["No Archive Warnings Apply"],
            categories: [],
            isComplete: true,
            dateUpdated: "2026-06-30",
            tags: [],
            summary: "Summary",
            language: "English",
            words: 1_000,
            chapters: "1/1",
            comments: nil,
            kudos: nil,
            hits: nil,
            seriesTitle: "Series",
            seriesURL: "https://archiveofourown.org/series/1",
            seriesPosition: 1
        )
    }

    @Test func addAppendAndMoveWriteNoMembership() async throws {
        let context = try context()
        // Populate Saved for Later and real library works BEFORE creating the smart queue,
        // so deleting either `!isSmart` seed guard in `createQueue` fails this test.
        let story = work("Story", words: 1_000)
        let other = work("Other", words: 1_000)
        context.insert(story)
        context.insert(other)
        let savedForLater = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        _ = ReadingQueueService.add(story, to: savedForLater, in: context)
        try context.save()

        let queue = ReadingQueueService.createQueue(
            named: "Smart",
            keepsWorksOffline: true,
            seededFrom: .savedForLater,
            seedWorkIDs: [story.id, other.id],
            smartRulesJSON: rulesJSON(),
            in: context
        )
        let manual = ReadingQueueService.createQueue(named: "Manual", in: context)
        _ = ReadingQueueService.add(story, to: manual, in: context)
        try context.save()

        let stampBeforeRefusals = queue.lastMembershipChangedAt
        _ = ReadingQueueService.add(story, to: queue, in: context)
        // Refusing an add onto a smart queue must not dirty the ModelContext.
        #expect(!context.hasChanges)
        ReadingQueueService.append([story, other], to: queue, in: context)
        ReadingQueueService.move([story], from: manual, to: queue, in: context)
        ReadingQueueService.move([story], from: queue, to: manual, in: context)
        ReadingQueueService.removeFromQueue(story, from: queue, in: context)
        ReadingQueueService.reorder([other.id, story.id], in: queue, context: context)
        #expect(ReadingQueueService.appendCandidates(from: [story, other], notIn: queue).isEmpty)
        _ = await ReadingQueueService.addAndPreserve(story, to: queue, in: context)
        let seriesResult = await ReadingQueueService.preserveSeries(
            [remoteSummary(901)],
            to: [queue],
            in: context,
            pauseNanos: 0
        )
        #expect(seriesResult.skipped == 1)
        #expect(seriesResult.preserved == 0)
        #expect(seriesResult.failed == 0)
        try context.save()

        let works = try context.fetch(FetchDescriptor<SavedWork>())
        #expect(works.count == 2)
        let memberships = try context.fetch(FetchDescriptor<ReadingQueueMembership>())
        #expect(memberships.count == 2)
        #expect(memberships.allSatisfy { $0.queue?.id != queue.id })
        #expect(queue.memberships.isEmpty)
        #expect(queue.lastMembershipChangedAt == stampBeforeRefusals)
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
        let queue = ReadingQueueService.createQueue(named: "Short and finished", smartRulesJSON: json, in: source)
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
        let restored = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first { $0.id == queue.id })
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

    @Test func olderIOSCustomDowngradeDoesNotConvertLocalSmartQueue() throws {
        let json = rulesJSON(words: 15_000)
        let modes: [BackupImportMode] = [.merge, .replaceLibrary, .reconcile]

        for mode in modes {
            let local = try context()
            let queue = ReadingQueueService.createQueue(
                named: "Short Reads",
                smartRulesJSON: json,
                in: local
            )
            queue.dateUpdated = Date(timeIntervalSince1970: 1_000)
            let story = work("Short Story", words: 4_000)
            local.insert(story)
            try local.save()

            let contents = try KudosBackupService.makeContents(
                works: [story],
                bookmarks: [],
                fonts: [],
                readingQueues: [queue],
                defaults: try defaults()
            )
            var root = try #require(
                JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any]
            )
            var exportedQueues = try #require(root["readingQueues"] as? [[String: Any]])
            let index = try #require(exportedQueues.firstIndex { $0["kindRaw"] as? String == "smart" })
            // Exact older-iOS writer shape: unknown kind decoded & written back as "custom",
            // `smartRulesJSON` absent, and a newer edit timestamp so `incomingWins` is true.
            exportedQueues[index]["kindRaw"] = ReadingQueueKind.custom.rawValue
            exportedQueues[index]["name"] = "Renamed on Old iOS"
            exportedQueues[index]["dateUpdated"] = "2099-01-01T00:00:00.000Z"
            exportedQueues[index].removeValue(forKey: "smartRulesJSON")
            root["readingQueues"] = exportedQueues

            let oldWriterManifest = try KudosBackupContents.decodeManifest(
                JSONSerialization.data(withJSONObject: root)
            )
            _ = try KudosBackupService.restore(
                KudosBackupContents(manifest: oldWriterManifest),
                into: local,
                defaults: try defaults(),
                mode: mode
            )

            let surviving = try #require(
                try local.fetch(FetchDescriptor<ReadingQueue>()).first { $0.id == queue.id }
            )
            #expect(surviving.kindRaw == ReadingQueueKind.smart.rawValue)
            #expect(surviving.kind == .smart)
            #expect(surviving.smartRulesJSON == json)
            #expect(surviving.keepsWorksOffline == false)
            #expect(ReadingQueueService.orderedWorks(in: surviving).map(\.title) == ["Short Story"])
            if mode == .merge {
                #expect(surviving.name == "Short Reads")
            } else {
                #expect(surviving.name == "Renamed on Old iOS")
            }
        }
    }

    @Test func restoreRefusesSmartQueueMembershipsKeepOfflineAndSearchSources() throws {
        let json = rulesJSON(words: 15_000)
        let source = try context()
        let smartQueue = ReadingQueueService.createQueue(
            named: "Smart",
            smartRulesJSON: json,
            in: source
        )
        let story = work("Short Story", words: 4_000)
        source.insert(story)
        let savedSearch = SavedSearch(name: "Query", filters: AO3SearchFilters())
        source.insert(savedSearch)
        try source.save()

        let base = try KudosBackupService.makeContents(
            works: [story],
            bookmarks: [],
            fonts: [],
            readingQueues: [smartQueue],
            savedSearches: [savedSearch],
            defaults: try defaults()
        )
        var root = try #require(
            JSONSerialization.jsonObject(with: base.manifestData()) as? [String: Any]
        )
        var exportedQueues = try #require(root["readingQueues"] as? [[String: Any]])
        let index = try #require(exportedQueues.firstIndex { $0["kindRaw"] as? String == "smart" })
        exportedQueues[index]["keepsWorksOffline"] = true
        exportedQueues[index]["searchSources"] = [[
            "searchID": savedSearch.id.uuidString,
            "newResultCount": 2
        ]]
        exportedQueues[index]["searchSourcesModifiedAt"] = "2099-01-01T00:00:00.000Z"
        root["readingQueues"] = exportedQueues
        root["readingQueueMemberships"] = [[
            "id": UUID().uuidString,
            "queueID": smartQueue.id.uuidString,
            "workID": story.id.uuidString,
            "queuedAt": "2026-11-01T00:00:00.000Z",
            "lastModifiedAt": "2099-01-01T00:00:00.000Z",
            "sortOrderInQueue": 0,
            "note": ""
        ]]

        let taintedManifest = try KudosBackupContents.decodeManifest(
            JSONSerialization.data(withJSONObject: root)
        )

        for mode in [BackupImportMode.merge, .replaceLibrary, .reconcile] {
            let target = try context()
            let summary = try KudosBackupService.restore(
                KudosBackupContents(manifest: taintedManifest),
                into: target,
                defaults: try defaults(),
                mode: mode
            )
            #expect(summary.skippedSmartQueueMemberships == 1)
            let restoredQueue = try #require(
                try target.fetch(FetchDescriptor<ReadingQueue>()).first { $0.id == smartQueue.id }
            )
            let restoredWork = try #require(
                try target.fetch(FetchDescriptor<SavedWork>()).first { $0.id == story.id }
            )
            #expect(restoredQueue.kind == .smart)
            #expect(restoredQueue.keepsWorksOffline == false)
            #expect(restoredQueue.memberships.isEmpty)
            #expect(restoredQueue.searchLinks.isEmpty)
            #expect(try target.fetch(FetchDescriptor<ReadingQueueMembership>()).isEmpty)
            #expect(!restoredWork.isQueuedForLater)
            #expect(!restoredWork.isKeptOffline)
            #expect(WorkDownload.keeper(of: restoredWork) == nil)
        }

        // Newly created smart queue whose archive omits `keepsWorksOffline` still gets `false`.
        var omittedOfflineQueues = exportedQueues
        omittedOfflineQueues[index].removeValue(forKey: "keepsWorksOffline")
        root["readingQueues"] = omittedOfflineQueues
        let omittedManifest = try KudosBackupContents.decodeManifest(
            JSONSerialization.data(withJSONObject: root)
        )
        let omittedTarget = try context()
        _ = try KudosBackupService.restore(
            KudosBackupContents(manifest: omittedManifest),
            into: omittedTarget,
            defaults: try defaults(),
            mode: .replaceLibrary
        )
        let omittedQueue = try #require(
            try omittedTarget.fetch(FetchDescriptor<ReadingQueue>()).first { $0.id == smartQueue.id }
        )
        #expect(omittedQueue.keepsWorksOffline == false)
    }
}
}

extension PersistenceGateSuites.SmartQueuePersistenceTests {
    @Test func exportOmitsSmartQueueMembershipsAndKeepOffline() throws {
        let source = try context()
        let smartQueue = ReadingQueueService.createQueue(
            named: "Smart",
            smartRulesJSON: rulesJSON(words: 15_000),
            in: source
        )
        let story = work("Short Story", words: 4_000)
        source.insert(story)
        let phantom = ReadingQueueMembership(queue: smartQueue, work: story, sortOrderInQueue: 0)
        source.insert(phantom)
        smartQueue.memberships.append(phantom)
        story.queueMemberships.append(phantom)
        smartQueue.keepsWorksOffline = true
        try source.save()

        let exportedContents = try KudosBackupService.makeContents(
            works: [story],
            bookmarks: [],
            fonts: [],
            readingQueues: [smartQueue],
            defaults: try defaults()
        )
        #expect(exportedContents.manifest.readingQueueMemberships.isEmpty)
        #expect(exportedContents.manifest.readingQueues.first?.keepsWorksOffline == false)
        let exportPlan = try KudosBackupService.makeExportPlan(
            works: [story],
            bookmarks: [],
            fonts: [],
            readingQueues: [smartQueue],
            defaults: try defaults()
        )
        let planManifest = try KudosBackupContents.decodeManifest(exportPlan.manifestData)
        #expect(planManifest.readingQueueMemberships.isEmpty)
        #expect(planManifest.readingQueues.first?.keepsWorksOffline == false)
        #expect(!story.isKeptOffline)
        #expect(WorkDownload.keeper(of: story) == nil)
    }

    @Test func fandomRuleUsesLearnedTagAliases() throws {
        let context = try context()
        _ = TagAliasStore.upsert(
            name: "HP",
            canonicalName: "Harry Potter - J. K. Rowling",
            kind: .fandom,
            in: context
        )
        let canonicalWork = work("Canonical", words: 2_000)
        canonicalWork.workFandoms = ["Harry Potter - J. K. Rowling"]
        let synonymWork = work("Synonym", words: 3_000)
        synonymWork.workFandoms = ["HP"]
        let otherWork = work("Other", words: 1_000)
        otherWork.workFandoms = ["Lockwood"]
        context.insert(canonicalWork)
        context.insert(synonymWork)
        context.insert(otherWork)

        let rule = SmartQueueDocument.Rule(
            id: UUID(),
            kind: .fandom,
            fandom: "Harry Potter - J. K. Rowling"
        )
        let json = try #require(
            SmartQueueRules.encode(SmartQueueDocument(match: .all, rules: [rule], sort: .title, limit: 25))
        )
        let queue = ReadingQueueService.createQueue(named: "HP Smart", smartRulesJSON: json, in: context)
        try context.save()

        #expect(ReadingQueueService.orderedWorks(in: queue).map(\.title) == ["Canonical", "Synonym"])
    }

    @Test func whatFitsPlanIncludesSmartQueueWorksAndDeduplicates() throws {
        let context = try context()
        let smartOnly = work("Smart Short", words: 2_000)
        let shared = work("Shared Short", words: 1_500)
        let tooLong = work("Novel", words: 90_000)
        context.insert(smartOnly)
        context.insert(shared)
        context.insert(tooLong)

        let smartQueue = ReadingQueueService.createQueue(
            named: "Quick Reads",
            smartRulesJSON: rulesJSON(words: 5_000),
            in: context
        )
        let manualQueue = ReadingQueueService.createQueue(named: "Manual", in: context)
        _ = ReadingQueueService.add(shared, to: manualQueue, in: context)
        try context.save()

        let plan = WhatFitsPlanner.plan(
            queues: [smartQueue, manualQueue],
            bucket: .fifteenMinutes,
            isVisible: { _ in true },
            fileExists: { _ in true }
        )
        let titles = plan.allEntries.map(\.work.title)
        #expect(titles.contains("Smart Short"))
        #expect(titles.contains("Shared Short"))
        #expect(titles.count == 2)
        let sharedEntry = try #require(plan.allEntries.first { $0.work.id == shared.id })
        #expect(sharedEntry.queueNames.count == 2)
    }

    @Test func browserOrderedQueuesSortsMixedKindsDeterministically() throws {
        let saved = ReadingQueue(name: "Saved for Later", kind: .savedForLater, sortOrder: 99)
        let smartZero = ReadingQueue(name: "Smart 0", kind: .smart, sortOrder: 0)
        let customOne = ReadingQueue(name: "Custom 1", kind: .custom, sortOrder: 1)
        let smartTwo = ReadingQueue(name: "Smart 2", kind: .smart, sortOrder: 2)
        let customThree = ReadingQueue(name: "Custom 3", kind: .custom, sortOrder: 3)

        let expected = [saved.id, smartZero.id, customOne.id, smartTwo.id, customThree.id]
        let permutations: [[ReadingQueue]] = [
            [customThree, smartTwo, customOne, smartZero, saved],
            [saved, customOne, smartTwo, customThree, smartZero],
            [smartTwo, customThree, saved, customOne, smartZero]
        ]
        for input in permutations {
            #expect(ReadingQueueBrowserView.orderedQueues(from: input).map(\.id) == expected)
        }
    }

    @Test func snapshotIncludePredicateRunsBeforeLimit() throws {
        let context = try context()
        var works: [SavedWork] = []
        for idx in 1...5 {
            let mature = work("Mature \(idx)", words: idx * 100)
            mature.rating = "Explicit"
            context.insert(mature)
            works.append(mature)
        }
        let visibleA = work("Visible A", words: 2_000)
        visibleA.rating = "General Audiences"
        let visibleB = work("Visible B", words: 3_000)
        visibleB.rating = "General Audiences"
        context.insert(visibleA)
        context.insert(visibleB)
        works.append(contentsOf: [visibleA, visibleB])

        let rule = SmartQueueDocument.Rule(
            id: UUID(),
            kind: .length,
            lengthComparison: .under,
            words: 10_000
        )
        let json = try #require(
            SmartQueueRules.encode(
                SmartQueueDocument(match: .all, rules: [rule], sort: .shortestFirst, limit: 3)
            )
        )
        let queue = ReadingQueueService.createQueue(named: "Top 3", smartRulesJSON: json, in: context)
        try context.save()

        let snapshot = ReadingQueueService.SmartLibrarySnapshot(works: works)
        // Without filtering, the 3 shortest works are all Mature.
        #expect(snapshot.matching(queue).count == 3)
        // Filtering hidden mature works before `limit` surfaces both visible works.
        let visible = snapshot.matching(queue) { !$0.isAdult }
        #expect(visible.map(\.title) == ["Visible A", "Visible B"])
    }
}
