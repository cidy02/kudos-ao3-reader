package io.github.cidy02.kudos.library

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.temporal.WeekFields
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of iOS `ReadingHistoryTimelineTests` (T-462). */
class ReadingHistoryTimelineTests {
    private val utc: ZoneId = ZoneOffset.UTC
    private val mondayWeeks: WeekFields = WeekFields.of(DayOfWeek.MONDAY, 1)
    private val sundayWeeks: WeekFields = WeekFields.of(DayOfWeek.SUNDAY, 1)

    @Test
    fun emptyFactsProduceEmptyPeriodAndZeroAverageAndSummary() {
        val now = Instant.parse("2026-04-15T12:00:00Z")

        val week = ReadingHistoryTimeline.make(
            scope = ReadingHistoryScope.Week,
            reference = now,
            facts = emptyList(),
            now = now,
            zone = utc,
            weekFields = mondayWeeks
        )
        assertEquals(7, week.buckets.size)
        assertEquals(0.0, week.totalSeconds, 0.0)
        assertEquals(0, week.workCount)
        assertEquals(0, week.finishedCount)
        assertEquals(0, week.streakDays)
        assertEquals(0, week.longestStreakDays)
        assertEquals(0.0, week.averageBucketSeconds, 0.0)
        assertNull(week.peakBucket)
        assertTrue(week.days.isEmpty())
        assertTrue(week.topWorks.isEmpty())
        assertNull(week.topFandom)
        assertNull(week.longestFinishedWork)
        assertNull(week.favoriteTimeOfDay)
        assertEquals("This week: no reading", week.chartSummary("This week", utc, Locale.US))

        val month = ReadingHistoryTimeline.make(
            scope = ReadingHistoryScope.Month,
            reference = now,
            facts = emptyList(),
            now = now,
            zone = utc,
            weekFields = mondayWeeks
        )
        assertEquals(30, month.buckets.size)

        val year = ReadingHistoryTimeline.make(
            scope = ReadingHistoryScope.Year,
            reference = now,
            facts = emptyList(),
            now = now,
            zone = utc,
            weekFields = mondayWeeks
        )
        assertEquals(12, year.buckets.size)
    }

    @Test
    fun aSittingAcrossMidnightBelongsWholeToTheDayItStarted() {
        val now = Instant.parse("2026-04-15T12:00:00Z")
        val lateStart = Instant.parse("2026-04-14T23:40:00Z")
        val sitting = ReadingSessionFacts(
            sessionID = "s-midnight",
            workID = "work-1",
            title = "Night Train",
            startedAt = lateStart,
            durationSeconds = 45 * 60.0,
            wordCount = 10_000,
            didFinish = false,
            fandom = "Doctor Who",
            endingProgress = 0.5,
            chapterCount = 4
        )

        val timeline = ReadingHistoryTimeline.make(
            scope = ReadingHistoryScope.Week,
            reference = now,
            facts = listOf(sitting),
            now = now,
            zone = utc,
            weekFields = mondayWeeks
        )

        assertEquals(45 * 60.0, timeline.totalSeconds, 0.0)
        assertEquals(1, timeline.days.size)
        assertEquals(Instant.parse("2026-04-14T00:00:00Z"), timeline.days.single().start)
        assertEquals(45 * 60.0, timeline.days.single().totalSeconds, 0.0)

        val apr14 = timeline.buckets.first { it.start == Instant.parse("2026-04-14T00:00:00Z") }
        val apr15 = timeline.buckets.first { it.start == Instant.parse("2026-04-15T00:00:00Z") }
        assertEquals(45 * 60.0, apr14.seconds, 0.0)
        assertEquals(0.0, apr15.seconds, 0.0)
    }

    @Test
    fun streakCarriesFromYesterdayWhileTodayIsOpenAndBreaksAfterSilentDay() {
        val facts = listOf(
            fact("w1", "2026-04-13T20:00:00Z", minutes = 30.0),
            fact("w1", "2026-04-14T20:00:00Z", minutes = 30.0)
        )

        val morningOf15th = Instant.parse("2026-04-15T09:00:00Z")
        assertEquals(
            2,
            ReadingHistoryTimeline.streak(
                through = morningOf15th,
                isToday = true,
                facts = facts,
                zone = utc
            )
        )
        assertEquals(
            0,
            ReadingHistoryTimeline.streak(
                through = morningOf15th,
                isToday = false,
                facts = facts,
                zone = utc
            )
        )

        val morningOf16th = Instant.parse("2026-04-16T09:00:00Z")
        assertEquals(
            0,
            ReadingHistoryTimeline.streak(
                through = morningOf16th,
                isToday = true,
                facts = facts,
                zone = utc
            )
        )
    }

    @Test
    fun weekPeriodHonorsSundayAndMondayFirstCalendars() {
        // 2026-04-12 is a Sunday.
        val sunday = Instant.parse("2026-04-12T15:00:00Z")

        val sundayPeriod = ReadingHistoryTimeline.period(
            scope = ReadingHistoryScope.Week,
            containing = sunday,
            zone = utc,
            weekFields = sundayWeeks
        )
        assertEquals(Instant.parse("2026-04-12T00:00:00Z"), sundayPeriod.start)
        assertEquals(Instant.parse("2026-04-19T00:00:00Z"), sundayPeriod.end)

        val mondayPeriod = ReadingHistoryTimeline.period(
            scope = ReadingHistoryScope.Week,
            containing = sunday,
            zone = utc,
            weekFields = mondayWeeks
        )
        assertEquals(Instant.parse("2026-04-06T00:00:00Z"), mondayPeriod.start)
        assertEquals(Instant.parse("2026-04-13T00:00:00Z"), mondayPeriod.end)
    }

    @Test
    fun monthBoundaryRespectsTimeZone() {
        // 2026-05-01T02:30:00Z is 2026-04-30T22:30:00 in America/New_York (EDT, UTC-4).
        val boundarySession = fact("w1", "2026-05-01T02:30:00Z", minutes = 40.0)
        val aprReference = Instant.parse("2026-04-15T12:00:00Z")
        val newYork = ZoneId.of("America/New_York")

        val inUtc = ReadingHistoryTimeline.make(
            scope = ReadingHistoryScope.Month,
            reference = aprReference,
            facts = listOf(boundarySession),
            now = Instant.parse("2026-05-02T12:00:00Z"),
            zone = utc,
            weekFields = sundayWeeks
        )
        assertEquals(0.0, inUtc.totalSeconds, 0.0)

        val inNewYork = ReadingHistoryTimeline.make(
            scope = ReadingHistoryScope.Month,
            reference = aprReference,
            facts = listOf(boundarySession),
            now = Instant.parse("2026-05-02T12:00:00Z"),
            zone = newYork,
            weekFields = sundayWeeks
        )
        assertEquals(40 * 60.0, inNewYork.totalSeconds, 0.0)
        assertEquals(
            LocalDate.of(2026, 4, 30),
            inNewYork.days.single().start.atZone(newYork).toLocalDate()
        )
    }

    @Test
    fun yearScopeBuildsTwelveMonthlyBucketsAndYearFacts() {
        val now = Instant.parse("2026-10-15T12:00:00Z")
        val facts = listOf(
            ReadingSessionFacts(
                sessionID = "s1",
                workID = "w1",
                title = "Short Story",
                startedAt = Instant.parse("2026-01-10T22:00:00Z"),
                durationSeconds = 3600.0,
                wordCount = 12_000,
                didFinish = true,
                fandom = "Naruto",
                endingProgress = 1.0,
                chapterCount = 2
            ),
            ReadingSessionFacts(
                sessionID = "s2",
                workID = "w2",
                title = "Long Epic",
                startedAt = Instant.parse("2026-03-14T23:00:00Z"),
                durationSeconds = 7200.0,
                wordCount = 95_000,
                didFinish = true,
                fandom = "Doctor Who",
                endingProgress = 1.0,
                chapterCount = 20
            )
        )

        val timeline = ReadingHistoryTimeline.make(
            scope = ReadingHistoryScope.Year,
            reference = now,
            facts = facts,
            now = now,
            zone = utc,
            weekFields = mondayWeeks
        )

        assertEquals(12, timeline.buckets.size)
        assertEquals(3 * 3600.0, timeline.totalSeconds, 0.0)
        assertEquals(2, timeline.workCount)
        assertEquals(2, timeline.finishedCount)
        assertEquals(1, timeline.buckets[0].finishedCount)
        assertEquals(1, timeline.buckets[2].finishedCount)
        assertEquals("Doctor Who", timeline.topFandom?.name)
        assertEquals("Long Epic", timeline.longestFinishedWork?.title)
        assertEquals(ReadingHistoryTimeline.TimeOfDay.Night, timeline.favoriteTimeOfDay)
        assertEquals(
            "2026: 3 hours, most in March (2 hours), 2 works finished",
            timeline.chartSummary("2026", utc, Locale.US)
        )
    }

    @Test
    fun futureDaysAreExcludedFromAverageAndMarkedFuture() {
        // Wednesday 2026-04-15 in Monday-first week Apr 13..Apr 19: 3 elapsed days, 4 future days.
        val now = Instant.parse("2026-04-15T12:00:00Z")
        val facts = listOf(
            fact("w1", "2026-04-13T18:00:00Z", minutes = 30.0),
            fact("w1", "2026-04-15T10:00:00Z", minutes = 60.0)
        )

        val timeline = ReadingHistoryTimeline.make(
            scope = ReadingHistoryScope.Week,
            reference = now,
            facts = facts,
            now = now,
            zone = utc,
            weekFields = mondayWeeks
        )

        assertEquals(3, timeline.buckets.count { !it.isFuture })
        assertEquals(4, timeline.buckets.count { it.isFuture })
        // 90 minutes across 3 elapsed days = 30 minutes per elapsed day.
        assertEquals(30 * 60.0, timeline.averageBucketSeconds, 0.001)
        assertEquals(
            "This week: 1 hour 30 minutes, most on Wednesday",
            timeline.chartSummary("This week", utc, Locale.US)
        )
    }

    @Test
    fun chapterSpanMapsProgressToOneBasedInclusiveRange() {
        assertNull(ReadingHistoryTimeline.ChapterSpan.make(total = 0, start = 0.0, end = 0.5, finished = false))

        val firstThree = ReadingHistoryTimeline.ChapterSpan.make(
            total = 10,
            start = 0.0,
            end = 0.3,
            finished = false
        )!!
        assertEquals(1, firstThree.first)
        assertEquals(3, firstThree.last)
        assertEquals(0, firstThree.readBefore)
        assertEquals(3, firstThree.readNow)
        assertEquals(7, firstThree.toCome)
        assertEquals("Ch. 1–3", firstThree.label)
        assertEquals("chapters 1 to 3 of 10", firstThree.accessibilityLabel)

        val withinFourth = ReadingHistoryTimeline.ChapterSpan.make(
            total = 10,
            start = 0.3,
            end = 0.35,
            finished = false
        )!!
        assertEquals(4, withinFourth.first)
        assertEquals(4, withinFourth.last)
        assertEquals(3, withinFourth.readBefore)
        assertEquals(1, withinFourth.readNow)
        assertEquals(6, withinFourth.toCome)
        assertEquals("Ch. 4", withinFourth.label)
        assertEquals("chapter 4 of 10", withinFourth.accessibilityLabel)

        val fourthToEighth = ReadingHistoryTimeline.ChapterSpan.make(
            total = 10,
            start = 0.35,
            end = 0.8,
            finished = false
        )!!
        assertEquals(4, fourthToEighth.first)
        assertEquals(8, fourthToEighth.last)

        val finishedAtEnd = ReadingHistoryTimeline.ChapterSpan.make(
            total = 10,
            start = 0.8,
            end = 0.91,
            finished = true
        )!!
        assertEquals(9, finishedAtEnd.first)
        assertEquals(10, finishedAtEnd.last)
        assertEquals(0, finishedAtEnd.toCome)
    }

    @Test
    fun rereadsResetStartingProgressAndIncrementReadThrough() {
        val now = Instant.parse("2026-04-15T18:00:00Z")
        val facts = listOf(
            ReadingSessionFacts(
                sessionID = "s1",
                workID = "w1",
                title = "Beloved Fic",
                startedAt = Instant.parse("2026-04-13T18:00:00Z"),
                durationSeconds = 1800.0,
                wordCount = 20_000,
                didFinish = false,
                endingProgress = 0.5,
                chapterCount = 4
            ),
            ReadingSessionFacts(
                sessionID = "s2",
                workID = "w1",
                title = "Beloved Fic",
                startedAt = Instant.parse("2026-04-14T18:00:00Z"),
                durationSeconds = 1800.0,
                wordCount = 20_000,
                didFinish = true,
                endingProgress = 1.0,
                chapterCount = 4
            ),
            ReadingSessionFacts(
                sessionID = "s3",
                workID = "w1",
                title = "Beloved Fic",
                startedAt = Instant.parse("2026-04-15T12:00:00Z"),
                durationSeconds = 900.0,
                wordCount = 20_000,
                didFinish = false,
                endingProgress = 0.25,
                chapterCount = 4
            )
        )

        val starts = ReadingInsights.startingProgress(facts)
        assertEquals(listOf(0.0, 0.5, 0.0), starts)

        val timeline = ReadingHistoryTimeline.make(
            scope = ReadingHistoryScope.Week,
            reference = now,
            facts = facts,
            now = now,
            zone = utc,
            weekFields = mondayWeeks
        )

        val sittingsNewestFirst = timeline.days.flatMap { it.sittings }
        assertEquals(listOf("s3", "s2", "s1"), sittingsNewestFirst.map { it.id })

        val firstSitting = sittingsNewestFirst[2]
        assertTrue(firstSitting.isFirstForWork)
        assertEquals(ReadingHistoryTimeline.Badge.Started, firstSitting.badge)
        assertEquals(1, firstSitting.readThrough)
        assertEquals("Ch. 1–2 · 30 min · 50% through", firstSitting.detailLine)

        val finishSitting = sittingsNewestFirst[1]
        assertFalse(finishSitting.isFirstForWork)
        assertEquals(ReadingHistoryTimeline.Badge.Finished, finishSitting.badge)
        assertEquals(1, finishSitting.readThrough)
        assertEquals("Ch. 3–4 · 30 min", finishSitting.detailLine)

        val rereadSitting = sittingsNewestFirst[0]
        assertFalse(rereadSitting.isFirstForWork)
        assertNull(rereadSitting.badge)
        assertEquals(2, rereadSitting.readThrough)
        assertEquals(0.0, rereadSitting.startingProgress, 0.0)
        assertEquals(1, rereadSitting.chapters?.first)
        assertEquals(1, rereadSitting.chapters?.last)
        assertEquals("Ch. 1 · 15 min · 25% through · 2nd read", rereadSitting.detailLine)
    }

    @Test
    fun unrecordedWorkIDsListsShelfWorksWithoutPersistableSessions() {
        val now = Instant.parse("2026-04-15T12:00:00Z")
        val facts = listOf(
            fact("recorded", "2026-04-15T10:00:00Z", minutes = 20.0),
            ReadingSessionFacts(
                workID = "brief",
                startedAt = Instant.parse("2026-04-15T11:00:00Z"),
                durationSeconds = 10.0,
                wordCount = 5_000,
                didFinish = false
            )
        )

        val timeline = ReadingHistoryTimeline.make(
            scope = ReadingHistoryScope.Week,
            reference = now,
            facts = facts,
            shelfWorkIDs = listOf("recorded", "untimed", "brief"),
            now = now,
            zone = utc,
            weekFields = mondayWeeks
        )

        assertEquals(listOf("untimed", "brief"), timeline.unrecordedWorkIDs)
    }

    private fun fact(
        workID: String,
        startedAt: String,
        minutes: Double,
        didFinish: Boolean = false
    ) = ReadingSessionFacts(
        workID = workID,
        startedAt = Instant.parse(startedAt),
        durationSeconds = minutes * 60.0,
        wordCount = 10_000,
        didFinish = didFinish
    )
}
