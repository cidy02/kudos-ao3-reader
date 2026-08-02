package io.github.cidy02.kudos.auth

import android.webkit.CookieManager
import io.github.cidy02.kudos.network.ao3.AO3Constants
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl

interface AO3CookieStore {
    suspend fun captureSession(username: String): AO3Session?
    suspend fun install(session: AO3Session)
    suspend fun clear()
}

class AndroidAO3CookieStore(
    private val cookieManager: CookieManager = CookieManager.getInstance()
) : AO3CookieStore {
    /**
     * Snapshot cookies from WebView's [CookieManager].
     *
     * [CookieManager.getCookie] only returns `name=value` pairs (no path/expiry/
     * HttpOnly). Defaults on [AO3StoredCookie] cover typical AO3 session cookies
     * (path `/`, Secure, HttpOnly). When full Set-Cookie lines are available
     * elsewhere (OkHttp responses), use [AO3StoredCookie.fromSetCookieHeaders] /
     * [AO3StoredCookie.fromOkHttp] so attributes are retained.
     */
    override suspend fun captureSession(username: String): AO3Session? {
        val cookies = parseCookieHeader(cookieManager.getCookie(AO3Constants.BASE_URL))
        return AO3Session(username = username, cookies = cookies)
            .takeIf { it.hasSessionCookie() }
    }

    override suspend fun install(session: AO3Session) {
        cookieManager.setAcceptCookie(true)
        session.validCookies().forEach { cookie ->
            // toCookieManagerSetCookieHeader writes Path/Domain/Secure/HttpOnly/Expires.
            cookieManager.setCookie(AO3Constants.BASE_URL, cookie.toCookieManagerSetCookieHeader())
        }
        cookieManager.flush()
    }

    override suspend fun clear() {
        parseCookieHeader(cookieManager.getCookie(AO3Constants.BASE_URL)).forEach { cookie ->
            val expired = cookie.copy(value = "")
            cookieManager.setCookie(AO3Constants.BASE_URL, expired.toCookieManagerSetCookieHeader(expired = true))
            cookieManager.setCookie(
                AO3Constants.BASE_URL,
                expired.copy(domain = AO3Constants.WORKS_HOST).toCookieManagerSetCookieHeader(expired = true)
            )
        }
        cookieManager.flush()
    }

    companion object {
        /**
         * Parses a Cookie *request* header (`name=value; name2=value2`) from
         * [CookieManager.getCookie]. Does not invent path/expiry (not present in
         * that format); model defaults apply.
         */
        fun parseCookieHeader(header: String?): List<AO3StoredCookie> {
            if (header.isNullOrBlank()) return emptyList()
            return header.split(";")
                .mapNotNull { raw ->
                    val pair = raw.trim()
                    val index = pair.indexOf("=")
                    if (index <= 0) return@mapNotNull null
                    val name = pair.substring(0, index).trim()
                    val value = pair.substring(index + 1).trim()
                    if (name.isBlank()) return@mapNotNull null
                    // CookieManager never exposes attributes; keep secure/httpOnly
                    // defaults so reinstall into WebView stays faithful for session
                    // cookies. Path/expiry stay at model defaults until a Set-Cookie
                    // merge supplies them.
                    AO3StoredCookie(name = name, value = value)
                }
        }

        /**
         * Parses full Set-Cookie response headers (path, Expires, Secure, HttpOnly)
         * via OkHttp. Prefer this whenever the source is Set-Cookie, not CookieManager.
         */
        fun parseSetCookieHeaders(
            url: HttpUrl = AO3Constants.BASE_URL.toHttpUrl(),
            setCookieLines: List<String>
        ): List<AO3StoredCookie> {
            return AO3StoredCookie.fromSetCookieHeaders(url, setCookieLines)
        }
    }
}
