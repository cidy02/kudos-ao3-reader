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
}
