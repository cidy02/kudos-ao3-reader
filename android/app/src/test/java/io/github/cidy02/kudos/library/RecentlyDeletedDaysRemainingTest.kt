package io.github.cidy02.kudos.library

import java.time.Instant
import java.time.temporal.ChronoUnit
import org.junit.Assert.assertEquals
import org.junit.Test

class RecentlyDeletedDaysRemainingTest {
    @Test
    fun fullDaysRemainingUsesExactCount() {
        val now = Instant.parse("2026-06-26T12:00:00Z")
        val scheduled = now.plus(90, ChronoUnit.DAYS)

        assertEquals(90L, daysRemainingUntil(scheduled, now))
    }

    @Test
    fun partialDayRoundsUpInsteadOfFlooring() {
        val now = Instant.parse("2026-06-26T12:00:00Z")
        // 89 days + 1 hour left → floor would be 89; ceiling is 90.
        val scheduled = now.plus(89, ChronoUnit.DAYS).plus(1, ChronoUnit.HOURS)

        assertEquals(90L, daysRemainingUntil(scheduled, now))
    }

    @Test
    fun underOneDayStillShowsOneDayLeft() {
        val now = Instant.parse("2026-06-26T12:00:00Z")
        val scheduled = now.plus(3, ChronoUnit.HOURS)

        assertEquals(1L, daysRemainingUntil(scheduled, now))
    }

    @Test
    fun pastOrEqualScheduledIsZero() {
        val now = Instant.parse("2026-06-26T12:00:00Z")

        assertEquals(0L, daysRemainingUntil(now, now))
        assertEquals(0L, daysRemainingUntil(now.minusSeconds(1), now))
    }
}
