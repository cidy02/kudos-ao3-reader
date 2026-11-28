import Foundation
import Testing
@testable import Kudos

/// Locks the Reading Insights board copy helpers against drift from `.design-ref/Insights*.dc.html`.
struct InsightsBoardCopyTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return cal
    }()

    private let locale = Locale(identifier: "en_US")

    private func date(year: Int = 2026, month: Int, day: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: - InsightsTop

    @Test func periodSubtitleAndPreviousComparisonMatchInsightsTopAndOverviewBoards() {
        let oct27 = date(month: 10, day: 27)
        #expect(
            InsightsBoardCopy.periodSubtitle(
                isYear: false,
                referenceDate: oct27,
                now: oct27,
                scopeSuffix: "",
                calendar: calendar,
                locale: locale
            ) == "1–27 Oct · vs September"
        )
        #expect(
            InsightsBoardCopy.periodSubtitle(
                isYear: false,
                referenceDate: oct27,
                now: oct27,
                scopeSuffix: " · incl. hidden",
                calendar: calendar,
                locale: locale
            ) == "1–27 Oct · vs September · incl. hidden"
        )
        #expect(
            InsightsBoardCopy.previousComparisonLabel(
                isYear: false,
                referenceDate: oct27,
                now: oct27,
                calendar: calendar,
                locale: locale
            ) == "Sep 1–27"
        )

        // First day of a month avoids "1–1".
        let oct1 = date(month: 10, day: 1)
        #expect(
            InsightsBoardCopy.periodSubtitle(
                isYear: false,
                referenceDate: oct1,
                now: oct1,
                calendar: calendar,
                locale: locale
            ) == "1 Oct · vs September"
        )
        #expect(
            InsightsBoardCopy.previousComparisonLabel(
                isYear: false,
                referenceDate: oct1,
                now: oct1,
                calendar: calendar,
                locale: locale
            ) == "Sep 1"
        )

        // Completed month spanning at least as many days as the previous month drops the day span.
        let nov15 = date(month: 11, day: 15)
        #expect(
            InsightsBoardCopy.previousComparisonLabel(
                isYear: false,
                referenceDate: oct27,
                now: nov15,
                calendar: calendar,
                locale: locale
            ) == "Sep"
        )

        // Year mode.
        #expect(
            InsightsBoardCopy.periodSubtitle(
                isYear: true,
                referenceDate: oct27,
                now: oct27,
                calendar: calendar,
                locale: locale
            ) == "2026 · vs 2025"
        )
        #expect(
            InsightsBoardCopy.previousComparisonLabel(
                isYear: true,
                referenceDate: oct27,
                now: oct27,
                calendar: calendar,
                locale: locale
            ) == "2025"
        )
    }

    // MARK: - Overview

    @Test func durationLabelsMatchSpacedBoardFormatAndVoiceOver() {
        #expect(InsightsBoardCopy.durationLabel(0) == "0 min")
        #expect(InsightsBoardCopy.durationLabel(24 * 60) == "24 min")
        #expect(InsightsBoardCopy.durationLabel(2 * 3600) == "2 h")
        #expect(InsightsBoardCopy.durationLabel((14 * 60 + 10) * 60) == "14 h 10 m")
        #expect(InsightsBoardCopy.durationLabel((1 * 60 + 47) * 60) == "1 h 47 m")

        #expect(
            InsightsBoardCopy.readingAndListeningBarLabel(
                silentSeconds: (12 * 60 + 25) * 60,
                listeningSeconds: (1 * 60 + 45) * 60,
                hideReadingTime: false
            ) == "Read 12 hours 25 minutes, listened 1 hour 45 minutes"
        )
        #expect(
            InsightsBoardCopy.readingAndListeningBarLabel(
                silentSeconds: 3600,
                listeningSeconds: 600,
                hideReadingTime: true
            ) == "Reading and Read Aloud time split"
        )
    }

    @Test func wordsPerDayTicksMatchOverviewBoard() {
        let days = (1...27).map { day in
            ReadingInsights.DailyWordsBucket(
                date: date(month: 10, day: day),
                dayNumber: day,
                words: day == 17 ? 31_400 : 5_000,
                isMax: day == 17,
                hasReading: true
            )
        }
        #expect(
            InsightsBoardCopy.wordsPerDayTicks(days: days, calendar: calendar, locale: locale)
                == ["Oct 1", "8", "15", "22", "27"]
        )
        #expect(InsightsBoardCopy.wordsPerDayTicks(days: [], calendar: calendar, locale: locale).isEmpty)
    }

    @Test func recordsGridDetailsMatchOverviewBoard() {
        let octDays = (1...27).map { day in
            let active = (10...20).contains(day) || day == 2
            return ReadingInsights.DailyWordsBucket(
                date: date(month: 10, day: day),
                dayNumber: day,
                words: active ? 4_000 : 0,
                isMax: false,
                hasReading: active
            )
        }
        #expect(
            InsightsBoardCopy.streakDateRangeLabel(
                days: octDays,
                expectedLength: 11,
                calendar: calendar,
                locale: locale
            ) == "Oct 10–20"
        )
        #expect(
            InsightsBoardCopy.streakDateRangeLabel(
                days: [octDays[1]],
                expectedLength: 1,
                calendar: calendar,
                locale: locale
            ) == "Oct 2"
        )
        #expect(
            InsightsBoardCopy.streakDateRangeLabel(
                days: octDays,
                expectedLength: 0,
                calendar: calendar,
                locale: locale
            ) == nil
        )

        // Oct 17, 2026 is a Saturday.
        let oct17 = date(month: 10, day: 17)
        let biggestDetail = InsightsBoardCopy.biggestDayDetail(date: oct17, calendar: calendar, locale: locale)
        #expect(biggestDetail.contains("Saturday"))
        #expect(biggestDetail.contains("Oct"))
        #expect(biggestDetail.contains("17"))
        #expect(InsightsBoardCopy.biggestDayDetail(date: nil, calendar: calendar, locale: locale) == "no data")

        #expect(InsightsBoardCopy.typicalSittingDetail(sittingsCount: 35) == "median of 35 sittings")
        #expect(InsightsBoardCopy.typicalSittingDetail(sittingsCount: 1) == "median of 1 sitting")
        #expect(InsightsBoardCopy.typicalSittingDetail(sittingsCount: 0) == "no sittings yet")
        #expect(InsightsBoardCopy.paceDetail(isCharacters: false) == "an hour, reading only")
        #expect(InsightsBoardCopy.paceDetail(isCharacters: true) == "characters an hour, reading only")
    }

    @Test func lengthMixAndFinishedMetaMatchOverviewBoard() {
        let mix = ReadingInsights.LengthMixCounts(under5k: 7, from5kTo50k: 9, from50kTo150k: 4, over150k: 1)
        #expect(
            InsightsBoardCopy.lengthMixBarLabel(mix)
                == "Works by length: 7 under 5,000 words, 9 from 5,000 to 50,000, 4 from 50,000 to 150,000, 1 over 150,000"
        )
        #expect(
            InsightsBoardCopy.finishedWorkMeta(wordCount: 21_880, finishCount: 4)
                == "\(21_880.formatted()) words · Read ×4"
        )
        #expect(
            InsightsBoardCopy.finishedWorkMeta(wordCount: 9_140, finishCount: 1)
                == "\(9_140.formatted()) words"
        )
        #expect(InsightsBoardCopy.finishedWorkMeta(wordCount: 0, finishCount: 2) == "Read ×2")
        #expect(InsightsBoardCopy.finishedWorkMeta(wordCount: 0, finishCount: 0).isEmpty)
    }

    // MARK: - Taste

    @Test func usualFicSentenceMatchesTasteBoardAndRespectsDiscreetMode() {
        var taste = ReadingTasteInsights()
        taste.usualStatus = "Complete"
        taste.usualRating = "Teen"
        taste.usualCategory = "F/M"
        taste.usualLengthBand = "50–150k"
        taste.usualTopFandom = "Persuasion"
        taste.usualTopRelationship = "Anne Elliot/Frederick Wentworth"
        taste.usualTopTag = "Slow Burn"
        taste.usualSecondTag = "Pining"
        taste.usualFicTags = ["Complete", "Teen", "F/M", "50–150k", "Persuasion", "Anne Elliot/Frederick Wentworth", "Slow Burn", "Pining"]

        let normal = InsightsBoardCopy.usualFicText(taste: taste)
        #expect(normal.boldFandom == "Persuasion")
        #expect(
            normal.plainText
                == "A complete, Teen-rated F/M fic in Persuasion, 50–150k words long, with Anne Elliot/Frederick Wentworth, Slow Burn and Pining."
        )

        var builder = InsightsDiscreetMasker.Builder()
        builder.registerFandom("Persuasion")
        builder.registerShip("Anne Elliot/Frederick Wentworth")
        builder.registerTag("Slow Burn")
        builder.registerTag("Pining")
        let masker = builder.build()

        let discreet = InsightsBoardCopy.usualFicText(taste: taste, discreetMode: true, discreetMasker: masker)
        #expect(discreet.boldFandom == "Fandom A")
        #expect(!discreet.plainText.contains("Persuasion"))
        #expect(!discreet.plainText.contains("Anne Elliot"))
        #expect(!discreet.plainText.contains("Slow Burn"))
        #expect(!discreet.plainText.contains("Pining"))
        #expect(discreet.plainText.contains("Ship A"))
        #expect(discreet.plainText.contains("Tag A and Tag B"))

        // Empty-state (< 5 works) preserves model explanation.
        var tooFew = ReadingTasteInsights()
        tooFew.usualFicSummary = "Read at least five works in this period to find your usual fic."
        #expect(
            InsightsBoardCopy.usualFicText(taste: tooFew).plainText
                == "Read at least five works in this period to find your usual fic."
        )

        // Indefinite article chooses "An" for vowel-sound starts.
        var wip = ReadingTasteInsights()
        wip.usualStatus = "Work in Progress"
        wip.usualRating = "Explicit"
        wip.usualCategory = "varied"
        wip.usualLengthBand = "Under 5k"
        wip.usualFicTags = ["Work in Progress", "Explicit"]
        #expect(
            InsightsBoardCopy.usualFicText(taste: wip).plainText
                == "An in-progress, Explicit-rated fic, under 5k words long."
        )
    }

    @Test func yearHistogramSeriesFillsGapsAndComputesFiveTicks() {
        let input = [
            ReadingTasteInsights.YearCount(year: 2010, count: 1),
            ReadingTasteInsights.YearCount(year: 2019, count: 3),
            ReadingTasteInsights.YearCount(year: 2026, count: 2)
        ]
        let series = InsightsBoardCopy.yearHistogramSeries(from: input)
        #expect(series.bars.count == 17)
        #expect(series.bars.first(where: { $0.year == 2015 })?.count == 0)
        #expect(series.ticks == [2010, 2014, 2018, 2022, 2026])

        let single = InsightsBoardCopy.yearHistogramSeries(from: [ReadingTasteInsights.YearCount(year: 2024, count: 5)])
        #expect(single.bars.count == 1)
        #expect(single.ticks == [2024])
    }

    // MARK: - Habits

    @Test func habitsCopyMatchesBoardWording() {
        // Exact minute distribution from Insights-Habits.dc.html.
        let boardMins = [59, 42, 37, 20, 8, 0, 0, 6, 11, 8, 6, 8, 25, 17, 8, 11, 14, 20, 37, 56, 82, 130, 146, 99]
        let hourly = boardMins.enumerated().map { hour, mins in
            ReadingInsights.HourlyBucket(hour: hour, seconds: Double(mins * 60))
        }
        #expect(InsightsBoardCopy.peakHoursLabel(hourly: hourly) == "most at 21:00–23:00")

        let emptyHourly = (0..<24).map { ReadingInsights.HourlyBucket(hour: $0, seconds: 0) }
        #expect(InsightsBoardCopy.peakHoursLabel(hourly: emptyHourly) == nil)

        #expect(
            InsightsBoardCopy.lateNightSummary(durationSeconds: 107 * 60, hideReadingTime: false, isYear: false)
                == "Late night, 1:00–5:00: 1 h 47 m this month"
        )
        #expect(
            InsightsBoardCopy.lateNightSummary(durationSeconds: 107 * 60, hideReadingTime: true, isYear: true)
                == "Late night, 1:00–5:00: — this year"
        )
        #expect(InsightsBoardCopy.sittingsHeaderSummary(total: 35, isYear: false) == "35 this month")
        #expect(InsightsBoardCopy.sittingsHeaderSummary(total: 210, isYear: true) == "210 this year")

        #expect(
            InsightsBoardCopy.rereadDetail(fandom: "Persuasion", totalWordsAcrossReads: 87_500)
                == "Persuasion · 87.5k words across reads"
        )
        #expect(
            InsightsBoardCopy.rereadDetail(fandom: "", totalWordsAcrossReads: 900)
                == "900 words across reads"
        )
        #expect(InsightsBoardCopy.stoppedHeaderSummary(inPeriod: 3, total: 23, isYear: false) == "3 this month · 23 in all")
        #expect(InsightsBoardCopy.stoppedHeaderSummary(inPeriod: 8, total: 23, isYear: true) == "8 this year · 23 in all")
    }

    // MARK: - Library & Metrics Sheet

    @Test func libraryCopyMatchesBoardWordingAndSingularPlural() {
        #expect(InsightsBoardCopy.unreadHeroSuffix(unreadCount: 86) == "words · 86 works")
        #expect(InsightsBoardCopy.unreadHeroSuffix(unreadCount: 1) == "words · 1 work")

        let wip = WIPFreshness(active: 21, quiet: 6, dormant: 11)
        #expect(
            InsightsBoardCopy.wipFreshnessBarLabel(wip)
                == "21 updated in the last 6 months, 6 in 6 to 12 months, 11 not for over a year"
        )

        #expect(
            InsightsBoardCopy.noLongerOnAO3Summary(count: 14, words: 1_100_000, lastCopies: 12)
                == "14 works · 1.1M words · 12 kept as your last copy"
        )
        #expect(
            InsightsBoardCopy.noLongerOnAO3Summary(count: 1, words: 850, lastCopies: 1)
                == "1 work · 850 words · 1 kept as your last copy"
        )

        #expect(
            InsightsBoardCopy.authorDetail(works: 9, words: 412_000, finished: 7)
                == "9 read · 412k words · 7 finished"
        )
        // The boards write 412k, 87.5k and 1.1M: trailing ".0" goes, real decimals stay, small counts are untouched.
        #expect(InsightsBoardCopy.compactWords(412_000) == "412k")
        #expect(InsightsBoardCopy.compactWords(87_500) == "87.5k")
        #expect(InsightsBoardCopy.compactWords(1_100_000) == "1.1M")
        #expect(InsightsBoardCopy.compactWords(2_000_000) == "2M")
        #expect(InsightsBoardCopy.compactWords(850) == "850")

        let jul2026 = date(year: 2026, month: 7, day: 15)
        let oct2026 = date(year: 2026, month: 10, day: 27)
        let jul2025 = date(year: 2025, month: 7, day: 15)
        #expect(InsightsBoardCopy.sinceLabel(date: jul2026, now: oct2026, calendar: calendar, locale: locale) == "since July")
        #expect(InsightsBoardCopy.sinceLabel(date: jul2025, now: oct2026, calendar: calendar, locale: locale) == "since Jul 2025")

        #expect(
            InsightsBoardCopy.foundEarlyUnder500Detail(count: 12, recordedFinishedCount: 35)
                == "of finished works had under 500 kudos when you saved them (12 of 35)"
        )
        #expect(
            InsightsBoardCopy.foundEarlyTripledDetail(grownCount: 4)
                == "have at least tripled their kudos since (4)"
        )
    }

    /// The sheet states numbers; each one is checked against the rule the code applies, so a change to
    /// a rule fails here instead of leaving the sheet claiming the old figure.
    @Test func howReadingInsightsAreCountedQuotesTheRulesTheCodeApplies() {
        #expect(HowInsightsAreCountedSheet.sheetTitle == "How Reading Insights Are Counted")
        let titles = HowInsightsAreCountedSheet.sections.map(\.title)
        #expect(titles == ["Device-Only Privacy", "Shared Rules", "Overview", "Taste", "Habits", "Library"])
        let allText = HowInsightsAreCountedSheet.sections.flatMap(\.paragraphs).joined(separator: " ")

        let boundary = ReadingInsights.dayBoundaryHour
        #expect(allText.contains("\(boundary):00 to \(boundary):00"))

        let mergeMinutes = Int(ReadingInsights.sittingMergeGapSeconds / 60)
        #expect(allText.contains("under \(mergeMinutes) minutes apart"))

        // Novels' worth: ÷ 70,000 to the nearest half, hidden under 35,000.
        #expect(allText.contains("divided by 70,000"))
        #expect(allText.contains("Hidden under 35,000 words"))
        #expect(ReadingInsights.novelsWorth(words: 34_999) == nil)
        #expect(ReadingInsights.novelsWorth(words: 35_000) == 0.5)
        #expect(ReadingInsights.novelsWorth(words: 70_000) == 1.0)

        // Skimmed / Peeked appear at 20 measured chapters of pace history, not before.
        #expect(allText.contains("after 20 measured chapters"))
        var timing = InsightsProvenance.ChapterTimingFigure()
        timing.paceHistoryChapters = 19
        #expect(!timing.canShowSkimAndPeek)
        timing.paceHistoryChapters = 20
        #expect(timing.canShowSkimAndPeek)
    }
}
