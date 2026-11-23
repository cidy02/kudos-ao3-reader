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
    /** Size of the input when known; sizes the up-front disk reservation and the staging budget. */
    val expectedBytes: Long? = null,
    /** Polled at every read-buffer refill (16 Ki chars), after the parse, between finalization steps and before returning. */
    val isCancelled: () -> Boolean = { false },
    /** Free bytes where the staging directory lives (overridable so a full disk can be tested). */
    val freeSpace: (File) -> Long = { it.usableSpace },
    /** Called after each commit with the number of rows staged so far. */
    val checkpoint: (Long) -> Unit = {}
)

/** What the sync recovery predicate may conclude about a live document (a complete file is never replaced from `.bak` unless MALFORMED). */
enum class RecoveryVerdict { WELL_FORMED, MALFORMED, PROTECT }

/**
 * Validates a manifest to EOF under the shared input contract and stages it in a private SQLite database.
 * Not called by any production path yet (A-567 P2). On every failure the staging directory is deleted
 * before the exception leaves (a directory that cannot be deleted is attached as a suppressed `IOException`);
 * on success the caller owns the returned [StagedManifest] and must close it.
 *
 * Precedence, decided once the whole document has been read: I/O > cancellation > syntax > resource > schema
 * (typed decode of every record and of the root fields) > unsupported version. Depth beyond 512 is the one resource
 * outcome raised as soon as it is seen. `BackupValidator.validateManifest` is a separate step ([StagedManifest.validate]).
 *
 * shortcut: the root fields (version, exportedAt, settings, exportedBy, pronunciations) are decoded in memory, so each is
 * limited to [StagingSink.MAX_ROOT_VALUE_BYTES] source bytes; record arrays and unknown top-level values have no such limit.
 */
object ManifestStager {
    /** Measured staging high-water is about 1.5x the input; the reservation and the budget are 1.7x + 16 MiB. */
    private const val DISK_FACTOR = 1.7
    private const val DISK_EXTRA = 16L * 1024 * 1024

    fun stage(input: InputStream, stagingRoot: File, options: ManifestStageOptions = ManifestStageOptions()): StagedManifest {
        var directory: File? = null
        var writer: StagingWriter? = null
        try {
            stagingRoot.mkdirs()
            val budget = options.expectedBytes?.let { (it * DISK_FACTOR).toLong() + DISK_EXTRA }
            val needed = budget ?: StagingWriter.MIN_FREE_BYTES
            if (options.freeSpace(stagingRoot) < needed) {
                throw ManifestStageException.ResourceExhausted("not enough free disk space to stage the manifest")
            }
            val dir = Files.createTempDirectory(stagingRoot.toPath(), "manifest-").toFile().also { directory = it }
            val w = StagingWriter(dir, { options.freeSpace(dir) }, budget, options.checkpoint).also { writer = it }
            val holder = SourceHolder()
            val cancelled = { if (options.isCancelled()) throw ManifestStageException.Cancelled() }
            val sink = StagingSink(w, holder) { w.maybeCommit() }
            val tokenizer = ManifestTokenizer(input, sink, options.isCancelled)
            holder.source = tokenizer
            try {
                tokenizer.parseDocument()
            } catch (e: ManifestStageException.Invalid) {
                if (options.isCancelled()) throw ManifestStageException.Cancelled() // cancellation outranks syntax
                throw e
            }
            cancelled()
            sink.resourceFailure?.let { throw ManifestStageException.ResourceExhausted(it) }
            w.commitAll()
            cancelled()
            sink.pendingFailure?.let { throw ManifestStageException.Invalid(it, syntactic = false) }
            val manifest = decodeRoot(w)
            if (!BackupVersion.isSupported(manifest.version)) throw ManifestStageException.UnsupportedVersion(manifest.version)
            w.finish(mapOf("version" to manifest.version.toString(), "exportedAt" to manifest.exportedAt), cancelled)
            cancelled()
            return StagedManifest(dir, w.db, manifest.version)
        } catch (t: Throwable) {
            writer?.abandon()
            val mapped = map(t)
            val dir = directory
            if (dir != null && dir.exists() && !dir.deleteRecursively()) mapped.addSuppressed(IOException("could not delete the staging directory $dir"))
            throw mapped
        }
    }

    /** One tokenizer position shared with the sink, which is built before the tokenizer. */
    private class SourceHolder : SourcePosition {
        var source: SourcePosition? = null
        override fun sourceBytes() = source!!.sourceBytes()
        override val valueStart get() = source!!.valueStart
    }

    /**
     * Verdict for a live document: [RecoveryVerdict.MALFORMED] only for a syntax error (the sole case that may be replaced
     * from `.bak`). Depth beyond the ceiling, any resource limit, an I/O failure or cancellation protect the live file.
     */
    fun recoveryVerdict(input: InputStream, isCancelled: () -> Boolean = { false }): RecoveryVerdict = try {
        ManifestTokenizer(input, object : ManifestEvents {
            override fun beginObject() {}
            override fun endObject() {}
            override fun beginArray() {}
            override fun endArray() {}
            override fun name(name: String) {}
            override fun stringChunk(buffer: CharArray, offset: Int, length: Int, last: Boolean) {}
            override fun literal(text: String) {}
        }, isCancelled).parseDocument()
        RecoveryVerdict.WELL_FORMED
    } catch (e: ManifestStageException.Invalid) {
        if (e.syntactic) RecoveryVerdict.MALFORMED else RecoveryVerdict.PROTECT // a complete array is a schema failure: protected like any rejected whole document
    } catch (e: ManifestStageException) {
        RecoveryVerdict.PROTECT
    }

    /**
     * Deletes staging runs under [stagingRoot] that a crashed process left behind: directories named `manifest-*` that carry
     * the run marker and have not been touched for [staleAfterMillis] (a live run refreshes its marker at every commit).
     * Call once at startup. Returns the deleted directories and the ones that could not be deleted.
     */
    fun sweepStaleRuns(stagingRoot: File, staleAfterMillis: Long = 60L * 60 * 1000, now: Long = System.currentTimeMillis()): SweepResult {
        val deleted = mutableListOf<File>()
        val failed = mutableListOf<File>()
        stagingRoot.listFiles { f -> f.isDirectory && f.name.startsWith("manifest-") }.orEmpty().forEach { dir ->
            val marker = File(dir, StagingWriter.MARKER)
            if (!marker.isFile || now - marker.lastModified() < staleAfterMillis) return@forEach
            if (dir.deleteRecursively()) deleted += dir else failed += dir
        }
        return SweepResult(deleted, failed)
    }

    class SweepResult(val deleted: List<File>, val failed: List<File>)

    /** Typed decode of the root fields (every known key that is not a record array); the arrays decode to their defaults. */
    private fun decodeRoot(w: StagingWriter): KudosBackupManifest {
        val slim = LinkedHashMap<String, JsonElement>()
        w.db.rawQuery("SELECT ord, key FROM root WHERE known = 1 AND kind != 'records' ORDER BY ord", null).use { c ->
            while (c.moveToNext()) slim[c.getString(1)] = Json.parseToJsonElement(w.readText("root_chunk", c.getLong(0)))
        }
        return try {
            BackupJson.decodeFromJsonElement(KudosBackupManifest.serializer(), JsonObject(slim))
        } catch (e: SerializationException) {
            throw ManifestStageException.Invalid(e.message ?: "typed decode failed", syntactic = false)
        } catch (e: IllegalArgumentException) {
            throw ManifestStageException.Invalid(e.message ?: "typed decode failed", syntactic = false)
        }
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
