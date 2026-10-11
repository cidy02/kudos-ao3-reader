package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Favorites › Authors: one page per author, in order, and never a filter over half the answers. */
class AuthorNewestWorkStoreTest {
    private var clock = 0L
    private var scope = "reader|1"
    private val asked = mutableListOf<String>()
    private val answers = mutableMapOf<String, AO3Result<AO3SearchPage>>()

    private fun work(id: Long) = AO3WorkSummary(id = id, title = "W$id", authors = emptyList(),
        fandoms = emptyList(), rating = "", warnings = emptyList(), categories = emptyList())
    private fun page(vararg works: AO3WorkSummary) = AO3Result.Success(AO3SearchPage(works.toList(), 1, 1))
    private fun store() = AuthorNewestWorkStore({ scope }, MutableStateFlow(0), { clock }) { name ->
        asked += name
        answers[name] ?: page(work(1))
    }

    @Test fun everyAuthorIsAskedOnceInTheOrderShownAndTheFirstWorkIsKept() = runTest {
        answers["a"] = page(work(7), work(3))
        val store = store()
        assertTrue(store.prefetch(listOf("a", "B", "A")))
        assertEquals(listOf("a", "B"), asked)
        assertEquals(7L, store.cached("A")?.work?.id)
        assertTrue("answers kept: a second round asks nothing", store.prefetch(listOf("b", "a")))
        assertEquals(2, asked.size)
    }

    @Test fun aBylineWithNoPageIsAnAnswerAndDoesNotStallTheRest() = runTest {
        answers["gone"] = AO3Result.Failure(AO3Error.NotFound)
        val store = store()
        assertTrue(store.prefetch(listOf("gone", "b")))
        assertEquals(listOf("gone", "b"), asked)
        assertNotNull(store.cached("gone"))
        assertNull(store.cached("gone")?.work)
    }

    @Test fun anUnwellAO3StopsTheRoundAndTheNextOneResumesWhereItStopped() = runTest {
        answers["b"] = AO3Result.Failure(AO3Error.Overloaded(0, null))
        val store = store()
        assertFalse(store.prefetch(listOf("a", "b", "c")))
        assertEquals("the author after the failure is not asked", listOf("a", "b"), asked)
        assertNull("a failure is not an answer", store.cached("b"))
        answers.remove("b")
        assertTrue(store.prefetch(listOf("a", "b", "c")))
        assertEquals(listOf("a", "b", "b", "c"), asked)
    }

    @Test fun anAnswerGoesStaleAfterHalfAnHourAndNeverCrossesToAnotherSession() = runTest {
        val store = store()
        store.prefetch(listOf("a"))
        clock = AuthorNewestWorkStore.TTL_MILLIS - 1
        assertNotNull(store.cached("a"))
        clock = AuthorNewestWorkStore.TTL_MILLIS
        assertNull(store.cached("a"))
        clock = 0
        scope = "other|2"
        assertNull(store.cached("a"))
    }

    @Test fun aSessionThatChangesWhileAO3AnswersKeepsNothingOfThatAnswer() = runTest {
        val store = AuthorNewestWorkStore({ scope }, MutableStateFlow(0), { clock }) {
            scope = "other|2"
            page(work(1))
        }
        assertFalse(store.prefetch(listOf("a")))
        assertNull(store.cached("a"))
        assertNull(store.cached("a", "reader|1"))
    }

    @Test fun withNewWorkKeepsOnlyAuthorsWhoseNewestWorkIsUnopened() {
        val rows = listOf(
            ReadingAffinities.Row("Opened", username = "opened"), ReadingAffinities.Row("New", username = "new"),
            ReadingAffinities.Row("Nothing posted", username = "none"), ReadingAffinities.Row("No account"),
            ReadingAffinities.Row("Not asked", username = "unasked")
        )
        val known = mapOf("opened" to AuthorNewestWorkStore.Answer(work(1)),
            "new" to AuthorNewestWorkStore.Answer(work(2)), "none" to AuthorNewestWorkStore.Answer(null))
        assertEquals(listOf("New"),
            FavoriteAuthorQuickFilter.WithNewWork.apply(rows, known::get, setOf(1L)).map { it.name })
        assertEquals(rows, FavoriteAuthorQuickFilter.All.apply(rows, known::get, setOf(1L)))
    }
}
