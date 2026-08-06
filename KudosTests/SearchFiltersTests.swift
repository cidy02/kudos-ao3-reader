import Foundation
import SwiftData
import Testing
@testable import Kudos

struct SearchFiltersTests {
    @Test func filterSelectionCyclesIncludeExcludeClear() {
        #expect(FilterSelectionState.clear.next == .included)
        #expect(FilterSelectionState.included.next == .excluded)
        #expect(FilterSelectionState.excluded.next == .clear)
    }

    @Test func defaultsDoNotAlterTheQuery() {
        let filters = AO3SearchFilters()

        #expect(!filters.hasActiveFilters)
        #expect(filters.searchQuery.isEmpty)
        #expect(filters.structuredRatingID == nil)
    }

    /// `Codable` is what SwiftData *requires* of a composite attribute, not what it
    /// stores with — that is `aSavedSearchSurvivesARealSwiftDataRoundTrip` below.
    /// This still earns its place: the conformance has to be lossless for the
    /// requirement to be met at all, and it is hand-written enough to break.
    @Test func filtersCodableRoundTripIsLossless() throws {
        var filters = AO3SearchFilters()
        filters.query = "found family"
        filters.fandom = "Naruto, Bleach"
        filters.excludedAdditionalTags = "Angst"
        filters.rating = .teen
        filters.ratingMatch = .orHigher
        filters.includeNotRated = false
        filters.warnings = [.noWarnings]
        filters.categories = [.gen]
        filters.excludedCategories = [.mm]
        filters.crossover = .exclude
        filters.completion = .complete
        filters.wordsFrom = "1000"
        filters.wordsTo = "50000"
        filters.updated = .week
        filters.language = AO3SearchFilters.Language.allCases.first { $0.id == "en" }!
        filters.chapterCount = .singleChapter
        filters.sort = .kudos

        let data = try JSONEncoder().encode(filters)
        let decoded = try JSONDecoder().decode(AO3SearchFilters.self, from: data)
        #expect(decoded == filters)
    }

    /// A `SavedSearch` encoded before `chapterCount`/`Language` existed in their
    /// current shape must still decode — old records have no `chapterCount` key at
    /// all, and `language` was a bare raw-value string ("en"), not `{"id","title"}`.
    @Test func preExistingSavedSearchJSONStillDecodes() throws {
        let legacyJSON = """
        {"query":"time travel","fandom":"","characters":"","relationships":"",
        "additionalTags":"","excludedFandoms":"","excludedCharacters":"",
        "excludedRelationships":"","excludedAdditionalTags":"","rating":"teen",
        "ratingMatch":"exact","includeNotRated":true,"warnings":[],"excludedWarnings":[],
        "categories":[],"excludedCategories":[],"crossover":"any","completion":"any",
        "wordsFrom":"","wordsTo":"","updated":"any","language":"en","sort":"relevance"}
        """
        let decoded = try JSONDecoder().decode(AO3SearchFilters.self, from: Data(legacyJSON.utf8))
        #expect(decoded.query == "time travel")
        #expect(decoded.language.id == "en")
        #expect(decoded.language.title == "English")
        #expect(decoded.chapterCount == .any)
    }

    @Test func exactRatingUsesStructuredField() {
        var filters = AO3SearchFilters()
        filters.query = "slow burn"
        filters.rating = .mature
        filters.includeNotRated = false

        #expect(filters.searchQuery == "slow burn")
        #expect(filters.structuredRatingID == "12")
    }

    @Test func ratingPlusUsesAORatingExpression() {
        var filters = AO3SearchFilters()
        filters.rating = .mature
        filters.ratingMatch = .orHigher
        filters.includeNotRated = false

        #expect(filters.searchQuery == "(rating_ids:12 OR rating_ids:13)")
        #expect(filters.structuredRatingID == nil)
    }

    @Test func ratingMinusCanIncludeUnratedWorks() {
        var filters = AO3SearchFilters()
        filters.rating = .teen
        filters.ratingMatch = .orLower
        filters.includeNotRated = true

        #expect(
            filters.searchQuery
                == "(rating_ids:10 OR rating_ids:11 OR rating_ids:9)"
        )
        #expect(filters.structuredRatingID == nil)
    }

    @Test func anyRatingCanExcludeUnratedWorks() {
        var filters = AO3SearchFilters()
        filters.includeNotRated = false

        #expect(filters.hasActiveFilters)
        #expect(filters.searchQuery == "-rating_ids:9")
        #expect(filters.structuredRatingID == nil)
    }

    @Test func categorizedExclusionsBecomeOneDeduplicatedTagNameList() {
        var filters = AO3SearchFilters()
        filters.excludedFandoms = "Naruto, Star Wars"
        filters.excludedCharacters = "Naruto"
        filters.excludedRelationships = "Alice/Bob"

        // AO3's own `excluded_tag_names` takes a comma list (live-verified to
        // handle more than one), so these no longer touch the free-text query at
        // all — which is what removed the need to escape user text into query
        // syntax. Duplicates across the four fields still collapse.
        #expect(filters.excludedTagNames == "Naruto,Star Wars,Alice/Bob")
        #expect(filters.searchQuery.isEmpty)
    }

    @Test func noExclusionsMeansNoExcludedTagNamesParameter() {
        #expect(AO3SearchFilters().excludedTagNames == nil)
    }

    @Test func excludedTagsNeedNoEscapingBecauseTheyLeaveQuerySyntax() {
        // The quote that used to terminate the phrase early is now just a
        // character in a structured field value, percent-encoded by URLComponents
        // like any other. `quotedPhrase` was deleted with its last caller.
        var filters = AO3SearchFilters()
        filters.excludedFandoms = "He said \"hi\""
        #expect(filters.excludedTagNames == "He said \"hi\"")
        #expect(filters.searchQuery.isEmpty)
    }

    @Test func warningExclusionsUseAO3FieldSyntax() {
        var filters = AO3SearchFilters()
        filters.excludedWarnings = [.noWarnings, .underage]

        #expect(
            filters.searchQuery
                == "-archive_warning_ids:16 -archive_warning_ids:20"
        )
    }

    @Test func categoryExclusionsUseAO3FieldSyntax() {
        var filters = AO3SearchFilters()
        filters.excludedCategories = [.mm, .other]

        #expect(filters.searchQuery == "-category_ids:23 -category_ids:24")
    }

    @Test func rangeExpressionCoversBothBoundsAndNeither() {
        #expect(AO3SearchFilters.rangeExpression(from: "10", to: "20") == "10-20")
        #expect(AO3SearchFilters.rangeExpression(from: "10", to: "") == "> 10")
        #expect(AO3SearchFilters.rangeExpression(from: "", to: "20") == "< 20")
        #expect(AO3SearchFilters.rangeExpression(from: "", to: "") == nil)
        #expect(AO3SearchFilters.rangeExpression(from: "  ", to: "  ") == nil)
    }

    @Test func sortColumnsCarryTheDirectionAReaderExpects() {
        // Names read forwards; counts and dates read biggest/newest first.
        #expect(AO3SearchFilters.Sort.workTitle.naturalDirection == .ascending)
        #expect(AO3SearchFilters.Sort.creator.naturalDirection == .ascending)
        #expect(AO3SearchFilters.Sort.kudos.naturalDirection == .descending)
        #expect(AO3SearchFilters.Sort.dateUpdated.naturalDirection == .descending)
    }

    @Test func savedSearchJSONPredatingTheNewFieldsStillDecodes() throws {
        // Regression guard for the whole F1/F2 batch: Swift's synthesized
        // Decodable treats a missing key as an error even when the property has
        // a default, so every field added here has to decode leniently or every
        // previously saved search breaks.
        let legacy = """
        {"query":"naruto","fandom":"","characters":"","relationships":"","additionalTags":"",
         "excludedFandoms":"","excludedCharacters":"","excludedRelationships":"",
         "excludedAdditionalTags":"","rating":"any","ratingMatch":"exact","includeNotRated":true,
         "warnings":[],"excludedWarnings":[],"categories":[],"excludedCategories":[],
         "crossover":"any","completion":"any","wordsFrom":"","wordsTo":"","updated":"any",
         "language":"","sort":"relevance"}
        """
        let filters = try JSONDecoder().decode(AO3SearchFilters.self, from: Data(legacy.utf8))
        #expect(filters.query == "naruto")
        #expect(filters.title.isEmpty)
        #expect(filters.creators.isEmpty)
        #expect(filters.hitsFrom.isEmpty)
        #expect(filters.kudosTo.isEmpty)
        #expect(filters.bookmarksFrom.isEmpty)
        #expect(filters.sortDirection == .descending)
        #expect(filters.chapterCount == .any)
        #expect(filters.dateFrom == nil)
        #expect(filters.dateTo == nil)
    }

    @Test func aSavedSearchSurvivesARealSwiftDataRoundTrip() throws {
        // The tests above exercise `Codable`, and SwiftData does not use it.
        // `filters` is a composite attribute, stored as one SQLite column per
        // stored property — `Language`'s custom `encode(to:)` emits a single bare
        // string, yet a real store carries `ZID` *and* `ZTITLE1`, its two stored
        // properties. So `Codable` has no production consumer at all here, and
        // until this test the mechanism that is actually used had no coverage.
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])

        var filters = AO3SearchFilters()
        filters.query = "naruto"
        filters.title = "A Title"
        filters.creators = "someone"
        filters.fandom = "Naruto"
        filters.excludedAdditionalTags = "Time Travel,Fluff"
        filters.rating = .teen
        filters.ratingMatch = .orHigher
        filters.includeNotRated = false
        filters.warnings = [.noWarnings]
        filters.excludedCategories = [.multi]
        filters.crossover = .exclude
        filters.completion = .complete
        filters.chapterCount = .singleChapter
        filters.wordsFrom = "1000"
        filters.kudosTo = "500"
        filters.updated = .month
        filters.dateFrom = Date(timeIntervalSince1970: 1_700_000_000)
        filters.dateTo = Date(timeIntervalSince1970: 1_760_000_000)
        filters.language = try #require(AO3SearchFilters.Language.allCases.first { $0.id == "fr" })
        filters.sort = .kudos
        filters.sortDirection = .ascending

        let writeContext = ModelContext(container)
        writeContext.insert(SavedSearch(name: "Everything", filters: filters))
        try writeContext.save()

        // A *fresh* context, so this is a read back out of the store rather than a
        // read of the object still sitting in the first context's cache.
        let readContext = ModelContext(container)
        let saved = try readContext.fetch(FetchDescriptor<SavedSearch>())
        #expect(saved.count == 1)
        let reloaded = try #require(saved.first)
        #expect(reloaded.name == "Everything")
        // Equatable over the whole struct: every field at once, so a property added
        // later is covered without anyone remembering to extend this list.
        #expect(reloaded.filters == filters)
        // Named individually anyway, because these are the ones with a history: the
        // two new date columns, and the language that stopped being a bare enum.
        #expect(reloaded.filters.dateFrom == filters.dateFrom)
        #expect(reloaded.filters.dateTo == filters.dateTo)
        #expect(reloaded.filters.language.id == "fr")
        #expect(reloaded.filters.warnings == [.noWarnings])
    }
}
