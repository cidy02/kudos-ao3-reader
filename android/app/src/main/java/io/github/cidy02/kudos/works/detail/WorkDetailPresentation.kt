package io.github.cidy02.kudos.works.detail

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.works.WorkIdentityIndex
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.roundToInt

object WorkDetailPresentation {
    enum class PostRemovalAction { KeepLocal, ShowRemote, Dismiss }

    enum class MyCopyKind { Progress, Downloaded, File, Tags, Collections, Queues }

    enum class MyCopyActionKind(val title: String) {
        Edit("Edit"),
        Add("Add")
    }

    data class MyCopyRow(
        val kind: MyCopyKind,
        val label: String,
        val value: String,
        val action: MyCopyActionKind? = null
    )

    fun postRemovalAction(isPendingDeletion: Boolean, hasRemoteSource: Boolean): PostRemovalAction =
        if (!isPendingDeletion) PostRemovalAction.KeepLocal
        else if (hasRemoteSource) PostRemovalAction.ShowRemote else PostRemovalAction.Dismiss

    fun summaryFromLocal(work: SavedWork): AO3WorkSummary? {
        val id = WorkIdentityIndex.ao3WorkId(work) ?: return null
        return AO3WorkSummary(
            id = id, title = work.title, authors = work.author.split(',').map { it.trim() }.filter { it.isNotEmpty() },
            fandoms = work.workFandoms, rating = work.rating, warnings = work.workWarnings, categories = work.workCategories,
            relationships = work.workRelationships, characters = work.workCharacters, freeforms = work.workFreeforms,
            summary = work.summary, language = work.language, wordCount = work.wordCount, chapters = work.chapters,
            kudos = work.kudos, comments = work.comments, hits = work.hits, bookmarks = work.bookmarks,
            seriesTitle = work.seriesTitle, seriesPosition = work.seriesPosition, seriesUrl = work.seriesUrl,
            isComplete = work.knownCompletion, updatedDate = work.dateUpdated, publishedDate = work.datePublished,
            authorIdentitiesJSON = work.authorIdentitiesJSON
        )
    }

    fun queueLabel(count: Int): String = if (count <= 0) "Add to Queue" else "In $count ${if (count == 1) "Queue" else "Queues"}"
    fun collectionLabel(count: Int): String = if (count <= 0) "Add to Collection" else "In $count ${if (count == 1) "Collection" else "Collections"}"

    fun myCopyRows(
        progress: Double?,
        chapterNumber: Int? = null,
        downloadedAt: Instant?,
        tags: List<String>,
        collections: List<String>,
        queues: List<String>,
        hasFile: Boolean,
        fileSize: String?,
        zoneId: ZoneId = ZoneId.systemDefault(),
        locale: Locale = Locale.getDefault()
    ): List<MyCopyRow> {
        val progressValue = if (progress == null) {
            "Not started"
        } else {
            val pct = (progress.coerceIn(0.0, 1.0) * 100.0).roundToInt()
            if (chapterNumber != null) "Ch $chapterNumber · $pct%" else "$pct%"
        }
        val dateText = downloadedAt?.let { instant ->
            DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
                .withLocale(locale)
                .withZone(zoneId)
                .format(instant)
        } ?: "Not recorded"
        val fileText = when {
            !hasFile -> "Not on this device"
            fileSize.isNullOrBlank() -> "EPUB"
            else -> "EPUB · $fileSize"
        }
        fun joined(items: List<String>) = if (items.isEmpty()) "None" else items.joinToString(", ")

        return listOf(
            MyCopyRow(MyCopyKind.Progress, "Progress", progressValue, null),
            MyCopyRow(MyCopyKind.Downloaded, "Downloaded", dateText, MyCopyActionKind.Edit),
            MyCopyRow(MyCopyKind.Tags, "Your Tags", joined(tags), MyCopyActionKind.Add),
            MyCopyRow(MyCopyKind.Collections, "Collections", joined(collections), MyCopyActionKind.Add),
            MyCopyRow(MyCopyKind.Queues, "Queues", joined(queues), MyCopyActionKind.Add),
            MyCopyRow(MyCopyKind.File, "File", fileText, null)
        )
    }

    /** Version E's two-column cells: Progress lives in the reading card, not repeated here. */
    fun myCopyCells(rows: List<MyCopyRow>): List<MyCopyRow> {
        val order = listOf(
            MyCopyKind.Downloaded,
            MyCopyKind.File,
            MyCopyKind.Tags,
            MyCopyKind.Collections,
            MyCopyKind.Queues
        )
        return order.mapNotNull { kind -> rows.firstOrNull { it.kind == kind } }
    }
}
