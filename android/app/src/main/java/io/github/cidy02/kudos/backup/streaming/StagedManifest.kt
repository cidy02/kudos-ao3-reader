package io.github.cidy02.kudos.backup.streaming

import android.database.sqlite.SQLiteDatabase
import io.github.cidy02.kudos.backup.BackupJson
import io.github.cidy02.kudos.backup.KudosBackupManifest
import java.io.File
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/** One top-level key of the staged document. [kind] is `records` for a known array of records, else the JSON kind of its value. */
data class StagedRootEntry(val ord: Long, val key: String, val kind: String, val known: Boolean, val oversize: Boolean, val chars: Long, val records: Long)

/** A direct member of a record that the typed model does not know, as a char range `[start, stop)` of the record's compact text. */
data class StagedUnknownRange(val name: String, val start: Long, val stop: Long)

/**
 * A manifest that has been read to EOF, validated against the shared input contract and staged on disk.
 * Closing it (or a failed stage) deletes the private directory. Nothing here is wired to a caller yet.
 */
class StagedManifest internal constructor(
    val directory: File,
    internal val db: SQLiteDatabase,
    val version: Int
) : AutoCloseable {
    fun rootEntries(): List<StagedRootEntry> = db.rawQuery(
        "SELECT ord, key, kind, known, oversize, chars, records FROM root ORDER BY ord", null
    ).use { c ->
        buildList {
            while (c.moveToNext()) add(StagedRootEntry(c.getLong(0), c.getString(1), c.getString(2), c.getInt(3) == 1, c.getInt(4) == 1, c.getLong(5), c.getLong(6)))
        }
    }

    fun count(section: String): Long = db.rawQuery("SELECT COUNT(*) FROM ${spec(section).table}", null).use { it.moveToFirst(); it.getLong(0) }

    /** Elements of a section in source order, each as its compact JSON text, in keyset batches. */
    fun forEachRecord(section: String, batch: Int = 200, body: (ord: Long, text: String) -> Unit) {
        val s = spec(section)
        var last = -1L
        while (true) {
            val ords = db.rawQuery("SELECT ord FROM ${s.table} WHERE ord > ? ORDER BY ord LIMIT $batch", arrayOf(last.toString())).use { c ->
                buildList { while (c.moveToNext()) add(c.getLong(0)) }
            }
            if (ords.isEmpty()) return
            for (ord in ords) body(ord, text(s.chunkTable, ord, 0, Long.MAX_VALUE))
            last = ords.last()
        }
    }

    fun recordText(section: String, ord: Long): String = text(spec(section).chunkTable, ord, 0, Long.MAX_VALUE)

    /** The chars `[start, stop)` of a record's compact text: only the chunk rows that overlap are read. */
    fun recordRange(section: String, ord: Long, start: Long, stop: Long): String = text(spec(section).chunkTable, ord, start, stop)

    fun rootText(key: String): String {
        val ord = db.rawQuery("SELECT ord FROM root WHERE key = ?", arrayOf(key)).use { c -> if (c.moveToFirst()) c.getLong(0) else null }
            ?: throw NoSuchElementException(key)
        return text("root_chunk", ord, 0, Long.MAX_VALUE)
    }

    fun unknownRanges(section: String, ord: Long): List<StagedUnknownRange> = db.rawQuery(
        "SELECT name, start, stop FROM unknown_range WHERE section = ? AND ord = ? ORDER BY start", arrayOf(section, ord.toString())
    ).use { c -> buildList { while (c.moveToNext()) add(StagedUnknownRange(c.getString(0), c.getLong(1), c.getLong(2))) } }

    /**
     * The raw document as a tree: top-level keys in source order, each record array rebuilt from its
     * staged elements. Holds the whole library in memory: for tests and bounded-size callers only.
     */
    fun reconstructRaw(): JsonObject {
        val map = LinkedHashMap<String, JsonElement>()
        for (entry in rootEntries()) {
            map[entry.key] = if (entry.kind == "records") {
                val items = ArrayList<JsonElement>()
                forEachRecord(entry.key) { _, text -> items += Json.parseToJsonElement(text) }
                JsonArray(items)
            } else {
                Json.parseToJsonElement(rootText(entry.key))
            }
        }
        return JsonObject(map)
    }

    /** The typed manifest (not yet through `BackupValidator.validateManifest`) and the raw view it was decoded from. */
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

    override fun close() {
        runCatching { db.close() }
        directory.deleteRecursively()
    }

    private fun spec(section: String) = ManifestSections.byName[section] ?: throw IllegalArgumentException("unknown section $section")

    private fun text(table: String, ord: Long, start: Long, stop: Long): String {
        val sb = StringBuilder()
        var offset = 0L
        db.rawQuery("SELECT seq, len FROM $table WHERE ord = ? ORDER BY seq", arrayOf(ord.toString())).use { c ->
            val parts = ArrayList<Pair<Int, Long>>()
            while (c.moveToNext()) parts += c.getInt(0) to c.getLong(1)
            for ((seq, len) in parts) {
                val chunkStart = offset
                offset += len
                if (offset <= start) continue
                if (chunkStart >= stop) break
                db.rawQuery("SELECT data FROM $table WHERE ord = ? AND seq = ?", arrayOf(ord.toString(), seq.toString())).use { d ->
                    d.moveToFirst()
                    val data = d.getString(0)
                    val from = (start - chunkStart).coerceAtLeast(0).toInt()
                    val to = (stop - chunkStart).coerceAtMost(len).toInt()
                    sb.append(data, from, to)
                }
            }
        }
        return sb.toString()
    }
}
