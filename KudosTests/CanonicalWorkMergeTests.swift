import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
struct CanonicalWorkMergeTests {
    // MARK: - remoteLed

    @Test func remoteLedPairsWorksMatchedByAO3WorkID() throws {
        let context = try makeContext()
        let local = try insertWork(into: context, ao3WorkID: 7001)

        let merged = CanonicalWorkMerge.remoteLed(remote: [summary(7001)], localLibrary: [local])

        #expect(merged.count == 1)
        #expect(merged[0].local?.id == local.id)
        #expect(merged[0].remote?.id == 7001)
    }

    @Test func remoteLedMatchesBySourceURLWhenNoStoredID() throws {
        let context = try makeContext()
        // The record has never had its ao3WorkID backfilled — only the source URL
        // (in a non-canonical variant form) carries the work's identity.
        let local = SavedWork(
            title: "URL Only",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/7002?view_adult=true"
        )
        context.insert(local)
        try context.save()

        let merged = CanonicalWorkMerge.remoteLed(remote: [summary(7002)], localLibrary: [local])

        #expect(merged.count == 1)
        #expect(merged[0].local?.id == local.id)
    }

    @Test func remoteLedPassesUnmatchedRemoteThroughAndDropsLocalOnly() throws {
        let context = try makeContext()
        let localOnly = try insertWork(into: context, ao3WorkID: 7003)

        let merged = CanonicalWorkMerge.remoteLed(remote: [summary(7004)], localLibrary: [localOnly])

        // The unmatched remote entry passes through without a local side; the
        // local-only work is absent (not part of the remote-defined list).
        #expect(merged.count == 1)
        #expect(merged[0].local == nil)
        #expect(merged[0].remote?.id == 7004)
    }

    @Test func remoteLedPreservesRemoteOrder() throws {
        let context = try makeContext()
        let localB = try insertWork(into: context, ao3WorkID: 7006)

        let merged = CanonicalWorkMerge.remoteLed(
            remote: [summary(7005), summary(7006), summary(7007)],
            localLibrary: [localB]
        )

        #expect(merged.map { $0.remote?.id } == [7005, 7006, 7007])
        #expect(merged[1].local?.id == localB.id)
    }

    @Test func remoteLedPairsADuplicateRemoteMentionOnlyOnce() throws {
        let context = try makeContext()
        let local = try insertWork(into: context, ao3WorkID: 7008)

        let merged = CanonicalWorkMerge.remoteLed(
            remote: [summary(7008), summary(7008)],
            localLibrary: [local]
        )

        #expect(merged.count == 2)
        #expect(merged[0].local?.id == local.id)
        #expect(merged[1].local == nil)
        // The pairing rule also keeps ForEach ids unique for the pair.
        #expect(merged[0].id != merged[1].id)
    }

    // MARK: - remoteOnly

    @Test func remoteOnlyDropsEntriesWithALocalTwin() throws {
        let context = try makeContext()
        let local = try insertWork(into: context, ao3WorkID: 7009)

        let remaining = CanonicalWorkMerge.remoteOnly(
            remote: [summary(7009), summary(7010)],
            localLibrary: [local]
        )

        #expect(remaining.map(\.id) == [7010])
    }

    // MARK: - WorkIdentityIndex record-UUID tier

    @Test func identityIndexFallsBackToRecordUUID() throws {
        let context = try makeContext()
        // No AO3 identity at all (a user-imported EPUB with no source URL) — only
        // the record UUID, the tier backup restore matches by.
        let local = SavedWork(title: "Import", author: "Writer", sourceURL: "")
        context.insert(local)
        try context.save()

        let index = WorkIdentityIndex([local])
        #expect(index.existingWork(ao3WorkID: nil, sourceURL: nil, recordID: local.id)?.id == local.id)
        #expect(index.existingWork(ao3WorkID: nil, sourceURL: nil, recordID: UUID()) == nil)
    }

    // MARK: - CanonicalWork identity

    @Test func canonicalWorkIDIsStableAcrossSides() throws {
        let context = try makeContext()
        let local = try insertWork(into: context, ao3WorkID: 7011)

        let paired = CanonicalWork(local: local, remote: summary(7011))
        let remoteOnly = CanonicalWork(local: nil, remote: summary(7012))

        #expect(paired.id == "local-\(local.id.uuidString)")
        #expect(remoteOnly.id == "remote-7012")
        #expect(paired.ao3WorkID == 7011)
        #expect(remoteOnly.title == "Summary Work 7012")
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @discardableResult
    private func insertWork(into context: ModelContext, ao3WorkID: Int) throws -> SavedWork {
        let work = SavedWork(
            title: "Local Work \(ao3WorkID)",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/\(ao3WorkID)"
        )
        work.ao3WorkID = ao3WorkID
        context.insert(work)
        try context.save()
        return work
    }

    private func summary(_ id: Int) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: "Summary Work \(id)",
            authors: ["Writer"],
            fandoms: ["Fandom"],
            rating: "Teen And Up Audiences",
            warnings: ["No Archive Warnings Apply"],
            categories: [],
            isComplete: true,
            dateUpdated: "2026-06-30",
            tags: ["Freeform"],
            summary: "Summary \(id)",
            language: "English",
            words: 1_000,
            chapters: "1/1",
            comments: nil,
            kudos: nil,
            hits: nil,
            seriesTitle: nil,
            seriesURL: nil,
            seriesPosition: nil
        )
    }
}
