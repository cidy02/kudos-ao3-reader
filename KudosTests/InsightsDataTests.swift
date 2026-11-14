import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
@Suite(.serialized)
struct InsightsDataTests {
    private func container() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
        ])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }

    @Test func snapshotSurvivesDeletedWorkAndBackfillSkipsExisting() async throws {
        ReadingLogService.resetOpenSessionsForTests()
        let container = try container()
        let context = ModelContext(container)
        let work = SavedWork(title: "A", author: "B")
        work.workFandoms = ["Fandom"]
        work.workFreeforms = ["Tag"]
        work.rating = "Mature"
        work.verifiedAuthorIdentities = [AO3AuthorIdentity(route: AO3AuthorRoute(username: "writer"))]
        context.insert(work)
        let start = Date(timeIntervalSince1970: 1_000)
        ReadingLogService.startSession(for: work, now: start)
        ReadingLogService.endSession(for: work, now: start.addingTimeInterval(30))
        let first = try #require(try context.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(first.fandoms == ["Fandom"])
        #expect(first.freeformTags == ["Tag"])
        #expect(first.rating == "Mature")
        #expect(first.authorAccounts == ["writer"])
        first.fandoms = ["Visit Fandom"]
        let old = ReadingSession(workID: work.id, startedAt: start, endedAt: start, durationSeconds: 30)
        context.insert(old)
        try context.save()
        let name = "InsightsDataTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        try await ReadingSessionSnapshotBackfill(modelContainer: container).run(defaults: defaults)
        let check = ModelContext(container)
        let filled = try #require(try check.fetch(FetchDescriptor<ReadingSession>())
            .first(where: { $0.id == old.id }))
        #expect(filled.fandoms == ["Fandom"])
        #expect(first.fandoms == ["Visit Fandom"])
        work.workFandoms = ["Changed"]
        try await ReadingSessionSnapshotBackfill(modelContainer: container).run(defaults: defaults)
        #expect(filled.fandoms == ["Fandom"])
        context.delete(work)
        try context.save()
        #expect(ReadingLogService.facts(from: [first], works: []).first?.fandom == "Visit Fandom")
        #expect(first.freeformTags == ["Tag"])
        #expect(first.authorAccounts == ["writer"])
    }

    @Test func statusesPartitionAndStackingThreshold() {
        let works = (0..<8).map { SavedWork(title: "\($0)", author: "A") }
        works[0].readingStatusRaw = "stopped"
        works[1].readingStatusRaw = "onHold"
        works[2].readingStatusRaw = "stacking"
        works[3].isFinished = true
        works[4].isComplete = false
        works[4].lastReadDate = .now
        works[4].readiumLocator = #"{"locations":{"totalProgression":1}}"#
        works[5].lastReadDate = .now
        works[6].isQueuedForLater = true
        works[7].readingStatusRaw = "reading"
        let expected: [SavedWork.InsightsReadingStatus] = [
            .stopped, .onHold, .stacking, .finished, .caughtUp, .reading,
            .savedForLater, .reading
        ]
        #expect(works.map(\.insightsReadingStatus) == expected)
        let counts = Dictionary(grouping: works, by: \.insightsReadingStatus)
        #expect(SavedWork.InsightsReadingStatus.allCases.reduce(0) { $0 + (counts[$1]?.count ?? 0) } == works.count)
        let stack = works[2]
        stack.knownChapterCount = 4
        stack.statusChangedAt = .now
        stack.stackThreshold = 3
        #expect(!stack.shouldResumeStacking(postedChapters: 6))
        #expect(stack.shouldResumeStacking(postedChapters: 7))
    }
}
