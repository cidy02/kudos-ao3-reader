import Foundation
import Testing
@testable import Kudos

/// T-473's computed sorts: rankings over the works already loaded, from the figures
/// on each blurb. Every one must survive a zero denominator, keep AO3's order for
/// ties, and push set-aside and unrankable works to the end.
struct LoadedWorksRankingTests {
    private var now: Date { WorkStat.date(from: "29 Oct 2026") ?? Date(timeIntervalSince1970: 0) }

    private func work(
        _ id: Int,
        kudos: Int?,
        hits: Int?,
        comments: Int? = 0,
        bookmarks: Int? = 0,
        words: Int? = 5_000,
        updated: String = "01 Oct 2026"
    ) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id, title: "Work \(id)", authors: [], authorIdentities: [],
            fandoms: [], rating: "",
            warnings: [], categories: [], isComplete: nil, dateUpdated: updated,
            tags: [], summary: "", language: "", words: words, chapters: "1/1",
            comments: comments, kudos: kudos, bookmarks: bookmarks, hits: hits,
            seriesTitle: nil, seriesURL: nil, seriesPosition: nil
        )
    }

    private func settings(
        _ rank: LoadedWorksRank,
        order: LoadedWorksRankOrder = .highestFirst,
        cautious: Bool = false,
        setAside: Bool = true
    ) -> LoadedWorksRanking {
        var settings = LoadedWorksRanking()
        settings.rank = rank
        settings.order = order
        settings.ranksCautiously = cautious
        settings.setsAsideUnusual = setAside
        return settings
    }

    private func ids(_ ranked: [RankedWork]) -> [Int] { ranked.map(\.work.id) }

    private func isClose(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 1e-9
    }

    /// Query items as `name → [values]`, as `SearchURLTests` reads them.
    private func params(_ filters: AO3SearchFilters) throws -> [String: [String]] {
        let url = try #require(AO3Client.searchURL(filters: filters, page: 1))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return (components.queryItems ?? []).reduce(into: [:]) { result, item in
            result[item.name, default: []].append(item.value ?? "")
        }
    }

    // MARK: - AO3's order

    @Test func ao3OrderIsUntouchedAndSaysNothing() {
        let works = [work(1, kudos: 5, hits: 100), work(2, kudos: 90, hits: 100), work(3, kudos: 0, hits: 0)]
        let ranked = LoadedWorksRanker.rank(works, by: LoadedWorksRanking(), now: now)
        #expect(ids(ranked) == [1, 2, 3])
        #expect(ranked.allSatisfy { $0.signal == nil && $0.score == nil })
    }

    // MARK: - Zero denominators

    @Test func zeroHitsIsUnrankedNotDividedBy() {
        let works = [work(1, kudos: 0, hits: 0), work(2, kudos: 10, hits: 100), work(3, kudos: 30, hits: 100)]
        for cautious in [false, true] {
            let ranked = LoadedWorksRanker.rank(works, by: settings(.kudosPerHitAdjusted, cautious: cautious), now: now)
            #expect(ids(ranked) == [3, 2, 1], "cautious: \(cautious)")
            #expect(ranked.last?.score == nil)
            #expect(ranked.last?.signal == "Not enough figures to rank")
            #expect(ranked.compactMap(\.score).allSatisfy { $0.isFinite })
        }
        // Kudos with no hits at all is "more kudos than hits": set aside, or, with
        // that off, still unranked rather than infinite.
        let odd = [work(1, kudos: 4, hits: 0), work(2, kudos: 10, hits: 100)]
        #expect(LoadedWorksRanker.rank(odd, by: settings(.kudosPerHitAdjusted), now: now).last?.isSetAside == true)
        let kept = LoadedWorksRanker.rank(odd, by: settings(.kudosPerHitAdjusted, setAside: false), now: now)
        #expect(ids(kept) == [2, 1])
        #expect(kept.last?.score == nil)
    }

    @Test func zeroKudosIsUnrankedForThePerKudosSorts() {
        let works = [
            work(1, kudos: 0, hits: 400, comments: 3, bookmarks: 0),
            work(2, kudos: 100, hits: 4_000, comments: 5, bookmarks: 10),
            work(3, kudos: 100, hits: 4_000, comments: 20, bookmarks: 40),
        ]
        for rank in [LoadedWorksRank.savesPerKudos, .commentsPerKudos] {
            let ranked = LoadedWorksRanker.rank(works, by: settings(rank, cautious: true), now: now)
            #expect(ids(ranked) == [3, 2, 1], "\(rank)")
            #expect(ranked.last?.score == nil)
        }
        // Every loaded work at zero kudos: the median is zero, and the adjusted
        // rank has nothing to compare with — AO3's order, no crash.
        let none = [work(1, kudos: 0, hits: 400), work(2, kudos: 0, hits: 900)]
        let ranked = LoadedWorksRanker.rank(none, by: settings(.kudosPerHitAdjusted, cautious: true), now: now)
        #expect(ids(ranked) == [1, 2])
        #expect(ranked.allSatisfy { $0.score == nil })
    }

    @Test func wordsAndMissingFiguresNeverDivideByZero() {
        let figures = LoadedWorksRanker.Figures(work(1, kudos: 100, hits: 1_000, words: 2_000), now: now)
        #expect(isClose(LoadedWorksRanker.rawFigure(.kudosPerThousandWords, figures), 50))
        let noWords = LoadedWorksRanker.Figures(work(2, kudos: 100, hits: 1_000, words: 0), now: now)
        #expect(LoadedWorksRanker.rawFigure(.kudosPerThousandWords, noWords) == nil)
        // A sparse row (no word count) has unknown figures, not zeros.
        let sparse = LoadedWorksRanker.Figures(work(3, kudos: nil, hits: nil, words: nil), now: now)
        #expect(sparse.kudos == nil && sparse.hits == nil)
        #expect(LoadedWorksRanker.rawFigure(.kudosPerHitAdjusted, sparse) == nil)
        // On a full blurb a missing count is AO3 leaving out a zero.
        let full = LoadedWorksRanker.Figures(work(4, kudos: 10, hits: 100, bookmarks: nil), now: now)
        #expect(full.bookmarks == 0)
    }

    // MARK: - The minimum-hits cut-off and Ways to Find (AO3 parameters)

    @Test func choosingARankSeedsTheCutOffAsAnAO3Parameter() throws {
        var ranking = LoadedWorksRanking()
        var filters = AO3SearchFilters(query: "lighthouse")
        filters.sort = .kudos
        filters.sortDirection = .ascending
        ranking.select(.savesPerKudos, filters: &filters)
        #expect(ranking.rank == .savesPerKudos)
        #expect(filters.hitsFrom == LoadedWorksRanking.defaultMinimumHits)
        // The Order control now ranks; AO3 loads in the column's own direction.
        #expect(filters.sortDirection == .descending)
        let values = try params(filters)
        #expect(values["work_search[hits]"] == ["> 500"])

        // Moving between computed ranks does not seed it again.
        filters.hitsFrom = ""
        ranking.select(.momentum, filters: &filters)
        #expect(filters.hitsFrom.isEmpty)
    }

    @Test func aHitsRangeAlreadySetIsLeftAlone() {
        var ranking = LoadedWorksRanking()
        var filters = AO3SearchFilters()
        filters.hitsTo = "2000"
        ranking.select(.kudosPerHitAdjusted, filters: &filters)
        #expect(filters.hitsFrom.isEmpty)
        #expect(filters.hitsTo == "2000")
    }

    @Test func waysToFindAreAO3QueryParameters() throws {
        var filters = AO3SearchFilters(query: "lighthouse")
        SearchWaysToFind.toggle(.hiddenGems, in: &filters, now: now)
        var values = try params(filters)
        #expect(values["work_search[hits]"] == ["300-5000"])
        #expect(values["work_search[sort_column]"] == ["kudos_count"])
        #expect(values["work_search[sort_direction]"] == ["desc"])
        #expect(SearchWaysToFind.applied(in: filters) == .hiddenGems)

        // Switching clears the one that was on.
        SearchWaysToFind.toggle(.newAndLoved, in: &filters, now: now)
        values = try params(filters)
        #expect(values["work_search[hits]"] == nil)
        #expect(values["work_search[revised_at]"] == ["< 6 months ago"])
        #expect(values["work_search[sort_column]"] == ["kudos_count"])

        SearchWaysToFind.toggle(.readerFavourites, in: &filters, now: now)
        values = try params(filters)
        #expect(values["work_search[hits]"] == ["> 1000"])
        #expect(values["work_search[revised_at]"] == nil)

        SearchWaysToFind.toggle(.activeWIPs, in: &filters, now: now)
        values = try params(filters)
        #expect(values["work_search[complete]"] == ["F"])
        #expect(values["work_search[sort_column]"] == ["revised_at"])
        let from = try #require(filters.dateFrom)
        #expect(Calendar.current.dateComponents([.day], from: from, to: now).day == SearchWaysToFind.activeWindowDays)
        #expect(values["work_search[date_from]"]?.count == 1)

        // Tapping the one that is on turns it off and puts the sort back.
        SearchWaysToFind.toggle(.activeWIPs, in: &filters, now: now)
        values = try params(filters)
        #expect(values["work_search[complete]"] == nil)
        #expect(values["work_search[date_from]"] == nil)
        #expect(values["work_search[sort_column]"] == nil)
        #expect(SearchWaysToFind.applied(in: filters) == nil)
    }

    /// Two on at once (a reader can set both by hand): switching clears both.
    @Test func switchingClearsEveryWayToFindThatWasOn() {
        var filters = AO3SearchFilters()
        filters.sort = .kudos
        filters.updated = .sixMonths
        filters.hitsFrom = "300"
        filters.hitsTo = "5000"
        #expect(SearchWaysToFind.newAndLoved.isApplied(in: filters))
        #expect(SearchWaysToFind.hiddenGems.isApplied(in: filters))
        SearchWaysToFind.toggle(.readerFavourites, in: &filters, now: now)
        #expect(filters.updated == .any)
        #expect(filters.hitsFrom == "1000" && filters.hitsTo.isEmpty)
        #expect(SearchWaysToFind.applied(in: filters) == .readerFavourites)
    }

    @Test func aTagListingFallsBackToDateUpdatedNotBestMatch() {
        var filters = AO3SearchFilters()
        filters.sort = .dateUpdated
        SearchWaysToFind.toggle(.hiddenGems, in: &filters, defaultSort: .dateUpdated, now: now)
        SearchWaysToFind.toggle(.hiddenGems, in: &filters, defaultSort: .dateUpdated, now: now)
        #expect(filters.sort == .dateUpdated)
        #expect(filters.hitsFrom.isEmpty && filters.hitsTo.isEmpty)
    }

    @Test func cutOffMenuShowsAValueSetElsewhere() {
        #expect(SearchWaysToFind.minimumHitsOptions(including: "500") == ["", "100", "300", "500", "1000", "5000"])
        #expect(SearchWaysToFind.minimumHitsOptions(including: "250")
            == ["", "100", "250", "300", "500", "1000", "5000"])
        #expect(SearchWaysToFind.minimumHitsTitle("") == "Off")
    }

    @Test func sortByRowNamesWhatIsInEffect() {
        var filters = AO3SearchFilters()
        var ranking = LoadedWorksRanking()
        #expect(SearchSortBySummary.value(filters: filters, ranking: ranking) == "Best Match")
        SearchWaysToFind.toggle(.hiddenGems, in: &filters, now: now)
        #expect(SearchSortBySummary.value(filters: filters, ranking: ranking) == "Hidden Gems")
        ranking.rank = .kudosPerHitAdjusted
        #expect(SearchSortBySummary.value(filters: filters, ranking: ranking) == "Kudos per Hit, Adjusted")
        #expect(SearchSortBySummary.value(filters: filters, ranking: nil) == "Hidden Gems")
    }

    // MARK: - Kudos per Hit, Adjusted

    /// Each work is measured against the median of its own length × age group, so a
    /// long old work is not buried under short new ones for having more hits per reader.
    @Test func adjustedComparesEachWorkWithItsOwnGroup() {
        let works = [
            work(1, kudos: 50, hits: 1_000, words: 2_000, updated: "01 Oct 2026"),
            work(2, kudos: 100, hits: 1_000, words: 2_000, updated: "02 Oct 2026"),
            work(3, kudos: 200, hits: 1_000, words: 2_000, updated: "03 Oct 2026"),
            work(4, kudos: 100, hits: 10_000, words: 100_000, updated: "01 Jan 2018"),
            work(5, kudos: 200, hits: 10_000, words: 100_000, updated: "01 Feb 2018"),
            work(6, kudos: 300, hits: 10_000, words: 100_000, updated: "01 Mar 2018"),
        ]
        let ranked = LoadedWorksRanker.rank(works, by: settings(.kudosPerHitAdjusted), now: now)
        #expect(Array(ids(ranked).prefix(2)) == [3, 6])
        let scores = Dictionary(uniqueKeysWithValues: ranked.map { ($0.work.id, $0.score) })
        #expect(isClose(scores[3] ?? nil, 2.0))
        #expect(isClose(scores[6] ?? nil, 1.5))
        #expect(isClose(scores[5] ?? nil, 1.0))
        #expect(isClose(scores[4] ?? nil, 0.5))
        // Raw kudos per hit would have put work 6 (3%) below work 1 (5%).
        let six = ranked.firstIndex { $0.work.id == 6 } ?? 0
        let one = ranked.firstIndex { $0.work.id == 1 } ?? 0
        #expect(six < one)
    }

    @Test func aGroupTooSmallFallsBackToEveryLoadedWork() {
        let works = [
            work(1, kudos: 100, hits: 1_000, words: 2_000),
            work(2, kudos: 300, hits: 1_000, words: 100_000, updated: "01 Jan 2015"),
        ]
        let ranked = LoadedWorksRanker.rank(works, by: settings(.kudosPerHitAdjusted), now: now)
        // Overall median of 0.1 and 0.3 is 0.2.
        #expect(isClose(ranked.first?.score, 1.5))
        #expect(ids(ranked) == [2, 1])
    }

    @Test func groupsAreLengthAndAge() {
        #expect(LoadedWorksRanker.lengthGroup(words: 9_999) == 0)
        #expect(LoadedWorksRanker.lengthGroup(words: 10_000) == 1)
        #expect(LoadedWorksRanker.lengthGroup(words: 50_000) == 2)
        #expect(LoadedWorksRanker.lengthGroup(words: nil) == nil)
        let monthAgo = now.addingTimeInterval(-30 * 86_400)
        let twoYearsAgo = now.addingTimeInterval(-2 * 365 * 86_400)
        let fiveYearsAgo = now.addingTimeInterval(-5 * 365 * 86_400)
        #expect(LoadedWorksRanker.ageGroup(updated: monthAgo, now: now) == 0)
        #expect(LoadedWorksRanker.ageGroup(updated: twoYearsAgo, now: now) == 1)
        #expect(LoadedWorksRanker.ageGroup(updated: fiveYearsAgo, now: now) == 2)
        #expect(LoadedWorksRanker.ageGroup(updated: nil, now: now) == nil)
    }

    // MARK: - Rank cautiously

    @Test func cautiousShrinksLowHitWorksTowardTheMedian() {
        let works = [
            work(1, kudos: 50, hits: 60, bookmarks: 30),          // 0.6 from 60 hits
            work(2, kudos: 1_000, hits: 20_000, bookmarks: 400),  // 0.4 from 20,000 hits
            work(3, kudos: 500, hits: 10_000, bookmarks: 100),    // 0.2
            work(4, kudos: 500, hits: 10_000, bookmarks: 50),     // 0.1
        ]
        let plain = LoadedWorksRanker.rank(works, by: settings(.savesPerKudos), now: now)
        #expect(ids(plain) == [1, 2, 3, 4])
        let cautious = LoadedWorksRanker.rank(works, by: settings(.savesPerKudos, cautious: true), now: now)
        #expect(ids(cautious) == [2, 1, 3, 4])
        // Median 0.3; work 1 keeps 60 of 560 parts of its own figure.
        let first = cautious.first { $0.work.id == 1 }
        #expect(isClose(first?.score, (60 * 0.6 + 500 * 0.3) / 560))
        // The signal states the work's own figure, not the shrunk one.
        #expect(first?.signal?.hasSuffix("saves per 100 kudos") == true)
        #expect(first?.signal?.hasPrefix("60") == true)
    }

    @Test func shrinkWeighsHitsAgainstThePseudoCount() {
        #expect(isClose(LoadedWorksRanker.shrink(0.6, toward: 0.3, hits: 0), 0.3))
        #expect(isClose(LoadedWorksRanker.shrink(0.6, toward: 0.3, hits: nil), 0.3))
        #expect(isClose(LoadedWorksRanker.shrink(0.6, toward: 0.3, hits: 500), 0.45))
        #expect(LoadedWorksRanker.shrink(0.6, toward: 0.3, hits: 1_000_000) > 0.599)
    }

    // MARK: - Set aside unusual stats

    @Test func unusualWorksGoToTheEndInAO3Order() {
        let works = [
            work(1, kudos: 200, hits: 100, bookmarks: 10),          // more kudos than hits
            work(2, kudos: 100, hits: 1_000, bookmarks: 20),
            work(3, kudos: 1_500, hits: 30_000, bookmarks: 5),      // thousands, almost no bookmarks
            work(4, kudos: 50, hits: 1_000, bookmarks: 5),
        ]
        let ranked = LoadedWorksRanker.rank(works, by: settings(.kudosPerHitAdjusted), now: now)
        #expect(ids(ranked) == [2, 4, 1, 3])
        #expect(ranked.suffix(2).allSatisfy { $0.isSetAside })
        #expect(ranked.last?.signal == "Unusual stats, set aside")
        // Left out of the median too: 0.1 against the median of 0.1 and 0.05.
        #expect(isClose(ranked.first?.score, 0.1 / 0.075))

        let off = LoadedWorksRanker.rank(works, by: settings(.kudosPerHitAdjusted, setAside: false), now: now)
        #expect(off.first?.work.id == 1)
        #expect(!off.contains { $0.isSetAside })
    }

    @Test func almostNoBookmarksMeansUnderOnePerHundredKudos() {
        let edge = LoadedWorksRanker.Figures(work(1, kudos: 1_000, hits: 9_000, bookmarks: 9), now: now)
        let enough = LoadedWorksRanker.Figures(work(2, kudos: 1_000, hits: 9_000, bookmarks: 10), now: now)
        let small = LoadedWorksRanker.Figures(work(3, kudos: 999, hits: 9_000, bookmarks: 0), now: now)
        #expect(LoadedWorksRanker.isUnusual(edge))
        #expect(!LoadedWorksRanker.isUnusual(enough))
        #expect(!LoadedWorksRanker.isUnusual(small))
    }

    // MARK: - Order and stability

    @Test func tiesKeepAO3OrderInBothDirections() {
        let works = [
            work(1, kudos: 10, hits: 100), work(2, kudos: 20, hits: 100),
            work(3, kudos: 10, hits: 100), work(4, kudos: 0, hits: 0), work(5, kudos: 10, hits: 100),
        ]
        let highest = LoadedWorksRanker.rank(works, by: settings(.kudosPerHitAdjusted), now: now)
        #expect(ids(highest) == [2, 1, 3, 5, 4])
        let lowest = LoadedWorksRanker.rank(works, by: settings(.kudosPerHitAdjusted, order: .lowestFirst), now: now)
        // Lowest first reverses the figures, not the ties, and the unranked work
        // still comes after every ranked one.
        #expect(ids(lowest) == [1, 3, 5, 2, 4])
        // Ranking again gives the same answer.
        #expect(ids(LoadedWorksRanker.rank(works, by: settings(.kudosPerHitAdjusted), now: now)) == ids(highest))
    }

    @Test func reRanksWhateverIsLoaded() {
        let pageOne = [work(1, kudos: 10, hits: 100), work(2, kudos: 30, hits: 100)]
        let pageTwo = [work(3, kudos: 50, hits: 100)]
        #expect(ids(LoadedWorksRanker.rank(pageOne, by: settings(.kudosPerHitAdjusted), now: now)) == [2, 1])
        #expect(ids(LoadedWorksRanker.rank(pageOne + pageTwo, by: settings(.kudosPerHitAdjusted), now: now))
            == [3, 2, 1])
    }

    @Test func medianOfEvenAndOddCounts() {
        #expect(LoadedWorksRanker.median([]) == nil)
        #expect(LoadedWorksRanker.median([3, 1, 2]) == 2)
        #expect(LoadedWorksRanker.median([4, 1, 3, 2]) == 2.5)
    }

    // MARK: - Momentum

    @Test func momentumCountsKudosSinceTheLastSighting() {
        let firstLook = [
            work(1, kudos: 100, hits: 1_000), work(2, kudos: 50, hits: 1_000), work(3, kudos: 80, hits: 900),
        ]
        var session = KudosSightings()
        let stored = session.record(firstLook, in: [:], now: now)
        #expect(session.previousKudos.isEmpty)
        let fresh = LoadedWorksRanker.rank(
            firstLook, by: settings(.momentum), previousKudos: session.previousKudos, now: now
        )
        #expect(ids(fresh) == [1, 2, 3])
        #expect(fresh.allSatisfy { $0.score == nil && $0.signal == "First time in your results" })

        // A later session: work 2 gained 40, work 1 gained 5, work 3 lost 2.
        let later = [work(1, kudos: 105, hits: 1_100), work(2, kudos: 90, hits: 1_200), work(3, kudos: 78, hits: 950)]
        var next = KudosSightings()
        let updated = next.record(later, in: stored, now: now.addingTimeInterval(86_400))
        #expect(next.previousKudos == [1: 100, 2: 50, 3: 80])
        #expect(updated[2]?.kudos == 90)
        let ranked = LoadedWorksRanker.rank(later, by: settings(.momentum), previousKudos: next.previousKudos, now: now)
        #expect(ids(ranked) == [2, 1, 3])
        #expect(ranked.last?.score == 0)
        #expect(ranked.last?.signal == "No new kudos since you last saw it")
        #expect(ranked.first?.signal?.hasPrefix("+") == true)

        // Seeing the same works again this session keeps the baseline it started with.
        _ = next.record([work(2, kudos: 120, hits: 1_300)], in: updated, now: now.addingTimeInterval(90_000))
        #expect(next.previousKudos[2] == 50)
    }

    @Test func momentumSkipsWorksWithUnknownKudos() {
        var session = KudosSightings()
        let stored = session.record([work(1, kudos: nil, hits: nil, words: nil)], in: [:], now: now)
        #expect(stored.isEmpty)
    }

    @Test func momentumRecordRoundTripsAndStaysBounded() throws {
        let suite = "LoadedWorksRankingTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let entries = [7: SeenKudos(kudos: 12, seenAt: Date(timeIntervalSince1970: 100))]
        LastSeenKudosStore.save(entries, to: defaults)
        #expect(LastSeenKudosStore.load(from: defaults) == entries)

        let many = Dictionary(uniqueKeysWithValues: (0 ... LastSeenKudosStore.entryLimit).map {
            ($0, SeenKudos(kudos: $0, seenAt: Date(timeIntervalSince1970: TimeInterval($0))))
        })
        let bounded = LastSeenKudosStore.bound(many)
        #expect(bounded.count == LastSeenKudosStore.entryLimit)
        // The one seen longest ago is the one dropped.
        #expect(bounded[0] == nil)
        #expect(bounded[LastSeenKudosStore.entryLimit] != nil)
    }
}
