import Foundation
import Testing
@testable import Kudos

/// T-466: each surface draws one layout, and a stored Detailed / Ledger /
/// Compact choice moves onto List / Grid without deleting the old key.
struct WorkSurfaceLayoutTests {
    @Test func eachSurfaceDrawsTheLayoutItIsGiven() {
        let kinds: [WorkSurface: WorkSurface.Kind] = [
            .home: .fixed, .library: .fixed, .writing: .fixed,
            .searchResults: .detailed, .browse: .detailed, .fandomWorks: .detailed,
            .tagWorks: .detailed, .authorLists: .detailed, .series: .detailed,
            .allWorks: .ledger, .shelf: .ledger, .queue: .ledger, .collection: .ledger,
            .markedForLater: .ledger, .bookmarks: .ledger, .ao3History: .ledger, .yourWorks: .ledger,
            .updates: .ownRows, .readingHistory: .ownRows, .inbox: .ownRows
        ]
        #expect(Set(kinds.keys) == Set(WorkSurface.allCases))
        for surface in WorkSurface.allCases {
            #expect(surface.kind == kinds[surface])
        }
    }

    @Test func onlyDetailedSurfacesRememberShowSummaries() {
        #expect(WorkSurface.searchResults.showSummariesKey == WorkListKeys.searchShowSummaries)
        #expect(WorkSurface.browse.showSummariesKey == WorkListKeys.fandomWorksShowSummaries)
        #expect(WorkSurface.fandomWorks.showSummariesKey == WorkSurface.browse.showSummariesKey)
        #expect(WorkSurface.tagWorks.showSummariesKey == WorkListKeys.tagWorksShowSummaries)
        #expect(WorkSurface.authorLists.showSummariesKey == WorkListKeys.authorListsShowSummaries)
        #expect(WorkSurface.series.showSummariesKey == WorkListKeys.seriesShowSummaries)
        for surface in WorkSurface.allCases where surface.kind != .detailed {
            #expect(surface.showSummariesKey == nil, "\(surface)")
        }
    }

    @Test func storedDisplayModeMapsOntoListOrGrid() {
        #expect(WorkListLayoutMigration.arrangement(fromStoredDisplayMode: "compact") == .grid)
        #expect(WorkListLayoutMigration.arrangement(fromStoredDisplayMode: "detailed") == .list)
        #expect(WorkListLayoutMigration.arrangement(fromStoredDisplayMode: "ledger") == .list)
        for raw in [nil, "", "shelves", "grid", "list", "unknown"] {
            #expect(WorkListLayoutMigration.arrangement(fromStoredDisplayMode: raw) == nil, "\(raw ?? "nil")")
        }
    }

    @Test func migrationCopiesALegacyChoiceOnceAndLeavesIt() {
        let defaults = makeDefaults()
        defaults.set("compact", forKey: "legacy.mode")

        let first = WorkListLayoutMigration.resolve(
            defaults: defaults, arrangementKey: "list.arrangement", legacyDisplayModeKey: "legacy.mode"
        )
        #expect(first == .grid)
        #expect(defaults.string(forKey: "legacy.mode") == "compact")
        #expect(defaults.string(forKey: "list.arrangement") == "grid")

        defaults.set("list", forKey: "list.arrangement")
        let second = WorkListLayoutMigration.resolve(
            defaults: defaults, arrangementKey: "list.arrangement", legacyDisplayModeKey: "legacy.mode"
        )
        #expect(second == .list)
        #expect(defaults.string(forKey: "legacy.mode") == "compact")
    }

    @Test func missingChoiceStaysUnwrittenAndUsesList() {
        let defaults = makeDefaults()
        let arrangement = WorkListLayoutMigration.resolve(
            defaults: defaults, arrangementKey: "list.arrangement", legacyDisplayModeKey: "legacy.mode"
        )
        #expect(arrangement == .list)
        #expect(defaults.string(forKey: "list.arrangement") == nil)
        #expect(defaults.string(forKey: "legacy.mode") == nil)
    }

    /// The dashboard key is not a display mode. Resolving some other list must
    /// not read it, write it, or delete it — "ledger" there is Shelves/Ledger,
    /// and mapping it would turn a dashboard into a list.
    @Test func dashboardLayoutKeyIsLeftAlone() {
        let defaults = makeDefaults()
        defaults.set("shelves", forKey: WorkListKeys.libraryDashboardLayout)
        let shelves = WorkListLayoutMigration.resolve(
            defaults: defaults,
            arrangementKey: "unrelated.arrangement",
            legacyDisplayModeKey: nil
        )
        #expect(shelves == .list)
        #expect(defaults.string(forKey: "unrelated.arrangement") == nil)
        #expect(defaults.string(forKey: WorkListKeys.libraryDashboardLayout) == "shelves")

        defaults.set("ledger", forKey: WorkListKeys.libraryDashboardLayout)
        let ledger = WorkListLayoutMigration.resolve(
            defaults: defaults,
            arrangementKey: "unrelated.arrangement",
            legacyDisplayModeKey: nil
        )
        #expect(ledger == .list)
        #expect(defaults.string(forKey: WorkListKeys.libraryDashboardLayout) == "ledger")
    }

    @Test func fullLedgerStatLineKeepsAuthorLanguageKudosAndTheDate() {
        let line = WorkStat.fullLedgerStatLine(
            author: "A. Writer",
            language: "English",
            wordCount: 12,
            chapters: "3/3",
            comments: 0,
            kudos: 4,
            bookmarks: 1,
            hits: 10,
            dateUpdated: "2020-01-02",
            showsZeroStats: false
        )
        #expect(line.contains("A. Writer"))
        #expect(line.contains("English"))
        #expect(line.contains("12 words"))
        #expect(line.contains("3/3"))
        #expect(line.contains("4 kudos"))
        #expect(line.contains("1 bookmark"))
        #expect(line.contains("10 hits"))
        #expect(line.contains("01/02/2020"))
        #expect(!line.contains("0 comments"))
    }

    @Test func zeroCountsNeedAKnownWordCount() {
        let unknown = WorkStat.fullLedgerStatLine(
            author: "A", language: "", wordCount: 0, chapters: "",
            comments: 0, kudos: 2, bookmarks: 0, hits: 0,
            dateUpdated: "", showsZeroStats: true
        )
        #expect(unknown == ["A", "2 kudos"])

        let known = WorkStat.fullLedgerStatLine(
            author: "", language: "", wordCount: 10, chapters: "",
            comments: 0, kudos: 0, bookmarks: 0, hits: 0,
            dateUpdated: "", showsZeroStats: true
        )
        #expect(known.contains("10 words"))
        #expect(known.contains("0 comments"))
        #expect(known.contains("0 kudos"))
    }

    @Test func longPressPreviewKeepsSummaryAndFandomsAndHidesABlurredWork() {
        let hidden = WorkLongPressFacts.hidden()
        #expect(hidden.title == WorkLongPressFacts.hiddenTitle)
        #expect(hidden.summary.isEmpty)
        #expect(hidden.tags.isEmpty)

        let visible = WorkLongPressFacts.visible(
            title: "Title",
            summaryHTML: "<p>Hello &amp; welcome</p>",
            tagGroups: [["Fandom"], ["Fandom", " "], ["Romance"]]
        )
        #expect(visible.summary == "Hello & welcome")
        #expect(visible.tags == ["Fandom", "Romance"])
    }

    private func makeDefaults() -> UserDefaults {
        let name = "WorkSurfaceLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
