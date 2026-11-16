import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Tests for `SavedWork.normalizedWorkTags`, which cleans EPUB subjects into a
/// work's tag list (drops the rating, trims, de-duplicates, preserves order).
@MainActor
struct WorkTagsTests {
    private func coverContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        return try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ).mainContext
    }
    @Test func dropsRatingTrimsAndDeduplicates() {
        let subjects = ["Teen And Up Audiences", "Fluff", "Fluff", "  Angst  ", ""]
        let tags = SavedWork.normalizedWorkTags(subjects, excludingRating: "Teen And Up Audiences")
        #expect(tags == ["Fluff", "Angst"])
    }

    @Test func preservesFirstSeenOrder() {
        let tags = SavedWork.normalizedWorkTags(["B", "A", "B", "C"], excludingRating: "")
        #expect(tags == ["B", "A", "C"])
    }

    @Test func emptyInputYieldsEmpty() {
        #expect(SavedWork.normalizedWorkTags([], excludingRating: "Mature").isEmpty)
    }

    @Test func canonicalAO3WorkURLStripsVariants() {
        #expect(
            WorkTags.canonicalAO3WorkURL(
                from: "https://archiveofourown.org/works/12345/?view_full_work=true#main"
            ) == "https://archiveofourown.org/works/12345"
        )
        #expect(
            WorkTags.canonicalAO3WorkURL(
                from: "https://archiveofourown.org/downloads/98765/work.epub"
            ) == "https://archiveofourown.org/works/98765"
        )
    }

    @Test func refreshFromAO3UpdatesAutomaticIncompletePinAndPreservesReaderActions() async throws {
        let context = try coverContext()
        let response = AO3WorkMetadata(
            id: 77_001, title: "Test", authors: ["Author"],
            fandoms: ["Sherlock Holmes"], freeforms: ["Fluff"], words: 5_000, chapters: "1/1"
        )

        // 1. Unshuffled automatic salt-0 pin without fandoms / wordCount == 0 gets refined (staying automatic).
        let autoMissingFandom = SavedWork(title: "Test", author: "Author",
                                          sourceURL: "https://archiveofourown.org/works/77001")
        autoMissingFandom.ao3WorkID = 77_001
        context.insert(autoMissingFandom)
        autoMissingFandom.pinCover(salt: 0, automatic: true)
        #expect(autoMissingFandom.generatedCoverRecipe.fandom.isEmpty)

        await WorkTags.refreshFromAO3(for: autoMissingFandom, in: context) { _ in response }
        #expect(autoMissingFandom.generatedCoverRecipe.fandom == "Sherlock Holmes")
        #expect(autoMissingFandom.generatedCoverRecipe.salt == 0)
        #expect(GeneratedCoverRecipe.isAutomaticPin(in: autoMissingFandom.coverRecipeJSON))

        // 2. Reader-shuffled pin stays shuffled, only upgrading tier when words cross a threshold.
        let shuffled = SavedWork(title: "Shuffled", author: "Author",
                                 sourceURL: "https://archiveofourown.org/works/77002")
        shuffled.ao3WorkID = 77_002
        context.insert(shuffled)
        shuffled.pinCover(salt: 2)
        let tierTwo = AO3WorkMetadata(
            id: 77_002, title: "Shuffled", authors: ["Author"],
            fandoms: ["Sherlock Holmes"], freeforms: ["Angst"], words: 92_000, chapters: "10/10"
        )
        await WorkTags.refreshFromAO3(for: shuffled, in: context) { _ in tierTwo }
        #expect(shuffled.generatedCoverRecipe.salt == 2)
        #expect(shuffled.generatedCoverRecipe.tier == 2)
        #expect(shuffled.generatedCoverRecipe.fandom.isEmpty)

        // 3. Reader-reset pin (salt 0, pinnedAt > 0) is NOT overwritten when tier matches.
        let readerReset = SavedWork(title: "Reset", author: "Author",
                                    sourceURL: "https://archiveofourown.org/works/77003")
        readerReset.ao3WorkID = 77_003
        context.insert(readerReset)
        readerReset.pinCover(salt: 0)
        let resetPin = readerReset.coverRecipeJSON
        await WorkTags.refreshFromAO3(for: readerReset, in: context) { _ in response }
        #expect(readerReset.coverRecipeJSON == resetPin)

        // 4. Unshuffled automatic salt-0 pin that already had a fandom but wordCount == 0
        // updates both tier and motif when AO3 word count + tags arrive.
        let zeroWords = SavedWork(title: "Zero", author: "Author",
                                  sourceURL: "https://archiveofourown.org/works/77004")
        zeroWords.ao3WorkID = 77_004
        zeroWords.workFandoms = ["Sherlock Holmes"]
        context.insert(zeroWords)
        zeroWords.pinCover(salt: 0, automatic: true)
        #expect(zeroWords.generatedCoverRecipe.tier == 0)
        await WorkTags.refreshFromAO3(for: zeroWords, in: context) { _ in
            AO3WorkMetadata(
                id: 77_004, title: "Zero", authors: ["Author"],
                fandoms: ["Sherlock Holmes"], freeforms: ["Angst"], words: 45_000, chapters: "3/3"
            )
        }
        #expect(zeroWords.generatedCoverRecipe.tier == 2)
        #expect(GeneratedCoverRecipe.isAutomaticPin(in: zeroWords.coverRecipeJSON))
    }
}
