package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Local-only reading insights derived from the Library's [SavedWork] records.
 *
 * The app does not track sessions or per-word progress, so "words read" counts
 * only finished works whose AO3 word count is known (non-negative; unknown → 0).
 *
 * Mirrors Apple `ReadingStatistics`.
 */
data class ReadingStatistics(
    val totalWorks: Int,
    val startedWorks: Int,
    val finishedWorks: Int,
    val inProgressWorks: Int,
    val wordsRead: Int,
    val openedLast7Days: Int,
    val openedLast30Days: Int,
    val latestReadDate: Instant?,
    val topFandoms: List<FandomCount>
) {
    data class FandomCount(
        val name: String,
        val count: Int
    )

    /** Finished / started; 0 when nothing has been started. */
    val completionRate: Double
        get() = if (startedWorks > 0) {
            finishedWorks.toDouble() / startedWorks.toDouble()
        } else {
            0.0
        }

    companion object {
        /**
         * Compute statistics from library works.
         *
         * @param works All saved (non-deleted) works.
         * @param now Reference instant (tests inject a fixed clock).
         * @param zone Calendar zone for day-window boundaries (defaults to system).
         */
        fun from(
            works: List<SavedWork>,
            now: Instant = Instant.now(),
            zone: ZoneId = ZoneId.systemDefault()
        ): ReadingStatistics {
            val started = works.filter { hasStarted(it) }
            val finished = works.filter { it.isFinished }
            val inProgress = started.filter { !it.isFinished }

            val wordsRead = finished.sumOf { work -> maxOf(0, work.wordCount) }
            val latestReadDate = works.mapNotNull { it.lastReadDate }.maxOrNull()

            val zonedNow = ZonedDateTime.ofInstant(now, zone)
            val startOfToday = zonedNow.toLocalDate()
            // Inclusive windows ending at `now`: past 7 calendar days = today + 6 prior.
            val sevenDayStart = startOfDay(startOfToday.minusDays(6), zone)
            val thirtyDayStart = startOfDay(startOfToday.minusDays(29), zone)

            return ReadingStatistics(
                totalWorks = works.size,
                startedWorks = started.size,
                finishedWorks = finished.size,
                inProgressWorks = inProgress.size,
                wordsRead = wordsRead,
                openedLast7Days = countOpened(works, since = sevenDayStart, through = now),
                openedLast30Days = countOpened(works, since = thirtyDayStart, through = now),
                latestReadDate = latestReadDate,
                topFandoms = fandomCounts(started)
            )
        }

        /**
         * A work counts as started if the user finished it, opened it, or has
         * non-zero progress. Matches Apple `ReadingStatistics.hasStarted`.
         */
        fun hasStarted(work: SavedWork): Boolean {
            return work.isFinished ||
                work.lastReadDate != null ||
                work.lastSpineIndex > 0 ||
                work.lastScrollFraction > 0.0
        }

        private fun countOpened(
            works: List<SavedWork>,
            since: Instant,
            through: Instant
        ): Int {
            return works.count { work ->
                val date = work.lastReadDate ?: return@count false
                !date.isBefore(since) && !date.isAfter(through)
            }
        }

        /**
         * Count each distinct fandom once per started work; sort by count desc,
         * then name case-insensitive ascending.
         */
        private fun fandomCounts(works: List<SavedWork>): List<FandomCount> {
            val counts = linkedMapOf<String, Int>()
            for (work in works) {
                val unique = work.workFandoms
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                    .toSet()
                for (fandom in unique) {
                    counts[fandom] = (counts[fandom] ?: 0) + 1
                }
            }
            return counts.entries
                .map { (name, count) -> FandomCount(name = name, count = count) }
                .sortedWith(
                    compareByDescending<FandomCount> { it.count }
                        .thenBy(String.CASE_INSENSITIVE_ORDER) { it.name }
                )
        }

        private fun startOfDay(date: LocalDate, zone: ZoneId): Instant {
            return date.atStartOfDay(zone).toInstant()
        }
    }
}
