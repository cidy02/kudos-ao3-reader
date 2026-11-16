package io.github.cidy02.kudos.app

/**
 * One-shot launch intent handed from Work Detail to Reader when the user taps
 * Contents or Read Aloud on the short reading card.
 *
 * Intentionally kept in-memory only (dropped across process death), matching iOS
 * (`WorkDetailView.readerStartsReadAloud` and `AppRouter.panel`): a cold process
 * restore must not unexpectedly start Read Aloud audio or pop a sheet later.
 */
object ReaderLaunchRequest {
    data class Pending(
        val workId: String,
        val openContents: Boolean = false,
        val startReadAloud: Boolean = false
    )

    private data class Entry(
        val request: Pending,
        val token: Long
    )

    @Volatile
    private var pending: Entry? = null
    private var nextToken: Long = 0L

    @Synchronized
    fun request(workId: String, openContents: Boolean = false, startReadAloud: Boolean = false) {
        pending = if (openContents || startReadAloud) {
            Entry(
                request = Pending(workId = workId, openContents = openContents, startReadAloud = startReadAloud),
                token = ++nextToken
            )
        } else {
            null
        }
    }

    @Synchronized
    fun peek(workId: String): Pending? = pending?.request?.takeIf { it.workId == workId }

    @Synchronized
    internal fun tokenFor(workId: String): Long? = pending?.takeIf { it.request.workId == workId }?.token

    @Synchronized
    fun consumeWhenReady(workId: String, speechReady: Boolean): Pending? {
        val current = peek(workId) ?: return null
        if (current.startReadAloud && !speechReady) return null
        return consume(workId)
    }

    @Synchronized
    fun consume(workId: String): Pending? {
        val current = pending ?: return null
        if (current.request.workId != workId) return null
        pending = null
        return current.request
    }

    @Synchronized
    internal fun clearIfMatches(workId: String, token: Long) {
        val current = pending ?: return
        if (current.request.workId == workId && current.token == token) {
            pending = null
        }
    }
}
