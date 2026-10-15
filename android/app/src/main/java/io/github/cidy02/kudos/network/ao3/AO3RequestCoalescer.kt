package io.github.cidy02.kudos.network.ao3

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext

/** A cache-bypassing fetch must not inherit a response started before a write. */
internal class AO3UncoalescedRead : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<AO3UncoalescedRead>
}

data class AO3RequestKey(
    val method: AO3HttpMethod,
    val canonicalUrl: String,
    val headers: Map<String, String>
) {
    companion object {
        fun get(url: String, headers: Map<String, String> = emptyMap()): AO3RequestKey {
            return AO3RequestKey(
                method = AO3HttpMethod.GET,
                canonicalUrl = url.toHttpUrl().toString(),
                headers = headers
                    .mapKeys { it.key.trim().lowercase() }
                    .mapValues { it.value.trim() }
                    .toSortedMap()
            )
        }
    }
}

class AO3RequestCoalescer<K : Any, V : Any>(
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) {
    private val mutex = Mutex()
    private class InFlight<V> {
        val result = CompletableDeferred<V>()
        lateinit var job: Job
        var waiters = 0
    }
    private val inFlight = mutableMapOf<K, InFlight<V>>()

    suspend fun coalesce(
        key: K,
        operation: suspend () -> V
    ): V {
        currentCoroutineContext().ensureActive()
        if (currentCoroutineContext()[AO3UncoalescedRead] != null) return operation()

        val shared = mutex.withLock {
            val entry = inFlight[key]?.takeUnless { it.result.isCompleted } ?: InFlight<V>().also { created ->
                // Register the first waiter before this job can start, even on an immediate dispatcher.
                created.job = scope.launch(start = CoroutineStart.LAZY) {
                    try {
                        created.result.complete(operation())
                    } catch (error: Throwable) {
                        created.result.completeExceptionally(error)
                    }
                }
                created.job.invokeOnCompletion { error ->
                    // A cancelled scope can stop a lazy job before its body ever runs.
                    if (error != null) created.result.completeExceptionally(error)
                }
                inFlight[key] = created
            }
            entry.waiters += 1
            entry
        }
        try {
            currentCoroutineContext().ensureActive()
            shared.job.start()
            return shared.result.await()
        } finally {
            // Cancellation must not interrupt unregistering the last waiter.
            withContext(NonCancellable) {
                mutex.withLock {
                    shared.waiters -= 1
                    if (shared.waiters == 0) {
                        if (inFlight[key] === shared) inFlight.remove(key)
                        shared.job.cancel()
                    }
                }
            }
        }
    }

    suspend fun inFlightCount(): Int = mutex.withLock { inFlight.size }
}
