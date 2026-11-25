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
import java.io.ByteArrayInputStream
import java.io.SequenceInputStream
import java.nio.file.Files
import java.util.Collections
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.CompositeDecoder
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.decodeFromStream

class ManifestStageOptions(
    /** Size of the input when known; sizes the up-front disk reservation and the staging budget. */
    val expectedBytes: Long? = null,
    /** Polled at every read-buffer refill (16 Ki chars), after the parse, between finalization steps and before returning. */
    val isCancelled: () -> Boolean = { false },
    /** Free bytes where the staging directory lives (overridable so a full disk can be tested). */
    val freeSpace: (File) -> Long = { it.usableSpace },
    /** Test hook for the component-budget boundary; production uses 2.5. */
    val componentBudgetFactor: Double = 2.5,
    /** Called after each commit with the number of rows staged so far. */
    val checkpoint: (Long) -> Unit = {},
    /** Called after a typed record is staged; used by opt-in live-heap measurement. */
    val recordCheckpoint: (Long) -> Unit = {}
)

/** What the sync recovery predicate may conclude about a live document (a complete file is never replaced from `.bak` unless MALFORMED). */
enum class RecoveryVerdict { WELL_FORMED, MALFORMED, PROTECT }

/**
 * Validates a manifest to EOF under the shared input contract and stages it in a private SQLite database.
 * Not called by any production path yet (A-567 P2). On every failure the staging directory is deleted
 * before the exception leaves (a directory that cannot be deleted is attached as a suppressed `IOException`);
 * on success the caller owns the returned [StagedManifest] and must close it.
 *
 * Precedence among observed failures: I/O > cancellation > syntax > root-type schema > resource > other schema
 * (typed decode of every record and of the root fields) > unsupported version. Depth beyond 512 is a resource
 * outcome recorded during scanning; a complete array root is schema even if a limit was also hit.
 * A later I/O error cannot be discovered after an earlier decided syntax error.
 * `BackupValidator.validateManifest` is a separate step ([StagedManifest.validate]).
 *
 * Known root fields are decoded from staged chunks, each bounded by [StagingSink.MAX_ROOT_VALUE_BYTES].
 * Record arrays and unknown top-level values have no such limit.
 */
object ManifestStager {
    /** Measured staging high-water is about 1.5x the input; the shared component budget is 2.5x + 32 MiB. */
    private const val DISK_EXTRA = 32L * 1024 * 1024

    fun stage(input: InputStream, stagingRoot: File, options: ManifestStageOptions = ManifestStageOptions()): StagedManifest {
        var directory: File? = null
        var writer: StagingWriter? = null
        try {
            stagingRoot.mkdirs()
            var bytesRead = 0L
            val factor = options.componentBudgetFactor
            require(factor > 0 && factor.isFinite())
            val budget = { ((options.expectedBytes ?: bytesRead) * factor).toLong() + DISK_EXTRA }
            val needed = options.expectedBytes?.let { budget() } ?: StagingWriter.MIN_FREE_BYTES
            if (options.freeSpace(stagingRoot) < needed) {
                throw ManifestStageException.ResourceExhausted("not enough free disk space to stage the manifest")
            }
            val dir = Files.createTempDirectory(stagingRoot.toPath(), "manifest-").toFile().also { directory = it }
            val w = StagingWriter(dir, { options.freeSpace(dir) }, budget, options.checkpoint).also { writer = it }
            val holder = SourceHolder()
            val cancelled = { if (options.isCancelled()) throw ManifestStageException.Cancelled() }
            val sink = StagingSink(w, holder, options.recordCheckpoint) { w.maybeCommit() }
            val tokenizer = ManifestTokenizer(input, sink, options.isCancelled)
            holder.source = tokenizer
            w.sourceBytes = { tokenizer.sourceBytes().also { bytesRead = it } }
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

    /** Decode and release one known root value at a time, without assembling root strings or trees. */
    @OptIn(ExperimentalSerializationApi::class)
    private fun decodeRoot(w: StagingWriter): KudosBackupManifest {
        var version: Int? = null
        var exportedAt: String? = null
        try {
            w.db.rawQuery("SELECT ord, key, kind FROM root WHERE known = 1 AND kind != 'records' ORDER BY ord", null).use { c ->
                while (c.moveToNext()) {
                    val key = c.getString(1) // known serializer field names are ASCII literals
                    val ord = c.getLong(0)
                    if (c.getString(2) == "null" && key in setOf("settings", "pronunciations")) continue
                    if (key == "settings") {
                        w.openTextStream("root_chunk", ord).use { BackupJson.decodeFromStream(RootSettingsShape.serializer(), it) }
                        continue
                    }
                    if (key == "pronunciations") {
                        w.openTextStream("root_chunk", ord).use { BackupJson.decodeFromStream(RootPronunciationShape.serializer(), it) }
                        continue
                    }
                    val prefix = when (key) {
                        "version" -> "{\"exportedAt\":\"\",\"version\":"
                        "exportedAt" -> "{\"version\":8,\"exportedAt\":"
                        else -> "{\"version\":8,\"exportedAt\":\"\",\"$key\":"
                    }
                    val parts = listOf(
                        ByteArrayInputStream(prefix.toByteArray(Charsets.UTF_8)),
                        w.openTextStream("root_chunk", ord),
                        ByteArrayInputStream("}".toByteArray(Charsets.UTF_8))
                    )
                    val decoded = SequenceInputStream(Collections.enumeration(parts)).use {
                        BackupJson.decodeFromStream(KudosBackupManifest.serializer(), it)
                    }
                    when (key) {
                        "version" -> version = decoded.version
                        "exportedAt" -> exportedAt = decoded.exportedAt
                    }
                }
            }
            // Required fields retain the production serializer's missing-field failure.
            if (version == null || exportedAt == null) {
                BackupJson.decodeFromStream(KudosBackupManifest.serializer(), "{}".byteInputStream())
            }
            return KudosBackupManifest(version = version!!, exportedAt = exportedAt!!)
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

/** Mirrors BackupSettingsPayload's typed fields. Its JsonElement field accepts any valid JSON, already
 * checked by ManifestTokenizer, so it is deliberately omitted to avoid building a large DOM. */
@Serializable
internal data class RootSettingsShape(
    val readerFontID: String = "system",
    val readerMode: String = "scroll",
    val readerTwoPage: Boolean = false,
    val readerCustomize: Boolean = false,
    val readerBoldText: Boolean = false,
    val readerFontPt: Double = 18.0,
    val readerLineHeight: Double = 1.65,
    val readerLetterSpacing: Double = 0.0,
    val readerWordSpacing: Double = 0.0,
    val readerMargin: Double = 28.0,
    val readerJustify: Boolean = false,
    val confirmBeforeDelete: Boolean = true,
    val hideMatureContent: Boolean = true,
    val matureContentMode: String = "obscure",
    val requireBiometricToReveal: Boolean = false,
    val appTheme: String = "light",
    val readerTheme: String = "light",
    val matchAppReaderTheme: Boolean = true,
    val accentColorHex: String? = null,
    val workSymbolPlacement: String? = null,
    val autoPreserveSmallSeriesOnSaveForLater: Boolean = false,
    val autoPreserveSeriesWorkThreshold: Int = 5
)

@Serializable
internal data class RootPronunciationShape(
    @Serializable(with = DiscardStringMap::class) val global: Unit = Unit,
    @Serializable(with = DiscardNestedStringMap::class) val fandoms: Unit = Unit,
    @Serializable(with = DiscardNestedStringMap::class) val works: Unit = Unit
)

/** Decode every map entry through the production primitive decoder, then discard it before the next entry. */
internal object DiscardStringMap : KSerializer<Unit> {
    override val descriptor: SerialDescriptor = MapSerializer(String.serializer(), String.serializer()).descriptor
    override fun deserialize(decoder: Decoder) {
        val map = decoder.beginStructure(descriptor)
        if (map.decodeSequentially()) {
            val count = map.decodeCollectionSize(descriptor)
            for (i in 0 until count) {
                map.decodeStringElement(descriptor, 2 * i)
                map.decodeStringElement(descriptor, 2 * i + 1)
            }
        } else {
            while (true) {
                val index = map.decodeElementIndex(descriptor)
                if (index == CompositeDecoder.DECODE_DONE) break
                map.decodeStringElement(descriptor, index)
            }
        }
        map.endStructure(descriptor)
    }
    override fun serialize(encoder: Encoder, value: Unit): Nothing = error("validation serializer is decode-only")
}

internal object DiscardNestedStringMap : KSerializer<Unit> {
    override val descriptor: SerialDescriptor = MapSerializer(String.serializer(), DiscardStringMap).descriptor
    override fun deserialize(decoder: Decoder) {
        val map = decoder.beginStructure(descriptor)
        if (map.decodeSequentially()) {
            val count = map.decodeCollectionSize(descriptor)
            for (i in 0 until count) {
                map.decodeStringElement(descriptor, 2 * i)
                map.decodeSerializableElement(descriptor, 2 * i + 1, DiscardStringMap)
            }
        } else {
            while (true) {
                val index = map.decodeElementIndex(descriptor)
                if (index == CompositeDecoder.DECODE_DONE) break
                if (index % 2 == 0) map.decodeStringElement(descriptor, index)
                else map.decodeSerializableElement(descriptor, index, DiscardStringMap)
            }
        }
        map.endStructure(descriptor)
    }
    override fun serialize(encoder: Encoder, value: Unit): Nothing = error("validation serializer is decode-only")
}
