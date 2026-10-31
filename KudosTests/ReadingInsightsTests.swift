import Foundation
import Testing
@testable import Kudos

/// Artboard 1bi's figures. Every rule here is arguable, so every test states
/// which answer was chosen and would fail if the other one were substituted —
/// a test that only checked "a number came out" would pass on either.
///
/// No `ModelContainer`: the rules take `ReadingSessionFacts`, which is the point
/// of that type.
struct ReadingInsightsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private func day(_ dayOfMonth: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = dayOfMonth
        components.hour = hour
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func fact(
        work: UUID = UUID(),
        on dayOfMonth: Int,
        hour: Int = 12,
        minutes: Double,
        words: Int = 0,
        didFinish: Bool = false,
        fandom: String = ""
    ) -> ReadingSessionFacts {
        ReadingSessionFacts(
            workID: work,
            startedAt: day(dayOfMonth, hour: hour),
            durationSeconds: minutes * 60,
            wordCount: words,
            didFinish: didFinish,
            fandom: fandom,
            wordsRead: words
        )
    }

    // MARK: Median

    @Test func theTypicalSessionIsTheMedianSoOneBingeCannotMoveIt() {
        let facts = [
            fact(on: 1, minutes: 20),
            fact(on: 2, minutes: 30),
            fact(on: 3, minutes: 40),
            fact(on: 4, minutes: 240)
        ]
        // Mean would be 82.5 minutes — a figure none of these four sessions
        // resembles. The median of the middle two is 35.
        #expect(ReadingInsights.medianSeconds(of: facts) == 35 * 60)
    }

    @Test func medianOfNothingIsZeroRatherThanACrash() {
        #expect(ReadingInsights.medianSeconds(of: []) == 0)
    }

    // MARK: Finish rate

    @Test func finishRateCountsWorksNotSessionsSoARereadCannotInflateIt() {
        let reread = UUID()
        let abandoned = UUID()
        let facts = [
            fact(work: reread, on: 1, minutes: 30, didFinish: true),
            fact(work: reread, on: 2, minutes: 30, didFinish: true),
            fact(work: reread, on: 3, minutes: 30, didFinish: true),
            fact(work: abandoned, on: 4, minutes: 30)
        ]
        // Per session this would be 75%. Two works, one finished: 50%.
        #expect(ReadingInsights.finishRate(of: facts) == 0.5)
    }

    @Test func noStartedWorksIsNoDataRatherThanZeroPercent() {
        #expect(ReadingInsights.finishRate(of: []) == nil)
    }

    // MARK: Streak

    @Test func aStreakCountsDaysSoTwoSessionsInOneEveningAreOneDay() {
        let facts = [
            fact(on: 1, hour: 19, minutes: 30),
            fact(on: 1, hour: 22, minutes: 30),
            fact(on: 2, minutes: 30),
            fact(on: 3, minutes: 30),
            // Gap.
            fact(on: 9, minutes: 30)
        ]
        #expect(ReadingInsights.longestStreak(of: facts, calendar: calendar) == 3)
    }

    @Test func aStreakOfOneDayIsOneNotZero() {
        #expect(ReadingInsights.longestStreak(of: [fact(on: 4, minutes: 30)],
                                              calendar: calendar) == 1)
    }

    // MARK: Fandom shares

    @Test func fandomSharesPartitionTheHoursRatherThanOverCounting() {
        let facts = [
            fact(on: 1, minutes: 60, fandom: "Naruto"),
            fact(on: 2, minutes: 30, fandom: "Cyberpunk 2077"),
            fact(on: 3, minutes: 20, fandom: "Blade Runner"),
            fact(on: 4, minutes: 10, fandom: "Dracula"),
            // A session whose work is gone: still real hours, no fandom.
            fact(on: 5, minutes: 5)
        ]
        let shares = ReadingInsights.fandomShares(from: facts)

        #expect(shares.map(\.name) == [
            "Naruto", "Cyberpunk 2077", "Blade Runner", "Everything else"
        ])
        // The fourth fandom and the unattributable session fold together, and
        // the shares still sum to the total — the whole reason attribution is a
        // partition rather than one row per fandom of a crossover.
        #expect(shares.last?.seconds == Double(15 * 60))
        #expect(shares.last?.isRemainder == true)
        #expect(shares.reduce(0) { $0 + $1.seconds } == 125 * 60)
    }

    @Test func noRemainderRowAppearsWhenNothingIsLeftOver() {
        let shares = ReadingInsights.fandomShares(from: [
            fact(on: 1, minutes: 60, fandom: "Naruto"),
            fact(on: 2, minutes: 30, fandom: "Dracula")
        ])
        #expect(shares.map(\.name) == ["Naruto", "Dracula"])
        #expect(shares.contains { $0.isRemainder } == false)
    }

    // MARK: Words per hour

    @Test func wordsPerHourIsWeightedByTimeNotAveragedAcrossSessions() {
        let facts = [
            fact(on: 1, minutes: 60, words: 10_000),
            fact(on: 2, minutes: 180, words: 60_000),
            // Ignored: a zero-length row would otherwise divide by zero.
            fact(on: 3, minutes: 0, words: 900_000)
        ]
        // Averaging the two rates would give 15,000. Weighted by time: 70,000
        // words over 4 hours.
        #expect(ReadingInsights.wordsPerHour(of: facts) == 17_500)
    }

    // MARK: The delta

    @Test func aFirstPeriodHasNoDeltaRatherThanADeltaAgainstZero() {
        let insights = ReadingInsights.make(
            facts: [fact(on: 1, minutes: 60)], calendar: calendar
        )
        #expect(insights.previousPeriodSeconds == nil)
        #expect(insights.totalSeconds == 3_600)
    }

    @Test func theDeltaComesFromThePriorPeriodsOwnRows() {
        let insights = ReadingInsights.make(
            facts: [fact(on: 1, minutes: 90)],
            previousPeriodFacts: [fact(on: 1, minutes: 30)],
            calendar: calendar
        )
        #expect(insights.previousPeriodSeconds == 1_800)
        #expect(ReadingInsights.signedHoursLabel(
            insights.totalSeconds - (insights.previousPeriodSeconds ?? 0)
        ) == "+1.0")
    }

    // MARK: Labels

    @Test func labelsMatchTheSpecsOwnFormats() {
        #expect(ReadingInsights.hoursLabel(18.4 * 3600) == "18.4")
        #expect(ReadingInsights.signedHoursLabel(-0.6 * 3600) == "−0.6")
        #expect(ReadingInsights.durationLabel(31 * 60) == "31 min")
        #expect(ReadingInsights.durationLabel(72 * 60) == "1h 12m")
        #expect(ReadingInsights.durationLabel(120 * 60) == "2h")
    }

    // MARK: Redesign Figures (T-497)

    @Test func novelsWorthCalculationRoundsToHalfAndHidesUnder35k() {
        // Spec rule: Words read ÷ 70,000 to nearest half; hidden under 35,000 words.
        #expect(ReadingInsights.novelsWorth(words: 30_000) == nil)
        #expect(ReadingInsights.novelsWorth(words: 35_000) == 0.5)
        #expect(ReadingInsights.novelsWorth(words: 70_000) == 1.0)
        #expect(ReadingInsights.novelsWorth(words: 100_000) == 1.5)
        #expect(ReadingInsights.novelsWorth(words: 212_600) == 3.0)

        #expect(
            ReadingInsights.novelsWorthLabel(words: 212_600) ==
                "About 3 novels’ worth, at 70,000 words a novel"
        )
        #expect(ReadingInsights.novelsWorthLabel(words: 25_000) == nil)
    }

    @Test func lengthMixCategorizesWordCountsCorrectly() {
        let words = [2_500, 15_000, 45_000, 60_000, 250_000]
        let mix = ReadingInsights.lengthMix(words: words)

        #expect(mix.under5k == 1)
        #expect(mix.from5kTo50k == 2)
        #expect(mix.from50kTo150k == 1)
        #expect(mix.over150k == 1)
        #expect(mix.totalWorks == 5)
    }

    @Test func romanticVsPlatonicRelationshipDetection() {
        #expect(ReadingInsights.isRomanticRelationship("Anne Elliot/Frederick Wentworth") == true)
        #expect(ReadingInsights.relationshipGlyph(for: "Anne Elliot/Frederick Wentworth") == "/")

        #expect(ReadingInsights.isRomanticRelationship("Sherlock Holmes & John Watson") == false)
        #expect(ReadingInsights.relationshipGlyph(for: "Sherlock Holmes & John Watson") == "&")
    }

    @Test func shipConcentrationCalculatesPercentageOnTopRelationship() {
        let ships = [
            RelationshipShare(
                name: "A/B",
                isRomantic: true,
                fandom: "Persuasion",
                worksCount: 4,
                words: 80_000
            ),
            RelationshipShare(
                name: "A&C",
                isRomantic: false,
                fandom: "Persuasion",
                worksCount: 1,
                words: 20_000
            )
        ]
        let conc = ReadingInsights.shipConcentrations(relationships: ships)
        #expect(conc.count == 1)
        #expect(conc.first?.percentage == 80)
        #expect(conc.first?.fandom == "Persuasion")
    }

    @Test func sittingBucketsDistributeCorrectlyByDuration() {
        let facts = [
            fact(on: 1, minutes: 5),    // < 10 m
            fact(on: 2, minutes: 20),   // 10–30 m
            fact(on: 3, minutes: 45),   // 30–60 m
            fact(on: 4, minutes: 90),   // 1–2 h
            fact(on: 5, minutes: 150)   // 2 h +
        ]
        let buckets = ReadingInsights.sittingBuckets(from: facts)
        #expect(buckets.map(\.count) == [1, 1, 1, 1, 1])
    }

    @Test func lateNightDurationOnlyCountsSessionsBetween1And5AM() {
        let facts = [
            fact(on: 1, hour: 3, minutes: 30),  // late night
            fact(on: 2, hour: 14, minutes: 60)  // afternoon
        ]
        #expect(ReadingInsights.lateNightDuration(from: facts, calendar: calendar) == 30 * 60)
    }
}
