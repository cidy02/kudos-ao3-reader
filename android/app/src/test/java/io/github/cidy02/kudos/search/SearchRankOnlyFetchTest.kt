package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.search.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS T-473: a computed rank reorders the loaded works and never asks AO3 for a page. */
@OptIn(ExperimentalCoroutinesApi::class)
class SearchRankOnlyFetchTest {
    private fun page(): String = requireNotNull(
        javaClass.classLoader?.getResourceAsStream("ao3/search_basic.html")
    ).bufferedReader().use { it.readText() }

    /** The parse runs on a real background dispatcher, so step the test clock until it lands. */
    private fun TestScope.awaitResults(model: SearchViewModel, calls: () -> Int, expectedCalls: Int) {
        repeat(1_000) {
            advanceUntilIdle()
            if (calls() >= expectedCalls && model.state.value is SearchUiState.Results) return
            Thread.sleep(10)
        }
        error("search never finished: ${model.state.value}, calls=${calls()}")
    }

    @Test fun aRankOnlyApplyFetchesNothingAndAnAO3ChangeFetchesOnce() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val html = page()
            var calls = 0
            val client = object : AO3Client {
                override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                    calls++
                    return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), html))
                }
            }
            val model = SearchViewModel(AO3SearchRepository(client))
            val base = AO3SearchFilters(query = "lanterns")
            model.updateFilters(base)
            model.runSearch(searchFilters = base)
            awaitResults(model, { calls }, 1)
            assertEquals(1, calls)

            // Only the local rank changes: Apply reorders and does not fetch.
            model.updateFilters(base.copy(loadedWorksRanking = LoadedWorksRanking(rank = LoadedWorksRank.COMMENTS_PER_KUDOS)))
            model.applyFilters()
            awaitResults(model, { calls }, 1)
            assertEquals(1, calls)

            // An AO3 parameter changes: one search.
            model.updateFilters(model.filters.value.copy(hitsFrom = "500"))
            model.applyFilters()
            awaitResults(model, { calls }, 2)
            assertEquals(2, calls)
        } finally { Dispatchers.resetMain() }
    }
}
