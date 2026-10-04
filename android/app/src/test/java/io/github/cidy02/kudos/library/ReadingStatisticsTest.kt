package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors Apple `ReadingStatisticsTests` and `ReadingInsightsTests`. */
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
    fun readiumOnlyWorkCountsAsStarted() {
        val locatorOnly = work("Locator only", readiumLocator = "{\"href\":\"chapter1.xhtml\"}")
        val statistics = ReadingStatistics.from(listOf(locatorOnly))

        assertEquals(1, statistics.startedWorks)
        assertEquals(1, statistics.inProgressWorks)
    }

    @Test
    fun theTypicalSessionIsTheMedianSoOneBingeCannotMoveIt() {
        val facts = listOf(
            fact(day = 1, minutes = 20.0),
            fact(day = 2, minutes = 30.0),
            fact(day = 3, minutes = 40.0),
            fact(day = 4, minutes = 240.0)
        )

        assertEquals(35 * 60.0, ReadingInsights.medianSeconds(facts), 0.0)
    }

    @Test
    fun medianOfNothingIsZeroRatherThanACrash() {
        assertEquals(0.0, ReadingInsights.medianSeconds(emptyList()), 0.0)
    }

    @Test
    fun finishRateCountsWorksNotSessionsSoARereadCannotInflateIt() {
        val reread = UUID.randomUUID().toString()
        val abandoned = UUID.randomUUID().toString()
        val facts = listOf(
            fact(work = reread, day = 1, minutes = 30.0, didFinish = true),
            fact(work = reread, day = 2, minutes = 30.0, didFinish = true),
            fact(work = reread, day = 3, minutes = 30.0, didFinish = true),
            fact(work = abandoned, day = 4, minutes = 30.0)
        )

        assertEquals(0.5, ReadingInsights.finishRate(facts) ?: -1.0, 0.0)
    }

    @Test
    fun noStartedWorksIsNoDataRatherThanZeroPercent() {
        assertNull(ReadingInsights.finishRate(emptyList()))
    }

    @Test
    fun aStreakCountsDaysSoTwoSessionsInOneEveningAreOneDay() {
        val facts = listOf(
            fact(day = 1, hour = 19, minutes = 30.0),
            fact(day = 1, hour = 22, minutes = 30.0),
            fact(day = 2, minutes = 30.0),
            fact(day = 3, minutes = 30.0),
            fact(day = 9, minutes = 30.0)
        )

        assertEquals(3, ReadingInsights.longestStreak(facts, ZoneOffset.UTC))
    }

    @Test
    fun aStreakOfOneDayIsOneNotZero() {
        assertEquals(
            1,
            ReadingInsights.longestStreak(
                listOf(fact(day = 4, minutes = 30.0)),
                ZoneOffset.UTC
            )
        )
    }

    @Test
    fun fandomSharesPartitionTheHoursRatherThanOverCounting() {
        val facts = listOf(
            fact(day = 1, minutes = 60.0, fandom = "Naruto"),
            fact(day = 2, minutes = 30.0, fandom = "Cyberpunk 2077"),
            fact(day = 3, minutes = 20.0, fandom = "Blade Runner"),
            fact(day = 4, minutes = 10.0, fandom = "Dracula"),
            fact(day = 5, minutes = 5.0)
        )

        val shares = ReadingInsights.fandomShares(facts)

        assertEquals(
            listOf("Naruto", "Cyberpunk 2077", "Blade Runner", "Everything else"),
            shares.map { it.name }
        )
        assertEquals(15 * 60.0, shares.last().seconds, 0.0)
        assertTrue(shares.last().isRemainder)
        assertEquals(125 * 60.0, shares.sumOf { it.seconds }, 0.0)
    }

    @Test
    fun noRemainderRowAppearsWhenNothingIsLeftOver() {
        val shares = ReadingInsights.fandomShares(
            listOf(
                fact(day = 1, minutes = 60.0, fandom = "Naruto"),
                fact(day = 2, minutes = 30.0, fandom = "Dracula")
            )
        )

        assertEquals(listOf("Naruto", "Dracula"), shares.map { it.name })
        assertFalse(shares.any { it.isRemainder })
    }

    @Test
    fun wordsPerHourIsWeightedByTimeNotAveragedAcrossSessions() {
        val facts = listOf(
            fact(day = 1, minutes = 60.0, words = 10_000),
            fact(day = 2, minutes = 180.0, words = 60_000),
            fact(day = 3, minutes = 0.0, words = 900_000)
        )

        assertEquals(17_500.0, ReadingInsights.wordsPerHour(facts), 0.0)
    }

    @Test
    fun aFirstPeriodHasNoDeltaRatherThanADeltaAgainstZero() {
        val insights = ReadingInsights.make(
            facts = listOf(fact(day = 1, minutes = 60.0)),
            zone = ZoneOffset.UTC
        )

        assertNull(insights.previousPeriodSeconds)
        assertEquals(3_600.0, insights.totalSeconds, 0.0)
    }

    @Test
    fun theDeltaComesFromThePriorPeriodsOwnRows() {
        val insights = ReadingInsights.make(
            facts = listOf(fact(day = 1, minutes = 90.0)),
            previousPeriodFacts = listOf(fact(day = 1, minutes = 30.0)),
            zone = ZoneOffset.UTC
        )

        assertEquals(1_800.0, insights.previousPeriodSeconds ?: -1.0, 0.0)
        assertEquals(
            "+1.0",
            ReadingInsights.signedHoursLabel(
                insights.totalSeconds - (insights.previousPeriodSeconds ?: 0.0)
            )
        )
    }

    @Test
    fun labelsMatchTheSpecsOwnFormats() {
        assertEquals("18.4", ReadingInsights.hoursLabel(18.4 * 3_600))
        assertEquals("−0.6", ReadingInsights.signedHoursLabel(-0.6 * 3_600))
        assertEquals("31 min", ReadingInsights.durationLabel(31 * 60.0))
        assertEquals("1h 12m", ReadingInsights.durationLabel(72 * 60.0))
        assertEquals("2h", ReadingInsights.durationLabel(120 * 60.0))
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

    private fun fact(
        work: String = UUID.randomUUID().toString(),
        day: Int,
        hour: Int = 12,
        minutes: Double,
        words: Int = 0,
        didFinish: Boolean = false,
        fandom: String = ""
    ): ReadingSessionFacts = ReadingSessionFacts(
        workID = work,
        startedAt = LocalDate.of(2026, 8, day)
            .atTime(hour, 0)
            .toInstant(ZoneOffset.UTC),
        durationSeconds = minutes * 60,
        wordCount = words,
        didFinish = didFinish,
        fandom = fandom
    )

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
