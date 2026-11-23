package io.github.cidy02.kudos.backup.streaming

import android.database.sqlite.SQLiteDatabaseCorruptException
import android.database.sqlite.SQLiteDiskIOException
import android.database.sqlite.SQLiteException
import android.database.sqlite.SQLiteFullException
import io.github.cidy02.kudos.backup.BackupJson
import io.github.cidy02.kudos.backup.BackupVersion
import io.github.cidy02.kudos.backup.KudosBackupManifest
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.nio.file.Files
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

class ManifestStageOptions(
    /** Size of the input when known; used for the up-front free-disk check. */
    val expectedBytes: Long? = null,
    /** Polled at every read-buffer refill (16 Ki chars); true stops the run with [ManifestStageException.Cancelled]. */
    val isCancelled: () -> Boolean = { false },
    /** Free bytes where the staging directory lives (overridable so a full disk can be tested). */
    val freeSpace: (File) -> Long = { it.usableSpace },
    /** Called after each commit with the number of rows staged so far. */
    val checkpoint: (Long) -> Unit = {}
)

/**
 * Validates a manifest to EOF under the shared input contract and stages it in a private SQLite database.
 * Not called by any production path yet (A-567 P2). On every failure the staging directory is deleted
 * before the exception leaves; on success the caller owns the returned [StagedManifest] and must close it.
 *
 * Evaluation order (today's route, `BackupValidator.decodeManifestWithRaw`): the document is parsed
 * completely (I/O, cancellation and syntax outcomes first), then every element and the root fields are
 * decoded with the existing kotlinx types, then the version is checked. Cross-record and clock
 * validation (`BackupValidator.validateManifest`) is a separate step on the staged data.
 *
 * shortcut: the root fields (version, exportedAt, settings, exportedBy, pronunciations) are decoded in memory,
 * so a known root value over [MAX_ROOT_VALUE_CHARS] is rejected as resource exhaustion; unknown top-level
 * values and record arrays are chunked and have no such limit. Revisit if settings can legitimately grow.
 */
object ManifestStager {
    const val MAX_ROOT_VALUE_CHARS = 16L * 1024 * 1024
    private const val BYTES_FACTOR = 3L

    fun stage(input: InputStream, stagingRoot: File, options: ManifestStageOptions = ManifestStageOptions()): StagedManifest {
        var directory: File? = null
        var writer: StagingWriter? = null
        try {
            stagingRoot.mkdirs()
            val needed = (options.expectedBytes ?: 0L) * BYTES_FACTOR + StagingWriter.MIN_FREE_BYTES
            if (options.freeSpace(stagingRoot) < needed) {
                throw ManifestStageException.ResourceExhausted("not enough free disk space to stage the manifest")
            }
            val dir = Files.createTempDirectory(stagingRoot.toPath(), "manifest-").toFile().also { directory = it }
            val w = StagingWriter(File(dir, "staging.db"), { options.freeSpace(dir) }, options.checkpoint).also { writer = it }
            val sink = StagingSink(w) { w.maybeCommit() }
            ManifestTokenizer(input, sink, options.isCancelled).parseDocument()
            w.commitAll()
            sink.pendingFailure?.let { throw ManifestStageException.Invalid(it, syntactic = false) }
            val manifest = decodeRoot(w)
            if (!BackupVersion.isSupported(manifest.version)) throw ManifestStageException.UnsupportedVersion(manifest.version)
            w.finish(mapOf("version" to manifest.version.toString(), "exportedAt" to manifest.exportedAt))
            return StagedManifest(dir, w.db, manifest.version)
        } catch (t: Throwable) {
            writer?.abandon()
            directory?.deleteRecursively()
            throw map(t)
        }
    }

    /** True when the bytes are well formed under the shared contract (the sync recovery predicate); stages nothing durable. */
    fun isWellFormedObject(input: InputStream, isCancelled: () -> Boolean = { false }): Boolean = try {
        ManifestTokenizer(input, object : ManifestEvents {
            override fun beginObject() {}
            override fun endObject() {}
            override fun beginArray() {}
            override fun endArray() {}
            override fun name(name: String) {}
            override fun stringChunk(buffer: CharArray, offset: Int, length: Int, last: Boolean) {}
            override fun literal(text: String) {}
        }, isCancelled).parseDocument()
        true
    } catch (e: ManifestStageException.Invalid) {
        false
    }

    /** Typed decode of the root fields (every known key that is not a record array); the arrays decode to their defaults. */
    private fun decodeRoot(w: StagingWriter): KudosBackupManifest {
        val slim = LinkedHashMap<String, JsonElement>()
        w.db.rawQuery("SELECT ord, key, chars, oversize FROM root WHERE known = 1 AND kind != 'records' ORDER BY ord", null).use { c ->
            while (c.moveToNext()) {
                if (c.getLong(2) > MAX_ROOT_VALUE_CHARS) throw ManifestStageException.ResourceExhausted("the value of '${c.getString(1)}' is too large to decode")
                slim[c.getString(1)] = Json.parseToJsonElement(rootText(w, c.getLong(0)))
            }
        }
        return try {
            BackupJson.decodeFromJsonElement(KudosBackupManifest.serializer(), JsonObject(slim))
        } catch (e: SerializationException) {
            throw ManifestStageException.Invalid(e.message ?: "typed decode failed", syntactic = false)
        } catch (e: IllegalArgumentException) {
            throw ManifestStageException.Invalid(e.message ?: "typed decode failed", syntactic = false)
        }
    }

    private fun rootText(w: StagingWriter, ord: Long): String {
        val sb = StringBuilder()
        w.db.rawQuery("SELECT data FROM root_chunk WHERE ord = ? ORDER BY seq", arrayOf(ord.toString())).use { c -> while (c.moveToNext()) sb.append(c.getString(0)) }
        return sb.toString()
    }

    internal fun map(t: Throwable): Throwable = when (t) {
        is ManifestStageException -> t
        is SQLiteFullException -> ManifestStageException.ResourceExhausted("the disk is full", t)
        is SQLiteDiskIOException, is SQLiteDatabaseCorruptException, is SQLiteException -> ManifestStageException.Io(t)
        is IOException -> ManifestStageException.Io(t)
        is kotlin.coroutines.cancellation.CancellationException -> ManifestStageException.Cancelled()
        is OutOfMemoryError -> ManifestStageException.ResourceExhausted("out of memory", t)
        else -> t
    }
}
