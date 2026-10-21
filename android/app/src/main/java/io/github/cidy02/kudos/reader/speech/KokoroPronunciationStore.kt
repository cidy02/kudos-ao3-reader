package io.github.cidy02.kudos.reader.speech

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** The manifest carries these three dictionaries verbatim, without the file's version key. */
@Serializable
data class PronunciationCorrections(
    val global: Map<String, String> = emptyMap(),
    val fandoms: Map<String, Map<String, String>> = emptyMap(),
    val works: Map<String, Map<String, String>> = emptyMap()
) {
    /** iOS KudosBackupPronunciations.apply: incoming wins, local-only entries always survive. */
    fun merging(incoming: PronunciationCorrections) = PronunciationCorrections(
        global + incoming.global,
        mergeLayers(fandoms, incoming.fandoms),
        mergeLayers(works, incoming.works)
    )

    fun lexicon(fandom: String? = null, workID: String? = null): Map<String, String> =
        global + fandoms[fandom].orEmpty() + works[workID].orEmpty()

    private fun mergeLayers(local: Map<String, Map<String, String>>, incoming: Map<String, Map<String, String>>) =
        local + incoming.mapValues { (key, words) -> local[key].orEmpty() + words }
}

/** Hand-made data in filesDir, never in the disposable/downloadable TTS model directory. */
class KokoroPronunciationStore(filesDir: File) {
    val file = File(filesDir, "kokoro-pronunciations.json")

    @Serializable
    data class Document(
        val version: Int = 1,
        val global: Map<String, String> = emptyMap(),
        val fandoms: Map<String, Map<String, String>> = emptyMap(),
        val works: Map<String, Map<String, String>> = emptyMap()
    ) {
        fun corrections() = PronunciationCorrections(global, fandoms, works)
    }

    fun load(): Document = synchronized(lock) {
        // A malformed existing file must not turn into an empty file on the next edit.
        if (file.exists()) json.decodeFromString<Document>(file.readText()) else Document()
    }

    fun save(document: Document) = synchronized(lock) {
        file.parentFile!!.mkdirs()
        val temporary = Files.createTempFile(file.parentFile!!.toPath(), ".pronunciations-", ".json")
        try {
            Files.write(temporary, json.encodeToString(document).toByteArray(Charsets.UTF_8))
            Files.move(temporary, file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            Unit
        } finally {
            Files.deleteIfExists(temporary)
        }
    }

    fun apply(incoming: PronunciationCorrections) = synchronized(lock) {
        if (incoming == PronunciationCorrections()) return@synchronized
        val held = load()
        val merged = held.corrections().merging(incoming)
        save(held.copy(global = merged.global, fandoms = merged.fandoms, works = merged.works))
    }

    /** Global editor, like iOS. A rename removes the old key and adds the new one atomically. */
    fun setOverride(word: String, ipa: String, previousWord: String? = null) = synchronized(lock) {
        require(word.isNotBlank() && ipa.isNotBlank())
        val held = load()
        save(held.copy(global = (held.global - listOfNotNull(previousWord)) + (word to ipa)))
    }

    fun removeOverride(word: String) = synchronized(lock) {
        val held = load()
        save(held.copy(global = held.global - word))
    }

    companion object {
        private val lock = Any() // Shared across Settings, reader, backup and sync instances.
        private val json = Json { encodeDefaults = true; ignoreUnknownKeys = true }
    }
}

/** iOS beginPronunciationCorrection: first token only; preserve case and ASCII ' and -. */
internal fun pronunciationSelectionWord(selection: String): String {
    val first = selection.trimStart { it.isWhitespace() || Character.isSpaceChar(it) }
        .takeWhile { !it.isWhitespace() && !Character.isSpaceChar(it) }
    val points = first.codePoints().toArray()
    fun kept(point: Int) = Character.isLetterOrDigit(point) || point == '\''.code || point == '-'.code
    val start = points.indexOfFirst(::kept)
    if (start < 0) return ""
    val end = points.indexOfLast(::kept)
    return String(points, start, end - start + 1)
}

/** Paste syntax shared with Misaki and iOS; no JVM-only regex flags (Android ICU). */
internal object KokoroInlinePronunciation {
    private val pattern = Regex("""\[\s*([^\[\]]+?)\s*\]\s*\(\s*/([^/]+)/\s*\)""")
    fun entries(text: String): List<Pair<String, String>> = pattern.findAll(text).mapNotNull {
        val word = it.groupValues[1].trim()
        val ipa = it.groupValues[2].trim()
        if (word.isEmpty() || ipa.isEmpty()) null else word to ipa
    }.toList()
    fun text(entries: Map<String, String>): String = entries.entries.joinToString("\n") { (word, ipa) ->
        "[$word](/$ipa/)"
    }
}
