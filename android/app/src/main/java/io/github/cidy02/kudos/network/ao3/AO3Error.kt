package io.github.cidy02.kudos.network.ao3

import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.UnknownHostException

sealed interface AO3Error {
    data object BadRequest : AO3Error
    data object AuthenticationRequired : AO3Error
    data object Forbidden : AO3Error
    data object NotFound : AO3Error
    data class RateLimited(val retryAfterMillis: Long?) : AO3Error
    data class Server(val statusCode: Int) : AO3Error
    data class Http(val statusCode: Int) : AO3Error
    /**
     * Transport-level failure. [offline] is true when the failure looks like
     * no connectivity (unknown host / connect refused / no route), so UI can
     * show a distinct offline message without polling ConnectivityManager.
     */
    data class Network(
        val message: String,
        val cause: Throwable? = null,
        val offline: Boolean = false
    ) : AO3Error
    data class Overloaded(val statusCode: Int, val retryAfterMillis: Long?) : AO3Error
    data class Parse(val message: String) : AO3Error
    data class Validation(val message: String) : AO3Error

    companion object {
        const val OFFLINE_MESSAGE =
            "You're offline. Try again when you're back online."

        /**
         * Map an OkHttp/IO transport failure into [Network], classifying offline
         * from the throwable chain (not from ConnectivityManager).
         */
        fun networkFromTransport(error: IOException): Network {
            val offline = isOfflineThrowable(error)
            return Network(
                message = if (offline) {
                    OFFLINE_MESSAGE
                } else {
                    error.message?.takeIf { it.isNotBlank() } ?: "Network request failed."
                },
                cause = error,
                offline = offline
            )
        }

        fun isOfflineThrowable(error: Throwable?): Boolean {
            var current: Throwable? = error
            var depth = 0
            while (current != null && depth < 6) {
                when (current) {
                    is UnknownHostException,
                    is ConnectException,
                    is NoRouteToHostException -> return true
                    is SocketException -> {
                        val msg = current.message.orEmpty()
                        if (msg.contains("Network is unreachable", ignoreCase = true) ||
                            msg.contains("Software caused connection abort", ignoreCase = true)
                        ) {
                            return true
                        }
                    }
                }
                current = current.cause
                depth += 1
            }
            return false
        }
    }
}

/** True when this error is a classified offline/transport-unreachable failure. */
fun AO3Error.isOffline(): Boolean = this is AO3Error.Network && offline

/**
 * Single user-facing string for AO3 failures. Prefer this over [Any.toString]
 * so UI never shows Kotlin data-class dump text like `Validation(message=…)`.
 */
fun AO3Error.displayMessage(): String = when (this) {
    AO3Error.BadRequest -> "AO3 rejected the request."
    AO3Error.AuthenticationRequired -> "AO3 requires login."
    AO3Error.Forbidden -> "AO3 denied access."
    AO3Error.NotFound -> "AO3 could not find that page."
    is AO3Error.Http -> "AO3 returned HTTP $statusCode."
    is AO3Error.Network -> if (offline) AO3Error.OFFLINE_MESSAGE else message
    is AO3Error.Overloaded -> "AO3 is busy. Try again shortly."
    is AO3Error.Parse -> message
    is AO3Error.RateLimited -> "AO3 is rate-limiting requests. Try again shortly."
    is AO3Error.Server -> "AO3 had a server problem (HTTP $statusCode)."
    is AO3Error.Validation -> message
}
