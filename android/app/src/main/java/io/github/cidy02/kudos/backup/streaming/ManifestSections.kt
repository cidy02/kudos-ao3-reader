package io.github.cidy02.kudos.backup.streaming

import io.github.cidy02.kudos.backup.BackupAnnotation
import io.github.cidy02.kudos.backup.BackupBookmark
import io.github.cidy02.kudos.backup.BackupCollection
import io.github.cidy02.kudos.backup.BackupFandomReadWatermark
import io.github.cidy02.kudos.backup.BackupFont
import io.github.cidy02.kudos.backup.BackupPaths
import io.github.cidy02.kudos.backup.BackupReadingFavorite
import io.github.cidy02.kudos.backup.BackupReadingQueue
import io.github.cidy02.kudos.backup.BackupReadingQueueMembership
import io.github.cidy02.kudos.backup.BackupReadingSession
import io.github.cidy02.kudos.backup.BackupSavedSearch
import io.github.cidy02.kudos.backup.BackupTombstone
import io.github.cidy02.kudos.backup.BackupWork
import io.github.cidy02.kudos.backup.KudosBackupManifest
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer

/**
 * One natural-key column of a staged section: built from direct scalar members of the record
 * ([fields], in order; a missing, null or non-scalar member is null). A null result, or a member longer
 * than [MAX_KEY_CHARS], leaves the column NULL: the resolver falls back to the record payload.
 */
internal class KeyColumn(val column: String, val fields: List<String>, val make: (List<String?>) -> String?)

/** A top-level array of records the manifest knows by name. */
internal class SectionSpec(val name: String, val serializer: KSerializer<*>, val keys: List<KeyColumn>) {
    val table = "s_$name"
    val chunkTable = "s_${name}_chunk"

    @OptIn(ExperimentalSerializationApi::class)
    val knownFields: Set<String> = (0 until serializer.descriptor.elementsCount)
        .mapTo(HashSet()) { serializer.descriptor.getElementName(it) }
}

internal object ManifestSections {
    const val MAX_KEY_CHARS = 2048

    private fun id(value: String?) = value?.let(BackupPaths::normalizeIdForComparison)
    private fun one(column: String, field: String, make: (String?) -> String? = { it }) =
        KeyColumn(column, listOf(field)) { make(it[0]) }

    val all: List<SectionSpec> = listOf(
        SectionSpec("works", BackupWork.serializer(), listOf(
            one("k_id", "id", ::id), one("k_ao3", "ao3WorkID"), one("k_url", "sourceURL")
        )),
        SectionSpec("bookmarks", BackupBookmark.serializer(), listOf(one("k_id", "id", ::id), one("k_url", "urlString"))),
        SectionSpec("fonts", BackupFont.serializer(), listOf(
            one("k_file", "fileName") { it?.let(BackupPaths::fontFileNameKey) }, one("k_name", "name") { it?.lowercase() }
        )),
        SectionSpec("collections", BackupCollection.serializer(), listOf(one("k_id", "id", ::id))),
        SectionSpec("savedSearches", BackupSavedSearch.serializer(), listOf(one("k_id", "id", ::id))),
        SectionSpec("readingQueues", BackupReadingQueue.serializer(), listOf(one("k_id", "id", ::id))),
        SectionSpec("readingQueueMemberships", BackupReadingQueueMembership.serializer(), listOf(
            one("k_id", "id", ::id), one("k_queue", "queueID", ::id), one("k_work", "workID", ::id)
        )),
        SectionSpec("annotations", BackupAnnotation.serializer(), listOf(
            one("k_id", "id", ::id),
            one("k_work", "workID", ::id),
            KeyColumn("k_passage", listOf("workID", "locatorString")) { v ->
                if (v[0] == null || v[1] == null) null else "${id(v[0])}\u0000${v[1]}"
            }
        )),
        SectionSpec("readingSessions", BackupReadingSession.serializer(), listOf(one("k_id", "id", ::id), one("k_work", "workID", ::id))),
        SectionSpec("readingFavorites", BackupReadingFavorite.serializer(), listOf(
            one("k_id", "id", ::id),
            KeyColumn("k_target", listOf("kindRaw", "targetKey")) { v -> if (v[1] == null) null else "${v[0] ?: "work"}\u0000${v[1]}" }
        )),
        SectionSpec("fandomReadWatermarks", BackupFandomReadWatermark.serializer(), listOf(
            one("k_id", "id", ::id), one("k_fandom", "fandomName")
        )),
        SectionSpec("tombstones", BackupTombstone.serializer(), listOf(
            one("k_id", "id", ::id),
            KeyColumn("k_record", listOf("recordTypeRaw", "recordID")) { v -> if (v[1] == null) null else "${v[0] ?: ""}\u0000${id(v[1])}" },
            one("k_stamp", "lastModifiedAt")
        ))
    )

    val byName: Map<String, SectionSpec> = all.associateBy { it.name }

    @OptIn(ExperimentalSerializationApi::class)
    val knownRootKeys: Set<String> = KudosBackupManifest.serializer().descriptor.let { d ->
        (0 until d.elementsCount).mapTo(HashSet()) { d.getElementName(it) }
    }
}
