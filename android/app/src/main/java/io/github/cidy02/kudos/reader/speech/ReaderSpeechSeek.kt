package io.github.cidy02.kudos.reader.speech

/** iOS ReaderSpeechSkip.seekIndex: each hold tick advances one position, stopping at bounds. */
internal object ReaderSpeechSeek {
    fun seekIndex(current: Int, count: Int, delta: Int): Int? {
        if (count <= 0 || delta == 0) return null
        val next = current.toLong() + delta
        return next.takeIf { it >= 0 && it < count }?.toInt()
    }
}
