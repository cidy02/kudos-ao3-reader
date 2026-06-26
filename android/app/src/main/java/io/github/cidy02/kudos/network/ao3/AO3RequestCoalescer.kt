package io.github.cidy02.kudos.network.ao3

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.HttpUrl.Companion.toHttpUrl

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
    private val inFlight = mutableMapOf<K, CompletableDeferred<V>>()

    suspend fun coalesce(
        key: K,
        operation: suspend () -> V
    ): V {
        val deferred = mutex.withLock {
            inFlight[key] ?: CompletableDeferred<V>().also { created ->
                inFlight[key] = created
                scope.launch {
                    try {
                        created.complete(operation())
                    } catch (error: Throwable) {
                        created.completeExceptionally(error)
                    } finally {
                        mutex.withLock {
                            if (inFlight[key] === created) inFlight.remove(key)
                        }
                    }
                }
            }
        }
        return deferred.await()
    }

    suspend fun inFlightCount(): Int = mutex.withLock { inFlight.size }
}
