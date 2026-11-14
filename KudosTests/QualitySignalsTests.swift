import Foundation
import Testing
@testable import Kudos

/// Swift Testing tests for pure logic added in FID40 (tone choice, section split).
struct QualitySignalsTests {
    private var now: Date {
        WorkStat.date(from: "29 Oct 2026") ?? Date(timeIntervalSince1970: 0)
    }

    private func work(
        _ id: Int,
        title: String = "Test Work",
        kudos: Int?,
        hits: Int?,
        comments: Int? = 0,
        bookmarks: Int? = 0,
        words: Int? = 5_000,
        updated: String = "01 Oct 2026"
    ) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id, title: title, authors: ["Author"], authorIdentities: [],
            fandoms: ["Fandom"], rating: "T",
            warnings: [], categories: [], isComplete: true, dateUpdated: updated,
            tags: [], summary: "Summary", language: "English", words: words, chapters: "1/1",
            comments: comments, kudos: kudos, bookmarks: bookmarks, hits: hits,
            seriesTitle: nil, seriesURL: nil, seriesPosition: nil
        )
    }

    private func settings(
        _ rank: LoadedWorksRank = .kudosPerHitAdjusted,
        order: LoadedWorksRankOrder = .highestFirst,
        cautious: Bool = false,
        setAside: Bool = true
    ) -> LoadedWorksRanking {
        var s = LoadedWorksRanking()
        s.rank = rank
        s.order = order
        s.ranksCautiously = cautious
        s.setsAsideUnusual = setAside
        return s
    }

    // MARK: - Tone Choice Pure Logic

    @Test func toneChoiceHighForHighAdjustedMultiplier() {
        let figures = LoadedWorksRanker.Figures(
            work(1, kudos: 1_804, hits: 19_200, bookmarks: 469),
            now: now
        )
        let signal = QualitySignalTones.chooseTone(
            rank: .kudosPerHitAdjusted,
            shown: 2.37,
            figures: figures,
            setAside: false
        )
        #expect(signal != nil)
        #expect(signal?.tone == .high)
        #expect(signal?.label == "2.4× kudos per hit")
        #expect(signal?.note == "Steady · 26% saved")
        #expect(signal?.accessibilityText == "2.4× kudos per hit, Steady · 26% saved")
    }

    @Test func toneChoiceGoodForAverageMultiplier() {
        let figures = LoadedWorksRanker.Figures(
            work(2, kudos: 500, hits: 10_000, bookmarks: 50),
            now: now
        )
        let signal = QualitySignalTones.chooseTone(
            rank: .kudosPerHitAdjusted,
            shown: 1.0,
            figures: figures,
            setAside: false
        )
        #expect(signal != nil)
        #expect(signal?.tone == .neutral)
        #expect(signal?.label == "1.0× kudos per hit")
        #expect(signal?.note == "Steady · 10% saved")
    }

    @Test func toneChoiceNeutralForLowMultiplier() {
        let figures = LoadedWorksRanker.Figures(
            work(3, kudos: 100, hits: 10_000, bookmarks: 5),
            now: now
        )
        let signal = QualitySignalTones.chooseTone(
            rank: .kudosPerHitAdjusted,
            shown: 0.5,
            figures: figures,
            setAside: false
        )
        #expect(signal != nil)
        #expect(signal?.tone == .neutral)
        #expect(signal?.label == "0.5× kudos per hit")
        #expect(signal?.note == "Settling · 5% saved")
    }

    @Test func toneChoiceUnusualForMoreKudosThanHits() {
        let figures = LoadedWorksRanker.Figures(
            work(4, kudos: 18_420, hits: 1_180),
            now: now
        )
        let signal = QualitySignalTones.chooseTone(
            rank: .kudosPerHitAdjusted,
            shown: nil,
            figures: figures,
            setAside: true
        )
        #expect(signal != nil)
        #expect(signal?.tone == .unusual)
        #expect(signal?.label == "Unusual stats")
        #expect(signal?.note == "More kudos than hits")
    }

    @Test func toneChoiceUnusualForKudosWithoutBookmarks() {
        let figures = LoadedWorksRanker.Figures(
            work(5, kudos: 2_000, hits: 30_000, bookmarks: 2),
            now: now
        )
        let signal = QualitySignalTones.chooseTone(
            rank: .kudosPerHitAdjusted,
            shown: nil,
            figures: figures,
            setAside: true
        )
        #expect(signal != nil)
        #expect(signal?.tone == .unusual)
        #expect(signal?.label == "Unusual stats")
        #expect(signal?.note == "Thousands of kudos and almost no bookmarks")
    }

    @Test func toneChoiceConfidenceBandsReflectKudosCount() {
        // Early: kudos < 50
        let earlyFigures = LoadedWorksRanker.Figures(work(1, kudos: 30, hits: 500, bookmarks: 0), now: now)
        let earlySignal = QualitySignalTones.chooseTone(
            rank: .kudosPerHitAdjusted,
            shown: 1.5,
            figures: earlyFigures,
            setAside: false
        )
        #expect(earlySignal?.note?.contains("Early") == true)

        // Settling: 50 <= kudos < 200
        let settlingFigures = LoadedWorksRanker.Figures(work(2, kudos: 120, hits: 2_000, bookmarks: 12), now: now)
        let settlingSignal = QualitySignalTones.chooseTone(
            rank: .kudosPerHitAdjusted,
            shown: 1.5,
            figures: settlingFigures,
            setAside: false
        )
        #expect(settlingSignal?.note?.contains("Settling") == true)

        // Steady: kudos >= 200
        let steadyFigures = LoadedWorksRanker.Figures(work(3, kudos: 350, hits: 5_000, bookmarks: 35), now: now)
        let steadySignal = QualitySignalTones.chooseTone(
            rank: .kudosPerHitAdjusted,
            shown: 1.5,
            figures: steadyFigures,
            setAside: false
        )
        #expect(steadySignal?.note?.contains("Steady") == true)
    }

    @Test func toneChoiceForOtherRanks() {
        let figures = LoadedWorksRanker.Figures(work(1, kudos: 250, hits: 2_500, comments: 25, bookmarks: 65), now: now)

        // Saves per kudos: 26% >= 20% -> high
        let savesSignal = QualitySignalTones.chooseTone(
            rank: .savesPerKudos,
            shown: 0.26,
            figures: figures,
            setAside: false
        )
        #expect(savesSignal?.tone == .high)
        #expect(savesSignal?.label == "26% saved")

        // Comments per kudos: 10% >= 5% -> high
        let commentsSignal = QualitySignalTones.chooseTone(
            rank: .commentsPerKudos,
            shown: 0.10,
            figures: figures,
            setAside: false
        )
        #expect(commentsSignal?.tone == .high)
        #expect(commentsSignal?.label == "10% comments")

        // Inactive ranking returns nil
        let inactive = QualitySignalTones.chooseTone(
            rank: .ao3Order,
            shown: nil,
            figures: figures,
            setAside: false
        )
        #expect(inactive == nil)

        // Nil shown returns neutral "Not enough figures to rank"
        let unranked = QualitySignalTones.chooseTone(
            rank: .kudosPerHitAdjusted,
            shown: nil,
            figures: figures,
            setAside: false
        )
        #expect(unranked?.tone == .neutral)
        #expect(unranked?.label == "Not enough figures to rank")
    }

    // MARK: - Section Split Pure Logic

    @Test func sectionSplitWhenRankingIsInactivePlacesAllInRanked() {
        let works = [
            work(1, kudos: 100, hits: 1_000),
            work(2, kudos: 200, hits: 2_000),
            work(3, kudos: 300, hits: 3_000)
        ]
        let partition = LoadedWorksRanker.partition(works, by: settings(.ao3Order), now: now)
        #expect(partition.ranked.map(\.work.id) == [1, 2, 3])
        #expect(partition.unranked.isEmpty)
    }

    @Test func sectionSplitSeparatesRankedAndUnrankedWorks() {
        let works = [
            work(1, kudos: 100, hits: 1_000), // normal: 10%
            work(2, kudos: 300, hits: 1_000), // high: 30%
            work(3, kudos: 5_000, hits: 100), // unusual: more kudos than hits
            work(4, kudos: nil, hits: nil),   // unscored: no hits or kudos
            work(5, kudos: 50, hits: 1_000)   // low: 5%
        ]
        let partition = LoadedWorksRanker.partition(works, by: settings(.kudosPerHitAdjusted), now: now)

        // Ranked: 2 (30%), 1 (10%), 5 (5%) in highest-first score order
        #expect(partition.ranked.map(\.work.id) == [2, 1, 5])
        #expect(partition.ranked[0].rankPosition == 1)
        #expect(partition.ranked[1].rankPosition == 2)
        #expect(partition.ranked[2].rankPosition == 3)
        #expect(partition.ranked.allSatisfy { $0.totalLoaded == 5 })

        // Unranked: 4 (unscored) and 3 (set aside) in AO3's original order
        #expect(partition.unranked.map(\.work.id) == [4, 3])
        #expect(partition.unranked.first { $0.work.id == 3 }?.isSetAside == true)
        #expect(partition.unranked.first { $0.work.id == 4 }?.score == nil)
    }

    @Test func sectionSplitOrderToggleInvertsRankedOnly() {
        let works = [
            work(1, kudos: 100, hits: 1_000),
            work(2, kudos: 300, hits: 1_000),
            work(3, kudos: 5_000, hits: 100)  // unusual
        ]
        let lowest = LoadedWorksRanker.partition(
            works,
            by: settings(.kudosPerHitAdjusted, order: .lowestFirst),
            now: now
        )
        // Ranked in lowest-first order: 1 (10%), then 2 (30%)
        #expect(lowest.ranked.map(\.work.id) == [1, 2])
        #expect(lowest.ranked[0].rankPosition == 1)
        #expect(lowest.ranked[1].rankPosition == 2)

        // Unranked remains 3
        #expect(lowest.unranked.map(\.work.id) == [3])
    }

    @Test func sectionSplitWhenSetAsideDisabledKeepsUnusualInRanked() {
        let works = [
            work(1, kudos: 100, hits: 1_000),
            work(2, kudos: 2_000, hits: 500) // more kudos than hits
        ]
        let withSetAside = LoadedWorksRanker.partition(
            works,
            by: settings(.kudosPerHitAdjusted, setAside: true),
            now: now
        )
        #expect(withSetAside.ranked.map(\.work.id) == [1])
        #expect(withSetAside.unranked.map(\.work.id) == [2])

        let withoutSetAside = LoadedWorksRanker.partition(
            works,
            by: settings(.kudosPerHitAdjusted, setAside: false),
            now: now
        )
        #expect(withoutSetAside.ranked.map(\.work.id) == [2, 1])
        #expect(withoutSetAside.unranked.isEmpty)
    }

    @Test func rankMethodMatchesPartitionConcatenation() {
        let works = [
            work(1, kudos: 100, hits: 1_000),
            work(2, kudos: 300, hits: 1_000),
            work(3, kudos: 10_000, hits: 500)
        ]
        let s = settings(.kudosPerHitAdjusted)
        let partition = LoadedWorksRanker.partition(works, by: s, now: now)
        let ranked = LoadedWorksRanker.rank(works, by: s, now: now)

        #expect(ranked.map(\.work.id) == (partition.ranked + partition.unranked).map(\.work.id))
    }

    // MARK: - T-520 review fixes

    @Test func kudos312IsSteadyAndKudos48IsEarly() {
        #expect(QualitySignalTones.confidenceWord(forKudos: 312) == "Steady")
        #expect(QualitySignalTones.confidenceWord(forKudos: 48) == "Early")
        // The cut-offs themselves: 49/50 and 199/200.
        #expect(QualitySignalTones.confidenceWord(forKudos: 49) == "Early")
        #expect(QualitySignalTones.confidenceWord(forKudos: 50) == "Settling")
        #expect(QualitySignalTones.confidenceWord(forKudos: 199) == "Settling")
        #expect(QualitySignalTones.confidenceWord(forKudos: 200) == "Steady")

        let steady = QualitySignalTones.chooseTone(
            rank: .kudosPerHitAdjusted,
            shown: 1.8,
            figures: LoadedWorksRanker.Figures(work(1, kudos: 312, hits: 2_900), now: now),
            setAside: false
        )
        #expect(steady?.note?.hasPrefix("Steady") == true)

        let early = QualitySignalTones.chooseTone(
            rank: .kudosPerHitAdjusted,
            shown: 1.8,
            figures: LoadedWorksRanker.Figures(work(2, kudos: 48, hits: 300, bookmarks: 0), now: now),
            setAside: false
        )
        #expect(early?.note?.hasPrefix("Early") == true)
    }

    /// (a) `kudos ≥ hits + 20` with `hits ≥ 20`. One under either cut is not unusual,
    /// and a work set aside for bookmarks does not get the hits note inside the margin.
    @Test func unusualStatsNeedAMarginOf20() {
        let atMargin = LoadedWorksRanker.Figures(work(1, kudos: 40, hits: 20, bookmarks: 20), now: now)
        let oneKudoUnder = LoadedWorksRanker.Figures(work(2, kudos: 39, hits: 20, bookmarks: 20), now: now)
        let hitsUnder = LoadedWorksRanker.Figures(work(3, kudos: 100, hits: 19, bookmarks: 50), now: now)
        #expect(LoadedWorksRanker.isUnusual(atMargin))
        #expect(!LoadedWorksRanker.isUnusual(oneKudoUnder))
        #expect(!LoadedWorksRanker.isUnusual(hitsUnder))

        let note = QualitySignalTones.chooseTone(
            rank: .kudosPerHitAdjusted, shown: nil, figures: atMargin, setAside: true
        )
        #expect(note?.note == "More kudos than hits")

        let insideTheMargin = LoadedWorksRanker.Figures(
            work(4, kudos: 1_000, hits: 990, bookmarks: 1), now: now
        )
        #expect(LoadedWorksRanker.isUnusual(insideTheMargin))
        let bookmarkNote = QualitySignalTones.chooseTone(
            rank: .kudosPerHitAdjusted, shown: nil, figures: insideTheMargin, setAside: true
        )
        #expect(bookmarkNote?.note == "Thousands of kudos and almost no bookmarks")
    }

    /// (b) Words under 1,000 use 1,000 as the denominator. 999 used to score just over 10.
    @Test func kudosPerThousandWordsFloorsTheDenominatorAt1000() {
        let justUnder = LoadedWorksRanker.Figures(work(1, kudos: 10, hits: 200, words: 999), now: now)
        let atFloor = LoadedWorksRanker.Figures(work(2, kudos: 10, hits: 200, words: 1_000), now: now)
        let longer = LoadedWorksRanker.Figures(work(3, kudos: 10, hits: 200, words: 2_000), now: now)
        #expect(isClose(LoadedWorksRanker.rawFigure(.kudosPerThousandWords, justUnder), 10))
        #expect(isClose(LoadedWorksRanker.rawFigure(.kudosPerThousandWords, atFloor), 10))
        #expect(isClose(LoadedWorksRanker.rawFigure(.kudosPerThousandWords, longer), 5))
        #expect(LoadedWorksRank.kudosPerThousandWords.subtitle.contains("favours short works"))
    }

    /// (c) The same gain of 20 on an earlier count below 20 ties the count at 20,
    /// and both outrank a larger absolute gain. The line says how many were seen before.
    @Test func momentumRanksGrowthAgainstEarlierKudosFlooredAt20() {
        let works = [
            work(1, kudos: 30, hits: 400),
            work(2, kudos: 40, hits: 400),
            work(3, kudos: 140, hits: 400),
        ]
        let previous = [1: 10, 2: 20, 3: 100]
        let ranked = LoadedWorksRanker.rank(
            works, by: settings(.momentum), previousKudos: previous, now: now
        )
        #expect(ranked.map(\.work.id) == [1, 2, 3])
        #expect(isClose(ranked[0].score, 1))
        #expect(isClose(ranked[1].score, 1))
        #expect(isClose(ranked[2].score, 0.4))
        #expect(ranked[0].signal == "+20 kudos since you last saw it")

        // Work 8 was seen before, but its current kudos are unknown, so momentum
        // cannot rank it. Counting every previousKudos key would say 2 of 40.
        var page = (1 ... 40).map { work($0, kudos: 10, hits: 200) }
        page[7] = work(8, kudos: nil, hits: nil, words: nil)
        let partition = LoadedWorksRanker.partition(
            page, by: settings(.momentum), previousKudos: [7: 10, 8: 4], now: now
        )
        #expect(partition.seenBeforeLine == "1 of 40 seen before")
    }

    /// Int.max hits, and Int.max kudos against a negative earlier count, used to
    /// trap in the addition and the subtraction. The gain line must not turn the
    /// Double back into an Int either.
    @Test func extremeCountsDoNotTrap() {
        #expect(!LoadedWorksRanker.kudosExceedHits(kudos: Int.max, hits: Int.max))
        #expect(LoadedWorksRanker.kudosExceedHits(kudos: Int.max, hits: 20))
        #expect(LoadedWorksRanker.momentumGain(kudos: Int.max, previous: -1) == Double(Int.max))

        let huge = Double(Int.max)
        let line = LoadedWorksRanker.signal(.momentum, shown: huge, setAside: false, hasPrevious: true)
        #expect(line?.hasPrefix("+") == true)
        let tone = QualitySignalTones.chooseTone(
            rank: .momentum,
            shown: huge,
            figures: LoadedWorksRanker.Figures(work(1, kudos: 1, hits: 100), now: now),
            setAside: false,
            hasPrevious: true
        )
        #expect(tone?.label.hasPrefix("+") == true)
        #expect(tone?.label != "No new kudos")
    }

    /// (d) Saves and comments per kudos shrink by kudos. Hits would keep
    /// (60 × 0.6 + 500 × 0.3) / 560.
    @Test func cautiousPerKudosSignalsWeighByKudos() {
        let works = [
            work(1, kudos: 50, hits: 60, comments: 30, bookmarks: 30),
            work(2, kudos: 1_000, hits: 20_000, comments: 400, bookmarks: 400),
            work(3, kudos: 500, hits: 10_000, comments: 100, bookmarks: 100),
            work(4, kudos: 500, hits: 10_000, comments: 50, bookmarks: 50),
        ]
        let expected = (50 * 0.6 + 500 * 0.3) / 550
        for rank in [LoadedWorksRank.savesPerKudos, .commentsPerKudos] {
            let ranked = LoadedWorksRanker.rank(works, by: settings(rank, cautious: true), now: now)
            let score = ranked.first { $0.work.id == 1 }?.score
            #expect(isClose(score, expected), "\(rank)")
        }

        // Kudos per hit still shrinks by the 60 hits. Weighing it by the 50 kudos
        // would move this score, so the evidence switch cannot be flattened.
        let own = 50.0 / 60.0
        let typical = 1_000.0 / 20_000.0
        let shrunkByHits = (60 * own + 500 * typical) / (60 + 500)
        let adjusted = LoadedWorksRanker.rank(
            works, by: settings(.kudosPerHitAdjusted, cautious: true), now: now
        )
        let adjustedScore = adjusted.first { $0.work.id == 1 }?.score
        #expect(isClose(adjustedScore, shrunkByHits / typical))
    }

    private func isClose(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 1e-9
    }
}
