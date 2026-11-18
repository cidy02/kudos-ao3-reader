import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-519: what AO3's series page says is kept, and Work Detail reads it.
@MainActor
struct SavedSeriesTests {
    private final class BundleAnchor {}

    private func makeContext() throws -> ModelContext {
        let schema = Schema([SavedSeries.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesTheSeriesHeaderInAO3sMarkup() throws {
        let parsed = try #require(AO3ParsedSeries.parse(
            html: try fixture("ao3_demo_dawn_series"), ao3SeriesID: 77, pageWorkIDs: [3, 1, 2], isWholeList: true
        ))
        #expect(parsed.title == "The Dawn Cycle")
        #expect(parsed.wordCount == 45_678)
        #expect(parsed.partCount == 3)
        #expect(parsed.isComplete)
        #expect(parsed.partWorkIDs == [3, 1, 2])
    }

    @Test func anUnfinishedSeriesSaysNo() throws {
        let html = """
        <h2 class="heading">Open Road</h2><dl class="series meta group"><dt class="stats">Stats:</dt>
        <dd class="stats"><dl class="stats"><dt class="words">Words:</dt><dd class="words">1,204</dd>
        <dt class="works">Works:</dt><dd class="works">2</dd><dt>Complete:</dt><dd>No</dd></dl></dd></dl>
        """
        let parsed = try #require(
            AO3ParsedSeries.parse(html: html, ao3SeriesID: 5, pageWorkIDs: [], isWholeList: false)
        )
        #expect(!parsed.isComplete)
        #expect(parsed.wordCount == 1_204)
        let noHeader = AO3ParsedSeries.parse(html: "<p>none</p>", ao3SeriesID: 5, pageWorkIDs: [], isWholeList: true)
        #expect(noHeader == nil)
    }

    @Test func upsertKeepsOneRowAndNeverClaimsAPartialListIsWhole() throws {
        let context = try makeContext()
        let whole = AO3ParsedSeries(ao3SeriesID: 9, title: "S", partCount: 2, isComplete: false, wordCount: 10,
                                    partWorkIDs: [11, 12], hasCompleteWorkList: true)
        SavedSeriesStore.upsert(whole, in: context)
        // The series grew to 3; only page 1 (2 works) was read this time.
        let pageOne = AO3ParsedSeries(ao3SeriesID: 9, title: "S", partCount: 3, isComplete: false, wordCount: 15,
                                      partWorkIDs: [11, 12], hasCompleteWorkList: false)
        SavedSeriesStore.upsert(pageOne, in: context)
        let rows = try context.fetch(FetchDescriptor<SavedSeries>())
        #expect(rows.count == 1)
        #expect(rows[0].partCount == 3)
        #expect(rows[0].partWorkIDs.isEmpty)
    }

    @Test func workDetailSaysPartNOfMOnlyWhenAO3sCountIsKnown() {
        #expect(WorkDetailDisclosure.seriesPartLabel(position: 2, partCount: 3) == "Part 2 of 3")
        #expect(WorkDetailDisclosure.seriesPartLabel(position: 2, partCount: nil) == "Part 2")
        // A count below the position is stale; don't print "Part 4 of 3".
        #expect(WorkDetailDisclosure.seriesPartLabel(position: 4, partCount: 3) == "Part 4")
        #expect(WorkDetailDisclosure.seriesDigest(title: "Coast", position: 2, partCount: 3) == "Coast · part 2 of 3")
    }
}
