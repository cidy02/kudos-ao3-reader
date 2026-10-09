package io.github.cidy02.kudos.network.ao3.writing

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3RedirectCookieRelay
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.jsoup.Jsoup
import org.jsoup.nodes.Document

/** Work and chapter previews share AO3's pane, headings and sanitized paragraphs. */
typealias AO3WorkPreview = AO3ChapterPreview

fun AO3WorkForm.adopting(preview: AO3WorkPreview): AO3WorkForm {
    val updated = copy(csrfToken = preview.csrfToken ?: csrfToken)
    if (workID != null) return updated
    val id = preview.workID
    require(id != null && id > 0) { AO3CollectionFields.UNCONFIRMED }
    return updated.copy(workID = id, actionUrl = workActionUrl(id), methodOverride = "patch",
        kind = AO3WorkFormKind.Draft, isPosted = false)
}

internal fun workActionUrl(id: Long) = "${AO3Constants.BASE_URL}/works/$id"
internal fun workConfirmDeleteUrl(id: Long) = "${workActionUrl(id)}/confirm_delete"

data class AO3WorkDeleteImplications(
    val actionUrl: String, val csrfToken: String, val methodOverride: String,
    val title: String, val isDraft: Boolean, val cautionText: String,
    val chapters: Int?, val kudos: Int?, val comments: Int?, val bookmarks: Int?, val words: Int?
)

/** Only supplied HTML; no library or persistence dependency. */
internal object AO3WorkDeleteParser {
    fun parse(html: String, pageUrl: String, workID: Long): AO3WorkDeleteImplications {
        val doc = Jsoup.parse(html, pageUrl)
        val form = doc.selectFirst("form.destroy, form[method=post]") ?: doc.selectFirst("form")
            ?: throw AO3WorkFormParseException.InvalidForm("Couldn't read AO3's work form.")
        val action = form.attr("abs:action")
        if (!AO3RedirectCookieRelay.isTrustedUrl(action) ||
            action.toHttpUrlOrNull()?.encodedPath?.trimEnd('/') != "/works/$workID")
            throw AO3WorkFormParseException.InvalidForm("Couldn't read AO3's work form.")
        fun input(name: String): String? {
            val matches = form.select("input[name]").filter { it.attr("name") == name }
            return (matches.firstOrNull { it.attr("type") !in setOf("hidden", "submit") } ?: matches.firstOrNull())?.attr("value")
        }
        val token = doc.selectFirst("meta[name=csrf-token]")?.attr("content")?.let(::trimWritingTag)?.takeIf(String::isNotEmpty)
            ?: input("authenticity_token")
            ?: throw AO3WorkFormParseException.InvalidForm("Couldn't read AO3's work form.")
        val heading = doc.selectFirst("h2.heading, h2")?.text()?.let(::trimWritingTag).orEmpty()
        val caution = doc.selectFirst("p.caution, p.notice, .caution.notice")?.text()?.let(::trimWritingTag).orEmpty()
        val first = caution.indexOf('"')
        val last = caution.lastIndexOf('"')
        val title = if (first >= 0 && last > first) trimWritingTag(caution.substring(first + 1, last)).ifEmpty { heading } else heading
        fun count(name: String, label: String): Int? = stat(doc, name) ?: Regex("(\\d[\\d,]*)\\s+$label", RegexOption.IGNORE_CASE)
            .find(caution)?.groupValues?.get(1)?.filter(Char::isDigit)?.toIntOrNull()
        return AO3WorkDeleteImplications(action, token,
            input("_method")?.takeIf(String::isNotEmpty) ?: "delete",
            title, heading.contains("draft", true) || caution.contains("draft", true), caution,
            count("chapters", "chapter"), count("kudos", "kudo"), count("comments", "comment"),
            count("bookmarks", "bookmark"), count("words", "word"))
    }

    private fun stat(doc: Document, name: String): Int? {
        val text = doc.selectFirst("dl.stats dd.$name, dd.$name")?.text().orEmpty()
        val all = text.filter(Char::isDigit).toIntOrNull()
        return if (name == "chapters") text.split('/').firstOrNull { it.isNotEmpty() }
            ?.filter(Char::isDigit)?.toIntOrNull() ?: all else all
    }
}
