package io.github.cidy02.kudos.network.ao3

sealed interface AO3Error {
    data object BadRequest : AO3Error
    data object AuthenticationRequired : AO3Error
    data object Forbidden : AO3Error
    data object NotFound : AO3Error
    data class RateLimited(val retryAfterMillis: Long?) : AO3Error
    data class Server(val statusCode: Int) : AO3Error
    data class Http(val statusCode: Int) : AO3Error
    data class Network(val message: String, val cause: Throwable? = null) : AO3Error
    data class Overloaded(val statusCode: Int, val retryAfterMillis: Long?) : AO3Error
    data class Parse(val message: String) : AO3Error
    data class Validation(val message: String) : AO3Error
}
