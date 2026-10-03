import Foundation
import SwiftData
import Testing
@testable import Kudos

/// The owner's Last Read and Kudos sorts (2026-10-03), shared with Android.
@MainActor
struct LibrarySortTests {
    @Test func lastReadPutsMostRecentFirstAndNeverReadLast() throws {
        let container = try ModelContainer(
            for: SavedWork.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let old = SavedWork(title: "Old", author: "A", summary: "")
        old.lastReadDate = Date(timeIntervalSince1970: 1_000)
        let never = SavedWork(title: "Never", author: "B", summary: "")
        let recent = SavedWork(title: "Recent", author: "C", summary: "")
        recent.lastReadDate = Date(timeIntervalSince1970: 2_000)
        [old, never, recent].forEach(context.insert)

        var filters = LibraryFilters()
        filters.sort = .lastRead
        #expect(filters.apply(to: [old, never, recent]).map(\.title) == ["Recent", "Old", "Never"])
    }

    @Test func kudosPutsHighestFirst() throws {
        let container = try ModelContainer(
            for: SavedWork.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let few = SavedWork(title: "Few", author: "A", summary: "")
        few.kudos = 3
        let many = SavedWork(title: "Many", author: "B", summary: "")
        many.kudos = 300
        [few, many].forEach(context.insert)

        var filters = LibraryFilters()
        filters.sort = .kudos
        #expect(filters.apply(to: [few, many]).map(\.title) == ["Many", "Few"])
    }

    @Test func sortsAreTheSameAsAndroid() {
        #expect(LibrarySort.allCases.map(\.title) == [
            "Default", "Date Added", "Date Downloaded", "Last Read", "Title", "Author", "Word Count", "Kudos",
        ])
    }
}
