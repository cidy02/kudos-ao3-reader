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

    // MARK: - Held data (T-522)

    /// Readers-only uses opened comments. An unopened thread leaves the blurb
    /// ratio alone and does not invent the author's share.
    @Test func readersOnlyRatioNeedsOpenedComments() {
        let figures = LoadedWorksRanker.Figures(
            work(1, kudos: 100, hits: 1_000, comments: 40),
            now: now
        )
        let blurb = LoadedWorksRanker.rawFigure(.commentsPerKudos, figures)
        #expect(isClose(blurb, 0.4))
        #expect(LoadedWorksRanker.readersOnlyCommentsPerKudos(
            openedComments: nil, kudos: 100,
            workAuthors: ["Pen Name"], workAuthorUsernames: ["creator"]
        ) == nil)
        #expect(LoadedWorksRanker.rawFigure(.commentsPerKudos, figures) == blurb)

        #expect(LoadedWorksRanker.readersOnlyCommentsPerKudos(
            openedComments: [], kudos: 100,
            workAuthors: ["Pen Name"], workAuthorUsernames: ["creator"]
        ) == 0)

        let opened = openedComments()
        let readersOnly = LoadedWorksRanker.readersOnlyCommentsPerKudos(
            openedComments: opened, kudos: 100,
            workAuthors: ["Pen Name"], workAuthorUsernames: ["creator"],
            currentUsername: "creator"
        )
        // Three reader comments held. Not the blurb's 40, and not that 40 scaled
        // by the reader share of the opened thread.
        #expect(isClose(readersOnly, 0.03))
        #expect(!isClose(readersOnly, 0.4))
        #expect(!isClose(readersOnly, 40.0 * (3.0 / 7.0) / 100.0))

        let viewer = AO3Comment(
            id: 70, author: "Me Pseud", isGuest: false, userPath: "/users/viewer/pseuds/viewer"
        )
        #expect(isClose(LoadedWorksRanker.readersOnlyCommentsPerKudos(
            openedComments: [viewer], kudos: 100,
            workAuthors: ["Pen Name"], workAuthorUsernames: ["creator"],
            currentUsername: "viewer"
        ), 0.01))

        // The viewer's own comment hides Author. Without the work's accounts,
        // that comment cannot be classified, so the rate stays unknown.
        #expect(LoadedWorksRanker.readersOnlyCommentsPerKudos(
            openedComments: [viewer], kudos: 100,
            workAuthors: ["Pen Name"], workAuthorUsernames: [],
            currentUsername: "viewer"
        ) == nil)
    }

    @Test func chapterCadenceUsesTheLastFiveGaps() {
        #expect(LoadedWorksRanker.chapterCadenceDays(publishedOn: [posted(0), posted(100)]) == nil)
        #expect(LoadedWorksRanker.chapterCadenceDays(publishedOn: [posted(0), posted(3), posted(6)]) == nil)
        // Span of 7 days is enough: gaps of 3 and 4, median 3.5. The lifetime mean is also 3.5 here.
        #expect(LoadedWorksRanker.chapterCadenceDays(publishedOn: [posted(0), posted(3), posted(7)]) == 3.5)

        // Six chapters, five gaps 10, 10, 10, 10, 60. Median 10; span ÷ (chapters − 1) is 20.
        let six = [0, 10, 20, 30, 40, 100].map { posted($0) as Date? }
        #expect(LoadedWorksRanker.chapterCadenceDays(publishedOn: six) == 10)

        // Seven chapters. The oldest gap is 100; the last five are 1, 2, 3, 4, 100, median 3.
        // All six gaps median to 3.5, and the lifetime mean is 35.
        let seven = [0, 100, 101, 103, 106, 110, 210].map { posted($0) as Date? }
        #expect(LoadedWorksRanker.chapterCadenceDays(publishedOn: seven) == 3)

        var hole = six
        hole[2] = nil
        #expect(LoadedWorksRanker.chapterCadenceDays(publishedOn: hole) == nil)
        var unparsed = AO3ChapterRef(id: 1, position: 2, title: "Two")
        unparsed.dateText = "not-a-date"
        let withUnparsed = [posted(0), unparsed.publishedOn, posted(20), posted(40)]
        #expect(LoadedWorksRanker.chapterCadenceDays(publishedOn: withUnparsed) == nil)
    }

    /// Quality-WIPs w4: interval 12 floored at 14, 31 days since, late 2.2.
    @Test func wipScheduleSaysSlowerThanUsual() {
        let slower = QualitySignalTones.wipScheduleWord(
            chaptersPosted: 6, chaptersExpected: nil, daysSinceUpdate: 31, cadenceDays: 12
        )
        #expect(slower == "Slower than usual")

        // 21 / max(14, 12) = 1.5. Dividing by the raw 12 would say slower.
        #expect(QualitySignalTones.wipScheduleWord(
            chaptersPosted: 6, chaptersExpected: nil, daysSinceUpdate: 21, cadenceDays: 12
        ) == "On schedule")
        #expect(QualitySignalTones.wipScheduleWord(
            chaptersPosted: 18, chaptersExpected: 20, daysSinceUpdate: 12, cadenceDays: 14
        ) == "Nearly done")
        #expect(QualitySignalTones.wipScheduleWord(
            chaptersPosted: 10, chaptersExpected: nil, daysSinceUpdate: 400, cadenceDays: 12
        ) == "Long pause")
        #expect(QualitySignalTones.wipScheduleWord(
            chaptersPosted: 1, chaptersExpected: nil, daysSinceUpdate: 400, cadenceDays: nil
        ) == "Just started")
        // No cadence, and no lifetime-mean substitute for it.
        #expect(QualitySignalTones.wipScheduleWord(
            chaptersPosted: 2, chaptersExpected: nil, daysSinceUpdate: 31, cadenceDays: nil
        ) == nil)
    }

    private func posted(_ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 1, day: 1 + day))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// Three reader comments, and creator replies by username, display name,
    /// anonymous creator, and the signed-in creator. A deleted parent keeps its
    /// reader reply. The cutoff's "12 more" is not a count of readers.
    private func openedComments() -> [AO3Comment] {
        let creatorReply = AO3Comment(
            id: 2, author: "Pen Name", isGuest: false, userPath: "/users/creator/pseuds/pen"
        )
        var reader = AO3Comment(
            id: 1, author: "Reader", isGuest: false, userPath: "/users/reader/pseuds/reader"
        )
        reader.replies = [creatorReply]
        var readerTwo = AO3Comment(
            id: 4, author: "Reader Two", isGuest: false, userPath: "/users/readertwo/pseuds/readertwo"
        )
        var deleted = AO3Comment(id: 3, author: "", isGuest: false)
        deleted.isDeleted = true
        deleted.replies = [readerTwo]
        var cutoff = AO3Comment(id: 5, author: "", isGuest: false)
        cutoff.isThreadCutoff = true
        cutoff.cutoffCount = 12
        let guest = AO3Comment(id: 6, author: "Pen Name", isGuest: true)
        let byName = AO3Comment(id: 7, author: "Pen Name", isGuest: false)
        var anonymous = AO3Comment(id: 8, author: "Anonymous", isGuest: false)
        anonymous.isAnonymousCreator = true
        let mine = AO3Comment(
            id: 9, author: "Other Pseud", isGuest: false, userPath: "/users/creator/pseuds/other"
        )
        return [reader, deleted, cutoff, guest, byName, anonymous, mine]
    }
}
