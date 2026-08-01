package io.github.cidy02.kudos.network.ao3

import okhttp3.Cookie
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/**
 * Keeps a same-host AO3 redirect's `Cookie` header current for requests whose
 * cookies are set explicitly rather than via OkHttp's CookieJar
 * (`authenticatedHeaders` / write POSTs set a per-request Cookie header from
 * the persisted [io.github.cidy02.kudos.auth.AO3Session]).
 *
 * Without this, a same-host 302 (otwarchive redirects every successful write to
 * a rendering page) is auto-followed carrying the *stale, pre-request* Cookie
 * header — because disabling ambient cookie handling also disables capturing a
 * redirect response's own `Set-Cookie`. otwarchive uses Rails' signed
 * `CookieStore` for `_otwarchive_session`, so the write's success/error flash is
 * serialized *into* that cookie's value and delivered via the redirect's own
 * `Set-Cookie` — a stale cookie on the followed GET means the flash was never
 * there to read.
 *
 * Pure (unit-tested) decision helpers plus an OkHttp interceptor that follows
 * redirects with the decided Cookie header. Stateless — safe under concurrent
 * requests from different accounts.
 *
 * Port of Apple `AO3RedirectCookieRelay` (hig-review).
 */
object AO3RedirectCookieRelay {
    const val SESSION_COOKIE_NAME: String = "_otwarchive_session"

    /**
     * What a redirect should do with the Cookie header — a three-way decision,
     * not a nullable string, because "make no change" and "strip whatever is
     * there" are different outcomes that must never be conflated.
     */
    sealed interface RedirectCookieAction {
        data object LeaveUnchanged : RedirectCookieAction
        data class Set(val value: String) : RedirectCookieAction
        data object Strip : RedirectCookieAction
    }

    /**
     * HTTPS AO3 hosts only (`archiveofourown.org` and subdomains). The live
     * account cookie must never follow a redirect off AO3.
     */
    fun isTrustedUrl(url: HttpUrl?): Boolean {
        if (url == null || !url.isHttps) return false
        val host = url.host.lowercase()
        return host == AO3Constants.WORKS_HOST || host.endsWith(".${AO3Constants.WORKS_HOST}")
    }

    fun isTrustedUrl(url: String?): Boolean = isTrustedUrl(url?.toHttpUrlOrNull())

    /**
     * Pure: decides what a redirected request's Cookie header should carry.
     * [RedirectCookieAction.Strip] when [newRequestUrl] is not a trusted AO3
     * host — the live auth cookie must never follow a redirect off AO3.
     * Otherwise defers to [mergedCookieHeader]'s same-host refresh logic,
     * making no change when it finds nothing to update.
     *
     * [isTrusted] is injectable so MockWebServer integration tests can treat
     * the local server host as trusted without loosening production policy.
     */
    fun redirectCookieAction(
        currentHeader: String?,
        setCookieHeaders: List<String>,
        responseUrl: HttpUrl?,
        newRequestUrl: HttpUrl?,
        isTrusted: (HttpUrl?) -> Boolean = ::isTrustedUrl
    ): RedirectCookieAction {
        if (!isTrusted(newRequestUrl)) return RedirectCookieAction.Strip
        val updated = mergedCookieHeader(
            currentHeader = currentHeader,
            setCookieHeaders = setCookieHeaders,
            responseUrl = responseUrl
        ) ?: return RedirectCookieAction.LeaveUnchanged
        return RedirectCookieAction.Set(updated)
    }

    /**
     * Pure: replaces only the AO3 session cookie's value in [currentHeader]
     * with whatever [setCookieHeaders] carries for `_otwarchive_session`,
     * leaving every other cookie pair untouched. Returns null when there is
     * nothing to update (no existing header, or the response set no session
     * cookie) — the caller then leaves the redirect request unchanged.
     */
    fun mergedCookieHeader(
        currentHeader: String?,
        setCookieHeaders: List<String>,
        responseUrl: HttpUrl?
    ): String? {
        if (currentHeader.isNullOrEmpty() || responseUrl == null) return null
        val updated = setCookieHeaders
            .mapNotNull { line -> Cookie.parse(responseUrl, line) }
            .firstOrNull { it.name == SESSION_COOKIE_NAME }
            ?: return null

        val pairs = currentHeader
            .split("; ")
            .mapNotNull { pair ->
                val index = pair.indexOf('=')
                if (index <= 0) return@mapNotNull null
                val name = pair.substring(0, index)
                val value = pair.substring(index + 1)
                name to value
            }
            .toMutableList()

        val existingIndex = pairs.indexOfFirst { it.first == updated.name }
        if (existingIndex >= 0) {
            pairs[existingIndex] = updated.name to updated.value
        } else {
            pairs.add(updated.name to updated.value)
        }
        return pairs.joinToString("; ") { "${it.first}=${it.second}" }
    }
}
