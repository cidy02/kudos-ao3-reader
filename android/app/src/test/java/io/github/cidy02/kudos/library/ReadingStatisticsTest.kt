package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Mirrors Apple `ReadingStatisticsTests`.
 */
class ReadingStatisticsTest {
    @Test
    fun separatesStartedFinishedAndInProgressWorks() {
        val unread = work("Unread")
        val reading = work("Reading", lastScrollFraction = 0.25)
        val finished = work("Finished", isFinished = true)

        val statistics = ReadingStatistics.from(listOf(unread, reading, finished))

        assertEquals(3, statistics.totalWorks)
        assertEquals(2, statistics.startedWorks)
        assertEquals(1, statistics.finishedWorks)
        assertEquals(1, statistics.inProgressWorks)
        assertEquals(0.5, statistics.completionRate, 0.0001)
    }

    @Test
    fun wordsReadCountsOnlyFinishedWorksWithKnownTotals() {
        val finished = work("Known", isFinished = true, wordCount = 12_500)
        val reading = work(
            "Still reading",
            lastReadDate = Instant.now(),
            wordCount = 90_000
        )
        val unknown = work("Unknown", isFinished = true)

        val statistics = ReadingStatistics.from(listOf(finished, reading, unknown))

        assertEquals(12_500, statistics.wordsRead)
    }

    @Test
    fun recentActivityUsesDistinctWorksAndCalendarDays() {
        val zone = ZoneOffset.UTC
        val now = LocalDate.of(2026, 6, 20)
            .atTime(LocalTime.of(12, 0))
            .toInstant(zone)

        fun daysAgo(days: Long): Instant =
            LocalDate.of(2026, 6, 20)
                .minusDays(days)
                .atTime(LocalTime.of(12, 0))
                .toInstant(zone)

        val today = work("Today", lastReadDate = now)
        val sixDaysAgo = work("Six days ago", lastReadDate = daysAgo(6))
        val tenDaysAgo = work("Ten days ago", lastReadDate = daysAgo(10))
        val old = work("Old", lastReadDate = daysAgo(31))

        val statistics = ReadingStatistics.from(
            works = listOf(today, sixDaysAgo, tenDaysAgo, old),
            now = now,
            zone = zone
        )

        assertEquals(2, statistics.openedLast7Days)
        assertEquals(3, statistics.openedLast30Days)
        assertEquals(now, statistics.latestReadDate)
    }

    @Test
    fun topFandomsCountEachFandomOncePerStartedWork() {
        val first = work(
            "First",
            lastReadDate = Instant.now(),
            workFandoms = listOf("Naruto", "Naruto", "Bleach")
        )
        val second = work(
            "Second",
            isFinished = true,
            workFandoms = listOf("Naruto")
        )
        val unread = work(
            "Unread",
            workFandoms = listOf("Bleach")
        )

        val statistics = ReadingStatistics.from(listOf(first, second, unread))

        assertEquals(
            listOf(
                ReadingStatistics.FandomCount(name = "Naruto", count = 2),
                ReadingStatistics.FandomCount(name = "Bleach", count = 1)
            ),
            statistics.topFandoms
        )
    }

    @Test
    fun emptyLibraryYieldsZeroMetrics() {
        val statistics = ReadingStatistics.from(emptyList())
        assertEquals(0, statistics.totalWorks)
        assertEquals(0, statistics.startedWorks)
        assertEquals(0, statistics.finishedWorks)
        assertEquals(0, statistics.inProgressWorks)
        assertEquals(0, statistics.wordsRead)
        assertEquals(0, statistics.openedLast7Days)
        assertEquals(0, statistics.openedLast30Days)
        assertNull(statistics.latestReadDate)
        assertEquals(emptyList<ReadingStatistics.FandomCount>(), statistics.topFandoms)
        assertEquals(0.0, statistics.completionRate, 0.0)
    }

    @Test
    fun finishedWithoutProgressStillCountsAsStarted() {
        val finished = work("Done", isFinished = true)
        assertEquals(true, ReadingStatistics.hasStarted(finished))
        val stats = ReadingStatistics.from(listOf(finished))
        assertEquals(1, stats.startedWorks)
        assertEquals(0, stats.inProgressWorks)
    }

    @Test
    fun readiumLocatorOnlyStillCountsAsStarted() {
        // A backup restore can land a work with only a Readium locator and no
        // lastReadDate/spine/scroll — SavedWork.hasStartedReading and
        // CategoryStats.hasBeenRead both already treat that as started.
        val locatorOnly = work("Locator only", readiumLocator = "{\"href\":\"chapter1.xhtml\"}")
        assertEquals(true, ReadingStatistics.hasStarted(locatorOnly))
    }

    @Test
    fun formatCompactNumberUsesKAndMSuffixes() {
        assertEquals("999", formatCompactNumber(999))
        assertEquals("1.3K", formatCompactNumber(1_250))
        assertEquals("12.5K", formatCompactNumber(12_500))
        assertEquals("1M", formatCompactNumber(1_000_000))
    }

    @Test
    fun formatCompactNumberPromotesUnitWhenRoundingCrossesAThousand() {
        // 999,950 / 1000 = 999.95, which rounds to "1000.0" at one decimal —
        // that belongs to the M tier, not a bogus "1000.0K".
        assertEquals("1M", formatCompactNumber(999_950))
        assertEquals("1B", formatCompactNumber(999_999_500))
    }

    private fun work(
        title: String,
        isFinished: Boolean = false,
        wordCount: Int = 0,
        lastReadDate: Instant? = null,
        lastScrollFraction: Double = 0.0,
        lastSpineIndex: Int = 0,
        workFandoms: List<String> = emptyList(),
        readiumLocator: String? = null
    ): SavedWork {
        return SavedWork(
            title = title,
            author = "Author",
            isFinished = isFinished,
            wordCount = wordCount,
            lastReadDate = lastReadDate,
            lastScrollFraction = lastScrollFraction,
            lastSpineIndex = lastSpineIndex,
            workFandoms = workFandoms,
            readiumLocator = readiumLocator
        )
    }
}
