package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.entity.ReadingSessionEntity
import java.time.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

enum class FavoriteScope(val id: String, val title: String, val singularNoun: String) {
    Works("works", "Works", "work"), Authors("authors", "Authors", "author"),
    Fandoms("fandoms", "Fandoms", "fandom"), Tags("tags", "Tags", "tag");

    companion object {
        fun fromId(id: String?) = entries.firstOrNull { it.id == id } ?: Works
    }
}

data class FavoritePreferences(
    val scope: FavoriteScope = FavoriteScope.Works,
    val order: ReadingAffinities.Order = ReadingAffinities.Order.Recent,
    val tagsUnreadOnly: Boolean = false
)

data class WorkReadingSummary(
    val totalSeconds: Double = 0.0,
    val visitCount: Int = 0,
    val finishCount: Int = 0,
    val lastEndedAt: Instant? = null
)

/** iOS ReadingAffinities: derived reading facts, never explicit stars or AO3 reads. */
object ReadingAffinities {
    data class Row(
        val name: String,
        val worksRead: Int = 0,
        val totalSeconds: Double = 0.0,
        val lastRead: Instant? = null,
        val username: String? = null,
        val unreadInLibrary: Int = 0,
        val downloadedInLibrary: Int = 0,
        val savedForLater: Int = 0,
        val favorited: Int = 0
    )

    enum class Order(val id: String, val title: String) {
        Recent("recent", "Recent"), MostRead("mostRead", "Most read"), MostTime("mostTime", "Most time");

        companion object {
            fun fromId(id: String?) = entries.firstOrNull { it.id == id } ?: Recent
        }
    }

    fun summaries(sessions: List<ReadingSessionEntity>): Map<String, WorkReadingSummary> =
        sessions.groupBy { it.workID }.mapValues { (_, visits) ->
            WorkReadingSummary(visits.sumOf { it.durationSeconds }, visits.size,
                visits.count { it.didFinish }, visits.maxOf { it.endedAt })
        }

    fun authors(works: List<SavedWork>, summaries: Map<String, WorkReadingSummary>,
                order: Order = Order.Recent, savedForLaterIds: Set<String> = emptySet()): List<Row> {
        val usernames = mutableMapOf<String, String>()
        for (work in works) {
            val byline = work.author.trim()
            if (byline.isEmpty() || byline in usernames) continue
            singleRegisteredUsername(work.authorIdentitiesJSON)?.let { usernames[byline] = it }
        }
        return rows(works, summaries, order, savedForLaterIds) { listOf(it.author) }
            .map { it.copy(username = usernames[it.name]) }
    }

    fun fandoms(works: List<SavedWork>, summaries: Map<String, WorkReadingSummary>,
                order: Order = Order.Recent, savedForLaterIds: Set<String> = emptySet()): List<Row> =
        rows(works, summaries, order, savedForLaterIds) { it.workFandoms }

    fun tags(works: List<SavedWork>, summaries: Map<String, WorkReadingSummary>,
             order: Order = Order.Recent, savedForLaterIds: Set<String> = emptySet()): List<Row> =
        rows(works, summaries, order, savedForLaterIds) { it.workFreeforms.ifEmpty { it.workTags } }

    fun forScope(scope: FavoriteScope, items: List<LibraryDisplayItem>,
                 summaries: Map<String, WorkReadingSummary>, order: Order): List<Row> {
        // Same privacy gate as Search's names: obscured identities must not leak through aggregates.
        val visible = items.filter { it.privacyVisibility == LibraryPrivacyVisibility.Visible &&
            !it.item.work.isQueueOnlyWork && !it.item.work.isDeleted }
        val works = visible.map { it.item.work }
        val queued = visible.filter { it.item.inSavedForLater }.mapTo(mutableSetOf()) { it.item.work.id }
        return when (scope) {
            FavoriteScope.Works -> emptyList()
            FavoriteScope.Authors -> authors(works, summaries, order, queued)
            FavoriteScope.Fandoms -> fandoms(works, summaries, order, queued)
            FavoriteScope.Tags -> tags(works, summaries, order, queued)
        }
    }

    private fun rows(works: List<SavedWork>, summaries: Map<String, WorkReadingSummary>,
                     order: Order, savedForLaterIds: Set<String>, keys: (SavedWork) -> List<String>): List<Row> {
        val byName = mutableMapOf<String, Row>()
        for (work in works) {
            val summary = summaries[work.id]
            val wasRead = (summary?.visitCount ?: 0) > 0 || work.hasStartedReading
            val unread = !work.hasStartedReading && summary == null
            for (name in keys(work).map { it.trim() }.filter { it.isNotEmpty() }) {
                val row = byName[name] ?: Row(name)
                val date = if (wasRead) summary?.lastEndedAt ?: work.lastReadDate else null
                byName[name] = row.copy(
                    worksRead = row.worksRead + if (wasRead) 1 else 0,
                    totalSeconds = row.totalSeconds + if (wasRead) summary?.totalSeconds ?: 0.0 else 0.0,
                    lastRead = listOfNotNull(row.lastRead, date).maxOrNull(),
                    unreadInLibrary = row.unreadInLibrary + if (unread) 1 else 0,
                    downloadedInLibrary = row.downloadedInLibrary + if (unread && work.isDownloaded) 1 else 0,
                    savedForLater = row.savedForLater + if (unread && (work.id in savedForLaterIds ||
                        (work.isSaved && !work.isQueuedForLater))) 1 else 0,
                    favorited = row.favorited + if (work.isFavorite) 1 else 0
                )
            }
        }
        val ranking = when (order) {
            Order.Recent -> compareByDescending<Row> { it.lastRead ?: Instant.MIN }
            Order.MostRead -> compareByDescending<Row> { it.worksRead }
            Order.MostTime -> compareByDescending<Row> { it.totalSeconds }
        }
        return byName.values.filter { it.worksRead > 0 }
            .sortedWith(ranking.thenBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    /** Stored iOS identity JSON is an array with kind/username, not the displayed pseud. */
    private fun singleRegisteredUsername(raw: String): String? {
        val identities = runCatching { Json.parseToJsonElement(raw) as? JsonArray }.getOrNull() ?: return null
        val registered = identities.filter { (it as? JsonObject)?.get("kind") == JsonPrimitive("registered") }
        val identity = registered.singleOrNull() as? JsonObject ?: return null
        return (identity["username"] as? JsonPrimitive)?.takeIf { it.isString }
            ?.contentOrNull?.takeIf { it.isNotBlank() }
    }
}
