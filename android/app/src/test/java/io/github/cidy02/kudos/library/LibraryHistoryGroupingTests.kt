package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale
import org.junit.Assert.*
import org.junit.Test

/** Swift LibraryHistoryGroupingTests, ported by name, with explicit clock/calendar inputs. */
class LibraryHistoryGroupingTests {
    private val now = Instant.ofEpochSecond(1_800_000_000)
    private val zone = ZoneId.of("UTC")
    private val weeks = WeekFields.of(Locale.US)

    private fun work(title: String, lastRead: Instant? = null, finished: Boolean = false,
        hasEPUB: Boolean = true, started: Boolean = false, fandoms: List<String> = emptyList()
    ) = SavedWork(id = title, title = title, author = "A", lastReadDate = lastRead,
        isFinished = finished, hasEpub = hasEPUB, lastSpineIndex = if (started) 2 else 0,
        workFandoms = fandoms)

    private fun groups(grouping: LibraryHistoryGrouping, works: List<SavedWork>,
        isAbandoned: (SavedWork) -> Boolean = { false }
    ) = LibraryHistoryGrouping.groups(grouping, works, now, zone, weeks, isAbandoned)

    private fun titles(grouping: LibraryHistoryGrouping, works: List<SavedWork>) =
        groups(grouping, works).map { it.title }

    @Test fun timeBucketsKeepTheirSourceOrderRatherThanSortingBySize() {
        assertEquals(listOf("Today", "Earlier"), titles(LibraryHistoryGrouping.Time, listOf(
            work("Today", now), work("Old 1", now.minusSeconds(200 * 86_400L)),
            work("Old 2", now.minusSeconds(300 * 86_400L)), work("Old 3", now.minusSeconds(400 * 86_400L)))))
    }

    @Test fun aWorkNeverOpenedIsItsOwnBucketNotTheOldestOne() {
        assertEquals(listOf("Earlier", "Never opened"), titles(LibraryHistoryGrouping.Time,
            listOf(work("Old", now.minusSeconds(400 * 86_400L)), work("Never"))))
    }

    @Test fun yesterdayIsMeasuredFromNowRatherThanTheWallClock() {
        assertEquals(listOf("Yesterday"), titles(LibraryHistoryGrouping.Time, listOf(work("Yesterday", now.minusSeconds(86_400)))))
    }

    @Test fun emptyBucketsAreDroppedRatherThanDrawnEmpty() {
        assertEquals(listOf("Today"), titles(LibraryHistoryGrouping.Time, listOf(work("Today", now))))
    }

    @Test fun aFreedFileThatWasNeverFinishedIsReadNotFinished() {
        assertEquals(listOf("Read, not finished"), titles(LibraryHistoryGrouping.State,
            listOf(work("Freed", now, hasEPUB = false, started = true))))
    }

    @Test fun abandonedWinsOverInProgressSoNoWorkIsCountedTwice() {
        val buckets = groups(LibraryHistoryGrouping.State,
            listOf(work("Stalled", now, started = true), work("Active", now, started = true))) { it.title == "Stalled" }
        assertEquals(listOf("In progress", "Abandoned"), buckets.map { it.title })
        assertEquals(2, buckets.flatMap { it.workIds }.size)
        assertEquals(2, buckets.flatMap { it.workIds }.toSet().size)
    }

    @Test fun stateTallyCountsInProgressAndAbandonedAndDropsZeros() {
        val stalled = work("Stalled", now, started = true)
        val active1 = work("Active1", now, started = true)
        val active2 = work("Active2", now, started = true)
        val done = work("Done", now, finished = true)
        val buckets = groups(LibraryHistoryGrouping.State, listOf(stalled, active1, active2, done)) { it.title == "Stalled" }
        assertEquals("4 works · 2 in progress · 1 abandoned", LibraryHistoryGrouping.tallyLine(4, LibraryHistoryGrouping.State, buckets))
        assertEquals("2 works · 1 in progress", LibraryHistoryGrouping.tallyLine(2, LibraryHistoryGrouping.State,
            groups(LibraryHistoryGrouping.State, listOf(active1, done))))
        assertEquals("1 work", LibraryHistoryGrouping.tallyLine(1, LibraryHistoryGrouping.State,
            groups(LibraryHistoryGrouping.State, listOf(done))))
    }

    @Test fun timeTallySaysTheOrderAndFandomSaysOnlyTheCount() {
        assertEquals("1 work · most recently read first", LibraryHistoryGrouping.tallyLine(1, LibraryHistoryGrouping.Time, emptyList()))
        assertEquals("6 works", LibraryHistoryGrouping.tallyLine(6, LibraryHistoryGrouping.Fandom, emptyList()))
        assertEquals("6 works · most recently read first", LibraryHistoryGrouping.tallyLine(6, LibraryHistoryGrouping.Flat, emptyList()))
    }

    @Test fun finishedWinsOverEverythingIncludingAFreedFile() {
        assertEquals(listOf("Finished"), titles(LibraryHistoryGrouping.State,
            listOf(work("Done", now, finished = true, hasEPUB = false))))
    }

    @Test fun fandomGroupsRankBySizeBecauseTheyHaveNoNaturalOrder() {
        assertEquals(listOf("Naruto", "Dracula", "No fandom"), titles(LibraryHistoryGrouping.Fandom,
            listOf(work("A", fandoms = listOf("Naruto")), work("B", fandoms = listOf("Naruto")),
                work("C", fandoms = listOf("Dracula")), work("D"))))
    }

    @Test fun everyWorkLandsInExactlyOneBucketUnderEveryGrouping() {
        val works = listOf(work("A", now, finished = true), work("B", now.minusSeconds(400 * 86_400L), hasEPUB = false, started = true),
            work("C", fandoms = listOf("Naruto")), work("D", now, started = true))
        for (grouping in LibraryHistoryGrouping.entries) {
            val ids = groups(grouping, works).flatMap { it.workIds }
            assertEquals(grouping.title, works.size, ids.size)
            assertEquals(grouping.title, works.size, ids.toSet().size)
        }
    }

    @Test fun flatIsOneBucketAndEmptyInputIsNoBuckets() {
        assertEquals(listOf("All"), titles(LibraryHistoryGrouping.Flat, listOf(work("A"), work("B"))))
        LibraryHistoryGrouping.entries.forEach { assertTrue(groups(it, emptyList()).isEmpty()) }
    }

    @Test fun fandomUsesFirstNonemptyFamilyAndPreservesRowOrder() {
        val works = listOf(work("B", fandoms = listOf("", "Doctor Who (2005)", "Naruto")), work("A", fandoms = listOf("Doctor Who")))
        assertEquals(listOf(LibraryHistoryGrouping.Bucket("Doctor Who", listOf("B", "A"))), groups(LibraryHistoryGrouping.Fandom, works))
    }

    @Test fun allFiveStatesHaveFixedOrder() {
        val works = listOf(work("Unread"), work("Done", finished = true), work("Freed", hasEPUB = false),
            work("Stalled", now, started = true), work("Active", now, started = true))
        assertEquals(listOf("In progress", "Abandoned", "Read, not finished", "Finished", "Not started"),
            groups(LibraryHistoryGrouping.State, works) { it.title == "Stalled" }.map { it.title })
    }

    @Test fun timeBucketsUseCalendarBoundariesAndSuppliedWeekStart() {
        val clock = Instant.parse("2026-10-08T12:00:00Z")
        fun bucket(date: String) = LibraryHistoryGrouping.TimeBucket.bucket(Instant.parse(date), clock, zone, weeks)
        assertEquals(LibraryHistoryGrouping.TimeBucket.Today, bucket("2026-10-08T00:00:00Z"))
        assertEquals(LibraryHistoryGrouping.TimeBucket.Yesterday, bucket("2026-10-07T23:59:59Z"))
        assertEquals(LibraryHistoryGrouping.TimeBucket.ThisWeek, bucket("2026-10-04T00:00:00Z"))
        assertEquals(LibraryHistoryGrouping.TimeBucket.ThisMonth, bucket("2026-10-03T23:59:59Z"))
        assertEquals(LibraryHistoryGrouping.TimeBucket.Earlier, bucket("2026-09-30T23:59:59Z"))
        val monday = WeekFields.ISO
        assertEquals(LibraryHistoryGrouping.TimeBucket.ThisMonth,
            LibraryHistoryGrouping.TimeBucket.bucket(Instant.parse("2026-10-04T12:00:00Z"), clock, zone, monday))
        val dstZone = ZoneId.of("America/New_York")
        assertEquals(LibraryHistoryGrouping.TimeBucket.Yesterday, LibraryHistoryGrouping.TimeBucket.bucket(
            Instant.parse("2026-03-08T05:00:00Z"), Instant.parse("2026-03-09T04:00:00Z"), dstZone, weeks))
        assertEquals(LibraryHistoryGrouping.TimeBucket.Yesterday, LibraryHistoryGrouping.TimeBucket.bucket(
            Instant.parse("2011-12-29T12:00:00Z"), Instant.parse("2011-12-30T12:00:00Z"), ZoneId.of("Pacific/Apia"), weeks))
    }

    /** Swift ReadingLogTests.abandonedIsDerivedAndOverrideSticks. */
    @Test fun abandonedIsDerivedAndOverrideSticks() {
        val dusty = work("Dusty", now.minusSeconds(30 * 86_400L)).copy(readiumLocator = locator(0.4))
        assertTrue(ReadingAbandonment.isAbandoned(dusty, now))
        assertFalse(ReadingAbandonment.isAbandoned(dusty.copy(keepInProgressOverride = true), now))
        assertFalse(ReadingAbandonment.isAbandoned(dusty.copy(readiumLocator = locator(0.02)), now))
        assertFalse(ReadingAbandonment.isAbandoned(dusty.copy(lastReadDate = now.minusSeconds(2 * 86_400L)), now))
        assertFalse(ReadingAbandonment.isAbandoned(dusty.copy(isFinished = true), now))
    }

    @Test fun abandonmentExcludesThresholdEndpointsMissingDateFileAndProgress() {
        val dusty = work("Dusty", now.minusSeconds(30 * 86_400L)).copy(legacyReaderProgress = 0.4)
        assertEquals(Duration.ofDays(21), ReadingAbandonment.DefaultThreshold)
        for (progress in listOf(0.0, 0.05, 0.95, 1.0)) {
            assertFalse(ReadingAbandonment.isAbandoned(dusty.copy(legacyReaderProgress = progress), now))
        }
        assertFalse(ReadingAbandonment.isAbandoned(dusty.copy(lastReadDate = now.minus(Duration.ofDays(21))), now))
        assertTrue(ReadingAbandonment.isAbandoned(dusty.copy(lastReadDate = now.minus(Duration.ofDays(21)).minusNanos(1)), now))
        assertFalse(ReadingAbandonment.isAbandoned(dusty.copy(hasEpub = false), now))
        assertFalse(ReadingAbandonment.isAbandoned(dusty.copy(lastReadDate = null, lastSpineIndex = 1), now))
        assertFalse(ReadingAbandonment.isAbandoned(dusty.copy(legacyReaderProgress = null), now))
        assertFalse(ReadingAbandonment.isAbandoned(work("Unread"), now))
        assertFalse(ReadingAbandonment.isAbandoned(dusty.copy(lastReadDate = now.plusSeconds(1)), now))
    }

    private fun locator(progress: Double) = """{"locations":{"totalProgression":$progress}}"""
}
