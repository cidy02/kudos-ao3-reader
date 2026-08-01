package io.github.cidy02.kudos.network.ao3

import java.net.ProtocolException
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response

/**
 * Follows HTTP redirects while applying [AO3RedirectCookieRelay] cookie-header
 * decisions. Pair with `followRedirects(false)` / `followSslRedirects(false)`
 * so OkHttp does not also auto-follow (which would keep a stale explicit
 * Cookie header across same-host redirects).
 *
 * Port of Apple `AO3RedirectCookieRelay` as a URLSession redirect delegate.
 */
class AO3RedirectCookieRelayInterceptor(
    private val maxRedirects: Int = 20,
    private val isTrusted: (HttpUrl?) -> Boolean = AO3RedirectCookieRelay::isTrustedUrl
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        var request = chain.request()
        var response = chain.proceed(request)
        var redirectCount = 0

        while (true) {
            val prior = response
            val redirect = buildRedirectRequest(prior) ?: return prior

            redirectCount += 1
            if (redirectCount > maxRedirects) {
                prior.close()
                throw ProtocolException("Too many follow-up requests: $redirectCount")
            }

            prior.close()
            request = redirect
            response = chain.proceed(request)
        }
    }

    private fun buildRedirectRequest(userResponse: Response): Request? {
        val code = userResponse.code
        if (!isRedirect(code)) return null

        val request = userResponse.request
        val location = userResponse.header("Location") ?: return null
        val newUrl = request.url.resolve(location) ?: return null

        val requestBuilder = request.newBuilder().url(newUrl)

        // Match OkHttp's RetryAndFollowUpInterceptor method/body rules for
        // redirects so write POSTs still convert to GET on 302/303.
        when (code) {
            HTTP_TEMP_REDIRECT, HTTP_PERM_REDIRECT -> {
                // Keep method and body.
            }
            HTTP_MULT_CHOICE, HTTP_MOVED_PERM, HTTP_MOVED_TEMP, HTTP_SEE_OTHER -> {
                requestBuilder.method("GET", null)
                requestBuilder.removeHeader("Transfer-Encoding")
                requestBuilder.removeHeader("Content-Length")
                requestBuilder.removeHeader("Content-Type")
            }
            else -> return null
        }

        // Drop Authorization when leaving the original host (OkHttp does this);
        // Cookie is decided separately by the relay so flash-bearing Set-Cookie
        // can still refresh a same-host follow-up.
        if (!sameConnection(request.url, newUrl)) {
            requestBuilder.removeHeader("Authorization")
            requestBuilder.removeHeader("Proxy-Authorization")
        }

        val action = AO3RedirectCookieRelay.redirectCookieAction(
            currentHeader = request.header("Cookie"),
            setCookieHeaders = userResponse.headers("Set-Cookie"),
            responseUrl = request.url,
            newRequestUrl = newUrl,
            isTrusted = isTrusted
        )
        when (action) {
            AO3RedirectCookieRelay.RedirectCookieAction.LeaveUnchanged -> Unit
            is AO3RedirectCookieRelay.RedirectCookieAction.Set ->
                requestBuilder.header("Cookie", action.value)
            AO3RedirectCookieRelay.RedirectCookieAction.Strip ->
                requestBuilder.removeHeader("Cookie")
        }

        return requestBuilder.build()
    }

    private fun isRedirect(code: Int): Boolean {
        return code == HTTP_PERM_REDIRECT ||
            code == HTTP_TEMP_REDIRECT ||
            code == HTTP_MULT_CHOICE ||
            code == HTTP_MOVED_PERM ||
            code == HTTP_MOVED_TEMP ||
            code == HTTP_SEE_OTHER
    }

    private fun sameConnection(a: HttpUrl, b: HttpUrl): Boolean {
        return a.host.equals(b.host, ignoreCase = true) &&
            a.port == b.port &&
            a.scheme == b.scheme
    }

    companion object {
        private const val HTTP_MULT_CHOICE = 300
        private const val HTTP_MOVED_PERM = 301
        private const val HTTP_MOVED_TEMP = 302
        private const val HTTP_SEE_OTHER = 303
        private const val HTTP_TEMP_REDIRECT = 307
        private const val HTTP_PERM_REDIRECT = 308
    }
}
