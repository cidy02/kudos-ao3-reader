package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.browse.FandomDisplayName
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.readingProgress
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * How iOS artboards **1ah** and **1ai** slice the reading history (iOS `LibraryHistoryGrouping`):
 * the same rows, four groupings, chosen with a scope strip above the list. 1ah is [Time], 1ai is
 * [State]; they are one screen with the control in two positions.
 *
 * Pure on purpose. "Which bucket does this work go in" is the whole content of these screens, and
 * a rule you can hand fixtures and a clock to is a rule you can check.
 */
enum class LibraryHistoryGrouping(val id: String, val title: String) {
    Time("time", "Time"),
    State("state", "State"),
    Fandom("fandom", "Fandom"),
    Flat("flat", "Flat");

    /** One group as the list draws it: a kicker and its works. */
    data class Bucket(val title: String, val workIds: List<String>) {
        val id: String get() = title
    }

    /** The spec's TODAY / THIS WEEK / … kickers. */
    enum class TimeBucket(val title: String) {
        Today("Today"),
        Yesterday("Yesterday"),
        ThisWeek("This week"),
        ThisMonth("This month"),
        Earlier("Earlier"),
        Never("Never opened");

        companion object {
            /**
             * `null` is a work that has a record but was never opened in the reader: its own bucket
             * rather than folded into Earlier, because "never" and "a long time ago" are different
             * answers. Measured against [now], not the wall clock.
             */
            fun bucket(
                date: Instant?,
                now: Instant,
                zone: ZoneId = ZoneId.systemDefault(),
                weekFields: WeekFields = WeekFields.of(Locale.getDefault())
            ): TimeBucket {
                if (date == null) return Never
                val day = date.atZone(zone).toLocalDate()
                val today = now.atZone(zone).toLocalDate()
                if (day == today) return Today
                // iOS subtracts one minute from today's midnight, including skipped civil days.
                if (day == today.atStartOfDay(zone).minusSeconds(60).toLocalDate()) return Yesterday
                if (sameWeek(day, today, weekFields)) return ThisWeek
                if (day.year == today.year && day.month == today.month) return ThisMonth
                return Earlier
            }

            private fun sameWeek(a: LocalDate, b: LocalDate, weekFields: WeekFields): Boolean =
                a.get(weekFields.weekBasedYear()) == b.get(weekFields.weekBasedYear()) &&
                    a.get(weekFields.weekOfWeekBasedYear()) == b.get(weekFields.weekOfWeekBasedYear())
        }
    }

    companion object {
        /** Named because the tally counts these two buckets by title; a renamed kicker must not zero it. */
        const val InProgressTitle = "In progress"
        const val AbandonedTitle = "Abandoned"
        const val ReadNotFinishedTitle = "Read, not finished"
        const val FinishedTitle = "Finished"
        const val NotStartedTitle = "Not started"
        const val FlatTitle = "All"
        const val NoFandomTitle = "No fandom"

        /** iOS `@AppStorage` default: History opens grouped by time. */
        val Default: LibraryHistoryGrouping = Time

        fun fromId(id: String?): LibraryHistoryGrouping? = entries.firstOrNull { it.id == id }

        /**
         * Buckets [works] under [grouping], keeping the incoming order inside each bucket (the
         * caller has already sorted most-recently-read first). Buckets come back in a **fixed**
         * order per grouping, not by size, except Fandom, which has no natural order and is ranked
         * by size, then alphabetically. Empty buckets are dropped.
         */
        fun groups(
            grouping: LibraryHistoryGrouping,
            works: List<SavedWork>,
            now: Instant = Instant.now(),
            zone: ZoneId = ZoneId.systemDefault(),
            weekFields: WeekFields = WeekFields.of(Locale.getDefault()),
            isAbandoned: (SavedWork) -> Boolean
        ): List<Bucket> = when (grouping) {
            Flat -> if (works.isEmpty()) emptyList() else listOf(Bucket(FlatTitle, works.map { it.id }))
            Time -> ordered(TimeBucket.entries.map { it.title }, works) {
                TimeBucket.bucket(it.lastReadDate, now, zone, weekFields).title
            }
            // Five buckets, not three, because the reading state is a four-way partition and one of
            // the four (in progress) is split by Abandoned. Abandoned is checked before In progress:
            // it is a kind of in-progress, and a work in both would be counted twice in the tally.
            State -> ordered(
                listOf(InProgressTitle, AbandonedTitle, ReadNotFinishedTitle, FinishedTitle, NotStartedTitle),
                works
            ) { work ->
                when {
                    work.isFinished -> FinishedTitle
                    !work.hasEpub -> ReadNotFinishedTitle
                    !work.hasStartedReading -> NotStartedTitle
                    isAbandoned(work) -> AbandonedTitle
                    else -> InProgressTitle
                }
            }
            Fandom -> {
                val byFandom = linkedMapOf<String, MutableList<String>>()
                for (work in works) {
                    // By family, so "Doctor Who" and "Doctor Who (2005)" are one group.
                    val name = work.workFandoms.firstOrNull { it.isNotEmpty() }
                        ?.let(FandomDisplayName::bareTitle) ?: NoFandomTitle
                    byFandom.getOrPut(name) { mutableListOf() }.add(work.id)
                }
                byFandom.entries
                    .sortedWith(
                        compareByDescending<Map.Entry<String, MutableList<String>>> { it.value.size }
                            .thenBy { it.key }
                    )
                    .map { Bucket(it.key, it.value.toList()) }
            }
        }

        /**
         * The header's second line. Time/Flat: "6 works · most recently read first"; State:
         * "5 works · 2 in progress · 1 abandoned"; Fandom: only the count (its sections are ranked
         * by size, so "most recently read first" would describe the rows, not the page). A state
         * count of zero is dropped rather than printed.
         */
        fun tallyLine(workCount: Int, grouping: LibraryHistoryGrouping, buckets: List<Bucket>): String {
            val works = "$workCount ${if (workCount == 1) "work" else "works"}"
            return when (grouping) {
                Time, Flat -> "$works · most recently read first"
                Fandom -> works
                State -> {
                    val inProgress = buckets.firstOrNull { it.title == InProgressTitle }?.workIds?.size ?: 0
                    val abandoned = buckets.firstOrNull { it.title == AbandonedTitle }?.workIds?.size ?: 0
                    buildList {
                        add(works)
                        if (inProgress > 0) add("$inProgress in progress")
                        if (abandoned > 0) add("$abandoned abandoned")
                    }.joinToString(" · ")
                }
            }
        }

        /** Buckets by [key], then emits the buckets in [order], dropping empty ones. */
        private fun ordered(
            order: List<String>,
            works: List<SavedWork>,
            key: (SavedWork) -> String
        ): List<Bucket> {
            val buckets = HashMap<String, MutableList<String>>()
            for (work in works) buckets.getOrPut(key(work)) { mutableListOf() }.add(work.id)
            return order.mapNotNull { title ->
                buckets[title]?.takeIf { it.isNotEmpty() }?.let { Bucket(title, it.toList()) }
            }
        }
    }
}

/** iOS `ReadingLogService.isAbandoned` and its threshold. */
object ReadingAbandonment {
    /** 1ai default: mid-way and untouched for this long, and no manual override. */
    val DefaultThreshold: Duration = Duration.ofDays(21)

    /**
     * Derived Abandoned (1ai). Every condition must hold: no stored keep-in-progress override; the
     * work is in progress (file on device, started, not finished); its progress is strictly
     * between 5% and 95%; it has a last-read date; and that date is **more than** [threshold]
     * before [now]. A work with no readable progress counts as 0 and so is never abandoned.
     */
    fun isAbandoned(
        work: SavedWork,
        now: Instant = Instant.now(),
        threshold: Duration = DefaultThreshold
    ): Boolean {
        if (work.keepInProgressOverride) return false
        if (!work.isInProgress) return false
        val progress = work.readingProgress ?: 0.0
        if (!(progress > 0.05 && progress < 0.95)) return false
        val lastRead = work.lastReadDate ?: return false
        return Duration.between(lastRead, now) > threshold
    }
}
