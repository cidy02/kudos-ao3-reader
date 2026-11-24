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
 * One natural-key column of a staged section, built from one direct scalar member of the record. A missing,
 * null or non-scalar member, or one longer than [ManifestSections.MAX_KEY_CHARS], leaves the column NULL: the
 * resolver falls back to the record payload. Composite identities are separate columns (never one joined
 * string, which two different pairs could produce) with a composite index over them.
 */
internal class KeyColumn(val column: String, val field: String, val make: (String?) -> String? = { it })

/** A top-level array of records the manifest knows by name. */
internal class SectionSpec(
    val name: String,
    val serializer: KSerializer<*>,
    val keys: List<KeyColumn>,
    val compositeIndexes: List<List<String>> = emptyList()
) {
    val table = "s_$name"
    val chunkTable = "s_${name}_chunk"

    @OptIn(ExperimentalSerializationApi::class)
    val knownFields: Set<String> = (0 until serializer.descriptor.elementsCount)
        .mapTo(HashSet()) { serializer.descriptor.getElementName(it) }
}

internal object ManifestSections {
    const val MAX_KEY_CHARS = 2048

    private fun id(value: String?) = value?.let(BackupPaths::normalizeIdForComparison)
    private fun key(column: String, field: String, make: (String?) -> String? = { it }) = KeyColumn(column, field, make)
    private fun idKey(column: String, field: String = "id") = key(column, field, ::id)

    val all: List<SectionSpec> = listOf(
        SectionSpec("works", BackupWork.serializer(), listOf(idKey("k_id"), key("k_ao3", "ao3WorkID") { it?.toIntOrNull()?.toString() }, key("k_url", "sourceURL"))),
        SectionSpec("bookmarks", BackupBookmark.serializer(), listOf(idKey("k_id"), key("k_url", "urlString"))),
        SectionSpec("fonts", BackupFont.serializer(), listOf(
            key("k_file", "fileName") { it?.let(BackupPaths::fontFileNameKey) }, key("k_name", "name") { it?.lowercase() }
        )),
        SectionSpec("collections", BackupCollection.serializer(), listOf(idKey("k_id"))),
        SectionSpec("savedSearches", BackupSavedSearch.serializer(), listOf(idKey("k_id"))),
        SectionSpec("readingQueues", BackupReadingQueue.serializer(), listOf(idKey("k_id"))),
        SectionSpec("readingQueueMemberships", BackupReadingQueueMembership.serializer(), listOf(
            idKey("k_id"), idKey("k_queue", "queueID"), idKey("k_work", "workID")
        ), listOf(listOf("k_queue", "k_work"))),
        SectionSpec("annotations", BackupAnnotation.serializer(), listOf(
            idKey("k_id"), idKey("k_work", "workID"), key("k_locator", "locatorString")
        ), listOf(listOf("k_work", "k_locator"))),
        SectionSpec("readingSessions", BackupReadingSession.serializer(), listOf(idKey("k_id"), idKey("k_work", "workID"))),
        SectionSpec("readingFavorites", BackupReadingFavorite.serializer(), listOf(
            idKey("k_id"), key("k_kind", "kindRaw"), key("k_target", "targetKey")
        ), listOf(listOf("k_kind", "k_target"))),
        SectionSpec("fandomReadWatermarks", BackupFandomReadWatermark.serializer(), listOf(idKey("k_id"), key("k_fandom", "fandomName"))),
        SectionSpec("tombstones", BackupTombstone.serializer(), listOf(
            idKey("k_id"), key("k_rtype", "recordTypeRaw"), idKey("k_rid", "recordID"), key("k_stamp", "lastModifiedAt")
        ), listOf(listOf("k_rtype", "k_rid")))
    )

    val byName: Map<String, SectionSpec> = all.associateBy { it.name }

    @OptIn(ExperimentalSerializationApi::class)
    val knownRootKeys: Set<String> = KudosBackupManifest.serializer().descriptor.let { d ->
        (0 until d.elementsCount).mapTo(HashSet()) { d.getElementName(it) }
    }
}
