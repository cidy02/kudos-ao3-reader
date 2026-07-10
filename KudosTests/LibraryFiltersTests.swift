import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Closes the coverage gap noted in docs/REGRESSION_TEST_MATRIX.md: the Library
/// facet predicate had no unit suite despite backing every Library surface.
@MainActor
struct LibraryFiltersTests {
    @Test func defaultFiltersMatchEverythingAndKeepNewestFirst() throws {
        let context = try makeContext()
        let older = work(in: context, title: "Older", dateAdded: Date(timeIntervalSince1970: 100))
        let newer = work(in: context, title: "Newer", dateAdded: Date(timeIntervalSince1970: 200))

        let result = LibraryFilters().apply(to: [older, newer])

        #expect(result.map(\.title) == ["Newer", "Older"])
    }

    @Test func fandomFacetUsesCategorizedTagsAndFallsBackToFlatTags() throws {
        let context = try makeContext()
        let categorized = work(in: context, title: "Categorized")
        categorized.workFandoms = ["Fandom A"]
        // Not yet enriched from AO3: only the flat EPUB tag list carries the fandom.
        let flatOnly = work(in: context, title: "FlatOnly")
        flatOnly.workTags = ["Fandom A", "Fluff"]
        let neither = work(in: context, title: "Neither")
        neither.workFandoms = ["Fandom B"]

        var filters = LibraryFilters()
        filters.fandoms = ["Fandom A"]

        let result = filters.apply(to: [categorized, flatOnly, neither]).map(\.title)
        #expect(result.contains("Categorized"))
        #expect(result.contains("FlatOnly"))
        #expect(!result.contains("Neither"))
    }

    @Test func excludeTagsRejectAnyFlatTagMatch() throws {
        let context = try makeContext()
        let angsty = work(in: context, title: "Angsty")
        angsty.workTags = ["Angst"]
        let fluffy = work(in: context, title: "Fluffy")
        fluffy.workTags = ["Fluff"]

        var filters = LibraryFilters()
        filters.excludeTags = ["Angst"]

        #expect(filters.apply(to: [angsty, fluffy]).map(\.title) == ["Fluffy"])
    }

    @Test func userTagFacetMatchesTheTagRelationship() throws {
        let context = try makeContext()
        let tagged = work(in: context, title: "Tagged")
        let tag = Tag(name: "comfort reads")
        context.insert(tag)
        tagged.tags = [tag]
        let untagged = work(in: context, title: "Untagged")

        var filters = LibraryFilters()
        filters.userTags = ["comfort reads"]

        #expect(filters.apply(to: [tagged, untagged]).map(\.title) == ["Tagged"])
    }

    @Test func ratingMatchesLenientText() throws {
        let context = try makeContext()
        let teen = work(in: context, title: "Teen")
        teen.rating = "Teen And Up Audiences"
        let explicitWork = work(in: context, title: "Explicit")
        explicitWork.rating = "Explicit"

        var filters = LibraryFilters()
        filters.rating = .teen

        #expect(filters.apply(to: [teen, explicitWork]).map(\.title) == ["Teen"])
    }

    @Test func underageWarningMatchesBothAO3Spellings() throws {
        let context = try makeContext()
        let epubSpelling = work(in: context, title: "EPUB")
        epubSpelling.workWarnings = ["Underage Sex"]
        let pageSpelling = work(in: context, title: "Page")
        pageSpelling.workWarnings = ["Underage"]
        let clean = work(in: context, title: "Clean")
        clean.workWarnings = ["No Archive Warnings Apply"]

        var filters = LibraryFilters()
        filters.warnings = [.underage]

        let result = filters.apply(to: [epubSpelling, pageSpelling, clean]).map(\.title)
        #expect(result.contains("EPUB"))
        #expect(result.contains("Page"))
        #expect(!result.contains("Clean"))
    }

    @Test func completionFacetSplitsCompleteAndWIP() throws {
        let context = try makeContext()
        let complete = work(in: context, title: "Complete")
        complete.isComplete = true
        let wip = work(in: context, title: "WIP")
        wip.isComplete = false

        var filters = LibraryFilters()
        filters.completion = .complete
        #expect(filters.apply(to: [complete, wip]).map(\.title) == ["Complete"])
        filters.completion = .inProgress
        #expect(filters.apply(to: [complete, wip]).map(\.title) == ["WIP"])
    }

    @Test func languageMatchesCaseInsensitively() throws {
        let context = try makeContext()
        let english = work(in: context, title: "English")
        english.language = "English"
        let french = work(in: context, title: "French")
        french.language = "Français"

        var filters = LibraryFilters()
        filters.language = "english"

        #expect(filters.apply(to: [english, french]).map(\.title) == ["English"])
    }

    @Test func wordBoundsSkipWorksWithUnknownCounts() throws {
        let context = try makeContext()
        let known = work(in: context, title: "Known")
        known.wordCount = 5_000
        let unknown = work(in: context, title: "Unknown") // 0 = never refreshed
        let big = work(in: context, title: "Big")
        big.wordCount = 100_000

        var filters = LibraryFilters()
        filters.wordsFrom = "1,000"
        filters.wordsTo = "10,000"

        let result = filters.apply(to: [known, unknown, big]).map(\.title)
        #expect(result.contains("Known"))
        // Unknown counts are deliberately not hidden by word bounds.
        #expect(result.contains("Unknown"))
        #expect(!result.contains("Big"))
    }

    @Test func sortOrdersBehave() throws {
        let context = try makeContext()
        let alpha = work(in: context, title: "alpha", dateAdded: Date(timeIntervalSince1970: 100))
        alpha.author = "Zed"
        alpha.wordCount = 10
        let bravo = work(in: context, title: "Bravo", dateAdded: Date(timeIntervalSince1970: 200))
        bravo.author = "anna"
        bravo.wordCount = 99

        var filters = LibraryFilters()
        filters.sort = .title
        #expect(filters.apply(to: [bravo, alpha]).map(\.title) == ["alpha", "Bravo"])
        filters.sort = .author
        #expect(filters.apply(to: [alpha, bravo]).map(\.author) == ["anna", "Zed"])
        filters.sort = .wordCount
        #expect(filters.apply(to: [alpha, bravo]).map(\.wordCount) == [99, 10])
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
    private func work(in context: ModelContext, title: String, dateAdded: Date = Date()) -> SavedWork {
        let work = SavedWork(title: title, author: "Writer")
        work.dateAdded = dateAdded
        context.insert(work)
        return work
    }
}
