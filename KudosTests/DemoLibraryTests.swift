import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
struct DemoLibraryTests {
    @Test func allDemoWorksHaveSummariesAndRealisticMetadata() throws {
        let defaults = UserDefaults.standard
        let oldDemo = defaults.object(forKey: "KudosDemoLibrary")
        defer {
            if let oldDemo {
                defaults.set(oldDemo, forKey: "KudosDemoLibrary")
            } else {
                defaults.removeObject(forKey: "KudosDemoLibrary")
            }
        }
        defaults.set(true, forKey: "KudosDemoLibrary")

        let schema = Schema([SavedWork.self, ReadingQueue.self, WorkCollection.self, Tag.self, ReadingSession.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        DemoLibrary.seedIfRequested(in: container.mainContext)

        let works = try container.mainContext.fetch(FetchDescriptor<SavedWork>())
        #expect(works.count >= 14, "Expected at least 14 demo works seeded")

        var hasShortSummary = false
        var hasCollapsingSummary = false
        var seriesCount = 0

        for work in works {
            #expect(
                !work.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Work '\(work.title)' must have a non-empty summary"
            )
            if work.summary.count <= 60 {
                hasShortSummary = true
            }
            if WorkDetailPresentation.summaryCollapses(work.summary) {
                hasCollapsingSummary = true
            }
            if !work.seriesTitle.isEmpty {
                seriesCount += 1
                #expect(work.seriesPosition > 0, "Work in series must have a positive position")
            }
        }

        #expect(hasShortSummary, "Must have at least one summary short enough to fit a line")
        #expect(hasCollapsingSummary, "Must have at least one summary long enough to need truncation")
        #expect(seriesCount > 0, "Must have at least one work in a series")
        #expect(seriesCount < works.count, "Not all works should be in a series (realistic mix)")
    }
}
