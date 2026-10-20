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
 * targets the exact stored locator, update its colour instead of stacking a second row.
 * The reader's Highlight action toggles off an exact same-colour repeat.
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
        if (existing == null) return
        val now = clock()
        dao.deleteWithTombstone(
            id, TombstoneSigning.sign(
                SyncTombstone(
                    id = uuidFactory(),
                    recordID = id.lowercase(),
                    recordTypeRaw = SyncTombstoneRecordType.READING_ANNOTATION,
                    createdAt = now,
                    lastModifiedAt = now,
                    deletionReason = "annotationDeleted"
                )
            ).toEntity(), tombstoneDao
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
        // iOS addBookmark(at:): a spot that already has a bookmark gives that one back, not a second.
        // ponytail: matched on the stored locator (the same Find in Work result tapped twice); iOS
        // matches Readium's position, which also catches the toolbar's bookmark on the same page.
        if (locatorString.isNotEmpty()) observeForWork(workId).first().firstOrNull {
            it.kindRaw.equals("bookmark", ignoreCase = true) && it.locatorString == locatorString
        }?.let { return it }
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

    /** Removes the bookmark at exactly this Readium [position] (iOS), or returns false. */
    suspend fun removeBookmarkAt(workId: String, position: Int?): Boolean {
        if (position == null) return false
        val existing = observeForWork(workId).first()
            .filter { it.kindRaw.equals("bookmark", ignoreCase = true) }
            .firstOrNull { readerLocatorPosition(it.locatorString) == position }
            ?: return false
        deleteAnnotation(existing.id)
        return true
    }

    /** Editor recolouring uses identity, not the selection path’s same-passage matcher. */
    suspend fun addOrRecolorHighlight(id: String, color: String) {
        val existing = dao.getById(id)?.toDomain() ?: return
        if (existing.isPendingDeletion ||
            (!existing.kindRaw.equals("highlight", ignoreCase = true) &&
                !existing.kindRaw.equals("note", ignoreCase = true) &&
                !existing.kindRaw.equals("bookmark", ignoreCase = true))
        ) return
        saveAnnotation(existing.copy(colorRaw = color))
    }

    /** Result also drives the iOS post-selection editor/colour-bar routing. */
    data class SelectionResult(val annotation: ReadingAnnotation?, val created: Boolean)

    suspend fun annotateSelection(
        workId: String, locatorString: String, selectedText: String, color: String,
        progression: Double, spineIndex: Int, withNote: Boolean
    ): SelectionResult {
        val existing = findSamePassage(workId, locatorString)
        if (existing != null) {
            // Add Note never toggles or recolours an existing mark, including its saved note.
            if (withNote) return SelectionResult(existing, created = false)
            if (existing.colorRaw == color) {
                deleteAnnotation(existing.id)
                return SelectionResult(null, created = false)
            }
        }
        val annotation = addOrRecolorHighlight(
            workId, locatorString, selectedText, color, progression = progression,
            spineIndex = spineIndex, kind = existing?.kindRaw ?: "highlight"
        )
        return SelectionResult(annotation, created = existing == null)
    }

    /** iOS: repeating Highlight with the current colour removes that exact passage. */
    suspend fun toggleHighlight(
        workId: String, locatorString: String, selectedText: String, color: String,
        progression: Double, spineIndex: Int
    ) {
        annotateSelection(workId, locatorString, selectedText, color, progression, spineIndex, withNote = false)
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
        val existing = findSamePassage(workId, locatorString)
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

    /**
     * iOS `ReadingAnnotationMatching.isSamePassage`: the same stored locator, nothing looser.
     * Matching by text and nearness took a second "Harry" a few lines down for the first,
     * moved the first mark onto it and left the first passage unmarked (audit A5-4).
     */
    private suspend fun findSamePassage(workId: String, locatorString: String): ReadingAnnotation? {
        if (locatorString.isBlank()) return null
        return observeForWork(workId).first().firstOrNull {
            (it.kindRaw.equals("highlight", ignoreCase = true) || it.kindRaw.equals("note", ignoreCase = true)) &&
                it.locatorString == locatorString
        }
    }
}
