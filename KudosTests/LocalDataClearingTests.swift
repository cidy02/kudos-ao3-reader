import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Spec 1ac's two bulk clears. Every test here is written so that reverting the
/// rule it covers makes it fail — the selection is the whole risk in a button
/// that frees files, and a test that only checks "something was cleared" would
/// pass just as happily on a rule that cleared everything.
@MainActor
@Suite(.serialized)
struct LocalDataClearingTests {
    private func schema() -> Schema {
        Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
        ])
    }

    private func context() throws -> ModelContext {
        let schema = schema()
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    /// `isProtected` is false only when the work has an AO3 id to come back
    /// from, so every fixture that should be freeable needs one.
    private func finishedWork(title: String, in context: ModelContext) -> SavedWork {
        let work = SavedWork(title: title, author: "A")
        work.ao3WorkID = abs(title.hashValue % 100_000) + 1
        work.isFinished = true
        work.hasEPUB = true
        context.insert(work)
        return work
    }

    // MARK: Downloads

    @Test func onlyFinishedUnprotectedWorksAreFreeable() throws {
        let context = try context()
        let plain = finishedWork(title: "Plain", in: context)
        let kept = finishedWork(title: "Kept", in: context)
        kept.isSaved = true
        let favorite = finishedWork(title: "Favorite", in: context)
        favorite.isFavorite = true
        let queued = finishedWork(title: "Queued", in: context)
        queued.isQueuedForLater = true
        let unfinished = finishedWork(title: "Unfinished", in: context)
        unfinished.isFinished = false
        let alreadyFreed = finishedWork(title: "AlreadyFreed", in: context)
        alreadyFreed.hasEPUB = false
        let imported = finishedWork(title: "Imported", in: context)
        imported.ao3WorkID = nil
        try context.save()

        let all = [plain, kept, favorite, queued, unfinished, alreadyFreed, imported]
        let freeable = LocalDataClearing.selectFreeableDownloads(from: all)

        #expect(freeable.map(\.title) == ["Plain"])
    }

    @Test func aSoftDeletedWorkIsNeverFreedFromThisScreen() throws {
        let context = try context()
        let deleted = finishedWork(title: "Deleted", in: context)
        deleted.isPendingDeletion = true
        try context.save()

        // Recently Deleted is a queue the reader can still undo from; a clear
        // button on the privacy page must not reach into it.
        #expect(LocalDataClearing.selectFreeableDownloads(from: [deleted]).isEmpty)
    }

    @Test func clearingDownloadsKeepsTheRecordAndDropsOnlyTheFile() throws {
        let context = try context()
        let plain = finishedWork(title: "Plain", in: context)
        let kept = finishedWork(title: "Kept", in: context)
        kept.isSaved = true
        try context.save()

        let freed = LocalDataClearing.clearFreeableDownloads(from: [plain, kept], in: context)

        #expect(freed == 1)
        #expect(plain.hasEPUB == false)
        #expect(kept.hasEPUB == true)
        // The record survives: a freed work is history, and reopening it
        // downloads it again.
        let survivors = try context.fetch(FetchDescriptor<SavedWork>())
        #expect(survivors.count == 2)
    }

    // MARK: Reading positions

    @Test func aLegacyReaderPositionCountsEvenWithNoReadiumLocator() throws {
        let context = try context()
        let readium = finishedWork(title: "Readium", in: context)
        readium.readiumLocator = #"{"href":"c1.xhtml"}"#
        let spine = finishedWork(title: "Spine", in: context)
        spine.lastSpineIndex = 4
        let scrolled = finishedWork(title: "Scrolled", in: context)
        scrolled.lastScrollFraction = 0.3
        let untouched = finishedWork(title: "Untouched", in: context)
        try context.save()

        let positioned = LocalDataClearing
            .selectReadingPositions(from: [readium, spine, scrolled, untouched])
            .map(\.title)
            .sorted()

        // Three fields, two readers. Checking only `readiumLocator` would drop
        // the two works someone is genuinely mid-way through.
        #expect(positioned == ["Readium", "Scrolled", "Spine"])
    }

    @Test func clearingPositionsLeavesTheContinueReadingOrderAlone() throws {
        let context = try context()
        let work = finishedWork(title: "Mid-read", in: context)
        work.readiumLocator = #"{"href":"c1.xhtml"}"#
        work.lastSpineIndex = 6
        work.lastScrollFraction = 0.75
        let lastRead = Date(timeIntervalSince1970: 5_000)
        work.lastReadDate = lastRead
        try context.save()

        let cleared = LocalDataClearing.clearReadingPositions(from: [work], in: context)

        #expect(cleared == 1)
        #expect(work.readiumLocator.isEmpty)
        #expect(work.lastSpineIndex == 0)
        #expect(work.lastScrollFraction == 0)
        // `lastReadDate` is the Library shelf's ordering, not a position inside
        // a file. Clearing it would empty a shelf nobody asked to empty.
        #expect(work.lastReadDate == lastRead)
    }

    @Test func clearingPositionsWithNothingToClearTouchesNothing() throws {
        let context = try context()
        let untouched = finishedWork(title: "Untouched", in: context)
        try context.save()

        #expect(LocalDataClearing.clearReadingPositions(from: [untouched], in: context) == 0)
    }
}
