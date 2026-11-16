package io.github.cidy02.kudos.app

/**
 * One-shot launch intent handed from Work Detail to Reader when the user taps
 * Contents or Read Aloud on the short reading card.
 */
object ReaderLaunchRequest {
    data class Pending(
        val workId: String,
        val openContents: Boolean = false,
        val startReadAloud: Boolean = false
    )

    @Volatile
    private var pending: Pending? = null

    fun request(workId: String, openContents: Boolean = false, startReadAloud: Boolean = false) {
        pending = if (openContents || startReadAloud) {
            Pending(workId = workId, openContents = openContents, startReadAloud = startReadAloud)
        } else {
            null
        }
    }

    fun peek(workId: String): Pending? = pending?.takeIf { it.workId == workId }

    fun consumeWhenReady(workId: String, speechReady: Boolean): Pending? {
        val current = peek(workId) ?: return null
        if (current.startReadAloud && !speechReady) return null
        return consume(workId)
    }

    fun consume(workId: String): Pending? {
        val current = pending ?: return null
        if (current.workId != workId) return null
        pending = null
        return current
    }
}
