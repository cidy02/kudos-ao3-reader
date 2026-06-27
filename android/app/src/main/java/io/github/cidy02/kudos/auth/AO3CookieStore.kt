package io.github.cidy02.kudos.auth

import android.webkit.CookieManager
import io.github.cidy02.kudos.network.ao3.AO3Constants

interface AO3CookieStore {
    suspend fun captureSession(username: String): AO3Session?
    suspend fun install(session: AO3Session)
    suspend fun clear()
}

class AndroidAO3CookieStore(
    private val cookieManager: CookieManager = CookieManager.getInstance()
) : AO3CookieStore {
    override suspend fun captureSession(username: String): AO3Session? {
        val cookies = parseCookieHeader(cookieManager.getCookie(AO3Constants.BASE_URL))
        return AO3Session(username = username, cookies = cookies)
            .takeIf { it.hasSessionCookie() }
    }

    override suspend fun install(session: AO3Session) {
        cookieManager.setAcceptCookie(true)
        session.validCookies().forEach { cookie ->
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
                    AO3StoredCookie(name = name, value = value)
                }
        }
    }
}
