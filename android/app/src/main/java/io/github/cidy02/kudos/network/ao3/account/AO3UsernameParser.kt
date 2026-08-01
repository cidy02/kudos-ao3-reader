package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.network.ao3.AO3Constants
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import org.jsoup.Jsoup

class AO3UsernameParser {
    /**
     * True when the HTML is a real AO3 document (logged-in or logged-out body).
     * Challenge walls, empty error pages, and pages that merely share `#main`
     * return false so session restore keeps cookies instead of wiping them.
     * Port of Apple `LiveAO3SessionValidator.looksLikeAO3Page`.
     */
    fun looksLikeAO3Page(html: String): Boolean {
        val body = Jsoup.parse(html, AO3Constants.BASE_URL).body()
        return body.hasClass("logged-in") || body.hasClass("logged-out")
    }

    fun isLoggedIn(html: String): Boolean {
        val document = Jsoup.parse(html, AO3Constants.BASE_URL)
        if (document.body().hasClass("logged-in")) return true
        return document.select("a[href=/users/logout], form[action=/users/logout]").isNotEmpty()
    }

    fun username(html: String): String? {
        val document = Jsoup.parse(html, AO3Constants.BASE_URL)
        document.select("#greeting a[href^=/users/]").forEach { link ->
            val href = link.attr("href")
            if (!href.startsWith("/users/") || href.endsWith("/login") || href.endsWith("/logout")) {
                return@forEach
            }
            val encoded = href.removePrefix("/users/").substringBefore("/")
            val decoded = URLDecoder.decode(encoded, StandardCharsets.UTF_8.name()).trim()
            if (decoded.isNotBlank()) return decoded
        }
        return null
    }

    fun isLoginRequiredPage(html: String, finalUrl: String? = null): Boolean {
        if (finalUrl?.let(AO3Constants::isLoginUrl) == true) return true
        if (isLoggedIn(html)) return false
        val document = Jsoup.parse(html, AO3Constants.BASE_URL)
        return document.select("form#new_user, form[action=/users/login], a[href=/users/login]").isNotEmpty()
    }
}
