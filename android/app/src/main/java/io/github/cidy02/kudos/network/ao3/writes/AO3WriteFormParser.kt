package io.github.cidy02.kudos.network.ao3.writes

import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

class AO3WriteFormParser {
    fun parseAuthenticityToken(html: String, formSelector: String? = null): String? {
        val document = Jsoup.parse(html)
        if (formSelector != null) {
            document.selectFirst(formSelector)?.authenticityToken()?.let { return it }
        }

        document.selectFirst("input[name=authenticity_token]")?.attr("value")?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.let { return it }

        return document.selectFirst("meta[name=csrf-token]")?.attr("content")?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    fun parseDefaultPseudId(html: String, field: String = "comment[pseud_id]"): String? {
        val document = Jsoup.parse(html)
        val select = document.selectFirst("select[name=\"$field\"]") ?: return null
        val selected = select.selectFirst("option[selected]")?.attr("value")?.trim()
        if (!selected.isNullOrEmpty()) return selected
        return select.selectFirst("option")?.attr("value")?.trim()?.takeIf { it.isNotEmpty() }
    }

    fun parseSubscription(html: String): AO3SubscriptionState {
        val document = Jsoup.parse(html)
        val form = document.selectFirst("form[action*=subscriptions]")
            ?: return AO3SubscriptionState(isSubscribed = false, unsubscribePath = null)
        val action = form.attr("action").trim()
        val method = form.selectFirst("input[name=_method]")?.attr("value")?.trim()?.lowercase()
        return if (method == "delete") {
            AO3SubscriptionState(isSubscribed = true, unsubscribePath = action.takeIf { it.isNotEmpty() })
        } else {
            AO3SubscriptionState(isSubscribed = false, unsubscribePath = null)
        }
    }

    fun writeErrorMessage(html: String): String? {
        val document = Jsoup.parse(html)
        return document.selectFirst(".errorlist li, .error p, .flash.error")
            ?.normalizedText()
            ?.takeIf { it.isNotBlank() }
    }

    fun alreadyKudosed(html: String): Boolean {
        return html.contains("already left kudos", ignoreCase = true)
    }
}

private fun Element.authenticityToken(): String? {
    return selectFirst("input[name=authenticity_token]")?.attr("value")?.trim()
        ?.takeIf { it.isNotEmpty() }
}

internal fun Document.loginRequired(): Boolean {
    return body().classNames().any { it.equals("logged-out", ignoreCase = true) } &&
        selectFirst("form[action*=/users/login], form#new_user") != null
}

internal fun Element.normalizedText(): String {
    return text().replace(Regex("\\s+"), " ").trim()
}
