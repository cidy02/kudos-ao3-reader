package io.github.cidy02.kudos.network.ao3.writing.recovery

import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.FileTime
import java.security.MessageDigest
import java.text.Normalizer
import java.time.Clock
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Shared serial IO executor; blocks below never suspend, so state and disk writes cannot interleave. */
internal val writingRecoveryIO = Dispatchers.IO.limitedParallelism(1)

/** E1 device-local files, independent of Room and Kudos backup/sync. Synchronous methods are IO-only. */
class WritingTextRecovery(val directory: Path, private val clock: Clock = Clock.systemUTC()) {
    @Serializable
    data class Entry(val text: String, val originalDigest: String, val savedAt: Double)
    data class Copy(val url: Path, val entry: Entry)

    fun fileURL(account: String, target: String, field: String): Path {
        val key = listOf(account.lowercase(Locale.ROOT), target, field).joinToString("") {
            "${it.toByteArray(Charsets.UTF_8).size}:$it"
        }
        return directory.resolve("${digest(key)}.json")
    }

    fun sessionURL(key: Path, session: UUID = UUID.randomUUID()): Path =
        key.resolveSibling("${key.fileName.toString().removeSuffix(".json")}.${session.toString().uppercase(Locale.ROOT)}.json")

    fun load(from: Path): Entry? {
        if (!Files.exists(from)) return null
        val source = Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(Files.readAllBytes(from))).toString()
        return json.decodeFromString<Entry>(source)
    }

    /** Each malformed copy is skipped independently. Sort decoded copies by savedAt, as on iOS. */
    fun copies(key: Path): List<Copy> = copyFileURLs(key.fileName.toString().removeSuffix(".json") + ".")
        .mapNotNull { url -> runCatching { load(url)?.let { Copy(url, it) } }.getOrNull() }
        .sortedByDescending { it.entry.savedAt }

    /** §8.5 / iOS loadRecoveries: no timestamp comparison to the form; offer every differing copy. */
    suspend fun copiesOnOpen(key: Path, currentSession: Path, formText: String): List<Copy> =
        withContext(writingRecoveryIO) {
            // Swift String equality is canonical Unicode equality. Preserve the actual source bytes.
            val normalizedForm = Normalizer.normalize(formText, Normalizer.Form.NFC)
            copies(key).filter {
                it.url.fileName != currentSession.fileName &&
                    Normalizer.normalize(it.entry.text, Normalizer.Form.NFC) != normalizedForm
            }
        }

    suspend fun deleteCopy(copy: Copy) = withContext(writingRecoveryIO) { Files.delete(copy.url) }

    fun save(text: String, original: String, to: Path) = saveDigest(text, digest(original), to)

    internal fun saveDigest(text: String, originalDigest: String, to: Path) {
        Files.createDirectories(directory)
        val now = clock.instant()
        val entry = Entry(text, originalDigest, (now.epochSecond - foundationEpoch).toDouble() + now.nano / 1e9)
        val bytes = encode(entry)
        val temporary = Files.createTempFile(directory, ".writing-", ".tmp")
        try {
            FileOutputStream(temporary.toFile()).use { output ->
                output.write(bytes)
                output.fd.sync()
            }
            // No non-atomic fallback: failure must preserve the previous complete copy.
            Files.move(temporary, to, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally {
            Files.deleteIfExists(temporary)
        }
        runCatching { prune(to) }
    }

    /** Keep the current file plus four newest others; metadata only, best-effort deletion. */
    fun prune(around: Path) {
        val name = around.fileName.toString()
        copyFileURLs(name.substringBefore('.') + ".")
            .filter { it.fileName.toString() != name }
            .drop(copyLimit - 1)
            .forEach { runCatching { Files.deleteIfExists(it) } }
    }

    fun allCopyURLs(): List<Path> = runCatching { jsonFiles() }.getOrDefault(emptyList())

    private fun jsonFiles(): List<Path> {
        if (!Files.exists(directory)) return emptyList()
        return Files.newDirectoryStream(directory).use { files ->
            files.filter { it.fileName.toString().endsWith(".json") }
        }
    }

    private fun copyFileURLs(prefix: String): List<Path> = jsonFiles()
        .filter { it.fileName.toString().startsWith(prefix) }
        .map { it to runCatching { Files.getLastModifiedTime(it) }.getOrDefault(FileTime.fromMillis(Long.MIN_VALUE)) }
        .sortedWith(compareByDescending<Pair<Path, FileTime>> { it.second }.thenByDescending { it.first.fileName.toString() })
        .map { it.first }

    companion object {
        const val copyLimit = 5
        private const val foundationEpoch = 978_307_200L
        private val json = Json { ignoreUnknownKeys = true }

        /** Future editor supplies Context.filesDir.toPath(); no app callers are installed by this brief. */
        fun inFilesDir(filesDir: Path, clock: Clock = Clock.systemUTC()): WritingTextRecovery =
            WritingTextRecovery(filesDir.resolve("WritingTextRecovery"), clock)

        fun digest(text: String): String = MessageDigest.getInstance("SHA-256")
            .digest(text.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it.toInt() and 0xff) }

        /** Foundation-compatible E1 values/escaping; Foundation's unsorted member order is unspecified. */
        internal fun encode(entry: Entry): ByteArray {
            require(entry.savedAt.isFinite())
            val value = buildJsonObject {
                put("text", entry.text)
                put("originalDigest", entry.originalDigest)
                put("savedAt", if (entry.savedAt == entry.savedAt.toLong().toDouble())
                    JsonPrimitive(entry.savedAt.toLong()) else JsonPrimitive(entry.savedAt))
            }
            // Default Foundation JSONEncoder escapes forward slashes too, without ASCII-escaping Unicode.
            return value.toString().replace("/", "\\/").toByteArray(Charsets.UTF_8)
        }
    }
}
