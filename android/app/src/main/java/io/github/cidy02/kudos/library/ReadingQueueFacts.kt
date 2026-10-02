package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Duration
import java.time.Instant
import java.util.Locale

/**
 * Decisions behind the queue organizer and queue page, kept out of the views.
 * Port of `ReadingQueueFacts`, `QueueQuickFilter`, and `QueueOrganizerSelection`.
 */
data class QueueProgress(
    val finished: Int = 0,
    val inProgress: Int = 0,
    val unread: Int = 0
) {
    val total: Int get() = finished + inProgress + unread
}

enum class QueueQuickFilter(val title: String) {
    All("All"),
    Unread("Unread"),
    Offline("Offline"),
    Wip("WIP");

    fun matches(work: SavedWork, preserved: Boolean): Boolean = when (this) {
        All -> true
        Unread -> !work.isFinished && !work.isInProgress
        Offline -> preserved
        Wip -> !work.isComplete
    }
}

object ReadingQueueFacts {
    const val UNTAGGED = "\u0000untagged"

    fun progress(works: List<SavedWork>): QueueProgress {
        var finished = 0
        var inProgress = 0
        var unread = 0
        for (work in works) {
            when {
                work.isFinished -> finished += 1
                work.isInProgress -> inProgress += 1
                else -> unread += 1
            }
        }
        return QueueProgress(finished, inProgress, unread)
    }

    /** 1-based place of the first work not yet finished. Null when every work is finished, or none. */
    fun nextUpPosition(works: List<SavedWork>): Int? {
        val index = works.indexOfFirst { !it.isFinished }
        return if (index < 0) null else index + 1
    }

    /** First unfinished work, else the first of a fully-read queue. [inLine] is everything else, in order. */
    fun upNext(works: List<SavedWork>): Pair<SavedWork?, List<SavedWork>> {
        if (works.isEmpty()) return null to emptyList()
        val index = works.indexOfFirst { !it.isFinished }.let { if (it < 0) 0 else it }
        val inLine = works.filterIndexed { position, _ -> position != index }
        return works[index] to inLine
    }

    fun legend(progress: QueueProgress, offlineCount: Int): String {
        val offline = if (offlineCount == progress.total) {
            "all ${progress.total} kept offline"
        } else {
            "$offlineCount of ${progress.total} kept offline"
        }
        return "${progress.finished} finished · ${progress.inProgress} in progress · " +
            "${progress.unread} unread · $offline"
    }

    fun kicker(origin: String, isDetails: Boolean = false): String {
        return "$origin › Queues" + if (isDetails) " › Queue details" else ""
    }

    /** Latest member `lastReadDate`, ignoring works that have never been opened. */
    fun lastRead(dates: List<Instant?>): Instant? = dates.filterNotNull().maxOrNull()

    /** "just now", "N minutes ago", "yesterday", "N days ago". A future instant is "just now". */
    fun relativeNamed(from: Instant, now: Instant): String {
        val seconds = Duration.between(from, now).seconds
        if (seconds < 60) return "just now"
        val minutes = seconds / 60
        if (minutes < 60) return if (minutes == 1L) "1 minute ago" else "$minutes minutes ago"
        val hours = seconds / 3600
        if (hours < 24) return if (hours == 1L) "1 hour ago" else "$hours hours ago"
        val days = seconds / 86400
        if (days < 2) return "yesterday"
        return "$days days ago"
    }

    fun subtitle(workCount: Int, preservedCount: Int, bytes: Long): String {
        val base = if (workCount == 1) "1 work" else "$workCount works"
        if (workCount == 0) return base
        val offline = if (preservedCount == workCount) "all kept offline" else "$preservedCount kept offline"
        return "$base · $offline · ${byteCountString(bytes)}"
    }

    fun storageLine(preservedCount: Int, bytes: Long): String {
        if (preservedCount == 0) return "nothing kept yet"
        return "$preservedCount offline · ${byteCountString(bytes)}"
    }

    /** Reorder shows the whole queue. Select keeps the handle live, except under a filter. */
    fun isDragLive(isReordering: Boolean, isSelecting: Boolean, isNarrowed: Boolean): Boolean {
        return isReordering || (isSelecting && !isNarrowed)
    }

    fun canReorder(tagFilterActive: Boolean, searchActive: Boolean): Boolean {
        return !tagFilterActive && !searchActive
    }

    fun deletable(queues: List<ReadingQueue>): List<ReadingQueue> {
        return queues.filter { it.kindRaw == ReadingQueueKind.CUSTOM }
    }

    /** Pin, unless every selected queue already is. */
    fun pinTarget(queues: List<ReadingQueue>): Boolean {
        return queues.isNotEmpty() && queues.any { !it.isPinned }
    }

    fun deleteTitle(queues: List<ReadingQueue>): String {
        return if (queues.size == 1) {
            "Delete “${queues[0].displayName}”?"
        } else {
            "Delete ${queues.size} queues?"
        }
    }

    fun deleteMessage(count: Int): String {
        return if (count == 1) {
            "Kudos will move this queue to Recently Deleted for 90 days. Its list of works stays with it, " +
                "and the works stay in Kudos."
        } else {
            "Kudos will move these $count queues to Recently Deleted for 90 days. Their lists of works stay with them, " +
                "and the works stay in Kudos."
        }
    }

    fun displayHue(queue: ReadingQueue): Double = queue.hue ?: coverHue(queue.displayName)

    /** djb2 over Unicode code points, then `hash % 360 / 360`. Matches `CoverArt.hue(for:)`. */
    fun coverHue(string: String): Double {
        var hash = 5381UL
        var index = 0
        while (index < string.length) {
            val codePoint = string.codePointAt(index)
            hash = hash * 33u + codePoint.toULong()
            index += Character.charCount(codePoint)
        }
        return (hash % 360u).toDouble() / 360.0
    }

    fun byteCountString(bytes: Long): String {
        if (bytes < 1000L) return "$bytes B"
        val units = arrayOf("KB", "MB", "GB", "TB")
        var value = bytes / 1000.0
        var unit = 0
        while (value >= 1000.0 && unit < units.lastIndex) {
            value /= 1000.0
            unit += 1
        }
        val text = if (value >= 10.0) {
            String.format(Locale.US, "%.0f", value)
        } else {
            String.format(Locale.US, "%.1f", value)
        }
        return "$text ${units[unit]}"
    }

    fun matchesSearch(
        queue: ReadingQueue,
        tags: List<String>,
        works: List<SavedWork>,
        term: String
    ): Boolean {
        val query = term.trim()
        if (query.isEmpty()) return true
        if (queue.displayName.contains(query, ignoreCase = true)) return true
        if (tags.any { it.contains(query, ignoreCase = true) }) return true
        return works.any { work ->
            work.title.contains(query, ignoreCase = true) || work.author.contains(query, ignoreCase = true)
        }
    }

    fun matchesTagFilter(tagNames: List<String>, filter: String): Boolean = when (filter) {
        "" -> true
        UNTAGGED -> tagNames.isEmpty()
        else -> tagNames.any { it == filter }
    }
}

