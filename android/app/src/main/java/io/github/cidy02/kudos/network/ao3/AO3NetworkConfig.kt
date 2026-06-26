package io.github.cidy02.kudos.network.ao3

data class AO3NetworkConfig(
    val maxConcurrentRequests: Int = 3,
    val minDelayBetweenRequestsMillis: Long = 500,
    val maxRetries: Int = 2,
    val callTimeoutSeconds: Long = 30
) {
    init {
        require(maxConcurrentRequests >= 1) { "maxConcurrentRequests must be at least 1." }
        require(minDelayBetweenRequestsMillis >= 0) {
            "minDelayBetweenRequestsMillis must not be negative."
        }
        require(maxRetries >= 0) { "maxRetries must not be negative." }
        require(callTimeoutSeconds > 0) { "callTimeoutSeconds must be positive." }
    }
}

fun interface AO3Delay {
    suspend fun delay(millis: Long)
}

fun interface AO3Clock {
    fun nowMillis(): Long
}

object CoroutineAO3Delay : AO3Delay {
    override suspend fun delay(millis: Long) {
        kotlinx.coroutines.delay(millis)
    }
}

object SystemAO3Clock : AO3Clock {
    override fun nowMillis(): Long = System.currentTimeMillis()
}
