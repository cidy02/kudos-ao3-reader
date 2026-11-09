package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.network.ao3.search.AO3SearchUrlBuilder
import io.github.cidy02.kudos.network.ao3.search.AO3SortDirection
import io.github.cidy02.kudos.network.ao3.search.AO3Updated
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.search.KudosSightings
import io.github.cidy02.kudos.network.ao3.search.LastSeenKudosStore
import io.github.cidy02.kudos.network.ao3.search.LoadedWorksRank
import io.github.cidy02.kudos.network.ao3.search.LoadedWorksRankOrder
import io.github.cidy02.kudos.network.ao3.search.LoadedWorksRanker
import io.github.cidy02.kudos.network.ao3.search.LoadedWorksRanking
import io.github.cidy02.kudos.network.ao3.search.MemoryKudosStringStore
import io.github.cidy02.kudos.network.ao3.search.RankedWork
import io.github.cidy02.kudos.network.ao3.search.SearchSortBySummary
import io.github.cidy02.kudos.network.ao3.search.SearchWaysToFind
import io.github.cidy02.kudos.network.ao3.search.SeenKudos
import io.github.cidy02.kudos.works.CanonicalWork
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of iOS LoadedWorksRankingTests. Each test fails if its ranking rule is reverted. */
class LoadedWorksRankingTest {
    private val now: LocalDate = LocalDate.of(2026, 10, 29)

    private fun work(
        id: Long,
        kudos: Int?,
        hits: Int?,
        comments: Int? = 0,
        bookmarks: Int? = 0,
        words: Int? = 5_000,
        updated: String = "01 Oct 2026"
    ) = AO3WorkSummary(
        id = id,
        title = "Work $id",
        authors = emptyList(),
        fandoms = emptyList(),
        rating = "",
        warnings = emptyList(),
        categories = emptyList(),
        wordCount = words,
        chapters = "1/1",
        comments = comments,
        kudos = kudos,
        bookmarks = bookmarks,
        hits = hits,
        updatedDate = updated
    )

    private fun settings(
        rank: LoadedWorksRank,
        order: LoadedWorksRankOrder = LoadedWorksRankOrder.HIGHEST_FIRST,
        cautious: Boolean = false,
        setAside: Boolean = true
    ) = LoadedWorksRanking(
        rank = rank,
        order = order,
        ranksCautiously = cautious,
        setsAsideUnusual = setAside
    )

    private fun ids(ranked: List<RankedWork>) = ranked.map { it.work.id }

    private fun isClose(value: Double?, expected: Double): Boolean {
        value ?: return false
        return kotlin.math.abs(value - expected) < 1e-9
    }

    private fun params(filters: AO3SearchFilters): Map<String, List<String>> {
        val url = AO3SearchUrlBuilder().buildSearchUrl(filters, page = 1).toHttpUrl()
        return url.queryParameterNames.associateWith { url.queryParameterValues(it) }
    }

    @Test
    fun ao3OrderIsUntouchedAndSaysNothing() {
        val works = listOf(work(1, kudos = 5, hits = 100), work(2, kudos = 90, hits = 100), work(3, kudos = 0, hits = 0))
        val ranked = LoadedWorksRanker.rank(works, LoadedWorksRanking(), now = now)
        assertEquals(listOf(1L, 2L, 3L), ids(ranked))
        assertTrue(ranked.all { it.signal == null && it.score == null })
    }

    @Test
    fun zeroHitsIsUnrankedNotDividedBy() {
        val works = listOf(work(1, kudos = 0, hits = 0), work(2, kudos = 10, hits = 100), work(3, kudos = 30, hits = 100))
        for (cautious in listOf(false, true)) {
            val ranked = LoadedWorksRanker.rank(works, settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED, cautious = cautious), now = now)
            assertEquals("cautious: $cautious", listOf(3L, 2L, 1L), ids(ranked))
            assertNull(ranked.last().score)
            assertEquals("Not enough figures to rank", ranked.last().signal)
            assertTrue(ranked.mapNotNull { it.score }.all { it.isFinite() })
        }
        val odd = listOf(work(1, kudos = 4, hits = 0), work(2, kudos = 10, hits = 100))
        assertTrue(LoadedWorksRanker.rank(odd, settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED), now = now).last().isSetAside)
        val kept = LoadedWorksRanker.rank(odd, settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED, setAside = false), now = now)
        assertEquals(listOf(2L, 1L), ids(kept))
        assertNull(kept.last().score)
    }

    @Test
    fun zeroKudosIsUnrankedForThePerKudosSorts() {
        val works = listOf(
            work(1, kudos = 0, hits = 400, comments = 3, bookmarks = 0),
            work(2, kudos = 100, hits = 4_000, comments = 5, bookmarks = 10),
            work(3, kudos = 100, hits = 4_000, comments = 20, bookmarks = 40)
        )
        for (rank in listOf(LoadedWorksRank.SAVES_PER_KUDOS, LoadedWorksRank.COMMENTS_PER_KUDOS)) {
            val ranked = LoadedWorksRanker.rank(works, settings(rank, cautious = true), now = now)
            assertEquals(rank.name, listOf(3L, 2L, 1L), ids(ranked))
            assertNull(ranked.last().score)
        }
        val none = listOf(work(1, kudos = 0, hits = 400), work(2, kudos = 0, hits = 900))
        val ranked = LoadedWorksRanker.rank(none, settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED, cautious = true), now = now)
        assertEquals(listOf(1L, 2L), ids(ranked))
        assertTrue(ranked.all { it.score == null })
    }

    @Test
    fun wordsAndMissingFiguresNeverDivideByZero() {
        val figures = LoadedWorksRanker.Figures(work(1, kudos = 100, hits = 1_000, words = 2_000), now)
        assertTrue(isClose(LoadedWorksRanker.rawFigure(LoadedWorksRank.KUDOS_PER_THOUSAND_WORDS, figures), 50.0))
        val noWords = LoadedWorksRanker.Figures(work(2, kudos = 100, hits = 1_000, words = 0), now)
        assertNull(LoadedWorksRanker.rawFigure(LoadedWorksRank.KUDOS_PER_THOUSAND_WORDS, noWords))
        val sparse = LoadedWorksRanker.Figures(work(3, kudos = null, hits = null, words = null), now)
        assertNull(sparse.kudos)
        assertNull(sparse.hits)
        assertNull(LoadedWorksRanker.rawFigure(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED, sparse))
        val full = LoadedWorksRanker.Figures(work(4, kudos = 10, hits = 100, bookmarks = null), now)
        assertEquals(0, full.bookmarks!!)
    }

    @Test
    fun choosingARankSeedsTheCutOffAsAnAO3Parameter() {
        var filters = AO3SearchFilters(query = "lighthouse").copy(
            sort = AO3SearchSort.KUDOS,
            sortDirection = AO3SortDirection.ASCENDING
        )
        filters = filters.loadedWorksRanking.select(LoadedWorksRank.SAVES_PER_KUDOS, filters)
        assertEquals(LoadedWorksRank.SAVES_PER_KUDOS, filters.loadedWorksRanking.rank)
        assertEquals(LoadedWorksRanking.DEFAULT_MINIMUM_HITS, filters.hitsFrom)
        assertEquals(AO3SortDirection.DESCENDING, filters.sortDirection)
        assertEquals(listOf("> 500"), params(filters)["work_search[hits]"])

        filters = filters.copy(hitsFrom = "")
        filters = filters.loadedWorksRanking.select(LoadedWorksRank.MOMENTUM, filters)
        assertEquals("", filters.hitsFrom)
    }

    @Test
    fun aHitsRangeAlreadySetIsLeftAlone() {
        var filters = AO3SearchFilters(hitsTo = "2000")
        filters = filters.loadedWorksRanking.select(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED, filters)
        assertEquals("", filters.hitsFrom)
        assertEquals("2000", filters.hitsTo)
    }

    @Test
    fun waysToFindAreAO3QueryParameters() {
        var filters = AO3SearchFilters(query = "lighthouse")
        filters = SearchWaysToFind.toggle(SearchWaysToFind.HIDDEN_GEMS, filters, now = now)
        var values = params(filters)
        assertEquals(listOf("300-5000"), values["work_search[hits]"])
        assertEquals(listOf("kudos_count"), values["work_search[sort_column]"])
        assertEquals(listOf("desc"), values["work_search[sort_direction]"])
        assertEquals(SearchWaysToFind.HIDDEN_GEMS, SearchWaysToFind.applied(filters))

        filters = SearchWaysToFind.toggle(SearchWaysToFind.NEW_AND_LOVED, filters, now = now)
        values = params(filters)
        assertNull(values["work_search[hits]"])
        assertEquals(listOf("< 6 months ago"), values["work_search[revised_at]"])
        assertEquals(listOf("kudos_count"), values["work_search[sort_column]"])

        filters = SearchWaysToFind.toggle(SearchWaysToFind.READER_FAVOURITES, filters, now = now)
        values = params(filters)
        assertEquals(listOf("> 1000"), values["work_search[hits]"])
        assertNull(values["work_search[revised_at]"])

        filters = SearchWaysToFind.toggle(SearchWaysToFind.ACTIVE_WIPS, filters, now = now)
        values = params(filters)
        assertEquals(listOf("F"), values["work_search[complete]"])
        assertEquals(listOf("revised_at"), values["work_search[sort_column]"])
        val from = filters.dateFrom
        assertTrue(from != null && ChronoUnit.DAYS.between(from, now) == SearchWaysToFind.ACTIVE_WINDOW_DAYS.toLong())
        assertEquals(1, values["work_search[date_from]"]?.size)

        filters = SearchWaysToFind.toggle(SearchWaysToFind.ACTIVE_WIPS, filters, now = now)
        values = params(filters)
        assertNull(values["work_search[complete]"])
        assertNull(values["work_search[date_from]"])
        assertNull(values["work_search[sort_column]"])
        assertNull(SearchWaysToFind.applied(filters))
    }

    @Test
    fun switchingClearsEveryWayToFindThatWasOn() {
        var filters = AO3SearchFilters(
            sort = AO3SearchSort.KUDOS,
            updated = AO3Updated.SIX_MONTHS,
            hitsFrom = "300",
            hitsTo = "5000"
        )
        assertTrue(SearchWaysToFind.NEW_AND_LOVED.isApplied(filters))
        assertTrue(SearchWaysToFind.HIDDEN_GEMS.isApplied(filters))
        filters = SearchWaysToFind.toggle(SearchWaysToFind.READER_FAVOURITES, filters, now = now)
        assertEquals(AO3Updated.ANY, filters.updated)
        assertEquals("1000", filters.hitsFrom)
        assertEquals("", filters.hitsTo)
        assertEquals(SearchWaysToFind.READER_FAVOURITES, SearchWaysToFind.applied(filters))
    }

    @Test
    fun aTagListingFallsBackToDateUpdatedNotBestMatch() {
        var filters = AO3SearchFilters(sort = AO3SearchSort.DATE_UPDATED)
        filters = SearchWaysToFind.toggle(
            SearchWaysToFind.HIDDEN_GEMS, filters, defaultSort = AO3SearchSort.DATE_UPDATED, now = now
        )
        filters = SearchWaysToFind.toggle(
            SearchWaysToFind.HIDDEN_GEMS, filters, defaultSort = AO3SearchSort.DATE_UPDATED, now = now
        )
        assertEquals(AO3SearchSort.DATE_UPDATED, filters.sort)
        assertEquals("", filters.hitsFrom)
        assertEquals("", filters.hitsTo)
    }

    @Test
    fun cutOffMenuShowsAValueSetElsewhere() {
        assertEquals(listOf("", "100", "300", "500", "1000", "5000"), SearchWaysToFind.minimumHitsOptions("500"))
        assertEquals(
            listOf("", "100", "250", "300", "500", "1000", "5000"),
            SearchWaysToFind.minimumHitsOptions("250")
        )
        assertEquals("Off", SearchWaysToFind.minimumHitsTitle(""))
    }

    @Test
    fun sortByRowNamesWhatIsInEffect() {
        var filters = AO3SearchFilters()
        var ranking = LoadedWorksRanking()
        assertEquals("Best Match", SearchSortBySummary.value(filters, ranking))
        filters = SearchWaysToFind.toggle(SearchWaysToFind.HIDDEN_GEMS, filters, now = now)
        assertEquals("Hidden Gems", SearchSortBySummary.value(filters, ranking))
        ranking = ranking.copy(rank = LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED)
        assertEquals("Kudos per Hit, Adjusted", SearchSortBySummary.value(filters, ranking))
        assertEquals("Hidden Gems", SearchSortBySummary.value(filters, ranking = null))
    }

    @Test
    fun adjustedComparesEachWorkWithItsOwnGroup() {
        val works = listOf(
            work(1, kudos = 50, hits = 1_000, words = 2_000, updated = "01 Oct 2026"),
            work(2, kudos = 100, hits = 1_000, words = 2_000, updated = "02 Oct 2026"),
            work(3, kudos = 200, hits = 1_000, words = 2_000, updated = "03 Oct 2026"),
            work(4, kudos = 100, hits = 10_000, words = 100_000, updated = "01 Jan 2018"),
            work(5, kudos = 200, hits = 10_000, words = 100_000, updated = "01 Feb 2018"),
            work(6, kudos = 300, hits = 10_000, words = 100_000, updated = "01 Mar 2018")
        )
        val ranked = LoadedWorksRanker.rank(works, settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED), now = now)
        assertEquals(listOf(3L, 6L), ids(ranked).take(2))
        val scores = ranked.associate { it.work.id to it.score }
        assertTrue(isClose(scores[3L], 2.0))
        assertTrue(isClose(scores[6L], 1.5))
        assertTrue(isClose(scores[5L], 1.0))
        assertTrue(isClose(scores[4L], 0.5))
        assertTrue(ids(ranked).indexOf(6L) < ids(ranked).indexOf(1L))
    }

    @Test
    fun aGroupTooSmallFallsBackToEveryLoadedWork() {
        val works = listOf(
            work(1, kudos = 100, hits = 1_000, words = 2_000),
            work(2, kudos = 300, hits = 1_000, words = 100_000, updated = "01 Jan 2015")
        )
        val ranked = LoadedWorksRanker.rank(works, settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED), now = now)
        assertTrue(isClose(ranked.first().score, 1.5))
        assertEquals(listOf(2L, 1L), ids(ranked))
    }

    @Test
    fun groupsAreLengthAndAge() {
        assertEquals(0, LoadedWorksRanker.lengthGroup(9_999)!!)
        assertEquals(1, LoadedWorksRanker.lengthGroup(10_000)!!)
        assertEquals(2, LoadedWorksRanker.lengthGroup(50_000)!!)
        assertNull(LoadedWorksRanker.lengthGroup(null))
        assertEquals(0, LoadedWorksRanker.ageGroup(now.minusDays(30), now)!!)
        assertEquals(1, LoadedWorksRanker.ageGroup(now.minusDays(2L * 365), now)!!)
        assertEquals(2, LoadedWorksRanker.ageGroup(now.minusDays(5L * 365), now)!!)
        assertNull(LoadedWorksRanker.ageGroup(null, now))
    }

    @Test
    fun cautiousShrinksLowHitWorksTowardTheMedian() {
        val works = listOf(
            work(1, kudos = 50, hits = 60, bookmarks = 30),
            work(2, kudos = 1_000, hits = 20_000, bookmarks = 400),
            work(3, kudos = 500, hits = 10_000, bookmarks = 100),
            work(4, kudos = 500, hits = 10_000, bookmarks = 50)
        )
        val plain = LoadedWorksRanker.rank(works, settings(LoadedWorksRank.SAVES_PER_KUDOS), now = now)
        assertEquals(listOf(1L, 2L, 3L, 4L), ids(plain))
        val cautious = LoadedWorksRanker.rank(works, settings(LoadedWorksRank.SAVES_PER_KUDOS, cautious = true), now = now)
        assertEquals(listOf(2L, 1L, 3L, 4L), ids(cautious))
        val first = cautious.first { it.work.id == 1L }
        assertTrue(isClose(first.score, (60 * 0.6 + 500 * 0.3) / 560))
        assertTrue(first.signal?.endsWith("saves per 100 kudos") == true)
        assertTrue(first.signal?.startsWith("60") == true)
    }

    @Test
    fun shrinkWeighsHitsAgainstThePseudoCount() {
        assertTrue(isClose(LoadedWorksRanker.shrink(0.6, 0.3, 0), 0.3))
        assertTrue(isClose(LoadedWorksRanker.shrink(0.6, 0.3, null), 0.3))
        assertTrue(isClose(LoadedWorksRanker.shrink(0.6, 0.3, 500), 0.45))
        assertTrue(LoadedWorksRanker.shrink(0.6, 0.3, 1_000_000) > 0.599)
    }

    @Test
    fun unusualWorksGoToTheEndInAO3Order() {
        val works = listOf(
            work(1, kudos = 200, hits = 100, bookmarks = 10),
            work(2, kudos = 100, hits = 1_000, bookmarks = 20),
            work(3, kudos = 1_500, hits = 30_000, bookmarks = 5),
            work(4, kudos = 50, hits = 1_000, bookmarks = 5)
        )
        val ranked = LoadedWorksRanker.rank(works, settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED), now = now)
        assertEquals(listOf(2L, 4L, 1L, 3L), ids(ranked))
        assertTrue(ranked.takeLast(2).all { it.isSetAside })
        assertEquals("Unusual stats, set aside", ranked.last().signal)
        assertTrue(isClose(ranked.first().score, 0.1 / 0.075))

        val off = LoadedWorksRanker.rank(works, settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED, setAside = false), now = now)
        assertEquals(1L, off.first().work.id)
        assertFalse(off.any { it.isSetAside })
    }

    @Test
    fun almostNoBookmarksMeansUnderOnePerHundredKudos() {
        val edge = LoadedWorksRanker.Figures(work(1, kudos = 1_000, hits = 9_000, bookmarks = 9), now)
        val enough = LoadedWorksRanker.Figures(work(2, kudos = 1_000, hits = 9_000, bookmarks = 10), now)
        val small = LoadedWorksRanker.Figures(work(3, kudos = 999, hits = 9_000, bookmarks = 0), now)
        assertTrue(LoadedWorksRanker.isUnusual(edge))
        assertFalse(LoadedWorksRanker.isUnusual(enough))
        assertFalse(LoadedWorksRanker.isUnusual(small))
    }

    @Test
    fun tiesKeepAO3OrderInBothDirections() {
        val works = listOf(
            work(1, kudos = 10, hits = 100),
            work(2, kudos = 20, hits = 100),
            work(3, kudos = 10, hits = 100),
            work(4, kudos = 0, hits = 0),
            work(5, kudos = 10, hits = 100)
        )
        val highest = LoadedWorksRanker.rank(works, settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED), now = now)
        assertEquals(listOf(2L, 1L, 3L, 5L, 4L), ids(highest))
        val lowest = LoadedWorksRanker.rank(
            works,
            settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED, order = LoadedWorksRankOrder.LOWEST_FIRST),
            now = now
        )
        assertEquals(listOf(1L, 3L, 5L, 2L, 4L), ids(lowest))
        assertEquals(ids(highest), ids(LoadedWorksRanker.rank(works, settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED), now = now)))
    }

    @Test
    fun reRanksWhateverIsLoaded() {
        val pageOne = listOf(work(1, kudos = 10, hits = 100), work(2, kudos = 30, hits = 100))
        val pageTwo = listOf(work(3, kudos = 50, hits = 100))
        assertEquals(listOf(2L, 1L), ids(LoadedWorksRanker.rank(pageOne, settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED), now = now)))
        assertEquals(
            listOf(3L, 2L, 1L),
            ids(LoadedWorksRanker.rank(pageOne + pageTwo, settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED), now = now))
        )
    }

    @Test
    fun medianOfEvenAndOddCounts() {
        assertNull(LoadedWorksRanker.median(emptyList()))
        assertEquals(2.0, LoadedWorksRanker.median(listOf(3.0, 1.0, 2.0))!!, 0.0)
        assertEquals(2.5, LoadedWorksRanker.median(listOf(4.0, 1.0, 3.0, 2.0))!!, 0.0)
    }

    @Test
    fun momentumCountsKudosSinceTheLastSighting() {
        val firstLook = listOf(
            work(1, kudos = 100, hits = 1_000),
            work(2, kudos = 50, hits = 1_000),
            work(3, kudos = 80, hits = 900)
        )
        val session = KudosSightings()
        val stored = session.record(firstLook, emptyMap(), now)
        assertTrue(session.previousKudos.isEmpty())
        val fresh = LoadedWorksRanker.rank(firstLook, settings(LoadedWorksRank.MOMENTUM), session.previousKudos, now)
        assertEquals(listOf(1L, 2L, 3L), ids(fresh))
        assertTrue(fresh.all { it.score == null && it.signal == "First time in your results" })

        val later = listOf(
            work(1, kudos = 105, hits = 1_100),
            work(2, kudos = 90, hits = 1_200),
            work(3, kudos = 78, hits = 950)
        )
        val next = KudosSightings()
        val updated = next.record(later, stored, now.plusDays(1))
        assertEquals(mapOf(1L to 100, 2L to 50, 3L to 80), next.previousKudos)
        assertEquals(90, updated[2L]?.kudos)
        val ranked = LoadedWorksRanker.rank(later, settings(LoadedWorksRank.MOMENTUM), next.previousKudos, now)
        assertEquals(listOf(2L, 1L, 3L), ids(ranked))
        assertEquals(0.0, ranked.last().score!!, 0.0)
        assertEquals("No new kudos since you last saw it", ranked.last().signal)
        assertTrue(ranked.first().signal?.startsWith("+") == true)

        next.record(listOf(work(2, kudos = 120, hits = 1_300)), updated, now.plusDays(1))
        assertEquals(50, next.previousKudos[2L])
    }

    @Test
    fun momentumSkipsWorksWithUnknownKudos() {
        val session = KudosSightings()
        val stored = session.record(listOf(work(1, kudos = null, hits = null, words = null)), emptyMap(), now)
        assertTrue(stored.isEmpty())
    }

    @Test
    fun momentumRecordRoundTripsAndStaysBounded() {
        val store = MemoryKudosStringStore()
        val entries = mapOf(7L to SeenKudos(kudos = 12, seenAtMillis = 100))
        LastSeenKudosStore.save(entries, store)
        assertEquals(entries, LastSeenKudosStore.load(store))

        val many = (0..LastSeenKudosStore.ENTRY_LIMIT).associate { index ->
            index.toLong() to SeenKudos(kudos = index, seenAtMillis = index.toLong())
        }
        val bounded = LastSeenKudosStore.bound(many)
        assertEquals(LastSeenKudosStore.ENTRY_LIMIT, bounded.size)
        assertNull(bounded[0L])
        assertTrue(bounded[LastSeenKudosStore.ENTRY_LIMIT.toLong()] != null)
    }

    @Test
    fun oldSavedSearchOmitsRankingAndAChangedRankRoundTrips() {
        val old = SearchFiltersCodec.decode("""{"query":"lighthouse","sort":"kudos"}""")
        assertEquals(LoadedWorksRanking(), old.loadedWorksRanking)
        assertEquals("lighthouse", old.query)
        assertEquals(AO3SearchSort.KUDOS, old.sort)
        val encodedOld = Json.parseToJsonElement(SearchFiltersCodec.encode(old)) as JsonObject
        assertNull(encodedOld["loadedWorksRank"])
        assertNull(encodedOld["showsSignal"])
        assertEquals(old, SearchFiltersCodec.decode(SearchFiltersCodec.encode(old)))

        val ranking = LoadedWorksRanking(
            rank = LoadedWorksRank.MOMENTUM,
            order = LoadedWorksRankOrder.LOWEST_FIRST,
            ranksCautiously = false,
            setsAsideUnusual = false,
            showsSignal = false
        )
        val decoded = SearchFiltersCodec.decode(
            SearchFiltersCodec.encode(AO3SearchFilters(query = "lighthouse", loadedWorksRanking = ranking))
        )
        assertEquals(ranking, decoded.loadedWorksRanking)
        assertEquals("lighthouse", decoded.query)
        assertEquals(ranking, SearchFiltersCodec.decode(SearchFiltersCodec.encode(decoded)).loadedWorksRanking)

        val unknown = SearchFiltersCodec.decode("""{"loadedWorksRank":"nope","showsSignal":false}""")
        assertEquals(LoadedWorksRank.AO3_ORDER, unknown.loadedWorksRanking.rank)
        assertFalse(unknown.loadedWorksRanking.showsSignal)
    }

    @Test
    fun signalLineFollowsTheToggle() {
        val works = listOf(
            CanonicalWork(null, work(1, kudos = 10, hits = 100)),
            CanonicalWork(null, work(2, kudos = 30, hits = 100))
        )
        val settings = settings(LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED)
        val shown = rankSearchWorks(works, settings, now = now)
        assertEquals(listOf(2L, 1L), shown.map { it.work.remote.id })
        assertTrue(shown.first().signal?.isNotEmpty() == true)
        val hidden = rankSearchWorks(works, settings.copy(showsSignal = false), now = now)
        assertEquals(listOf(2L, 1L), hidden.map { it.work.remote.id })
        assertTrue(hidden.all { it.signal == null })
    }
}
