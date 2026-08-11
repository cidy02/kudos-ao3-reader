package io.github.cidy02.kudos.auth

import io.github.cidy02.kudos.network.ao3.AO3Constants
import java.time.Clock
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

class AO3CookieJar(
    private val clock: Clock = Clock.systemUTC()
) {
    fun cookieHeader(session: AO3Session, url: String): String? {
        val parsed = url.toHttpUrlOrNull() ?: return null
        if (!parsed.isHttps || !isAO3Host(parsed.host)) return null

        val pairs = session.validCookies(clock)
            .filter { it.appliesTo(url, clock) }
            .sortedByDescending { it.path.length }
            .map { it.toCookieHeaderPair() }

        return pairs.takeIf { it.isNotEmpty() }?.joinToString("; ")
    }

    private fun isAO3Host(host: String): Boolean {
        val normalized = host.lowercase()
        return normalized == AO3Constants.WORKS_HOST || normalized.endsWith(".${AO3Constants.WORKS_HOST}")
    }
}
