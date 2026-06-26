package io.github.cidy02.kudos.network.ao3

enum class AO3HttpMethod {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE
}

class AO3RetryPolicy(
    private val config: AO3NetworkConfig = AO3NetworkConfig()
) {
    fun shouldRetry(
        method: AO3HttpMethod,
        error: AO3Error,
        retryNumber: Int
    ): Boolean {
        if (method != AO3HttpMethod.GET) return false
        if (retryNumber > config.maxRetries) return false
        return when (error) {
            is AO3Error.Network,
            is AO3Error.Overloaded,
            is AO3Error.RateLimited,
            is AO3Error.Server -> true
            AO3Error.BadRequest,
            AO3Error.AuthenticationRequired,
            AO3Error.Forbidden,
            AO3Error.NotFound,
            is AO3Error.Http,
            is AO3Error.Validation -> false
        }
    }

    fun retryDelayMillis(error: AO3Error, retryNumber: Int): Long {
        val backoff = 500L * (1L shl (retryNumber - 1).coerceAtLeast(0))
        return when (error) {
            is AO3Error.RateLimited -> maxOf(error.retryAfterMillis ?: 0L, backoff)
            is AO3Error.Overloaded -> maxOf(error.retryAfterMillis ?: 0L, backoff)
            else -> backoff
        }
    }
}
