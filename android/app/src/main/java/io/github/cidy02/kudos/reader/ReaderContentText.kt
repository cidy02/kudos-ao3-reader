package io.github.cidy02.kudos.reader

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.content.content

/**
 * Extracts plain text from the publication for TTS, starting at [from] when set.
 * Uses Readium ContentService when available; falls back to empty.
 */
@OptIn(ExperimentalReadiumApi::class)
object ReaderContentText {
    private const val MAX_CHARS = 80_000
    private const val CHUNK = 350

    suspend fun paragraphs(
        publication: Publication,
        from: Locator? = null
    ): List<String> = withContext(Dispatchers.IO) {
        val content = runCatching { publication.content(from) }.getOrNull()
            ?: return@withContext emptyList()
        val full = runCatching { content.text() }.getOrNull().orEmpty()
        if (full.isBlank()) return@withContext emptyList()
        splitIntoSpeakableChunks(full.take(MAX_CHARS))
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
