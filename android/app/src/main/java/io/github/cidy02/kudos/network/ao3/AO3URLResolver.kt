package io.github.cidy02.kudos.network.ao3

import java.net.URI

/**
 * Port of Apple `AO3URLResolver`: resolve relative AO3 hrefs and reject
 * non-AO3 / non-http(s) destinations for in-app navigation and write form action URLs.
 */
object AO3URLResolver {
    private val trustedHosts = setOf(
        "archiveofourown.org",
        "www.archiveofourown.org"
    )

    /**
     * @return absolute https URL on a trusted AO3 host, or null if the href is
     * external, unsupported, or malformed.
     */
    fun resolve(
        href: String,
        baseUrl: String = "https://archiveofourown.org/",
        allowExternalHost: Boolean = false
    ): String? {
        val trimmed = href.trim()
        if (trimmed.isEmpty()) return null
        if (trimmed.startsWith("javascript:", ignoreCase = true) ||
            trimmed.startsWith("data:", ignoreCase = true) ||
            trimmed.startsWith("mailto:", ignoreCase = true)
        ) {
            return null
        }

        val absolute = try {
            when {
                trimmed.startsWith("//") -> "https:$trimmed"
                trimmed.startsWith("http://", ignoreCase = true) ||
                    trimmed.startsWith("https://", ignoreCase = true) -> trimmed
                else -> URI(baseUrl).resolve(trimmed).toString()
            }
        } catch (_: Exception) {
            return null
        }

        val uri = try {
            URI(absolute)
        } catch (_: Exception) {
            return null
        }

        val scheme = uri.scheme?.lowercase() ?: return null
        if (scheme != "http" && scheme != "https") return null

        val host = uri.host?.lowercase() ?: return null
        if (!allowExternalHost && host !in trustedHosts) return null

        // Force https for AO3 hosts.
        val https = if (host in trustedHosts && scheme == "http") {
            URI("https", uri.userInfo, host, uri.port, uri.path, uri.query, uri.fragment).toString()
        } else {
            absolute
        }
        return https
    }

    fun isTrustedAo3Host(url: String): Boolean {
        return try {
            val host = URI(url).host?.lowercase() ?: return false
            host in trustedHosts
        } catch (_: Exception) {
            false
        }
    }

    fun canonicalWorkUrl(ao3WorkId: Long): String {
        return "https://archiveofourown.org/works/$ao3WorkId"
    }
}
