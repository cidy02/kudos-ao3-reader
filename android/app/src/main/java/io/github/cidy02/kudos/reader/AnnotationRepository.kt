package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.backup.TombstoneSigning
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.dao.AnnotationDao
import io.github.cidy02.kudos.data.local.dao.SyncTombstoneDao
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/**
 * Live annotation CRUD for the reader. Room schema + backup round-trip already
 * existed; this is the in-session repository the reader UI uses.
 *
 * Same-passage recolor (iOS `ReadingAnnotationMatching`): if a new highlight
 * targets the same selected text + similar progression, update color instead of
 * stacking a second row.
 *
 * Deletes mint a signed `readingAnnotation` tombstone so folder-sync RECONCILE
 * cannot resurrect the highlight from an older peer snapshot (iOS
 * `SyncTombstones.recordDeletion`).
 */
class AnnotationRepository(
    private val dao: AnnotationDao,
    private val tombstoneDao: SyncTombstoneDao,
    private val clock: () -> Instant = { Instant.now() },
    private val uuidFactory: () -> String = { UUID.randomUUID().toString() }
) {
    fun observeForWork(workId: String): Flow<List<ReadingAnnotation>> {
        return dao.observeForWork(workId).map { rows -> rows.map { it.toDomain() } }
    }

    suspend fun saveAnnotation(annotation: ReadingAnnotation) {
        dao.upsert(annotation.copy(lastModifiedAt = Instant.now()).toEntity())
    }

    suspend fun deleteAnnotation(id: String) {
        val existing = dao.getById(id)
        dao.deleteById(id)
        if (existing == null) return
        val now = clock()
        tombstoneDao.upsert(
            TombstoneSigning.sign(
                SyncTombstone(
                    id = uuidFactory(),
                    recordID = id.lowercase(),
                    recordTypeRaw = SyncTombstoneRecordType.READING_ANNOTATION,
                    createdAt = now,
                    lastModifiedAt = now,
                    deletionReason = "annotationDeleted"
                )
            ).toEntity()
        )
    }

    suspend fun updateNote(id: String, note: String) {
        val existing = dao.getById(id)?.toDomain() ?: return
        saveAnnotation(existing.copy(note = note, lastModifiedAt = Instant.now()))
    }

    suspend fun addBookmark(
        workId: String,
        locatorString: String,
        progression: Double,
        spineIndex: Int,
        chapterTitle: String = "",
        selectedText: String = ""
    ): ReadingAnnotation {
        val annotation = ReadingAnnotation(
            workID = workId,
            kindRaw = "bookmark",
            locatorString = locatorString,
            selectedText = selectedText,
            progression = progression,
            spineIndex = spineIndex,
            chapterTitle = chapterTitle,
            createdAt = Instant.now(),
            lastModifiedAt = Instant.now()
        )
        saveAnnotation(annotation)
        return annotation
    }

    suspend fun removeBookmarkNear(
        workId: String,
        spineIndex: Int,
        progression: Double,
        tolerance: Double = 0.02
    ): Boolean {
        val existing = observeForWork(workId).first()
            .filter { it.kindRaw.equals("bookmark", ignoreCase = true) }
            .filter { it.spineIndex == spineIndex }
            .minByOrNull { kotlin.math.abs(it.progression - progression) }
            ?: return false
        if (kotlin.math.abs(existing.progression - progression) > tolerance) return false
        deleteAnnotation(existing.id)
        return true
    }

    /**
     * Creates a highlight/note, or recolors an existing same-passage highlight.
     */
    suspend fun addOrRecolorHighlight(
        workId: String,
        locatorString: String,
        selectedText: String,
        color: String,
        note: String = "",
        progression: Double,
        spineIndex: Int,
        chapterTitle: String = "",
        kind: String = "highlight"
    ): ReadingAnnotation {
        val existing = findSamePassage(workId, selectedText, progression, spineIndex)
        val annotation = if (existing != null) {
            existing.copy(
                colorRaw = color,
                note = note.ifBlank { existing.note },
                kindRaw = kind,
                locatorString = locatorString.ifBlank { existing.locatorString },
                lastModifiedAt = Instant.now()
            )
        } else {
            ReadingAnnotation(
                id = UUID.randomUUID().toString(),
                workID = workId,
                kindRaw = kind,
                colorRaw = color,
                locatorString = locatorString,
                selectedText = selectedText,
                note = note,
                progression = progression,
                spineIndex = spineIndex,
                chapterTitle = chapterTitle,
                createdAt = Instant.now(),
                lastModifiedAt = Instant.now()
            )
        }
        saveAnnotation(annotation)
        return annotation
    }

    private suspend fun findSamePassage(
        workId: String,
        selectedText: String,
        progression: Double,
        spineIndex: Int
    ): ReadingAnnotation? {
        val needle = selectedText.trim().lowercase()
        if (needle.isEmpty()) return null
        return observeForWork(workId).first()
            .filter {
                it.kindRaw.equals("highlight", ignoreCase = true) ||
                    it.kindRaw.equals("note", ignoreCase = true)
            }
            .filter { it.spineIndex == spineIndex }
            .filter { it.selectedText.trim().equals(needle, ignoreCase = true) }
            .minByOrNull { kotlin.math.abs(it.progression - progression) }
            ?.takeIf { kotlin.math.abs(it.progression - progression) < 0.05 }
    }
}
