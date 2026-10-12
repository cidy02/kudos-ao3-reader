package io.github.cidy02.kudos.network.ao3.account

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

/** iOS `AO3HistoryVisitBucket`: the headings of History's time groups (artboard 1t). */
enum class AO3HistoryVisitBucket(val title: String) {
    Today("Today"),
    Yesterday("Yesterday"),
    ThisWeek("This week"),
    ThisMonth("This month"),
    Earlier("Earlier");

    companion object {
        private val absolute = Regex("""^\d{1,2} [A-Za-z]{3} \d{4}$""")
        private val dayMonthYear = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.US)

        /** [lastVisited] is AO3's own phrase: "2 days", "about 1 month", or "04 Mar 2024". */
        fun of(lastVisited: String, today: LocalDate = LocalDate.now()): AO3HistoryVisitBucket {
            val text = lastVisited.trim()
            if (text.isEmpty()) return Earlier
            if (absolute.matches(text)) {
                val date = runCatching { LocalDate.parse(text, dayMonthYear) }.getOrNull() ?: return Earlier
                return if (date.year == today.year && date.month == today.month) ThisMonth else Earlier
            }
            val lower = text.lowercase()
            if ("second" in lower || "minute" in lower || "hour" in lower) return Today
            count(lower, "day")?.let { days ->
                return when {
                    days <= 1 -> Yesterday
                    days <= 6 -> ThisWeek
                    else -> ThisMonth
                }
            }
            count(lower, "month")?.let { months -> return if (months <= 1) ThisMonth else Earlier }
            return Earlier
        }

        /** "2 days", "1 day", "about 1 month": the shapes Rails' `time_ago_in_words` gives. */
        private fun count(text: String, unit: String): Int? =
            Regex("""^(?:about\s+)?(\d+)\s+$unit""").find(text)?.groupValues?.get(1)?.toIntOrNull()
    }
}

/**
 * One run of rows, in the page's order, under one heading. A later row in an earlier bucket
 * starts a new group and is not pulled upward: the order is AO3's, and a heading goes in
 * where that order changes bucket (iOS `AO3HistoryVisitGrouping`).
 */
data class AO3HistoryVisitGroup<T>(val bucket: AO3HistoryVisitBucket, val items: List<T>)

fun <T> historyVisitGroups(
    items: List<T>,
    today: LocalDate = LocalDate.now(),
    lastVisited: (T) -> String
): List<AO3HistoryVisitGroup<T>> {
    val result = mutableListOf<AO3HistoryVisitGroup<T>>()
    for (item in items) {
        val bucket = AO3HistoryVisitBucket.of(lastVisited(item), today)
        val last = result.lastOrNull()
        if (last != null && last.bucket == bucket) result[result.lastIndex] = last.copy(items = last.items + item)
        else result += AO3HistoryVisitGroup(bucket, listOf(item))
    }
    return result
}

/** iOS `AO3HistoryLocalProgress.label`: where the reader is in their own copy of the work. */
fun historyLocalProgress(isFinished: Boolean, lastSpineIndex: Int, chapters: String, readingProgress: Double?): String? {
    if (isFinished) return "Finished"
    if (lastSpineIndex > 0) {
        val current = lastSpineIndex + 1
        val total = chapters.split("/").takeIf { it.size == 2 }?.get(1)?.trim()?.toIntOrNull()?.takeIf { it > 0 }
        return if (total != null) "Ch. $current of $total" else "Ch. $current"
    }
    val percent = ((readingProgress ?: return null).coerceAtMost(1.0) * 100).roundToInt()
    return if (percent > 0) "$percent%" else null
}
