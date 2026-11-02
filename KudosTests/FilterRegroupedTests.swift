import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
struct FilterRegroupedTests {
    @Test func lengthPresetMatchingAndApplying() {
        // Any
        #expect(FilterLengthPreset.matching(from: "", to: "") == .any)
        #expect(FilterLengthPreset.matching(from: "   ", to: "") == .any)

        // Under 1k
        #expect(FilterLengthPreset.matching(from: "", to: "1000") == .under1k)
        #expect(FilterLengthPreset.matching(from: "", to: "1,000") == .under1k)

        // 1k–10k
        #expect(FilterLengthPreset.matching(from: "1000", to: "10000") == .oneTo10k)
        #expect(FilterLengthPreset.matching(from: "1,000", to: "10,000") == .oneTo10k)

        // 10k+
        #expect(FilterLengthPreset.matching(from: "10000", to: "") == .tenPlus)
        #expect(FilterLengthPreset.matching(from: "10,000", to: "") == .tenPlus)

        // 50k+
        #expect(FilterLengthPreset.matching(from: "50000", to: "") == .fiftyPlus)
        #expect(FilterLengthPreset.matching(from: "50,000", to: "") == .fiftyPlus)

        // Custom
        #expect(FilterLengthPreset.matching(from: "500", to: "2500") == .custom)
        #expect(FilterLengthPreset.matching(from: "20000", to: "30000") == .custom)

        // Applying presets
        var from = "initial"
        var to = "initial"

        FilterLengthPreset.any.apply(to: &from, to: &to)
        #expect(from == "")
        #expect(to == "")

        FilterLengthPreset.under1k.apply(to: &from, to: &to)
        #expect(from == "")
        #expect(to == "1000")

        FilterLengthPreset.oneTo10k.apply(to: &from, to: &to)
        #expect(from == "1000")
        #expect(to == "10000")

        FilterLengthPreset.tenPlus.apply(to: &from, to: &to)
        #expect(from == "10000")
        #expect(to == "")

        FilterLengthPreset.fiftyPlus.apply(to: &from, to: &to)
        #expect(from == "50000")
        #expect(to == "")
    }

    @Test func libraryFiltersExcludedWarningsRejectMatchingWorks() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SavedWork.self, configurations: config)
        let context = container.mainContext

        let deathWork = SavedWork(title: "Tragedy", author: "Author A")
        deathWork.workWarnings = ["Major Character Death"]
        context.insert(deathWork)

        let safeWork = SavedWork(title: "Fluff", author: "Author B")
        safeWork.workWarnings = ["No Archive Warnings Apply"]
        context.insert(safeWork)

        var filters = LibraryFilters()
        filters.excludedWarnings = [.death]

        let results = filters.apply(to: [deathWork, safeWork]).map(\.title)
        #expect(!results.contains("Tragedy"))
        #expect(results.contains("Fluff"))
        #expect(filters.hasActiveFilters)
    }

    @Test func libraryFiltersExcludedCategoriesRejectMatchingWorks() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SavedWork.self, configurations: config)
        let context = container.mainContext

        let fmWork = SavedWork(title: "Romance", author: "Author A")
        fmWork.workCategories = ["F/M"]
        context.insert(fmWork)

        let genWork = SavedWork(title: "Friendship", author: "Author B")
        genWork.workCategories = ["Gen"]
        context.insert(genWork)

        var filters = LibraryFilters()
        filters.excludedCategories = [.fm]

        let results = filters.apply(to: [fmWork, genWork]).map(\.title)
        #expect(!results.contains("Romance"))
        #expect(results.contains("Friendship"))
        #expect(filters.hasActiveFilters)
    }

    @Test func libraryFiltersSummaryLabelsIncludeExcludedPrefix() {
        var filters = LibraryFilters()
        filters.excludedWarnings = [.death]
        filters.excludedCategories = [.other]

        let labels = filters.summaryLabels().map(\.text)
        #expect(labels.contains("−Major Character Death"))
        #expect(labels.contains("−Other"))
    }

    @Test func libraryFiltersRevisionKeyIsDeterministicAndReflectsExclusions() {
        var f1 = LibraryFilters()
        f1.excludedWarnings = [.death]
        f1.excludedCategories = [.ff]

        var f2 = LibraryFilters()
        f2.excludedWarnings = [.death]
        f2.excludedCategories = [.ff]

        #expect(f1.revisionKey == f2.revisionKey)

        var f3 = LibraryFilters()
        #expect(f1.revisionKey != f3.revisionKey)
    }

    @Test func boardWordCountExamplesMatchCustomPreset() {
        // Board 03: 10,000 to 150,000 words
        #expect(FilterLengthPreset.matching(from: "10,000", to: "150,000") == .custom)
        // Board 12: 10,000 to 60,000 words
        #expect(FilterLengthPreset.matching(from: "10,000", to: "60,000") == .custom)
    }

    @Test func filterSelectionStateCycleProgression() {
        #expect(FilterSelectionState.clear.next == .included)
        #expect(FilterSelectionState.included.next == .excluded)
        #expect(FilterSelectionState.excluded.next == .clear)
    }
}
