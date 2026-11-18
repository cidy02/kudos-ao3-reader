import Foundation
import SwiftData
import Testing
@testable import Kudos

@Suite(.serialized)
@MainActor
struct TagAliasInsightsTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
            ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self,
            QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self,
            FollowedTag.self, TagAlias.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func overviewAndTasteMergeLearnedAliasesAndKeepUnlearnedDistinct() {
        let cal = Calendar(identifier: .gregorian)
        let day1 = Date(timeIntervalSince1970: 1_750_000_000)
        let day2 = day1.addingTimeInterval(3_600)

        let workA = SavedWork(title: "Work A", author: "Author 1")
        workA.wordCount = 10_000
        workA.workFandoms = ["BNHA"]
        workA.workRelationships = ["Bakugou x Midoriya"]
        workA.workCharacters = ["Deku"]
        workA.workTags = ["h/c", "Angst", "slow burn"]

        let workB = SavedWork(title: "Work B", author: "Author 2")
        workB.wordCount = 20_000
        workB.workFandoms = ["Boku no Hero Academia"]
        workB.workRelationships = [
            "Bakugou Katsuki/Midoriya Izuku",
            "Bakugou Katsuki & Midoriya Izuku"
        ]
        workB.workCharacters = ["Midoriya Izuku"]
        workB.workTags = ["Hurt/Comfort", "Angst", "Slow Burn"]

        // Canon + learned umbrella tag on the same work is NOT a crossover.
        let umbrellaWork = SavedWork(title: "Umbrella", author: "Author 3")
        umbrellaWork.wordCount = 5_000
        umbrellaWork.workFandoms = [
            "Spider-Man: Into the Spider-Verse",
            "Spider-Man - All Media Types"
        ]

        // Unrelated two fandoms IS a crossover.
        let realCrossover = SavedWork(title: "Cross", author: "Author 4")
        realCrossover.wordCount = 5_000
        realCrossover.workFandoms = ["Boku no Hero Academia", "Harry Potter - J. K. Rowling"]

        let facts = [
            ReadingSessionFacts(
                workID: workA.id, startedAt: day1, durationSeconds: 1_200,
                wordCount: 10_000, didFinish: true, fandom: "BNHA", wordsRead: 10_000
            ),
            ReadingSessionFacts(
                workID: workB.id, startedAt: day2, durationSeconds: 1_800,
                wordCount: 20_000, didFinish: true, fandom: "Boku no Hero Academia", wordsRead: 20_000
            ),
            ReadingSessionFacts(
                workID: umbrellaWork.id, startedAt: day2, durationSeconds: 600,
                wordCount: 5_000, didFinish: false, fandom: "Spider-Man: Into the Spider-Verse",
                wordsRead: 5_000
            ),
            ReadingSessionFacts(
                workID: realCrossover.id, startedAt: day2, durationSeconds: 600,
                wordCount: 5_000, didFinish: false, fandom: "Boku no Hero Academia", wordsRead: 5_000
            )
        ]
        let works = [workA, workB, umbrellaWork, realCrossover]

        // Baseline without aliases: names remain identical-strings only.
        let unaliased = ReadingInsights.make(facts: facts, calendar: cal)
        #expect(unaliased.byFandom.first(where: { $0.name == "BNHA" })?.seconds == 1_200)
        #expect(unaliased.byFandom.first(where: { $0.name == "Boku no Hero Academia" })?.seconds == 2_400)

        let resolver = TagAliasResolver(aliases: [
            LearnedTagAlias(name: "BNHA", canonicalName: "Boku no Hero Academia", kind: .fandom),
            LearnedTagAlias(
                name: "Bakugou x Midoriya",
                canonicalName: "Bakugou Katsuki/Midoriya Izuku",
                kind: .relationship
            ),
            LearnedTagAlias(name: "Deku", canonicalName: "Midoriya Izuku", kind: .character),
            LearnedTagAlias(name: "h/c", canonicalName: "Hurt/Comfort", kind: .freeform),
            LearnedTagAlias(
                name: "Spider-Verse",
                canonicalName: "Spider-Man: Into the Spider-Verse",
                kind: .fandom,
                parentFandoms: ["Spider-Man - All Media Types"]
            )
        ])

        let overview = ReadingInsights.make(facts: facts, calendar: cal, aliases: resolver)
        let mhaShare = overview.byFandom.first { $0.name == "Boku no Hero Academia" }
        #expect(mhaShare?.seconds == 3_600)
        #expect(!overview.byFandom.contains { $0.name == "BNHA" })
        #expect(overview.fandomWordsShares.first { $0.name == "Boku no Hero Academia" }?.words == 35_000)

        let taste = ReadingTasteInsights.make(works: works, facts: facts, aliases: resolver)
        // Platonic "&" relationship retains "&"; "/" merges across workA & workB.
        let romanticShip = taste.relationships.first { $0.name == "Bakugou Katsuki/Midoriya Izuku" }
        let platonicShip = taste.relationships.first { $0.name == "Bakugou Katsuki & Midoriya Izuku" }
        #expect(romanticShip?.words == 30_000)
        #expect(romanticShip?.worksCount == 2)
        #expect(romanticShip?.fandom == "Boku no Hero Academia")
        #expect(platonicShip?.words == 20_000)

        #expect(taste.characters.first { $0.name == "Midoriya Izuku" }?.count == 2)
        #expect(!taste.characters.contains { $0.name == "Deku" })

        #expect(taste.tags.first { $0.name == "Hurt/Comfort" }?.words == 30_000)
        // Unlearned "slow burn" vs "Slow Burn" remain strictly separate (identical strings only).
        #expect(taste.tags.contains { $0.name == "slow burn" && $0.words == 10_000 })
        #expect(taste.tags.contains { $0.name == "Slow Burn" && $0.words == 20_000 })

        #expect(
            taste.oftenTogether.contains {
                ($0.tagA == "Angst" && $0.tagB == "Hurt/Comfort" && $0.worksCount == 2)
                    || ($0.tagA == "Hurt/Comfort" && $0.tagB == "Angst" && $0.worksCount == 2)
            }
        )
        // Only realCrossover is a crossover; umbrellaWork collapses canon + umbrella fandom.
        #expect(taste.crossoverCount == 1)
    }

    @Test func habitsStatsAndTagCountsMergeLearnedAliases() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        // 2025-02-10 12:00 UTC (month index 1) and 2025-03-10 12:00 UTC (month index 2)
        let monthFeb = try #require(cal.date(from: DateComponents(year: 2025, month: 2, day: 10, hour: 12)))
        let monthMar = try #require(cal.date(from: DateComponents(year: 2025, month: 3, day: 10, hour: 12)))

        let workA = SavedWork(title: "Work A", author: "Author 1")
        workA.wordCount = 10_000
        workA.workFandoms = ["BNHA"]
        workA.workTags = ["h/c", "slow burn"]
        workA.lastReadDate = monthFeb

        let workB = SavedWork(title: "Work B", author: "Author 2")
        workB.wordCount = 20_000
        workB.workFandoms = ["Boku no Hero Academia"]
        workB.workTags = ["Hurt/Comfort", "Slow Burn"]
        workB.lastReadDate = monthMar

        let realCrossover = SavedWork(title: "Cross", author: "Author 4")
        realCrossover.wordCount = 5_000
        realCrossover.workFandoms = ["Boku no Hero Academia", "Harry Potter - J. K. Rowling"]
        realCrossover.lastReadDate = monthMar

        let works = [workA, workB, realCrossover]
        let facts = [
            ReadingSessionFacts(
                workID: workA.id, startedAt: monthFeb, durationSeconds: 1_200,
                wordCount: 10_000, didFinish: true, fandom: "BNHA", wordsRead: 10_000
            ),
            ReadingSessionFacts(
                workID: workB.id, startedAt: monthMar, durationSeconds: 1_800,
                wordCount: 20_000, didFinish: true, fandom: "Boku no Hero Academia", wordsRead: 20_000
            ),
            ReadingSessionFacts(
                workID: realCrossover.id, startedAt: monthMar, durationSeconds: 600,
                wordCount: 5_000, didFinish: false, fandom: "Boku no Hero Academia", wordsRead: 5_000
            )
        ]
        let resolver = TagAliasResolver(aliases: [
            LearnedTagAlias(name: "BNHA", canonicalName: "Boku no Hero Academia", kind: .fandom),
            LearnedTagAlias(name: "h/c", canonicalName: "Hurt/Comfort", kind: .freeform)
        ])

        let habits = ReadingHabitsInsights.make(
            works: works, facts: facts, allFacts: facts, calendar: cal, aliases: resolver
        )
        let mhaLane = try #require(habits.fandomTimeline.first { $0.name == "Boku no Hero Academia" })
        // Feb (10k via "BNHA") = ratio 0.4 -> tier 2; Mar (25k via canonical) = tier 3.
        #expect(mhaLane.monthlyActivity[1] == 2)
        #expect(mhaLane.monthlyActivity[2] == 3)

        let statsRead = ReadingStatistics(
            works: works, now: monthMar, calendar: cal, aliases: resolver
        )
        #expect(statsRead.topFandoms.first { $0.name == "Boku no Hero Academia" }?.count == 3)

        let sessions = [
            ReadingSession(
                workID: workA.id, startedAt: monthFeb,
                endedAt: monthFeb.addingTimeInterval(600), durationSeconds: 600
            ),
            ReadingSession(
                workID: workB.id, startedAt: monthMar,
                endedAt: monthMar.addingTimeInterval(600), durationSeconds: 600
            )
        ]
        let logTags = ReadingLogService.tagCounts(from: sessions, works: works, aliases: resolver)
        #expect(logTags.first { $0.tag == "Hurt/Comfort" }?.count == 2)
        #expect(logTags.contains { $0.tag == "slow burn" && $0.count == 1 })
        #expect(logTags.contains { $0.tag == "Slow Burn" && $0.count == 1 })
    }

    @Test func readingLogServiceInsightsQueriesModelContextAliases() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cal = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let interval = try #require(cal.dateInterval(of: .month, for: now))

        let w1 = SavedWork(title: "Fic 1", author: "A1")
        w1.workFandoms = ["Alias Fandom"]
        let w2 = SavedWork(title: "Fic 2", author: "A2")
        w2.workFandoms = ["Canonical Fandom"]
        context.insert(w1)
        context.insert(w2)

        let s1 = ReadingSession(
            workID: w1.id,
            startedAt: now,
            endedAt: now.addingTimeInterval(300),
            durationSeconds: 300
        )
        s1.fandoms = ["Alias Fandom"]
        let s2 = ReadingSession(
            workID: w2.id,
            startedAt: now.addingTimeInterval(600),
            endedAt: now.addingTimeInterval(1_200),
            durationSeconds: 600
        )
        s2.fandoms = ["Canonical Fandom"]
        context.insert(s1)
        context.insert(s2)

        _ = TagAliasStore.upsert(
            name: "Alias Fandom",
            canonicalName: "Canonical Fandom",
            kind: .fandom,
            in: context,
            now: now
        )

        let insights = ReadingLogService.insights(
            for: interval,
            previousPeriod: nil,
            works: [w1, w2],
            calendar: cal,
            context: context
        )
        #expect(insights.byFandom.count == 1)
        #expect(insights.byFandom.first?.name == "Canonical Fandom")
        #expect(insights.byFandom.first?.seconds == 900)

        // Cycle-safe resolution terminates cleanly on mutual aliases.
        let cyclic = TagAliasResolver(aliases: [
            LearnedTagAlias(name: "A", canonicalName: "B", kind: .freeform),
            LearnedTagAlias(name: "B", canonicalName: "A", kind: .freeform)
        ])
        let resolvedCycle = cyclic.resolve("A", kind: .freeform)
        #expect(resolvedCycle == "A" || resolvedCycle == "B")
    }
}
