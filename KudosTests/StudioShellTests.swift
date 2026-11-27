import Foundation
import Testing
@testable import Kudos

@MainActor
struct StudioShellTests {
    // MARK: - Day log (positive deltas, local midnight, streak)

    @Test func dayLogRecordsOnlyPositiveChangesAndPersists() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("day-log.json")

        let calendar = fixedCalendar(secondsFromGMT: -5 * 3600)
        let noon = try makeDate(year: 2026, month: 11, day: 25, hour: 12, minute: 0, calendar: calendar)
        let log = StudioWritingDayLog(url: fileURL, calendar: { calendar }, now: { noon })

        let initial = try await log.words(on: noon)
        #expect(initial == 0)

        let afterFirstBurst = try await log.recordChange(from: 0, to: 120, at: noon)
        #expect(afterFirstBurst == 120)

        // Deletions and zero changes must not decrease or add to today's count.
        let afterDeletion = try await log.recordChange(from: 120, to: 90, at: noon)
        #expect(afterDeletion == 120)

        let afterZero = try await log.recordChange(from: 90, to: 90, at: noon)
        #expect(afterZero == 120)

        let afterNegativeDelta = try await log.record(delta: -40, at: noon)
        #expect(afterNegativeDelta == 120)

        // Subsequent positive growth from the post-delete baseline records only the new positive delta.
        let afterRetype = try await log.recordChange(from: 90, to: 140, at: noon)
        #expect(afterRetype == 170)

        // Reloading from disk in a fresh actor instance preserves the recorded total.
        let reloaded = StudioWritingDayLog(url: fileURL, calendar: { calendar }, now: { noon })
        let persisted = try await reloaded.words(on: noon)
        #expect(persisted == 170)
    }

    @Test func dayLogBucketsPositiveChangesAcrossLocalMidnight() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("day-log.json")

        // UTC-5: 23:55 local on Nov 25 is already Nov 26 in UTC, proving local calendar bucketing.
        let calendar = fixedCalendar(secondsFromGMT: -5 * 3600)
        let beforeMidnight = try makeDate(year: 2026, month: 11, day: 25, hour: 23, minute: 55, calendar: calendar)
        let afterMidnight = try makeDate(year: 2026, month: 11, day: 26, hour: 0, minute: 5, calendar: calendar)
        let log = StudioWritingDayLog(url: fileURL, calendar: { calendar }, now: { afterMidnight })

        let nov25Total = try await log.record(delta: 150, at: beforeMidnight)
        #expect(nov25Total == 150)

        let nov26Total = try await log.record(delta: 80, at: afterMidnight)
        #expect(nov26Total == 80)

        let nov25Words = try await log.words(on: beforeMidnight)
        let nov26Words = try await log.words(on: afterMidnight)
        let allCounts = try await log.counts()
        #expect(nov25Words == 150)
        #expect(nov26Words == 80)
        #expect(allCounts == ["2026-11-25": 150, "2026-11-26": 80])
    }

    @Test func dayLogStreakIncludesAndExcludesToday() async throws {
        let calendar = fixedCalendar(secondsFromGMT: -5 * 3600)
        let today = try makeDate(year: 2026, month: 11, day: 26, hour: 15, minute: 0, calendar: calendar)

        // Empty log has streak 0.
        #expect(StudioWritingDayLogMath.streak(counts: [:], asOf: today, calendar: calendar) == 0)

        // Consecutive prior days without today yet written still hold the streak (excluding today).
        let priorOnly = [
            "2026-11-24": 300,
            "2026-11-25": 420
        ]
        #expect(StudioWritingDayLogMath.streak(counts: priorOnly, asOf: today, calendar: calendar) == 2)

        // Writing any positive words today increments the streak (including today).
        var withToday = priorOnly
        withToday["2026-11-26"] = 50
        #expect(StudioWritingDayLogMath.streak(counts: withToday, asOf: today, calendar: calendar) == 3)

        // A missing yesterday breaks the prior run when today is still 0.
        let brokenBeforeToday = [
            "2026-11-23": 200,
            "2026-11-24": 300
        ]
        #expect(StudioWritingDayLogMath.streak(counts: brokenBeforeToday, asOf: today, calendar: calendar) == 0)

        // Writing today after a missed yesterday starts a fresh 1-day streak.
        var freshToday = brokenBeforeToday
        freshToday["2026-11-26"] = 10
        #expect(StudioWritingDayLogMath.streak(counts: freshToday, asOf: today, calendar: calendar) == 1)

        // Snapshot exposes words today, streak, and 7 recent days ending on today.
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = StudioWritingDayLog(
            url: directory.appendingPathComponent("day-log.json"),
            calendar: { calendar },
            now: { today }
        )
        let twoDaysAgo = try makeDate(year: 2026, month: 11, day: 24, hour: 10, minute: 0, calendar: calendar)
        let yesterday = try makeDate(year: 2026, month: 11, day: 25, hour: 10, minute: 0, calendar: calendar)
        _ = try await log.record(delta: 200, at: twoDaysAgo)
        _ = try await log.record(delta: 350, at: yesterday)

        let beforeWritingToday = try await log.snapshot(asOf: today)
        #expect(beforeWritingToday.wordsToday == 0)
        #expect(beforeWritingToday.streak == 2)
        #expect(beforeWritingToday.recentDays.count == 7)
        #expect(beforeWritingToday.recentDays.last?.dayKey == "2026-11-26")
        #expect(beforeWritingToday.recentDays.last?.isToday == true)

        _ = try await log.record(delta: 75, at: today)
        let afterWritingToday = try await log.snapshot(asOf: today)
        #expect(afterWritingToday.wordsToday == 75)
        #expect(afterWritingToday.streak == 3)
    }

    @Test func dayLogTrackerSeedsExistingChapterWithoutCreditingLoadedWords() {
        var tracker = StudioWritingDayLogTracker()

        // Not ready yet: never records.
        let unreadyDelta = tracker.receive(words: 500, isReady: false, sessionKey: "doc-1")
        #expect(unreadyDelta == 0)

        // Opening an existing 1,240-word chapter seeds the baseline without logging 1,240 words.
        let seedDelta = tracker.receive(words: 1_240, isReady: true, sessionKey: "doc-1")
        #expect(seedDelta == 0)

        let firstTyped = tracker.receive(words: 1_265, isReady: true, sessionKey: "doc-1")
        #expect(firstTyped == 25)

        let afterDelete = tracker.receive(words: 1_250, isReady: true, sessionKey: "doc-1")
        #expect(afterDelete == 0)

        let afterRetype = tracker.receive(words: 1_270, isReady: true, sessionKey: "doc-1")
        #expect(afterRetype == 20)

        // Switching to a different chapter resets the baseline instead of diffing across chapters.
        let switchedSeed = tracker.receive(words: 2_000, isReady: true, sessionKey: "doc-2")
        #expect(switchedSeed == 0)

        let secondChapterTyped = tracker.receive(words: 2_015, isReady: true, sessionKey: "doc-2")
        #expect(secondChapterTyped == 15)
    }

    @Test func dayLogTrackerDoesNotCreditThePreviousChapterAcrossASessionChange() {
        var tracker = StudioWritingDayLogTracker()
        let opened = tracker.receive(words: 100, isReady: true, sessionKey: "chapter-a")
        #expect(opened == 0)
        let typed = tracker.receive(words: 110, isReady: true, sessionKey: "chapter-a")
        #expect(typed == 10)

        // The host reports the session change as not-ready: the count in that callback can
        // still be chapter A's. Marking it ready would seed 110, then record chapter B's 500 as +390.
        let switched = tracker.receive(words: 110, isReady: false, sessionKey: "chapter-b")
        #expect(switched == 0)
        let seeded = tracker.receive(words: 500, isReady: true, sessionKey: "chapter-b")
        #expect(seeded == 0)
        let typedNext = tracker.receive(words: 515, isReady: true, sessionKey: "chapter-b")
        #expect(typedNext == 15)
    }

    // MARK: - Daily goal preference (default 1,000, off allowed)

    @Test func dailyGoalDefaultsToOneThousandAndSupportsOff() throws {
        let suiteName = "StudioShellTests.goal.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(StudioWritingGoal.goal(in: defaults) == 1_000)
        #expect(StudioWritingGoal.summaryText(for: StudioWritingGoal.goal(in: defaults)) == "1,000 words")

        StudioWritingGoal.setGoal(nil, in: defaults)
        #expect(StudioWritingGoal.storedValue(in: defaults) == 0)
        #expect(StudioWritingGoal.goal(in: defaults) == nil)
        #expect(StudioWritingGoal.summaryText(for: StudioWritingGoal.goal(in: defaults)) == "Off")
        #expect(StudioWritingGoal.progress(wordsToday: 640, goal: nil) == 0)
        #expect(StudioWritingGoal.percent(wordsToday: 640, goal: nil) == 0)

        StudioWritingGoal.setGoal(0, in: defaults)
        #expect(StudioWritingGoal.goal(in: defaults) == nil)

        StudioWritingGoal.setGoal(500, in: defaults)
        #expect(StudioWritingGoal.goal(in: defaults) == 500)
        #expect(StudioWritingGoal.progress(wordsToday: 250, goal: 500) == 0.5)
        #expect(StudioWritingGoal.percent(wordsToday: 250, goal: 500) == 50)
        #expect(StudioWritingGoal.progress(wordsToday: 900, goal: 500) == 1.0)
    }

    // MARK: - Shell section memory

    @Test func shellSectionStoreRemembersSelectionAndAccountRequirements() throws {
        let suiteName = "StudioShellTests.section.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(StudioSectionStore.load(in: defaults) == .overview)

        for section in StudioSection.allCases {
            StudioSectionStore.save(section, in: defaults)
            #expect(StudioSectionStore.load(in: defaults) == section)
        }

        defaults.set("unknown-section", forKey: StudioSectionStore.storageKey)
        #expect(StudioSectionStore.load(in: defaults) == .overview)

        #expect(StudioSection.overview.requiresAccount == false)
        #expect(StudioSection.documents.requiresAccount == false)
        #expect(StudioSection.comments.requiresAccount == true)
        #expect(StudioSection.stats.requiresAccount == true)
    }

    // MARK: - Start Writing & hasLocalDrafts

    @Test func startWritingCreatesFirstDocumentAndFlipsHasLocalDraftsAtOnce() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "StudioShellTests.startWriting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let stateStore = WritingTabStateStore(defaults: defaults)
        let store = WritingDocumentStore(root: root)
        let router = AppRouter(writingStateStore: stateStore, localDocumentsRoot: root)

        // Signed out with no documents: Writing tab stays hidden.
        let initialShows = router.evaluateWritingTab(isSignedIn: false)
        #expect(initialShows == false)
        #expect(router.hasLocalDrafts == false)
        #expect(router.showsWritingTab == false)
        #expect(router.mainTabs == [.home, .library, .browse])

        // Start Writing creates a document and flips hasLocalDrafts + showsWritingTab at once.
        let target = try await StudioStartWritingAction.createFirstDocument(in: store, router: router)
        #expect(router.hasLocalDrafts == true)
        #expect(router.showsWritingTab == true)
        #expect(router.mainTabs == [.home, .library, .writing, .browse])

        // Verify the created manuscript and its first chapter exist on disk.
        let works = try await store.listWorks()
        #expect(works.count == 1)
        #expect(works.first?.id == target.workID)
        let chapters = try await store.listChapters(workID: target.workID)
        #expect(chapters.count == 1)
        #expect(chapters.first?.id == target.chapterID)

        // A fresh router on next signed-out launch discovers the local document and keeps Writing visible.
        let relaunchedRouter = AppRouter(writingStateStore: stateStore, localDocumentsRoot: root)
        let relaunchedShows = relaunchedRouter.evaluateWritingTab(isSignedIn: false)
        #expect(relaunchedShows == true)
        #expect(relaunchedRouter.hasLocalDrafts == true)
        #expect(relaunchedRouter.showsWritingTab == true)

        // Deleting the last local document hides Writing again on a signed-out launch.
        try await store.deleteWork(target.workID)
        let afterDeleteRouter = AppRouter(writingStateStore: stateStore, localDocumentsRoot: root)
        let afterDeleteShows = afterDeleteRouter.evaluateWritingTab(isSignedIn: false)
        #expect(afterDeleteShows == false)
        #expect(afterDeleteRouter.hasLocalDrafts == false)
        #expect(afterDeleteRouter.showsWritingTab == false)
    }

    @Test func startWritingDoubleTapCreatesOneDocument() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WritingDocumentStore(root: root)

        async let first = StudioStartWritingAction.createFirstDocument(in: store, router: nil)
        async let second = StudioStartWritingAction.createFirstDocument(in: store, router: nil)
        let firstTarget = try await first
        let secondTarget = try await second
        #expect(firstTarget == secondTarget)

        let works = try await store.listWorks()
        #expect(works.count == 1)
    }

    @Test func ao3LoadSkipsAFreshSnapshotUntilRefreshSignInOrTheWindow() {
        let window = StudioAO3Load.freshnessWindow
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let fresh = StudioAO3Load.Stamp(
            loadedAt: start,
            sessionGeneration: 3,
            username: "writer",
            reloadToken: 1
        )

        let insideWindow = StudioAO3Load.shouldLoad(
            stamp: fresh,
            now: start.addingTimeInterval(window - 1),
            sessionGeneration: 3,
            username: "writer",
            reloadToken: 1,
            force: false
        )
        #expect(insideWindow == false)

        let atWindow = StudioAO3Load.shouldLoad(
            stamp: fresh,
            now: start.addingTimeInterval(window),
            sessionGeneration: 3,
            username: "writer",
            reloadToken: 1,
            force: false
        )
        #expect(atWindow == true)

        let neverLoaded = StudioAO3Load.shouldLoad(
            stamp: StudioAO3Load.Stamp(),
            now: start,
            sessionGeneration: 3,
            username: "writer",
            reloadToken: 0,
            force: false
        )
        #expect(neverLoaded == true)

        let sessionChanged = StudioAO3Load.shouldLoad(
            stamp: fresh,
            now: start.addingTimeInterval(10),
            sessionGeneration: 4,
            username: "writer",
            reloadToken: 1,
            force: false
        )
        #expect(sessionChanged == true)

        let usernameChanged = StudioAO3Load.shouldLoad(
            stamp: fresh,
            now: start.addingTimeInterval(10),
            sessionGeneration: 3,
            username: "other",
            reloadToken: 1,
            force: false
        )
        #expect(usernameChanged == true)

        let retryOrWrite = StudioAO3Load.shouldLoad(
            stamp: fresh,
            now: start.addingTimeInterval(10),
            sessionGeneration: 3,
            username: "writer",
            reloadToken: 2,
            force: false
        )
        #expect(retryOrWrite == true)

        let pullToRefresh = StudioAO3Load.shouldLoad(
            stamp: fresh,
            now: start.addingTimeInterval(10),
            sessionGeneration: 3,
            username: "writer",
            reloadToken: 1,
            force: true
        )
        #expect(pullToRefresh == true)
    }

    @Test func htmlExcerptStripsMarkupAndDecodesEntities() {
        let html = "<p>The tide &amp; wind turned.</p><p><em>Still</em> the boat sat&nbsp;there.</p>"
        let excerpt = StudioHTMLText.excerpt(from: html)
        #expect(excerpt == "The tide & wind turned. Still the boat sat there.")
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudioShellTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixedCalendar(secondsFromGMT: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: secondsFromGMT) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) throws -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return try #require(calendar.date(from: components))
    }
}
