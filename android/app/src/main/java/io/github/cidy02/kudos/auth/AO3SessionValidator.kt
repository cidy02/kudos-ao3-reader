package io.github.cidy02.kudos.auth

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3UsernameParser
import java.io.IOException
import okhttp3.Cookie
import okhttp3.HttpUrl.Companion.toHttpUrl

/**
 * Result of validating a restored AO3 session against a live (or fixture) page.
 * Network failures are thrown rather than mapped here — offline must not log out.
 */
sealed interface AO3SessionValidation {
    data class Valid(val session: AO3Session) : AO3SessionValidation
    data object Expired : AO3SessionValidation
}

fun interface AO3SessionValidating {
    /**
     * @throws IOException when validation could not run (network, non-AO3 page,
     * transient server errors). Callers keep the stored session in that case.
     */
    suspend fun validate(session: AO3Session): AO3SessionValidation
}

/**
 * Validates a restored cookie without involving the visible UI. A connectivity
 * failure is intentionally thrown rather than treated as expiration; being
 * offline must not log the user out.
 *
 * Port of Apple `LiveAO3SessionValidator` (hig-review).
 */
class LiveAO3SessionValidator(
    private val client: AO3Client,
    private val cookieJar: AO3CookieJar = AO3CookieJar(),
    private val usernameParser: AO3UsernameParser = AO3UsernameParser(),
    private val validationUrl: String = AO3Constants.BASE_URL
) : AO3SessionValidating {
    override suspend fun validate(session: AO3Session): AO3SessionValidation {
        val cookieHeader = cookieJar.cookieHeader(session, validationUrl)
            ?: return AO3SessionValidation.Expired

        return when (val result = client.get(validationUrl, mapOf("Cookie" to cookieHeader))) {
            is AO3Result.Failure -> mapFailure(result.error)
            is AO3Result.Success -> mapSuccess(session, result.value)
        }
    }

    private fun mapFailure(error: AO3Error): AO3SessionValidation {
        // Only an explicit auth failure is treated as expiry. Every other error
        // is thrown so the caller keeps the session (offline-preserving).
        if (error == AO3Error.AuthenticationRequired) {
            return AO3SessionValidation.Expired
        }
        throw IOException("AO3 session validation unavailable: $error")
    }

    private fun mapSuccess(
        storedSession: AO3Session,
        response: AO3HttpResponse
    ): AO3SessionValidation {
        val html = response.body
        // Cloudflare / empty / non-AO3 responses must not wipe the session.
        if (!usernameParser.looksLikeAO3Page(html)) {
            throw IOException("AO3 session validation response did not look like an AO3 page.")
        }
        if (!usernameParser.isLoggedIn(html)) {
            return AO3SessionValidation.Expired
        }
        val username = usernameParser.username(html) ?: storedSession.username
        return AO3SessionValidation.Valid(
            mergingResponseCookies(storedSession, response, username)
        )
    }

    companion object {
        internal fun mergingResponseCookies(
            session: AO3Session,
            response: AO3HttpResponse,
            username: String
        ): AO3Session {
            val responseUrl = response.url.toHttpUrl()
            val setCookies = response.headers
                .entries
                .filter { it.key.equals("Set-Cookie", ignoreCase = true) }
                .flatMap { it.value }
                .mapNotNull { line -> Cookie.parse(responseUrl, line) }
                .filter { AO3StoredCookie.isAO3Domain(it.domain) }

            if (setCookies.isEmpty()) {
                return if (username == session.username) session else session.copy(username = username)
            }

            val byKey = linkedMapOf<String, AO3StoredCookie>()
            session.validCookies().forEach { cookie ->
                byKey[cookieKey(cookie)] = cookie
            }
            setCookies.forEach { cookie ->
                val stored = AO3StoredCookie.fromOkHttp(cookie)
                byKey[cookieKey(stored)] = stored
            }
            return AO3Session(username = username, cookies = byKey.values.toList())
        }

        private fun cookieKey(cookie: AO3StoredCookie): String {
            return "${cookie.domain.lowercase()}|${cookie.path}|${cookie.name}"
        }
    }
}
