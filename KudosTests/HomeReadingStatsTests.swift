import Foundation
import Testing
@testable import Kudos

/// Tests for Home's reading statistics line under the title (T-487).
struct HomeReadingStatsTests {
    @Test func defaultStatsProduceCleanZeroStrings() {
        let stats = HomeReadingStats()
        #expect(stats.durationSeconds == 0)
        #expect(stats.finishedCount == 0)
        #expect(stats.streakDays == 0)
        #expect(stats.formattedDuration == "0 m")
        #expect(stats.spokenDuration == "0 minutes")
        #expect(stats.formattedStreak == "0-day")
        #expect(stats.accessibilityLabel == "0 minutes this week, 0 finished, 0-day streak")
    }

    @Test func formattedDurationRoundsToMinutesAndFormatsHours() {
        // Less than 1 hour
        let thirtyFiveM = HomeReadingStats(durationSeconds: 2100)
        #expect(thirtyFiveM.formattedDuration == "35 m")
        #expect(thirtyFiveM.spokenDuration == "35 minutes")

        // Exact hours
        let oneH = HomeReadingStats(durationSeconds: 3600)
        #expect(oneH.formattedDuration == "1 h")
        #expect(oneH.spokenDuration == "1 hour")

        let twoH = HomeReadingStats(durationSeconds: 7200)
        #expect(twoH.formattedDuration == "2 h")
        #expect(twoH.spokenDuration == "2 hours")

        // Hours and minutes
        let fourHTenM = HomeReadingStats(durationSeconds: 15000)
        #expect(fourHTenM.formattedDuration == "4 h 10 m")
        #expect(fourHTenM.spokenDuration == "4 hours 10 minutes")
    }

    @Test func formattedStreakAddsDaySuffix() {
        let oneDay = HomeReadingStats(streakDays: 1)
        #expect(oneDay.formattedStreak == "1-day")

        let nineDay = HomeReadingStats(streakDays: 9)
        #expect(nineDay.formattedStreak == "9-day")
    }

    @Test func accessibilityLabelCombinesSpokenFacts() {
        let stats = HomeReadingStats(durationSeconds: 15000, finishedCount: 2, streakDays: 9)
        #expect(stats.accessibilityLabel == "4 hours 10 minutes this week, 2 finished, 9-day streak")
    }

    @Test func calculateSumsWeekDurationAndDeduplicatesFinishedWorks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2 // Monday

        // Wednesday, Oct 28, 2026, 12:00:00 GMT
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 28
        components.hour = 12
        let now = calendar.date(from: components)!

        let work1 = UUID()
        let work2 = UUID()
        let workOld = UUID()

        // Oct 27 (Tuesday, this week): 2 hours, finished work1
        let session1 = ReadingSessionFacts(
            workID: work1,
            startedAt: calendar.date(byAdding: .day, value: -1, to: now)!,
            durationSeconds: 7200,
            wordCount: 15000,
            didFinish: true
        )

        // Oct 28 (Wednesday, today): 2 hours 10 min, finished work2
        let session2 = ReadingSessionFacts(
            workID: work2,
            startedAt: now,
            durationSeconds: 7800,
            wordCount: 20000,
            didFinish: true
        )

        // Oct 28 (Wednesday, today): 10 min on work2, already counted finished
        let session3 = ReadingSessionFacts(
            workID: work2,
            startedAt: calendar.date(byAdding: .minute, value: 30, to: now)!,
            durationSeconds: 600,
            wordCount: 20000,
            didFinish: true
        )

        // Oct 10 (over two weeks ago): 3 hours, finished workOld
        let sessionOld = ReadingSessionFacts(
            workID: workOld,
            startedAt: calendar.date(byAdding: .day, value: -18, to: now)!,
            durationSeconds: 10800,
            wordCount: 30000,
            didFinish: true
        )

        let facts = [session1, session2, session3, sessionOld]
        let stats = HomeReadingStats.calculate(facts: facts, now: now, calendar: calendar)

        // Weekly duration: 7200 + 7800 + 600 = 15600 seconds = 4 h 20 m
        #expect(stats.durationSeconds == 15600)
        #expect(stats.formattedDuration == "4 h 20 m")

        // Finished count: work1 and work2 = 2 unique works finished this week
        #expect(stats.finishedCount == 2)

        // Streak: consecutive reading days ending on today (Tuesday and Wednesday) = 2
        #expect(stats.streakDays == 2)
        #expect(stats.formattedStreak == "2-day")
    }

    @Test func insightsFilterExcludesUnrevealedAdultWorkAndIncludesRevealed() {
        let adultWork = SavedWork(title: "Dark Romance", author: "Author")
        adultWork.rating = "Explicit"

        let generalWork = SavedWork(title: "Fluff Fic", author: "Author")
        generalWork.rating = "General Audiences"

        let queueOnlyWork = SavedWork(title: "Queued Only", author: "Author")
        queueOnlyWork.rating = "General Audiences"
        queueOnlyWork.isQueuedForLater = true
        queueOnlyWork.isSaved = false
        queueOnlyWork.isFavorite = false

        let works = [adultWork, generalWork, queueOnlyWork]
        let gate = PrivacyGate()

        // Hide mature is enabled, unrevealed: adult work excluded, queue-only excluded
        let concealedWorks = HomeReadingStats.insightsWorks(from: works, gate: gate, hideMature: true)
        #expect(concealedWorks.map(\.title) == ["Fluff Fic"])

        // When the mature work is revealed, it is now included
        gate.reveal(adultWork)
        let revealedWorks = HomeReadingStats.insightsWorks(from: works, gate: gate, hideMature: true)
        #expect(revealedWorks.map(\.title) == ["Dark Romance", "Fluff Fic"])

        // When hide mature is off, all non-queue-only works are included
        let gateUnused = PrivacyGate()
        let allWorks = HomeReadingStats.insightsWorks(from: works, gate: gateUnused, hideMature: false)
        #expect(allWorks.map(\.title) == ["Dark Romance", "Fluff Fic"])
    }

    @Test func statsRevisionKeyChangesAcrossDayBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var lateNightComponents = DateComponents()
        lateNightComponents.year = 2026
        lateNightComponents.month = 10
        lateNightComponents.day = 31
        lateNightComponents.hour = 23
        lateNightComponents.minute = 59
        lateNightComponents.second = 50
        let lateNight = calendar.date(from: lateNightComponents)!

        var midnightComponents = DateComponents()
        midnightComponents.year = 2026
        midnightComponents.month = 11
        midnightComponents.day = 1
        midnightComponents.hour = 0
        midnightComponents.minute = 0
        midnightComponents.second = 10
        let justAfterMidnight = calendar.date(from: midnightComponents)!

        let sameDayEarlier = calendar.date(byAdding: .minute, value: -10, to: lateNight)!

        let sessionCount = 5
        let newestModified: TimeInterval = 1730419190

        let lateNightKey = HomeReadingStats.revisionKey(
            sessionCount: sessionCount,
            newestModified: newestModified,
            now: lateNight,
            calendar: calendar
        )
        let midnightKey = HomeReadingStats.revisionKey(
            sessionCount: sessionCount,
            newestModified: newestModified,
            now: justAfterMidnight,
            calendar: calendar
        )
        let sameDayKey = HomeReadingStats.revisionKey(
            sessionCount: sessionCount,
            newestModified: newestModified,
            now: sameDayEarlier,
            calendar: calendar
        )

        // Day boundary must change the key so stats don't go stale at midnight
        #expect(lateNightKey != midnightKey)

        // Within the same day with same sessions, key remains stable
        #expect(lateNightKey == sameDayKey)
    }
}
