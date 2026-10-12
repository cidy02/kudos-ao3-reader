package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.network.ao3.account.AO3HistoryVisitBucket.Earlier
import io.github.cidy02.kudos.network.ao3.account.AO3HistoryVisitBucket.ThisMonth
import io.github.cidy02.kudos.network.ao3.account.AO3HistoryVisitBucket.ThisWeek
import io.github.cidy02.kudos.network.ao3.account.AO3HistoryVisitBucket.Today
import io.github.cidy02.kudos.network.ao3.account.AO3HistoryVisitBucket.Yesterday
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The cases of iOS `AO3HistoryScreenTests`. */
class AO3HistoryVisitTest {
    private val today = LocalDate.of(2026, 9, 25)

    @Test
    fun relativePhrasesLandInTheNearestHeading() {
        listOf(
            "less than a minute" to Today, "12 minutes" to Today, "about 1 hour" to Today, "about 5 hours" to Today,
            "1 day" to Yesterday, "2 days" to ThisWeek, "6 days" to ThisWeek, "7 days" to ThisMonth,
            "29 days" to ThisMonth, "about 1 month" to ThisMonth, "3 months" to Earlier, "" to Earlier,
            "not a date" to Earlier
        ).forEach { (phrase, bucket) -> assertEquals(phrase, bucket, AO3HistoryVisitBucket.of(phrase, today)) }
    }

    @Test
    fun absoluteDatesUseTheCalendarMonth() {
        assertEquals(ThisMonth, AO3HistoryVisitBucket.of("21 Sep 2026", today))
        assertEquals(Earlier, AO3HistoryVisitBucket.of("04 Mar 2024", today))
        assertEquals(Earlier, AO3HistoryVisitBucket.of("31 Aug 2026", today))
    }

    /** A heading goes in where the page's own order changes bucket; rows are not pulled into date order. */
    @Test
    fun groupsFollowSourceOrder() {
        val groups = historyVisitGroups(listOf("04 Mar 2024", "about 1 hour", "3 minutes", "2 days", "6 days"), today) { it }
        assertEquals(listOf(Earlier, Today, ThisWeek), groups.map { it.bucket })
        assertEquals(listOf(1, 2, 2), groups.map { it.items.size })
    }

    @Test
    fun localProgressPairsChapterOrFinished() {
        assertEquals("Ch. 14 of 24", historyLocalProgress(false, 13, "14/24", 0.5))
        assertEquals("Finished", historyLocalProgress(true, 13, "14/24", 1.0))
        assertEquals("42%", historyLocalProgress(false, 0, "14/24", 0.42))
        assertNull(historyLocalProgress(false, 0, "", null))
    }
}
