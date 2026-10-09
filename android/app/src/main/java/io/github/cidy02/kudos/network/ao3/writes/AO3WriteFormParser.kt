package io.github.cidy02.kudos.network.ao3.writes

import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

class AO3WriteFormParser {
    /** Work flashes are layout evidence, never the writer's chapter/preview HTML. */
    fun workWriteError(html: String): String? {
        val document = Jsoup.parse(html)
        if (document.selectFirst("#main > #previewpane") != null) return null
        return document.select("#main .flash.error, #main #error li")
            .firstOrNull { element ->
                element.parents().none { it.id() == "workskin" || it.id() == "previewpane" || it.hasClass("userstuff") } &&
                    element.normalizedText().isNotEmpty()
            }?.let { evidence ->
                // Scope first, then use the shared AO3 validation-list reader (A4-3).
                if (evidence.tagName() == "li") writeErrorMessage("<div id='error'><ul>${evidence.outerHtml()}</ul></div>")
                else writeErrorMessage(evidence.outerHtml())
            }
    }

    fun workWriteNotice(html: String): String? = Jsoup.parse(html)
        .selectFirst("#main > .flash.notice")?.normalizedText()?.takeIf { it.isNotEmpty() }

    fun parseAuthenticityToken(html: String, formSelector: String? = null, metaOnly: Boolean = false): String? {
        val document = Jsoup.parse(html)
        // iOS fetchCSRFPage uses the page's csrf-token meta, not another row's input.
        if (metaOnly) return document.selectFirst("meta[name=csrf-token]")?.attr("content")?.trim()
            ?.takeIf { it.isNotEmpty() }
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

    fun parsePostingPseuds(html: String, field: String): List<AO3PostingPseudOption> {
        val document = Jsoup.parse(html)
        val select = document.selectFirst("select[name=\"$field\"]") ?: return emptyList()
        return select.select("option").mapNotNull { option ->
            val id = option.attr("value").trim()
            val name = option.text().trim()
            if (id.isEmpty() || name.isEmpty()) return@mapNotNull null
            AO3PostingPseudOption(
                id = id,
                name = name,
                selected = option.hasAttr("selected")
            )
        }
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

    /**
     * Parse the bookmark form embedded on a work page.
     *
     * Create form: `action` like `/works/{id}/bookmarks`, no `_method`.
     * Edit form: `action` like `/bookmarks/{id}`, hidden `_method=put`, fields
     * pre-filled with the existing notes/tags/private/rec values.
     *
     * // ponytail: relies on the work page embedding the edit form when a
     * bookmark already exists (same convention as parseSubscription). If AO3
     * ever only embeds a blank create form on the work page, upgrade by GETting
     * `/works/{id}/bookmarks/new` (AO3 redirects to the edit form when one
     * exists) and re-running this parser on that HTML.
     */
    fun parseBookmarkState(html: String): AO3BookmarkState {
        val document = Jsoup.parse(html)
        val form = document.selectFirst("form[action*=bookmarks]")
            ?: return AO3BookmarkState(exists = false, editPath = null)
        val action = form.attr("action").trim()
        val method = form.selectFirst("input[name=_method]")?.attr("value")?.trim()?.lowercase()
        val collectionNames = form.selectFirst("input[name=\"bookmark[collection_names]\"]")
            ?.attr("value")
            ?.trim()
            .orEmpty()
        val input = AO3BookmarkInput(
            notes = form.selectFirst("textarea[name=\"bookmark[bookmarker_notes]\"]")
                ?.text()
                ?.trim()
                .orEmpty(),
            tags = form.selectFirst("input[name=\"bookmark[tag_string]\"]")
                ?.attr("value")
                ?.trim()
                .orEmpty(),
            isPrivate = form.selectFirst("input[name=\"bookmark[private]\"]")
                ?.hasAttr("checked") == true,
            isRecommendation = form.selectFirst("input[name=\"bookmark[rec]\"]")
                ?.hasAttr("checked") == true,
            pseudId = parseDefaultPseudId(html, "bookmark[pseud_id]")
        )
        val availablePseuds = parsePostingPseuds(html, "bookmark[pseud_id]")
        return if (method == "put" && action.isNotEmpty()) {
            AO3BookmarkState(
                exists = true,
                editPath = action,
                input = input,
                collectionNames = collectionNames,
                availablePseuds = availablePseuds
            )
        } else {
            // Create form (or unexpected markup): never throw; open blank create mode.
            AO3BookmarkState(
                exists = false,
                editPath = null,
                input = AO3BookmarkInput(pseudId = availablePseuds.find { it.selected }?.id),
                collectionNames = collectionNames,
                availablePseuds = availablePseuds
            )
        }
    }

    /**
     * iOS `AO3Client.commentWriteVerdict`: a refusal AO3 names; "done" only with AO3's own
     * notice; any other page that came back fine (a maintenance page, an interstitial) is
     * neither. Null is done; otherwise the reason to show. Comment and Inbox writes counted
     * every such page as done, and the composer then threw the typed text away (audit A17-1).
     */
    fun commentWriteFailure(statusCode: Int, body: String, fallback: String): String? {
        writeErrorMessage(body)?.let { return it }
        if (statusCode !in 200..399) return fallback
        return if (writeSuccessMessage(body) != null) null else io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields.UNCONFIRMED
    }

    fun writeSuccessMessage(html: String): String? = Jsoup.parse(html)
        .selectFirst(".flash.comment_notice, .flash.notice")?.normalizedText()?.takeIf { it.isNotBlank() }

    /**
     * iOS `AO3Client.writeErrorMessage`. `#error li` is AO3's validation list
     * (`error_messages_for`: a `div#error.error` holding an `h4` and a `ul`), which nothing else
     * here matches: a form AO3 re-rendered with its reasons read as "no error", and a refused
     * bookmark said "Bookmarked." (audit A4-3).
     */
    fun writeErrorMessage(html: String): String? {
        val document = Jsoup.parse(html)
        return document.selectFirst("#error li, .errorlist li, .error p, .flash.error, .flash.comment_error, .flash.caution")
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
