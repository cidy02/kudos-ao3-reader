package io.github.cidy02.kudos.auth

import io.github.cidy02.kudos.network.ao3.AO3Constants
import java.time.Clock
import kotlinx.serialization.Serializable
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

@Serializable
data class AO3StoredCookie(
    val name: String,
    val value: String,
    val domain: String = ".archiveofourown.org",
    val path: String = "/",
    val expiresAtEpochMillis: Long? = null,
    val isSecure: Boolean = true,
    val isHttpOnly: Boolean = true
) {
    fun isExpired(clock: Clock = Clock.systemUTC()): Boolean {
        return expiresAtEpochMillis?.let { it <= clock.millis() } ?: false
    }

    fun appliesTo(url: String, clock: Clock = Clock.systemUTC()): Boolean {
        if (isExpired(clock)) return false
        val parsed = url.toHttpUrlOrNull() ?: return false
        val normalizedDomain = domain.trim().lowercase().trimStart('.')
        val requestHost = parsed.host.lowercase()
        val hostMatches = requestHost == normalizedDomain || requestHost.endsWith(".$normalizedDomain")
        val requestPath = parsed.encodedPath.ifBlank { "/" }
        val pathMatches = requestPath == path ||
            (requestPath.startsWith(path) && (path.endsWith("/") || requestPath.drop(path.length).startsWith("/")))
        val schemeMatches = !isSecure || parsed.isHttps
        return hostMatches && pathMatches && schemeMatches
    }

    fun toCookieHeaderPair(): String = "$name=$value"

    fun toCookieManagerSetCookieHeader(expired: Boolean = false): String {
        val maxAge = if (expired) "; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT" else ""
        val secure = if (isSecure) "; Secure" else ""
        val httpOnly = if (isHttpOnly) "; HttpOnly" else ""
        return "$name=$value; Domain=$domain; Path=$path$maxAge$secure$httpOnly"
    }

    companion object {
        const val SessionCookieName = "_otwarchive_session"

        fun isAO3Domain(domain: String): Boolean {
            val normalized = domain.trim().lowercase().trimStart('.')
            return normalized == AO3Constants.WORKS_HOST || normalized.endsWith(".${AO3Constants.WORKS_HOST}")
        }
    }
}

@Serializable
data class AO3Session(
    val username: String,
    val cookies: List<AO3StoredCookie>,
    val savedAtEpochMillis: Long = Clock.systemUTC().millis()
) {
    fun validCookies(clock: Clock = Clock.systemUTC()): List<AO3StoredCookie> {
        return cookies.filter { !it.isExpired(clock) && AO3StoredCookie.isAO3Domain(it.domain) }
    }

    fun hasSessionCookie(clock: Clock = Clock.systemUTC()): Boolean {
        return validCookies(clock).any { it.name == AO3StoredCookie.SessionCookieName }
    }
}
