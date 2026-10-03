package io.github.cidy02.kudos.browse

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant
import java.util.Locale

/**
 * One library work reduced to the fields Browse ranking needs.
 * Port of iOS `MediaBrowserView.LibraryWorkSnapshot`.
 */
data class LibraryWorkSnapshot(
    val fandomsLower: List<String>,
    val fandomsDisplay: List<String>,
    val hasBeenRead: Boolean,
    val dateAdded: Instant,
    val lastReadDate: Instant?,
    val isOnDevice: Boolean = true
) {
    /** Last read, or added when a read never stamped a date. */
    val recency: Instant
        get() = lastReadDate ?: dateAdded
}

fun SavedWork.toBrowseSnapshot(): LibraryWorkSnapshot = LibraryWorkSnapshot(
    fandomsLower = workFandoms.map { it.lowercase(Locale.US) },
    fandomsDisplay = workFandoms,
    hasBeenRead = isFinished || hasStartedReading,
    dateAdded = dateAdded,
    lastReadDate = lastReadDate,
    isOnDevice = isDownloaded
)

/**
 * Jump Back In's ranking, kept apart from the view so it stays pure.
 * Port of iOS `MediaBrowserJumpBackIn.jumpBackInFandoms` (T-351).
 */
object JumpBackIn {
    /** Owner, 2026-10-01: the carousel holds ten cards. */
    const val LIMIT = 10

    /** A fandom page opened from Browse (`FandomReadWatermark.lastVisitedAt`). */
    data class Visit(val fandom: String, val at: Instant)

    /** The fandom as the library spells it, its category, and AO3's work count. */
    data class Pick(
        val fandom: String,
        val categoryId: String,
        val workCount: Int?
    )

    /**
     * Each fandom's latest visit or read, newest first. [categoryFor] and
     * [workCountFor] take a lowercased name. A fandom with no category is skipped.
     * Ties keep the earlier sighting.
     */
    fun fandoms(
        works: List<LibraryWorkSnapshot>,
        visits: List<Visit> = emptyList(),
        categoryFor: (String) -> String?,
        workCountFor: (String) -> Int?,
        limit: Int
    ): List<Pick> {
        data class Seen(val display: String, val at: Instant, val order: Int)
        val latest = LinkedHashMap<String, Seen>()
        var order = 0
        val read = works.filter { it.hasBeenRead }.sortedByDescending { it.recency }
        for (work in read) {
            for (index in work.fandomsLower.indices) {
                val key = work.fandomsLower[index]
                if (latest.containsKey(key)) continue
                latest[key] = Seen(
                    display = work.fandomsDisplay[index],
                    at = work.recency,
                    order = order
                )
                order += 1
            }
        }
        for (visit in visits) {
            val lower = visit.fandom.lowercase(Locale.US)
            val known = latest[lower]
            if (known != null) {
                if (visit.at > known.at) {
                    latest[lower] = known.copy(at = visit.at)
                }
            } else {
                latest[lower] = Seen(display = visit.fandom, at = visit.at, order = order)
                order += 1
            }
        }
        val ranked = latest.entries.sortedWith(
            compareByDescending<Map.Entry<String, Seen>> { it.value.at }.thenBy { it.value.order }
        )
        val picks = ArrayList<Pick>(minOf(limit, ranked.size))
        for ((lower, entry) in ranked) {
            val categoryId = categoryFor(lower) ?: continue
            picks += Pick(
                fandom = entry.display,
                categoryId = categoryId,
                workCount = workCountFor(lower)
            )
            if (picks.size == limit) break
        }
        return picks
    }
}
