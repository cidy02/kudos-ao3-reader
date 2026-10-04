package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.entity.ReadingSessionEntity
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/** Local-only shelf totals derived from the Library's [SavedWork] records. */
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
    data class FandomCount(val name: String, val count: Int)

    val completionRate: Double
        get() = if (startedWorks > 0) {
            finishedWorks.toDouble() / startedWorks.toDouble()
        } else {
            0.0
        }

    companion object {
        fun from(
            works: List<SavedWork>,
            now: Instant = Instant.now(),
            zone: ZoneId = ZoneId.systemDefault()
        ): ReadingStatistics {
            val started = works.filter(::hasStarted)
            val finished = works.filter { it.isFinished }

            val startOfToday = ZonedDateTime.ofInstant(now, zone).toLocalDate()
            val sevenDayStart = startOfDay(startOfToday.minusDays(6), zone)
            val thirtyDayStart = startOfDay(startOfToday.minusDays(29), zone)

            return ReadingStatistics(
                totalWorks = works.size,
                startedWorks = started.size,
                finishedWorks = finished.size,
                inProgressWorks = started.count { !it.isFinished },
                wordsRead = finished.sumOf { maxOf(0, it.wordCount) },
                openedLast7Days = countOpened(works, sevenDayStart, now),
                openedLast30Days = countOpened(works, thirtyDayStart, now),
                latestReadDate = works.mapNotNull { it.lastReadDate }.maxOrNull(),
                topFandoms = fandomCounts(started)
            )
        }

        /** Finished counts as started even if its progress fields were cleared. */
        fun hasStarted(work: SavedWork): Boolean = work.isFinished || work.hasStartedReading

        private fun countOpened(
            works: List<SavedWork>,
            since: Instant,
            through: Instant
        ): Int = works.count { work ->
            val date = work.lastReadDate ?: return@count false
            !date.isBefore(since) && !date.isAfter(through)
        }

        private fun fandomCounts(works: List<SavedWork>): List<FandomCount> {
            val counts = mutableMapOf<String, Int>()
            for (work in works) {
                val uniqueFandoms = work.workFandoms
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                    .toSet()
                for (fandom in uniqueFandoms) {
                    counts[fandom] = (counts[fandom] ?: 0) + 1
                }
            }
            return counts.map { (name, count) -> FandomCount(name, count) }
                .sortedWith(
                    compareByDescending<FandomCount> { it.count }
                        .thenBy(String.CASE_INSENSITIVE_ORDER) { it.name }
                )
        }

        private fun startOfDay(date: LocalDate, zone: ZoneId): Instant =
            date.atStartOfDay(zone).toInstant()
    }
}

enum class ReadingInsightsPeriod(val title: String) {
    Month("This month"),
    Year("This year")
}

/** One stored session reduced to the fields used by Reading Insights. */
data class ReadingSessionFacts(
    val workID: String,
    val startedAt: Instant,
    val durationSeconds: Double,
    val wordCount: Int,
    val didFinish: Boolean,
    val fandom: String = ""
)

/** iOS Reading Insights' session-derived figures. */
data class ReadingInsights(
    val totalSeconds: Double = 0.0,
    val previousPeriodSeconds: Double? = null,
    val weeklySeconds: List<WeeklyBucket> = emptyList(),
    val byFandom: List<FandomShare> = emptyList(),
    val medianSessionSeconds: Double = 0.0,
    val wordsPerHour: Double = 0.0,
    val finishRate: Double? = null,
    val longestStreakDays: Int = 0
) {
    data class WeeklyBucket(val weekStart: Instant, val seconds: Double)

    data class FandomShare(
        val name: String,
        val seconds: Double,
        val isRemainder: Boolean = false
    )

    companion object {
        const val minimumPersistableDurationSeconds = 15
        const val namedFandomLimit = 3
        const val remainderName = "Everything else"

        fun from(
            sessions: List<ReadingSessionEntity>,
            works: List<SavedWork>,
            period: ReadingInsightsPeriod,
            now: Instant = Instant.now(),
            zone: ZoneId = ZoneId.systemDefault()
        ): ReadingInsights {
            val facts = facts(sessions, works)
            val window = periodWindow(period, now, zone)
            val current = facts.filter { it.startedAt >= window.start && it.startedAt < window.end }
            val previous = facts.filter {
                it.startedAt >= window.previousStart && it.startedAt < window.start
            }
            val chartStart = minOf(now.atZone(zone).minusWeeks(6).toInstant(), window.start)
            val chartEnd = maxOf(now, window.end)
            val chartFacts = facts.filter { it.startedAt >= chartStart && it.startedAt < chartEnd }

            return make(current, previous, zone).copy(
                weeklySeconds = weeklyBuckets(chartFacts, zone)
            )
        }

        fun facts(
            sessions: List<ReadingSessionEntity>,
            works: List<SavedWork>
        ): List<ReadingSessionFacts> {
            val worksByID = works.associateBy { it.id }
            return sessions.map { session ->
                ReadingSessionFacts(
                    workID = session.workID,
                    startedAt = session.startedAt,
                    durationSeconds = session.durationSeconds,
                    wordCount = session.wordCount,
                    didFinish = session.didFinish,
                    fandom = worksByID[session.workID]?.workFandoms
                        ?.firstOrNull { it.isNotEmpty() }
                        .orEmpty()
                )
            }
        }

        fun make(
            facts: List<ReadingSessionFacts>,
            previousPeriodFacts: List<ReadingSessionFacts> = emptyList(),
            zone: ZoneId = ZoneId.systemDefault()
        ): ReadingInsights = ReadingInsights(
            totalSeconds = facts.sumOf { it.durationSeconds },
            previousPeriodSeconds = previousPeriodFacts.takeIf { it.isNotEmpty() }
                ?.sumOf { it.durationSeconds },
            weeklySeconds = weeklyBuckets(facts, zone),
            byFandom = fandomShares(facts),
            medianSessionSeconds = medianSeconds(facts),
            wordsPerHour = wordsPerHour(facts),
            finishRate = finishRate(facts),
            longestStreakDays = longestStreak(facts, zone)
        )

        fun weeklyBuckets(
            facts: List<ReadingSessionFacts>,
            zone: ZoneId
        ): List<WeeklyBucket> {
            val firstDay = WeekFields.of(Locale.getDefault()).firstDayOfWeek
            return facts.groupBy { fact ->
                fact.startedAt.atZone(zone).toLocalDate()
                    .with(TemporalAdjusters.previousOrSame(firstDay))
                    .atStartOfDay(zone)
                    .toInstant()
            }.map { (weekStart, rows) ->
                WeeklyBucket(weekStart, rows.sumOf { it.durationSeconds })
            }.sortedBy { it.weekStart }
        }

        fun fandomShares(facts: List<ReadingSessionFacts>): List<FandomShare> {
            val seconds = mutableMapOf<String, Double>()
            var unattributed = 0.0
            for (fact in facts) {
                if (fact.fandom.isEmpty()) {
                    unattributed += fact.durationSeconds
                } else {
                    seconds[fact.fandom] = (seconds[fact.fandom] ?: 0.0) + fact.durationSeconds
                }
            }
            val ranked = seconds.entries.sortedWith(
                compareByDescending<Map.Entry<String, Double>> { it.value }.thenBy { it.key }
            )
            val shares = ranked.take(namedFandomLimit).map { FandomShare(it.key, it.value) }
                .toMutableList()
            val remainder = ranked.drop(namedFandomLimit).sumOf { it.value } + unattributed
            if (remainder > 0) shares += FandomShare(remainderName, remainder, true)
            return shares
        }

        fun medianSeconds(facts: List<ReadingSessionFacts>): Double {
            val durations = facts.map { it.durationSeconds }.filter { it > 0 }.sorted()
            if (durations.isEmpty()) return 0.0
            val middle = durations.size / 2
            return if (durations.size % 2 == 0) {
                (durations[middle - 1] + durations[middle]) / 2
            } else {
                durations[middle]
            }
        }

        fun wordsPerHour(facts: List<ReadingSessionFacts>): Double {
            val usable = facts.filter { it.durationSeconds > 0 }
            val totalSeconds = usable.sumOf { it.durationSeconds }
            if (totalSeconds <= 0) return 0.0
            return usable.sumOf { it.wordCount }.toDouble() / (totalSeconds / 3_600)
        }

        fun finishRate(facts: List<ReadingSessionFacts>): Double? {
            val startedWorkIDs = facts.map { it.workID }.toSet()
            if (startedWorkIDs.isEmpty()) return null
            val finishedWorkIDs = facts.filter { it.didFinish }.map { it.workID }.toSet()
            return finishedWorkIDs.size.toDouble() / startedWorkIDs.size.toDouble()
        }

        fun longestStreak(
            facts: List<ReadingSessionFacts>,
            zone: ZoneId
        ): Int {
            val days = facts.map { it.startedAt.atZone(zone).toLocalDate() }.toSortedSet()
            if (days.isEmpty()) return 0
            var longest = 1
            var current = 1
            days.zipWithNext().forEach { (previous, day) ->
                if (previous.plusDays(1) == day) {
                    current += 1
                    longest = maxOf(longest, current)
                } else {
                    current = 1
                }
            }
            return longest
        }

        fun hoursLabel(seconds: Double): String =
            String.format(Locale.US, "%.1f", maxOf(0.0, seconds) / 3_600)

        fun signedHoursLabel(deltaSeconds: Double): String {
            val hours = deltaSeconds / 3_600
            return (if (hours < 0) "−" else "+") +
                String.format(Locale.US, "%.1f", abs(hours))
        }

        fun durationLabel(seconds: Double): String {
            val totalMinutes = (maxOf(0.0, seconds) / 60).roundToInt()
            if (totalMinutes < 60) return "$totalMinutes min"
            val hours = totalMinutes / 60
            val minutes = totalMinutes % 60
            return if (minutes == 0) "${hours}h" else "${hours}h ${minutes}m"
        }

        private fun periodWindow(
            period: ReadingInsightsPeriod,
            now: Instant,
            zone: ZoneId
        ): PeriodWindow {
            val today = now.atZone(zone).toLocalDate()
            val startDate = when (period) {
                ReadingInsightsPeriod.Month -> today.withDayOfMonth(1)
                ReadingInsightsPeriod.Year -> today.withDayOfYear(1)
            }
            val endDate = when (period) {
                ReadingInsightsPeriod.Month -> startDate.plusMonths(1)
                ReadingInsightsPeriod.Year -> startDate.plusYears(1)
            }
            val previousDate = when (period) {
                ReadingInsightsPeriod.Month -> startDate.minusMonths(1)
                ReadingInsightsPeriod.Year -> startDate.minusYears(1)
            }
            return PeriodWindow(
                start = startDate.atStartOfDay(zone).toInstant(),
                end = endDate.atStartOfDay(zone).toInstant(),
                previousStart = previousDate.atStartOfDay(zone).toInstant()
            )
        }

        private data class PeriodWindow(
            val start: Instant,
            val end: Instant,
            val previousStart: Instant
        )
    }
}
