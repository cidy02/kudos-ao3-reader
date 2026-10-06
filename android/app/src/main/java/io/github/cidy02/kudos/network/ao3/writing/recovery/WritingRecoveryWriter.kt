package io.github.cidy02.kudos.network.ao3.writing.recovery

import java.nio.file.Path
import kotlinx.coroutines.withContext

/** One writer per field session. iOS semantics: discard late old calls, retry newest received text. */
class WritingRecoveryWriter(
    private val store: WritingTextRecovery,
    private val url: Path,
    private val original: String,
) {
    private var originalDigest: String? = null
    private var lastWrittenSequence = 0
    private var newest: Pair<String, Int>? = null

    // Like iOS, failed writes retry only on a subsequent call; the caller surfaces the error.
    suspend fun write(text: String, sequence: Int): Boolean = withContext(writingRecoveryIO) {
        if (sequence > (newest?.second ?: 0)) newest = text to sequence
        val pending = newest ?: return@withContext false
        if (pending.second <= lastWrittenSequence) return@withContext false
        val digest = originalDigest ?: WritingTextRecovery.digest(original).also { originalDigest = it }
        store.saveDigest(pending.first, digest, url)
        lastWrittenSequence = pending.second
        true
    }
}
