import Foundation
import Testing
@testable import Kudos

private let sprintStart = Date(timeIntervalSince1970: 1_700_000_000)

private func weekCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2 // Monday
    return calendar
}

private func day(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

private func record(_ date: Date, words: Int) -> SprintRecord {
    SprintRecord(id: UUID(), date: date, minutes: 25, words: words, workID: nil)
}

struct SprintMathTests {
    @Test func wordsNeverGoBelowZero() {
        #expect(SprintMath.words(current: 40, start: 100) == 0)
        #expect(SprintMath.words(current: 160, start: 100) == 60)
        var state = SprintState(startedAt: sprintStart, plannedMinutes: 25, startWords: 100)
        state.update(currentWords: 80, now: sprintStart.addingTimeInterval(30))
        #expect(state.words == 0)
    }

    @Test func hapticThresholdsAreTheHundredsCrossed() {
        #expect(SprintMath.hapticThresholds(from: 0, to: 99).isEmpty)
        #expect(SprintMath.hapticThresholds(from: 99, to: 100) == [100])
        #expect(SprintMath.hapticThresholds(from: 100, to: 100).isEmpty)
        #expect(SprintMath.hapticThresholds(from: 90, to: 310) == [100, 200, 300])
        #expect(SprintMath.hapticThresholds(from: 250, to: 150).isEmpty)
        #expect(SprintMath.hapticThresholds(from: 0, to: 0).isEmpty)
    }

    @Test func aMarkIsNotTappedTwiceWhenWordsAreDeletedAndRetyped() {
        var state = SprintState(startedAt: sprintStart, plannedMinutes: 10, startWords: 0)
        let first = state.update(currentWords: 105, now: sprintStart.addingTimeInterval(10))
        let down = state.update(currentWords: 95, now: sprintStart.addingTimeInterval(20))
        let again = state.update(currentWords: 110, now: sprintStart.addingTimeInterval(30))
        let next = state.update(currentWords: 205, now: sprintStart.addingTimeInterval(40))
        #expect(first == [100])
        #expect(down.isEmpty)
        #expect(again.isEmpty)
        #expect(next == [200])
    }

    @Test func fiveMinuteBuckets() {
        let samples = [
            SprintSample(offset: 60, words: 10),
            SprintSample(offset: 299, words: 30),
            SprintSample(offset: 300, words: 35),
            SprintSample(offset: 301, words: 50),
            SprintSample(offset: 900, words: 80),
        ]
        #expect(SprintMath.buckets(samples: samples, elapsed: 900) == [35, 15, 30])
        #expect(SprintMath.buckets(samples: [], elapsed: 0) == [0])
        #expect(SprintMath.buckets(samples: samples, elapsed: 301).count == 2)
    }

    @Test func bucketsKeepWordsSampledAtOffsetZero() {
        let instant = [SprintSample(offset: 0, words: 25)]
        #expect(SprintMath.buckets(samples: instant, elapsed: 60) == [25])
        let paired = [
            SprintSample(offset: 0, words: 20),
            SprintSample(offset: 120, words: 50),
            SprintSample(offset: 360, words: 80),
        ]
        #expect(SprintMath.buckets(samples: paired, elapsed: 600) == [50, 30])
    }

    @Test func bestThisWeekStopsAtTheWeekBoundary() throws {
        let calendar = weekCalendar()
        let sunday = day(calendar, 2023, 11, 26)
        let monday = day(calendar, 2023, 11, 27)
        let tuesday = day(calendar, 2023, 11, 28)
        let history = [record(sunday, words: 500), record(monday, words: 200)]

        // Last week's 500 doesn't count against Tuesday.
        #expect(SprintMath.isBestThisWeek(words: 250, at: tuesday, among: history, calendar: calendar))
        #expect(!SprintMath.isBestThisWeek(words: 150, at: tuesday, among: history, calendar: calendar))
        // Equal is not a best.
        #expect(!SprintMath.isBestThisWeek(words: 200, at: tuesday, among: history, calendar: calendar))
        // Sunday still belongs to the week that began the Monday before.
        #expect(SprintMath.isBestThisWeek(words: 600, at: sunday, among: history, calendar: calendar))
        // A first sprint of the week has nothing to beat.
        let nextMonday = day(calendar, 2023, 12, 4)
        #expect(!SprintMath.isBestThisWeek(words: 900, at: nextMonday, among: history, calendar: calendar))
        #expect(!SprintMath.isBestThisWeek(words: 0, at: tuesday, among: history, calendar: calendar))
        #expect(!SprintMath.isBestThisWeek(words: 50, at: tuesday, among: [], calendar: calendar))

        // Earlier zero-word sprints don't make the first real sprint of the week a best.
        let zeroOnly = [record(monday, words: 0)]
        #expect(!SprintMath.isBestThisWeek(words: 50, at: tuesday, among: zeroOnly, calendar: calendar))

        // Exact midnight boundary between Sunday 23:59:59 and Monday 00:00:00.
        let sundayEnd = try #require(
            calendar.date(from: DateComponents(year: 2023, month: 11, day: 26, hour: 23, minute: 59, second: 59))
        )
        let mondayStart = try #require(
            calendar.date(from: DateComponents(year: 2023, month: 11, day: 27, hour: 0, minute: 0, second: 0))
        )
        let sundayRecord = [record(sundayEnd, words: 100)]
        #expect(!SprintMath.isBestThisWeek(words: 600, at: mondayStart, among: sundayRecord, calendar: calendar))

        // Calendar week straddling a year boundary (Mon Dec 30, 2024 to Wed Jan 1, 2025).
        let dec30 = day(calendar, 2024, 12, 30)
        let jan1 = day(calendar, 2025, 1, 1)
        let dec30Record = [record(dec30, words: 200)]
        #expect(SprintMath.isBestThisWeek(words: 300, at: jan1, among: dec30Record, calendar: calendar))
    }
}

struct SprintStateTests {
    @Test func endingAfterATripToTheBackgroundStillEndsAtThePlannedLength() {
        var state = SprintState(startedAt: sprintStart, plannedMinutes: 25, startWords: 1_000)
        state.update(currentWords: 1_150, now: sprintStart.addingTimeInterval(120))
        // No updates while the app is away; it comes back three hours later.
        let result = state.finish(now: sprintStart.addingTimeInterval(3 * 3_600))
        #expect(result.minutes == 25)
        #expect(result.words == 150)
        #expect(result.buckets.count == 5)
        #expect(result.endedAt == state.endsAt)
    }

    @Test func endingEarlyRoundsTheMinutesUp() {
        var state = SprintState(startedAt: sprintStart, plannedMinutes: 25, startWords: 0)
        state.update(currentWords: 40, now: sprintStart.addingTimeInterval(200))
        let result = state.finish(now: sprintStart.addingTimeInterval(7 * 60))
        #expect(result.minutes == 7)
        #expect(result.plannedMinutes == 25)
        #expect(result.buckets.count == 2)
        #expect(result.words == 40)
    }

    @Test func nonPositiveMinutesAndBackwardClockAreClamped() {
        let state = SprintState(startedAt: sprintStart, plannedMinutes: 0, startWords: 0)
        #expect(state.plannedMinutes == 1)
        #expect(state.endsAt == sprintStart.addingTimeInterval(60))
        let result = state.finish(now: sprintStart.addingTimeInterval(-30))
        #expect(result.endedAt == sprintStart)
        #expect(result.minutes == 1)
    }
}

@MainActor
struct SprintControllerTests {
    private func makeController(_ body: (SprintController, SprintHistory) async throws -> Void) async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprints-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("sprints.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let history = SprintHistory(url: url)
        try await body(SprintController(history: history, calendar: weekCalendar()), history)
    }

    @Test func tapsOnceForEveryHundredWords() async throws {
        try await makeController { controller, _ in
            var taps = 0
            controller.tap = { taps += 1 }
            controller.start(minutes: 10, currentWords: 500, workID: nil, now: sprintStart)
            controller.noteWords(590, now: sprintStart.addingTimeInterval(30))
            controller.noteWords(720, now: sprintStart.addingTimeInterval(60))
            #expect(taps == 1)
            controller.noteWords(930, now: sprintStart.addingTimeInterval(90))
            #expect(taps == 2)
            #expect(controller.statusInfo?.words == 430)
        }
    }

    @Test func tickBeforeTheEndKeepsGoingAndAfterTheEndShowsTheResult() async throws {
        try await makeController { controller, _ in
            controller.start(minutes: 10, currentWords: 0, workID: nil, now: sprintStart)
            controller.noteWords(120, now: sprintStart.addingTimeInterval(100))
            controller.tick(now: sprintStart.addingTimeInterval(599))
            #expect(controller.active != nil)
            #expect(controller.result == nil)

            controller.tick(now: sprintStart.addingTimeInterval(4_000))
            #expect(controller.active == nil)
            #expect(controller.result?.words == 120)
            #expect(controller.result?.minutes == 10)
        }
    }

    @Test func aFinishedSprintIsWrittenToTheHistory() async throws {
        try await makeController { controller, history in
            controller.start(minutes: 10, currentWords: 0, workID: nil, now: sprintStart)
            controller.noteWords(75, now: sprintStart.addingTimeInterval(100))
            _ = controller.finish(now: sprintStart.addingTimeInterval(300))

            var stored: [SprintRecord] = []
            for _ in 0..<50 where stored.isEmpty {
                try await Task.sleep(for: .milliseconds(50))
                stored = try await history.list()
            }
            #expect(stored.count == 1)
            #expect(stored.first?.words == 75)
            #expect(stored.first?.minutes == 5)
        }
    }

    @Test func endingByHandAndClosingTheEditorBothStopTheSprint() async throws {
        try await makeController { controller, _ in
            controller.start(minutes: 10, currentWords: 0, workID: nil, now: sprintStart)
            controller.toggleFromMenu(now: sprintStart.addingTimeInterval(90))
            #expect(controller.active == nil)
            #expect(controller.result?.minutes == 2)

            controller.result = nil
            controller.start(minutes: 10, currentWords: 0, workID: nil, now: sprintStart)
            _ = controller.finish(now: sprintStart.addingTimeInterval(30), showsResult: false)
            #expect(controller.active == nil)
            #expect(controller.result == nil)
        }
    }

    @Test func theMenuItemAsksHowLongWhenNoSprintIsRunning() async throws {
        try await makeController { controller, _ in
            #expect(controller.isChoosingDuration == false)
            controller.toggleFromMenu()
            #expect(controller.isChoosingDuration == true)
        }
    }

    @Test func wordsAfterTheDeadlineFinishWithoutCountingOrTapping() async throws {
        try await makeController { controller, _ in
            var taps = 0
            controller.tap = { taps += 1 }
            controller.start(minutes: 10, currentWords: 0, workID: nil, now: sprintStart)
            controller.noteWords(100, now: sprintStart.addingTimeInterval(60))
            #expect(taps == 1)

            controller.noteWords(250, now: sprintStart.addingTimeInterval(600))
            #expect(controller.active == nil)
            #expect(controller.result?.words == 100)
            #expect(taps == 1)
        }
    }

    @Test func preloadedHistoryMarksEarlyFinishAsBestThisWeek() async throws {
        try await makeController { controller, history in
            let calendar = weekCalendar()
            let monday = day(calendar, 2023, 11, 27)
            let tuesday = day(calendar, 2023, 11, 28)
            try await history.append(record(monday, words: 120))
            await controller.loadHistory()

            controller.start(minutes: 25, currentWords: 0, workID: nil, now: tuesday)
            controller.noteWords(180, now: tuesday.addingTimeInterval(30))
            let finished = controller.finish(now: tuesday.addingTimeInterval(60))
            #expect(finished?.isBestThisWeek == true)
        }
    }
}

struct SprintHistoryTests {
    @Test func historySurvivesANewInstance() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprints-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("sprints.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let saved = record(sprintStart, words: 321)
        try await SprintHistory(url: url).append(saved)
        let loaded = try await SprintHistory(url: url).list()
        #expect(loaded == [saved])
    }

    @Test func missingHistoryListsEmptyAndCorruptHistoryIsPreserved() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprints-corrupt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sprints.json")
        let history = SprintHistory(url: url)

        let empty = try await history.list()
        #expect(empty.isEmpty)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corrupt = Data("{bad".utf8)
        try corrupt.write(to: url)

        await #expect(throws: WritingDocumentError.corrupt("sprints.json")) {
            _ = try await history.list()
        }
        let sample = record(sprintStart, words: 50)
        await #expect(throws: WritingDocumentError.corrupt("sprints.json")) {
            try await history.append(sample)
        }
        let preserved = try Data(contentsOf: url)
        #expect(preserved == corrupt)
    }

    @Test func concurrentAppendsAcrossSeparateInstancesKeepEveryRecord() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprints-concurrent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sprints.json")
        let first = SprintHistory(url: url)
        let second = SprintHistory(url: url)
        let entries = (0..<20).map { index in
            record(sprintStart.addingTimeInterval(Double(index)), words: index + 1)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, entry) in entries.enumerated() {
                let target = index.isMultiple(of: 2) ? first : second
                group.addTask {
                    try await target.append(entry)
                }
            }
            try await group.waitForAll()
        }

        let stored = try await SprintHistory(url: url).list()
        #expect(stored.count == 20)
        #expect(Set(stored.map(\.id)) == Set(entries.map(\.id)))
    }
}

struct SprintMenuTests {
    @Test func menuOffersStartOrEndNextToTheDocumentItems() {
        var capabilities = ChapterEditorMenuCapabilities(canStartSprint: true)
        #expect(capabilities.visibleActions.contains(.startSprint))
        #expect(!capabilities.visibleActions.contains(.endSprint))
        #expect(capabilities.menuModel().documentItems.map(\.title).contains("Start Sprint"))

        capabilities.isSprintRunning = true
        #expect(capabilities.visibleActions.contains(.endSprint))
        #expect(!capabilities.visibleActions.contains(.startSprint))
        #expect(capabilities.menuModel().documentItems.map(\.title).contains("End Sprint"))

        let none = ChapterEditorMenuCapabilities()
        #expect(!none.visibleActions.contains(.startSprint))
    }
}
