package io.github.cidy02.kudos.library

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.TextStyle
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.EnumMap
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt

/** Scope of the Reading History timeline (`Week`, `Month`, `Year`). */
enum class ReadingHistoryScope(val id: String, val title: String) {
    Week("week", "Week"),
    Month("month", "Month"),
    Year("year", "Year")
}

/**
 * Pure session-derived Reading History timeline (port of iOS `ReadingHistoryTimeline`, T-462).
 *
 * A sitting belongs whole to the calendar day it started (`startedAt` in [zone]), matching
 * [ReadingInsights.weeklyBuckets]. No new tracking or persistence is introduced.
 */
data class ReadingHistoryTimeline(
    val scope: ReadingHistoryScope,
    val period: Period,
    val isCurrent: Boolean,
    val totalSeconds: Double,
    val workCount: Int,
    val finishedCount: Int,
    val streakDays: Int,
    val longestStreakDays: Int,
    val buckets: List<Bucket>,
    val days: List<Day>,
    val topWorks: List<WorkTime>,
    val topFandom: ReadingInsights.FandomShare?,
    val longestFinishedWork: ReadingSessionFacts?,
    val favoriteTimeOfDay: TimeOfDay?,
    /** Shelf works that have no persistable reading session at all. */
    val unrecordedWorkIDs: List<String>
) {
    /** Half-open `[start, end)` window in the reader's calendar. */
    data class Period(val start: Instant, val end: Instant)

    /** One chart column or calendar cell: a day in Week/Month, a month in Year. */
    data class Bucket(
        val start: Instant,
        val seconds: Double,
        val finishedCount: Int,
        val isFuture: Boolean
    ) {
        val id: Instant get() = start
    }

    /** A calendar day with at least one sitting in [period], newest day first. */
    data class Day(
        val start: Instant,
        val totalSeconds: Double,
        val sittings: List<Sitting>
    ) {
        val id: Instant get() = start
    }

    /** One reading sitting on the day's vertical time rail, newest first within the day. */
    data class Sitting(
        val id: String,
        val workID: String,
        val title: String,
        val fandom: String,
        val startedAt: Instant,
        val durationSeconds: Double,
        val startingProgress: Double,
        val endingProgress: Double,
        val chapters: ChapterSpan?,
        val didFinish: Boolean,
        val isFirstForWork: Boolean,
        /** `1` on the first read, `2` after one finished read, etc. */
        val readThrough: Int
    ) {
        val badge: Badge?
            get() = when {
                didFinish -> Badge.Finished
                isFirstForWork -> Badge.Started
                else -> null
            }

        val detailLine: String
            get() {
                val parts = mutableListOf<String>()
                chapters?.let { parts += it.label }
                parts += ReadingInsights.durationLabel(durationSeconds)
                if (!didFinish && endingProgress > 0.0) {
                    val percent = (minOf(1.0, endingProgress) * 100.0).roundToInt()
                    parts += "$percent% through"
                }
                if (readThrough > 1) {
                    parts += "${ordinal(readThrough)} read"
                }
                return parts.joinToString(" · ")
            }
    }

    /**
     * 1-based inclusive chapter range `[first, last]` out of [total] chapters,
     * derived from the sitting's `[start, end]` progress fractions.
     */
    data class ChapterSpan(
        val total: Int,
        val first: Int,
        val last: Int
    ) {
        val readBefore: Int get() = maxOf(0, first - 1)
        val readNow: Int get() = maxOf(1, last - first + 1)
        val toCome: Int get() = maxOf(0, total - last)

        val label: String
            get() = if (first == last) "Ch. $first" else "Ch. $first–$last"

        val accessibilityLabel: String
            get() {
                val range = if (first == last) "chapter $first" else "chapters $first to $last"
                return "$range of $total"
            }

        companion object {
            fun make(
                total: Int,
                start: Double,
                end: Double,
                finished: Boolean
            ): ChapterSpan? {
                if (total <= 0) return null
                val count = total.toDouble()
                val before = floor(start.coerceIn(0.0, 1.0) * count + 1e-9).toInt()
                val first = minOf(total, before + 1)
                val reached = if (finished) {
                    total
                } else {
                    minOf(total, maxOf(1, ceil(end.coerceIn(0.0, 1.0) * count - 1e-9).toInt()))
                }
                return ChapterSpan(total = total, first = first, last = maxOf(first, reached))
            }
        }
    }

    enum class Badge(val title: String) {
        Finished("Finished"),
        Started("Started")
    }

    /** Per-work total time in the period, for Month's Most Read list. */
    data class WorkTime(
        val workID: String,
        val title: String,
        val fandom: String,
        val seconds: Double,
        val sittings: Int,
        val didFinish: Boolean
    ) {
        val id: String get() = workID
    }

    enum class TimeOfDay(val title: String, val hours: String) {
        Morning("Morning", "5am–noon"),
        Afternoon("Afternoon", "noon–5pm"),
        Evening("Evening", "5pm–9pm"),
        Night("Night", "9pm–5am");

        companion object {
            fun bucket(hour: Int): TimeOfDay = when (hour) {
                in 5 until 12 -> Morning
                in 12 until 17 -> Afternoon
                in 17 until 21 -> Evening
                else -> Night
            }
        }
    }

    /** Mean seconds across elapsed (non-future) buckets. */
    val averageBucketSeconds: Double
        get() {
            val elapsed = buckets.filter { !it.isFuture }
            if (elapsed.isEmpty()) return 0.0
            return elapsed.sumOf { it.seconds } / elapsed.size.toDouble()
        }

    /** Bucket with the most reading time; earlier bucket wins ties. */
    val peakBucket: Bucket?
        get() = buckets
            .filter { it.seconds > 0.0 }
            .maxWithOrNull { lhs, rhs ->
                if (lhs.seconds != rhs.seconds) {
                    lhs.seconds.compareTo(rhs.seconds)
                } else {
                    rhs.start.compareTo(lhs.start)
                }
            }

    /** Single-sentence VoiceOver / TalkBack summary of the chart. */
    fun chartSummary(
        periodName: String,
        zone: ZoneId = ZoneId.systemDefault(),
        locale: Locale = Locale.getDefault()
    ): String {
        val peak = peakBucket
        if (totalSeconds <= 0.0 || peak == null) {
            return "$periodName: no reading"
        }
        val total = spokenDuration(totalSeconds)
        return when (scope) {
            ReadingHistoryScope.Week -> {
                val weekday = peak.start.atZone(zone).dayOfWeek.getDisplayName(TextStyle.FULL, locale)
                "$periodName: $total, most on $weekday"
            }
            ReadingHistoryScope.Month -> {
                val daysRead = buckets.count { !it.isFuture && it.seconds > 0.0 }
                val daysElapsed = maxOf(1, buckets.count { !it.isFuture })
                val zdt = peak.start.atZone(zone)
                val day = "${zdt.month.getDisplayName(TextStyle.FULL, locale)} ${zdt.dayOfMonth}"
                "$periodName: $total, read on $daysRead of $daysElapsed days, most on $day (${spokenDuration(peak.seconds)})"
            }
            ReadingHistoryScope.Year -> {
                val month = peak.start.atZone(zone).month.getDisplayName(TextStyle.FULL, locale)
                val works = if (finishedCount == 1) "1 work finished" else "$finishedCount works finished"
                "$periodName: $total, most in $month (${spokenDuration(peak.seconds)}), $works"
            }
        }
    }

    companion object {
        fun make(
            scope: ReadingHistoryScope,
            reference: Instant,
            facts: List<ReadingSessionFacts>,
            shelfWorkIDs: List<String> = emptyList(),
            now: Instant = Instant.now(),
            zone: ZoneId = ZoneId.systemDefault(),
            weekFields: WeekFields = WeekFields.of(Locale.getDefault())
        ): ReadingHistoryTimeline {
            val period = period(scope = scope, containing = reference, zone = zone, weekFields = weekFields)
            val currentPeriod = period(scope = scope, containing = now, zone = zone, weekFields = weekFields)
            val isCurrent = period == currentPeriod

            val usable = facts.filter {
                it.durationSeconds >= ReadingInsights.minimumPersistableDurationSeconds.toDouble()
            }
            val sittingsByID = makeSittings(usable)
            val periodFacts = usable.filter { it.startedAt >= period.start && it.startedAt < period.end }
            val buckets = makeBuckets(scope = scope, period = period, facts = periodFacts, now = now, zone = zone)
            val days = makeDays(facts = usable, period = period, sittingsByID = sittingsByID, zone = zone)

            val streakEnd = if (isCurrent) now else period.end.minusSeconds(1)
            val recordedWorkIDs = usable.map { it.workID }.toSet()
            val unrecorded = shelfWorkIDs.filter { it !in recordedWorkIDs }

            return ReadingHistoryTimeline(
                scope = scope,
                period = period,
                isCurrent = isCurrent,
                totalSeconds = periodFacts.sumOf { it.durationSeconds },
                workCount = periodFacts.map { it.workID }.toSet().size,
                finishedCount = periodFacts.filter { it.didFinish }.map { it.workID }.toSet().size,
                streakDays = streak(through = streakEnd, isToday = isCurrent, facts = usable, zone = zone),
                longestStreakDays = ReadingInsights.longestStreak(periodFacts, zone),
                buckets = buckets,
                days = days,
                topWorks = makeTopWorks(periodFacts),
                topFandom = ReadingInsights.fandomShares(periodFacts).firstOrNull { !it.isRemainder },
                longestFinishedWork = makeLongestFinishedWork(periodFacts),
                favoriteTimeOfDay = makeFavoriteTimeOfDay(periodFacts, zone),
                unrecordedWorkIDs = unrecorded
            )
        }

        fun period(
            scope: ReadingHistoryScope,
            containing: Instant,
            zone: ZoneId = ZoneId.systemDefault(),
            weekFields: WeekFields = WeekFields.of(Locale.getDefault())
        ): Period {
            val date = containing.atZone(zone).toLocalDate()
            val startDate = when (scope) {
                ReadingHistoryScope.Week -> date.with(TemporalAdjusters.previousOrSame(weekFields.firstDayOfWeek))
                ReadingHistoryScope.Month -> date.withDayOfMonth(1)
                ReadingHistoryScope.Year -> date.withDayOfYear(1)
            }
            val endDate = when (scope) {
                ReadingHistoryScope.Week -> startDate.plusWeeks(1)
                ReadingHistoryScope.Month -> startDate.plusMonths(1)
                ReadingHistoryScope.Year -> startDate.plusYears(1)
            }
            return Period(
                start = startDate.atStartOfDay(zone).toInstant(),
                end = endDate.atStartOfDay(zone).toInstant()
            )
        }

        /**
         * Consecutive reading days ending at [through]. When [isToday] is true and today has no
         * reading yet, yesterday's streak is still alive until today ends.
         */
        fun streak(
            through: Instant,
            isToday: Boolean,
            facts: List<ReadingSessionFacts>,
            zone: ZoneId = ZoneId.systemDefault()
        ): Int {
            val readingDays = facts.map { it.startedAt.atZone(zone).toLocalDate() }.toSet()
            if (readingDays.isEmpty()) return 0
            var day = through.atZone(zone).toLocalDate()
            if (isToday && day !in readingDays) {
                day = day.minusDays(1)
            }
            var count = 0
            while (day in readingDays) {
                count += 1
                day = day.minusDays(1)
            }
            return count
        }

        fun spokenDuration(seconds: Double): String {
            val totalMinutes = (maxOf(0.0, seconds) / 60.0).roundToInt()
            val hours = totalMinutes / 60
            val minutes = totalMinutes % 60
            val hourWord = if (hours == 1) "1 hour" else "$hours hours"
            val minuteWord = if (minutes == 1) "1 minute" else "$minutes minutes"
            if (hours == 0) return minuteWord
            if (minutes == 0) return hourWord
            return "$hourWord $minuteWord"
        }

        private fun makeSittings(facts: List<ReadingSessionFacts>): Map<Int, Sitting> {
            val starts = ReadingInsights.startingProgress(facts)
            val orderedIndices = facts.indices.sortedWith { lhs, rhs ->
                ReadingInsights.sittingOrder(facts[lhs], facts[rhs])
            }
            val seenWorks = HashSet<String>()
            val priorFinishesByWork = HashMap<String, Int>()
            val sittings = HashMap<Int, Sitting>(facts.size)
            for (index in orderedIndices) {
                val fact = facts[index]
                val start = starts[index]
                val end = fact.endingProgress.coerceIn(0.0, 1.0)
                val isFirst = seenWorks.add(fact.workID)
                val priorFinishes = priorFinishesByWork[fact.workID] ?: 0
                val chapters = ChapterSpan.make(
                    total = fact.chapterCount,
                    start = start,
                    end = end,
                    finished = fact.didFinish
                )
                sittings[index] = Sitting(
                    id = sittingID(fact, index),
                    workID = fact.workID,
                    title = fact.title,
                    fandom = fact.fandom,
                    startedAt = fact.startedAt,
                    durationSeconds = fact.durationSeconds,
                    startingProgress = start,
                    endingProgress = end,
                    chapters = chapters,
                    didFinish = fact.didFinish,
                    isFirstForWork = isFirst,
                    readThrough = priorFinishes + 1
                )
                if (fact.didFinish) {
                    priorFinishesByWork[fact.workID] = priorFinishes + 1
                }
            }
            return sittings
        }

        private fun sittingID(fact: ReadingSessionFacts, index: Int): String {
            val id = fact.sessionID
            if (!id.isNullOrEmpty()) return id
            return "${fact.workID}-${fact.startedAt.epochSecond}-$index"
        }

        private fun makeBuckets(
            scope: ReadingHistoryScope,
            period: Period,
            facts: List<ReadingSessionFacts>,
            now: Instant,
            zone: ZoneId
        ): List<Bucket> {
            val startDate = period.start.atZone(zone).toLocalDate()
            val endDate = period.end.atZone(zone).toLocalDate()
            val dates = mutableListOf<LocalDate>()
            var cursor = startDate
            while (cursor < endDate) {
                dates += cursor
                val next = if (scope == ReadingHistoryScope.Year) cursor.plusMonths(1) else cursor.plusDays(1)
                if (next <= cursor) break
                cursor = next
            }
            return dates.map { date ->
                val start = date.atStartOfDay(zone).toInstant()
                val nextDate = if (scope == ReadingHistoryScope.Year) date.plusMonths(1) else date.plusDays(1)
                val end = nextDate.atStartOfDay(zone).toInstant()
                val slice = facts.filter { it.startedAt >= start && it.startedAt < end }
                val finished = slice.filter { it.didFinish }.map { it.workID }.toSet().size
                Bucket(
                    start = start,
                    seconds = slice.sumOf { it.durationSeconds },
                    finishedCount = finished,
                    isFuture = start > now
                )
            }
        }

        private fun makeDays(
            facts: List<ReadingSessionFacts>,
            period: Period,
            sittingsByID: Map<Int, Sitting>,
            zone: ZoneId
        ): List<Day> {
            val indicesByDay = HashMap<Instant, MutableList<Int>>()
            for (index in facts.indices) {
                val fact = facts[index]
                if (fact.startedAt < period.start || fact.startedAt >= period.end) continue
                val day = fact.startedAt.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
                indicesByDay.getOrPut(day) { mutableListOf() }.add(index)
            }
            return indicesByDay.keys.sortedDescending().map { day ->
                val indices = indicesByDay[day].orEmpty().sortedWith { lhs, rhs ->
                    ReadingInsights.sittingOrder(facts[rhs], facts[lhs])
                }
                val sittings = indices.mapNotNull { sittingsByID[it] }
                val seconds = sittings.sumOf { it.durationSeconds }
                Day(start = day, totalSeconds = seconds, sittings = sittings)
            }
        }

        private fun makeTopWorks(facts: List<ReadingSessionFacts>): List<WorkTime> {
            return facts.groupBy { it.workID }.map { (workID, rows) ->
                val latest = rows.maxWithOrNull { lhs, rhs -> ReadingInsights.sittingOrder(lhs, rhs) }
                WorkTime(
                    workID = workID,
                    title = latest?.title.orEmpty(),
                    fandom = latest?.fandom.orEmpty(),
                    seconds = rows.sumOf { it.durationSeconds },
                    sittings = rows.size,
                    didFinish = rows.any { it.didFinish }
                )
            }.sortedWith { lhs, rhs ->
                if (lhs.seconds != rhs.seconds) {
                    rhs.seconds.compareTo(lhs.seconds)
                } else {
                    lhs.workID.compareTo(rhs.workID)
                }
            }
        }

        private fun makeLongestFinishedWork(facts: List<ReadingSessionFacts>): ReadingSessionFacts? {
            return facts
                .filter { it.didFinish && it.wordCount > 0 }
                .maxWithOrNull { lhs, rhs ->
                    if (lhs.wordCount != rhs.wordCount) {
                        lhs.wordCount.compareTo(rhs.wordCount)
                    } else {
                        rhs.startedAt.compareTo(lhs.startedAt)
                    }
                }
        }

        private fun makeFavoriteTimeOfDay(
            facts: List<ReadingSessionFacts>,
            zone: ZoneId
        ): TimeOfDay? {
            if (facts.isEmpty()) return null
            val secondsBySlice = EnumMap<TimeOfDay, Double>(TimeOfDay::class.java)
            for (fact in facts) {
                val hour = fact.startedAt.atZone(zone).hour
                val slice = TimeOfDay.bucket(hour)
                secondsBySlice[slice] = (secondsBySlice[slice] ?: 0.0) + fact.durationSeconds
            }
            return TimeOfDay.entries
                .filter { (secondsBySlice[it] ?: 0.0) > 0.0 }
                .maxByOrNull { secondsBySlice[it] ?: 0.0 }
        }

        private fun ordinal(n: Int): String {
            val mod100 = n % 100
            val suffix = if (mod100 in 11..13) {
                "th"
            } else {
                when (n % 10) {
                    1 -> "st"
                    2 -> "nd"
                    3 -> "rd"
                    else -> "th"
                }
            }
            return "$n$suffix"
        }
    }
}
