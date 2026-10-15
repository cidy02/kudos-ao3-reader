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

    suspend fun paragraphs(
        publication: Publication,
        from: Locator? = null,
        readAuthorNotes: Boolean = true
    ): List<String> = withContext(Dispatchers.IO) {
        val content = runCatching { publication.content(from) }.getOrNull()
            ?: return@withContext emptyList()
        // Each text element is a paragraph; a blockquote is a quote (where AO3 puts a note).
        val blocks = runCatching { content.elements() }.getOrNull().orEmpty().mapNotNull { element ->
            val text = (element as? Content.TextualElement)?.text?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            SpeechBlock(text, (element as? Content.TextElement)?.role is Content.TextElement.Role.Quote)
        }
        if (blocks.isEmpty()) return@withContext emptyList()
        // To the end of the work, as iOS reads on. It stopped after 80,000 characters (about an
        // hour and a half), though `text()` had already read the rest in.
        // ponytail: the rest of the work is read in before the first word; walk
        // `content.iterator()` lazily if a very long work is slow to start.
        speakableParagraphs(blocks, readAuthorNotes).flatMap(::splitIntoSpeakableChunks)
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
        val spoken = mutableListOf<String>()
        // iOS's rule for "Read author's notes" off: a note runs from its label to the end of the
        // quotation after it, and anything that is not a quote ends it. A label followed by a
        // plain paragraph leaves that paragraph spoken: a note read that was meant to be
        // skipped is far better than a chapter skipped that was meant to be read.
        var inSkippedNote = false
        for (block in blocks) {
            val paragraph = block.text.replace(WHITESPACE, " ").trim()
            if (paragraph.isEmpty()) continue
            val plain = normalized(paragraph)
            if (plain in LABELS || plain == KUDOS_PLUG) {
                inSkippedNote = !readAuthorNotes && plain in LABELS
                continue
            }
            if (inSkippedNote) {
                if (block.isQuote) continue
                inSkippedNote = false
            }
            spoken += URL.replace(paragraph) { host(it.value) }
        }
        return spoken
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
