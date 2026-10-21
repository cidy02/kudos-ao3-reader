package io.github.cidy02.kudos.reader

/** A paragraph is extracted only when playback is ready for it. Null means the work ended. */
fun interface ReaderSpeechSource {
    suspend fun next(): String?
}

/** Preserve the player's title/contents fallback only when the publication has no prose. */
internal fun ReaderSpeechSource.withFallback(paragraphs: List<String>): ReaderSpeechSource {
    var hadProse = false
    var fallback: Iterator<String>? = null
    return ReaderSpeechSource {
        val text = if (fallback == null) next() else null
        if (text != null) {
            hadProse = true
            text
        } else if (hadProse) null else {
            val iterator = fallback ?: paragraphs.iterator().also { fallback = it }
            if (iterator.hasNext()) iterator.next() else null
        }
    }
}
