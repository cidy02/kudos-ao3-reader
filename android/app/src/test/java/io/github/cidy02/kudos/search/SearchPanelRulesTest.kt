package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.search.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SearchPanelRulesTest {
    @Test fun aClosedPanelPutsBackTheRequestedSearchAndNothingInBrowse() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val answer = CompletableDeferred<AO3Result<AO3HttpResponse>>()
            val client = object : AO3Client {
                override suspend fun get(url: String, headers: Map<String, String>) = answer.await()
            }
            val model = SearchViewModel(AO3SearchRepository(client))
            val requested = AO3SearchFilters(fandom = "Fandom A", completion = AO3Completion.COMPLETE)
            val edited = AO3SearchFilters(query = "typed since", rating = AO3Rating.TEEN)
            model.runSearch(searchFilters = requested)
            runCurrent()
            assertEquals(SearchUiState.Loading, model.state.value)
            model.updateFilters(edited)
            model.discardFilterEdits()
            assertEquals(requested.copy(query = "typed since"), model.filters.value)
            answer.complete(AO3Result.Failure(AO3Error.Forbidden))
            advanceUntilIdle()
            model.updateFilters(edited)
            model.discardFilterEdits()
            assertEquals(requested.copy(query = "typed since"), model.filters.value)
            model.goBack()
            model.updateFilters(edited)
            model.discardFilterEdits()
            assertEquals(edited, model.filters.value)
        } finally { Dispatchers.resetMain() }
    }
}
