package io.github.cidy02.kudos.reader

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.content.Content
import org.readium.r2.shared.publication.services.content.content

/**
 * Extracts plain text from the publication for TTS, starting at [from] when set.
 * Uses Readium ContentService when available; falls back to empty.
 */
@OptIn(ExperimentalReadiumApi::class)
object ReaderContentText {
    private const val CHUNK = 350

    /** iOS disables Read aloud when Readium has no extractable content service. */
    fun isAvailable(publication: Publication): Boolean =
        runCatching { publication.content() != null }.getOrDefault(false)

    /** A pull source: no other resource is read until speech asks for its next paragraph. */
    fun source(
        publication: Publication,
        from: Locator? = null,
        readAuthorNotes: Boolean = true
    ): ReaderSpeechSource {
        return source(readAuthorNotes) { publication.content(from) }
    }

    internal fun source(readAuthorNotes: Boolean, content: () -> Content?): ReaderSpeechSource {
        var iterator: Content.Iterator? = null
        var initialized = false
        val filter = SpeechFilter(readAuthorNotes)
        var chunks: Iterator<String> = emptyList<String>().iterator()
        return ReaderSpeechSource {
            withContext(Dispatchers.IO) {
                if (!initialized) {
                    iterator = content()?.iterator()
                    initialized = true
                }
                while (!chunks.hasNext()) {
                    val element = iterator?.nextOrNull() ?: return@withContext null
                    val text = (element as? Content.TextualElement)?.text ?: continue
                    val spoken = filter.paragraph(SpeechBlock(
                        text, (element as? Content.TextElement)?.role is Content.TextElement.Role.Quote
                    )) ?: continue
                    chunks = splitIntoSpeakableChunks(spoken).iterator()
                }
                chunks.next()
            }
        }
    }

    internal data class SpeechBlock(val text: String, val isQuote: Boolean = false)

    /** One paragraph per line, none a quote: what the tests give. */
    internal fun speakableParagraphs(text: String): List<String> =
        speakableParagraphs(text.split('\n').map { SpeechBlock(it) }, readAuthorNotes = true)

    /**
     * iOS's `KokoroBoilerplateFilter` (3ea). Readium gives one paragraph per line; they were
     * run together, AO3's own labels ("Chapter Notes", "Summary") and its closing plug were
     * read out, and a link was spelt out letter by letter. Now each paragraph is its own
     * stretch, a paragraph that is nothing but a label is dropped (a note that only starts
     * with one is read), and a link is said as its site ("tumblr.com.").
     */
    internal fun speakableParagraphs(blocks: List<SpeechBlock>, readAuthorNotes: Boolean): List<String> {
        val filter = SpeechFilter(readAuthorNotes)
        return blocks.mapNotNull(filter::paragraph)
    }

    /** Retains the author's-note boundary while paragraphs are pulled one at a time. */
    private class SpeechFilter(private val readAuthorNotes: Boolean) {
        private var inSkippedNote = false

        fun paragraph(block: SpeechBlock): String? {
            val paragraph = block.text.replace(WHITESPACE, " ").trim()
            if (paragraph.isEmpty()) return null
            val plain = normalized(paragraph)
            if (plain in LABELS || plain == KUDOS_PLUG) {
                inSkippedNote = !readAuthorNotes && plain in LABELS
                return null
            }
            if (inSkippedNote) {
                if (block.isQuote) return null
                inSkippedNote = false
            }
            return URL.replace(paragraph) { host(it.value) }
        }
    }

    private val WHITESPACE = Regex("\\s+")
    private val URL = Regex("(?:https?://|www\\.)\\S+")
    private val LABELS = setOf(
        "Summary", "Notes", "End Notes", "Chapter Summary", "Chapter Notes",
        "Author's Note", "Author's Note:"
    )
    private const val KUDOS_PLUG =
        "Please drop by the Archive and comment to let the creator know if you enjoyed their work!"

    private fun normalized(text: String) = text.replace('\u2019', '\'').replace('\u2018', '\'')

    private fun host(run: String): String {
        val rest = run.substringAfter("://").removePrefix("www.")
        val host = rest.takeWhile { it !in "/?#" }
        if (host.isEmpty()) return "a link"
        // Keep the sentence's own full stop the match took with it ("…works/407062.").
        val last = run.last()
        return if (last in ".,;:!?" && !host.endsWith(last)) host + last else host
    }

    fun splitIntoSpeakableChunks(text: String): List<String> {
        val normalized = text.replace(Regex("\\s+"), " ").trim()
        if (normalized.isEmpty()) return emptyList()
        val chunks = mutableListOf<String>()
        var remaining = normalized
        while (remaining.isNotEmpty()) {
            if (remaining.length <= CHUNK) {
                chunks.add(remaining)
                break
            }
            val window = remaining.take(CHUNK)
            val splitAt = window.lastIndexOfAny(charArrayOf('.', '!', '?', ';', '\n'))
                .takeIf { it > CHUNK / 3 }
                ?: window.lastIndexOf(' ').takeIf { it > CHUNK / 3 }
                ?: CHUNK
            chunks.add(remaining.take(splitAt + 1).trim())
            remaining = remaining.drop(splitAt + 1).trimStart()
        }
        return chunks.filter { it.isNotBlank() }
    }
}
