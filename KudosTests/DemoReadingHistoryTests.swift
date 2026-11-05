import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
struct DemoReadingHistoryTests {
    @Test func seedsReadingHistoryAcrossMultipleMonthsWhenDemoIsOn() throws {
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

        let schema = Schema([
            SavedWork.self, ReadingQueue.self, WorkCollection.self, Tag.self, ReadingSession.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        DemoLibrary.seedIfRequested(in: context)

        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(!sessions.isEmpty, "Demo library should seed reading sessions")

        let calendar = Calendar.current
        let distinctMonths = Set(sessions.map {
            calendar.dateComponents([.year, .month], from: $0.startedAt)
        })
        #expect(distinctMonths.count > 1, "Reading sessions must span across more than one month")

        let works = try context.fetch(FetchDescriptor<SavedWork>())
        let workIDs = Set(works.map(\.id))
        for session in sessions {
            #expect(workIDs.contains(session.workID), "Session should map to a seeded demo work")
            #expect(session.durationSeconds >= 15, "Session duration should meet minimum persistable duration")
            #expect(!session.workTitle.isEmpty, "Session must have a denormalised work title")
        }
    }
}
