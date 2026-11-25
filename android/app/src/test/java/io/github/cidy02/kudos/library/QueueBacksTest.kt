package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.components.CoverStackLayout
import org.junit.Assert.assertEquals
import org.junit.Test

class QueueBacksTest {
    private fun work(id: String, finished: Boolean = false) =
        SavedWork(id = id, title = id, author = "a", isFinished = finished)

    @Test
    fun backsStartWithUpNextThenTheRestInOrderAndSkipHiddenWorks() {
        // "hidden" sits before "next": without the visibility filter it would lead as Up Next.
        val queue = listOf(work("done", finished = true), work("hidden"), work("next"), work("later"))
        val backs = queueBacks(queue, visibleWorkIds = setOf("done", "next", "later"))
        // Home's order: the first unfinished work leads, the finished one follows in line.
        assertEquals(listOf("next", "done", "later").take(CoverStackLayout.maxBacks), backs.map { it.id })
    }

    @Test
    fun aHiddenFirstWorkNeverShowsEvenWhenItIsTheOnlyUnfinishedOne() {
        val queue = listOf(work("hidden"), work("a", true), work("b", true))
        val backs = queueBacks(queue, setOf("a", "b"))
        assertEquals(listOf("a", "b").take(CoverStackLayout.maxBacks), backs.map { it.id })
        assertEquals(false, backs.any { it.id == "hidden" })
    }

    @Test
    fun aFullyReadQueueLeadsWithItsFirstWork() {
        val queue = listOf(work("a", true), work("b", true))
        assertEquals(listOf("a", "b").take(CoverStackLayout.maxBacks), queueBacks(queue, setOf("a", "b")).map { it.id })
    }
}
