import Foundation
import Testing
@testable import Kudos

/// The Lock Screen widget's data (T-576e): what the app writes into its App Group and the widget reads.
struct KudosWidgetSnapshotTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func sprintWordsCountForTheirDayOnly() {
        var snapshot = KudosWidgetSnapshot()
        snapshot.addSprint(words: 412, at: date(26, 9), calendar: calendar)
        snapshot.addSprint(words: 100, at: date(26, 21), calendar: calendar)
        #expect(snapshot.sprintWordsToday(now: date(26, 23), calendar: calendar) == 512)
        #expect(snapshot.sprintWordsToday(now: date(27, 1), calendar: calendar) == 0, "a new day starts at zero")
        snapshot.addSprint(words: 50, at: date(27, 8), calendar: calendar)
        #expect(snapshot.sprintWordsToday(now: date(27, 9), calendar: calendar) == 50)
        snapshot.addSprint(words: -5, at: date(27, 10), calendar: calendar)
        #expect(snapshot.sprintWordsToday(now: date(27, 11), calendar: calendar) == 50, "never below what was written")
    }

    @Test func eachAppHasItsOwnGroupAndTheExtensionSharesIt() {
        #expect(KudosAppGroup.identifier(bundleID: "com.cidy02.Kudos") == "group.com.cidy02.Kudos")
        #expect(KudosAppGroup.identifier(bundleID: "com.cidy02.Kudos.widgets") == "group.com.cidy02.Kudos")
        #expect(KudosAppGroup.identifier(bundleID: "com.cidy02.Kudos.next.widgets") == "group.com.cidy02.Kudos.next")
        #expect(KudosAppGroup.identifier(bundleID: nil) == nil)
    }

    @Test func updateWritesOnlyAChangeAndReadsBackWhatItWrote() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("widget-snapshot.json")
        #expect(KudosWidgetSnapshotStore.read(from: url) == KudosWidgetSnapshot(), "nothing written yet")
        let first = KudosWidgetSnapshotStore.update(at: url) { $0.workTitle = "What the Tide Keeps" }
        #expect(first)
        let same = KudosWidgetSnapshotStore.update(at: url) { $0.workTitle = "What the Tide Keeps" }
        #expect(!same, "no change, no write, no widget reload")
        #expect(KudosWidgetSnapshotStore.read(from: url).workTitle == "What the Tide Keeps")
        let noGroup = KudosWidgetSnapshotStore.update(at: nil) { $0.workTitle = "x" }
        #expect(!noGroup, "an unsigned build has no App Group")
    }
}
