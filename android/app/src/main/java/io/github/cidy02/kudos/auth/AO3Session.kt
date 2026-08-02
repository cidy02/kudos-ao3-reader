package io.github.cidy02.kudos.auth

import io.github.cidy02.kudos.network.ao3.AO3Constants
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.serialization.Serializable
import okhttp3.Cookie
import okhttp3.HttpUrl
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

    /**
     * Builds a Set-Cookie line for [android.webkit.CookieManager.setCookie].
     * Preserves path, domain, Secure, HttpOnly, and Expires when we have them —
     * earlier code only expired cookies wrote Expires, so reinstall dropped expiry.
     */
    fun toCookieManagerSetCookieHeader(expired: Boolean = false): String {
        val parts = mutableListOf(
            "$name=$value",
            "Domain=$domain",
            "Path=$path"
        )
        if (expired) {
            parts += "Max-Age=0"
            parts += "Expires=Thu, 01 Jan 1970 00:00:00 GMT"
        } else {
            expiresAtEpochMillis?.let { millis ->
                parts += "Expires=${HTTP_DATE.format(Instant.ofEpochMilli(millis))}"
            }
        }
        if (isSecure) parts += "Secure"
        if (isHttpOnly) parts += "HttpOnly"
        return parts.joinToString("; ")
    }

    companion object {
        const val SessionCookieName = "_otwarchive_session"

        private val HTTP_DATE: DateTimeFormatter = DateTimeFormatter
            .ofPattern("EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US)
            .withZone(ZoneOffset.UTC)

        fun isAO3Domain(domain: String): Boolean {
            val normalized = domain.trim().lowercase().trimStart('.')
            return normalized == AO3Constants.WORKS_HOST || normalized.endsWith(".${AO3Constants.WORKS_HOST}")
        }

        /**
         * Maps an OkHttp [Cookie] (from Set-Cookie parsing) retaining path, expiry,
         * Secure, and HttpOnly. Prefer this over name=value-only capture when the
         * full cookie object is available.
         */
        fun fromOkHttp(cookie: Cookie): AO3StoredCookie {
            return AO3StoredCookie(
                name = cookie.name,
                value = cookie.value,
                domain = cookie.domain,
                path = cookie.path,
                expiresAtEpochMillis = if (cookie.expiresAt != Long.MAX_VALUE) {
                    cookie.expiresAt
                } else {
                    null
                },
                isSecure = cookie.secure,
                isHttpOnly = cookie.httpOnly
            )
        }

        /**
         * Parses full Set-Cookie header lines against [url], keeping attributes
         * OkHttp exposes. Filters to AO3 hosts only.
         */
        fun fromSetCookieHeaders(url: HttpUrl, setCookieLines: List<String>): List<AO3StoredCookie> {
            return setCookieLines
                .mapNotNull { line -> Cookie.parse(url, line) }
                .filter { isAO3Domain(it.domain) }
                .map { fromOkHttp(it) }
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
