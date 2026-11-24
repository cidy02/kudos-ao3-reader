package io.github.cidy02.kudos.backup.streaming

import android.database.sqlite.SQLiteDatabase
import io.github.cidy02.kudos.backup.BackupError
import io.github.cidy02.kudos.backup.BackupJson
import io.github.cidy02.kudos.backup.BackupValidator
import io.github.cidy02.kudos.backup.BackupWork
import io.github.cidy02.kudos.backup.BackupBookmark
import io.github.cidy02.kudos.backup.BackupFont
import io.github.cidy02.kudos.backup.BackupCollection
import io.github.cidy02.kudos.backup.BackupSavedSearch
import io.github.cidy02.kudos.backup.KudosBackupManifest
import java.io.File
import java.io.IOException
import java.time.Instant
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromStream

/** One top-level key of the staged document. [kind] is `records` for a known array of records, else the JSON kind of its value. */
data class StagedRootEntry(val ord: Long, val key: String, val kind: String, val known: Boolean, val oversize: Boolean, val chars: Long, val records: Long)

/** A direct member of a record that the typed model does not know, as a char range `[start, stop)` of the record's compact text. */
data class StagedUnknownRange(val name: String, val start: Long, val stop: Long)

/** Row metadata of one staged element; the payload is read only through [StagedManifest.readRecord]. */
data class StagedRecordMeta(val ord: Long, val kind: String, val chars: Long, val sourceBytes: Long, val oversize: Boolean, val keys: Map<String, String?>)

/** How a section appeared in the document: the apply view Replace needs (missing and null are not the same as `[]`). */
enum class SectionPresence { MISSING, NULL, EMPTY, POPULATED }

/**
 * A manifest that has been read to EOF, validated against the shared input contract and staged on disk. Every
 * record was decoded under the typed budget before this handle existed, so a staged run is never partly unchecked.
 * Closing it (or a failed stage) deletes the private directory. Nothing here is wired to a caller yet.
 *
 * Bounded access for P3/P4: [records] (keyset over row metadata), [readRecord] / [readRoot] (a char range to a sink,
 * one chunk row at a time), [unknownRanges]. The `*InMemory` functions and [reconstruct] hold whole texts and trees:
 * tests and small inputs only.
 */
class StagedManifest internal constructor(
    val directory: File,
    internal val db: SQLiteDatabase,
    val version: Int
) : AutoCloseable {
    /** Root metadata keyset page, with a fixed maximum; payloads remain in chunk rows. */
    fun rootEntries(afterOrd: Long = -1, limit: Int = 500): List<StagedRootEntry> = db.rawQuery(
        "SELECT ord, key, kind, known, oversize, chars, records FROM root WHERE ord > ? ORDER BY ord LIMIT ${limit.coerceIn(1, MAX_METADATA_PAGE)}",
        arrayOf(afterOrd.toString())
    ).use { c ->
        buildList {
            while (c.moveToNext()) add(StagedRootEntry(c.getLong(0), c.getString(1), c.getString(2), c.getInt(3) == 1, c.getInt(4) == 1, c.getLong(5), c.getLong(6)))
        }
    }

    fun count(section: String): Long = db.rawQuery("SELECT COUNT(*) FROM ${spec(section).table}", null).use { it.moveToFirst(); it.getLong(0) }

    /** missing / null / `[]` / populated, from the root row, for the apply view (see [ReplacePolicy]). */
    fun presence(section: String): SectionPresence {
        spec(section)
        val row = db.rawQuery("SELECT kind, records FROM root WHERE key = ?", arrayOf(section)).use { c ->
            if (c.moveToFirst()) c.getString(0) to c.getLong(1) else null
        } ?: return SectionPresence.MISSING
        return when {
            row.first == "null" -> SectionPresence.NULL
            row.second == 0L -> SectionPresence.EMPTY
            else -> SectionPresence.POPULATED
        }
    }

    /** Row metadata after [afterOrd] in source order, at most [limit] rows: a keyset cursor, no payloads. */
    fun records(section: String, afterOrd: Long = -1, limit: Int = 500): List<StagedRecordMeta> {
        val s = spec(section)
        val cols = s.keys.joinToString("") { ", ${it.column}" }
        return db.rawQuery("SELECT ord, kind, chars, source_bytes, oversize$cols FROM ${s.table} WHERE ord > ? ORDER BY ord LIMIT ${limit.coerceIn(1, MAX_METADATA_PAGE)}", arrayOf(afterOrd.toString())).use { c ->
            buildList {
                while (c.moveToNext()) {
                    add(StagedRecordMeta(c.getLong(0), c.getString(1), c.getLong(2), c.getLong(3), c.getInt(4) == 1, s.keys.withIndex().associate { (i, k) -> k.column to if (c.isNull(5 + i)) null else c.getString(5 + i) }))
                }
            }
        }
    }

    /** The chars `[from, to)` of a record's compact text handed to [sink] one chunk slice at a time (at most 64 Ki chars each). */
    fun readRecord(section: String, ord: Long, from: Long = 0, to: Long = Long.MAX_VALUE, sink: (CharSequence) -> Unit) =
        range(spec(section).chunkTable, ord, from, to, sink)

    fun readRoot(key: String, from: Long = 0, to: Long = Long.MAX_VALUE, sink: (CharSequence) -> Unit) {
        val ord = db.rawQuery("SELECT ord FROM root WHERE key = ?", arrayOf(key)).use { c -> if (c.moveToFirst()) c.getLong(0) else null }
            ?: throw NoSuchElementException(key)
        range("root_chunk", ord, from, to, sink)
    }

    /** Unknown direct members, paged by their unique start offset. */
    fun unknownRanges(section: String, ord: Long, afterStart: Long = -1, limit: Int = 500): List<StagedUnknownRange> = db.rawQuery(
        "SELECT name, start, stop FROM unknown_range WHERE section = ? AND ord = ? AND start > ? ORDER BY start LIMIT ${limit.coerceIn(1, MAX_METADATA_PAGE)}",
        arrayOf(section, ord.toString(), afterStart.toString())
    ).use { c -> buildList { while (c.moveToNext()) add(StagedUnknownRange(c.getString(0), c.getLong(1), c.getLong(2))) } }

    /** Whole record text: tests and small records only. */
    fun recordTextInMemory(section: String, ord: Long, from: Long = 0, to: Long = Long.MAX_VALUE): String =
        StringBuilder().also { sb -> readRecord(section, ord, from, to) { sb.append(it) } }.toString()

    fun rootTextInMemory(key: String): String = StringBuilder().also { sb -> readRoot(key) { sb.append(it) } }.toString()

    /** Whole section, one record text at a time: tests and small inputs only. */
    fun forEachRecordTextInMemory(section: String, body: (ord: Long, text: String) -> Unit) {
        var last = -1L
        while (true) {
            val batch = records(section, last, 200)
            if (batch.isEmpty()) return
            for (r in batch) body(r.ord, recordTextInMemory(section, r.ord))
            last = batch.last().ord
        }
    }

    /**
     * Semantic validation over the final staged metadata (today's `BackupValidator.validateManifest` rules, with the clock
     * fixed by [now]): one record is decoded at a time and batch accounting flushes at 200 records or 16 MiB of
     * source bytes. Duplicate ids across batches use indexed key columns. Call before any mutation.
     */
    fun validate(
        now: Instant = Instant.now(),
        /** Canonical typed projection. Consumers may spool it, but must not mutate the library until validation returns. */
        onValidatedRecord: (String, Long, Any) -> Unit = { _, _, _ -> },
        onBatch: (Int, Long) -> Unit = { _, _ -> }
    ) {
        val head = BackupValidator.validateManifest(KudosBackupManifest(version = version, exportedAt = exportedAt()), now)
        for (name in listOf("works", "bookmarks", "fonts", "collections", "savedSearches")) {
            var last = -1L
            var batchCount = 0
            var batchBytes = 0L
            while (true) {
                val batch = records(name, last, 200)
                if (batch.isEmpty()) break
                for (record in batch) {
                    if (batchCount > 0 && (batchCount == 200 || batchBytes + record.sourceBytes > VALIDATION_BATCH_BYTES)) {
                        onBatch(batchCount, batchBytes)
                        batchCount = 0
                        batchBytes = 0
                    }
                    validateOneRecord(name, record.ord, head, now, onValidatedRecord)
                    batchCount++
                    batchBytes += record.sourceBytes
                }
                last = batch.last().ord
            }
            if (batchCount > 0) onBatch(batchCount, batchBytes)
            val idColumn = spec(name).keys.firstOrNull { it.column == "k_id" }?.column ?: spec(name).keys.first().column
            val dup = db.rawQuery("SELECT $idColumn FROM s_$name WHERE $idColumn IS NOT NULL GROUP BY $idColumn HAVING COUNT(*) > 1 LIMIT 1", null).use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
            if (dup != null && name != "bookmarks") throw BackupError.InvalidPackage("Duplicate ${if (name == "works") "work" else name} id: $dup")
        }
    }

    /** One call frame per record, so its decoded value is unreachable before the next record is read. */
    private fun validateOneRecord(
        name: String, ord: Long, head: KudosBackupManifest, now: Instant,
        onValidatedRecord: (String, Long, Any) -> Unit
    ) {
        val partial = when (name) {
            "works" -> head.copy(works = listOf(decodeRecord(name, ord, BackupWork.serializer())))
            "bookmarks" -> head.copy(bookmarks = listOf(decodeRecord(name, ord, BackupBookmark.serializer())))
            "fonts" -> head.copy(fonts = listOf(decodeRecord(name, ord, BackupFont.serializer())))
            "collections" -> head.copy(collections = listOf(decodeRecord(name, ord, BackupCollection.serializer())))
            "savedSearches" -> head.copy(savedSearches = listOf(decodeRecord(name, ord, BackupSavedSearch.serializer())))
            else -> error("unsupported validation section $name")
        }
        val canonical = BackupValidator.validateManifest(partial, now)
        onValidatedRecord(name, ord, when (name) {
            "works" -> canonical.works.single()
            "bookmarks" -> canonical.bookmarks.single()
            "fonts" -> canonical.fonts.single()
            "collections" -> canonical.collections.single()
            else -> canonical.savedSearches.single()
        })
    }

    @OptIn(ExperimentalSerializationApi::class)
    private fun <T> decodeRecord(section: String, ord: Long, serializer: KSerializer<T>): T =
        StagedChunkInputStream(db, spec(section).chunkTable, ord).use { BackupJson.decodeFromStream(serializer, it) }

    private fun exportedAt(): String = db.rawQuery("SELECT v FROM meta WHERE k = 'exportedAt'", null).use { it.moveToFirst(); it.getString(0) }

    /**
     * The raw document as a tree: top-level keys in source order, each record array rebuilt from its
     * staged elements. Holds the whole library in memory: tests and bounded-size callers only.
     */
    fun reconstructRaw(): JsonObject {
        val map = LinkedHashMap<String, JsonElement>()
        var after = -1L
        while (true) {
            val page = rootEntries(after)
            if (page.isEmpty()) break
            for (entry in page) {
                map[entry.key] = if (entry.kind == "records") {
                    val items = ArrayList<JsonElement>()
                    forEachRecordTextInMemory(entry.key) { _, text -> items += Json.parseToJsonElement(text) }
                    JsonArray(items)
                } else {
                    Json.parseToJsonElement(rootTextInMemory(entry.key))
                }
            }
            after = page.last().ord
        }
        return JsonObject(map)
    }

    /** The typed manifest (not yet through `validateManifest`) and the raw view it was decoded from, as today's reader decodes them. */
    fun reconstruct(): Pair<KudosBackupManifest, JsonObject> {
        val raw = reconstructRaw()
        val manifest = try {
            BackupJson.decodeFromJsonElement(KudosBackupManifest.serializer(), raw)
        } catch (e: SerializationException) {
            throw ManifestStageException.Invalid(e.message ?: "typed decode failed", syntactic = false)
        } catch (e: IllegalArgumentException) {
            throw ManifestStageException.Invalid(e.message ?: "typed decode failed", syntactic = false)
        }
        return manifest to raw
    }

    fun stagedBytes(): Long = directory.walkTopDown().filter { it.isFile }.sumOf { it.length() }

    /** Closes the database and deletes the directory; a directory that cannot be deleted is reported, not ignored. */
    override fun close() {
        runCatching { db.close() }
        if (directory.exists() && !directory.deleteRecursively()) throw IOException("could not delete the staging directory $directory")
    }

    private fun spec(section: String) = ManifestSections.byName[section] ?: throw IllegalArgumentException("unknown section $section")

    companion object {
        const val MAX_METADATA_PAGE = 500
        const val VALIDATION_BATCH_BYTES = 16L * 1024 * 1024
    }

    /** Streams `[from, to)` of one staged text: finds the first overlapping chunk by its indexed start, then walks forward one row at a time. */
    private fun range(table: String, ord: Long, from: Long, to: Long, sink: (CharSequence) -> Unit) {
        var at = from
        while (at < to) {
            val chunk = db.rawQuery("SELECT start, data FROM $table WHERE ord = ? AND start <= ? ORDER BY start DESC LIMIT 1", arrayOf(ord.toString(), at.toString())).use { c ->
                if (c.moveToFirst()) c.getLong(0) to c.getString(1) else null
            } ?: return
            val end = chunk.first + chunk.second.length
            if (end <= at) return // past the last chunk
            val a = (at - chunk.first).toInt()
            val b = (minOf(to, end) - chunk.first).toInt()
            sink(chunk.second.subSequence(a, b))
            at = chunk.first + b
        }
    }
}

/**
 * Replace's handling of a section by how it appeared, decided here and tested before anything is wired (A-567 review,
 * Android finding). Today Android collapses missing, `null` and `[]` into an empty list and `replaceCollections` and its
 * siblings then drop every local row the manifest does not list. The policy is the plan's contract (iOS T-563): for the four
 * guarded sections a missing or `null` section never sweeps local rows, and only a present `[]` (or a populated list) does.
 */
object ReplacePolicy {
    val guardedSections: Set<String> = setOf("collections", "readingQueues", "annotations", "savedSearches")

    /** True when a Replace may remove local rows of [section] that the incoming manifest does not list. */
    fun sweepsLocalRows(section: String, presence: SectionPresence): Boolean =
        section !in guardedSections || presence == SectionPresence.EMPTY || presence == SectionPresence.POPULATED

    /** Local ids that survive a Replace of [section] given what the manifest listed. */
    fun survivors(section: String, presence: SectionPresence, localIds: Set<String>, incomingIds: Set<String>): Set<String> =
        if (sweepsLocalRows(section, presence)) localIds.intersect(incomingIds) else localIds
}
