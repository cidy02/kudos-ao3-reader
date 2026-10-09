package io.github.cidy02.kudos.network.ao3.writing

import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import io.github.cidy02.kudos.network.ao3.AO3RedirectCookieRelay
import io.github.cidy02.kudos.network.ao3.account.AO3UsernameParser
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.jsoup.Jsoup
import org.jsoup.nodes.Document

class AO3SeriesFormParser {
    private fun document(html: String, url: String): Document {
        val doc = Jsoup.parse(html, url)
        val chrome = doc.clone().apply { select("form.series, #work-form form, form[action*=/series], #sortable_series_list").remove() }
        if (AO3OverloadDetector.isOverloadPage(chrome.text())) throw AO3WorkFormParseException.Overloaded()
        if (doc.selectFirst("form#new_user, form[action='/users/login']") != null ||
            AO3UsernameParser().isLoginRequiredPage(html, url)) throw AO3WorkFormParseException.LoginRequired()
        return doc
    }

    fun parse(html: String, pageUrl: String): AO3SeriesForm {
        val doc = document(html, pageUrl)
        val form = doc.selectFirst("form.series, #work-form form, form[action*=/series]") ?: invalid()
        val action = form.attr("abs:action")
        val address = action.toHttpUrlOrNull() ?: invalid()
        if (!AO3RedirectCookieRelay.isTrustedUrl(action) || !Regex("^/series(?:/[0-9]+)?/?$").matches(address.encodedPath) ||
            !form.attr("method").equals("post", true)) invalid()
        val controls = AO3WorkFormParser().servedControls(doc, form)
        fun input(name: String): String? {
            val matches = controls.filter { it.tag == "input" && it.name == name }
            return (matches.firstOrNull { it.type != "hidden" && it.type != "submit" } ?: matches.firstOrNull())
                ?.attributes?.get("value")
        }
        fun text(name: String) = controls.firstOrNull { it.tag == "textarea" && it.name == name }?.text.orEmpty()
        val token = doc.selectFirst("meta[name=csrf-token]")?.attr("content")?.trim()?.takeIf(String::isNotEmpty)
            ?: input("authenticity_token")?.takeIf(String::isNotEmpty) ?: invalid()
        val options = controls.firstOrNull { it.tag == "select" && it.name == AO3SeriesField.ids }?.options.orEmpty()
            .map { AO3FormOption(it.value, it.text.trim(), "selected" in it.attributes) }
        val ids = options.filter { it.isSelected }.map { it.value }.ifEmpty {
            controls.filter { it.name == AO3SeriesField.ids && it.tag == "input" && it.type == "hidden" }
                .mapNotNull { it.attributes["value"]?.takeIf(String::isNotEmpty) }
        }
        val id = address.pathSegments.getOrNull(1)?.toLongOrNull()
        if (id != null && (id <= 0 || controls.none { it.tag == "input" && it.name == AO3SeriesField.title } ||
            input("_method")?.takeIf(String::isNotEmpty)?.let { it !in setOf("put", "patch") } == true)) invalid()
        val create = id == null || doc.selectFirst("h2.heading, h2")?.text().orEmpty().contains("new series", true)
        return AO3SeriesForm(id, action, token, input("_method")?.takeIf(String::isNotEmpty), controls,
            input(AO3SeriesField.title).orEmpty(), text(AO3SeriesField.summary), text(AO3SeriesField.notes),
            controls.any { it.name == AO3SeriesField.complete && it.type == "checkbox" && "checked" in it.attributes },
            AO3CreatorDraft(ids, options, input(AO3SeriesField.byline).orEmpty()),
            openOnAO3ForCreate = create && controls.none { it.name == AO3SeriesField.title && it.tag == "input" })
    }

    fun parseManage(html: String, pageUrl: String): List<AO3SeriesWorkRow> {
        val doc = document(html, pageUrl)
        val list = doc.selectFirst("#sortable_series_list") ?: invalid()
        val rows = list.select("li").mapIndexedNotNull { index, li ->
            val marker = li.selectFirst("[id^=position-for-]")
            val serial = li.id().removePrefix("serial_").toLongOrNull()
                ?: marker?.id()?.removePrefix("position-for-")?.toLongOrNull() ?: return@mapIndexedNotNull null
            val title = li.selectFirst("h3.heading, h4.heading, a")?.text()?.trim().orEmpty()
            val work = li.select("a[href]").firstNotNullOfOrNull {
                Regex("/works/([0-9]+)").find(it.attr("href"))?.groupValues?.get(1)?.toLongOrNull()
            }
            AO3SeriesWorkRow(serial, title, marker?.text()?.trim()?.toIntOrNull() ?: index + 1, work,
                title.endsWith(" (DRAFT)"))
        }
        if (rows.isEmpty() || rows.map { it.serialWorkID }.distinct().size != rows.size) invalid()
        return rows
    }

    private fun invalid(): Nothing = throw AO3WorkFormParseException.InvalidForm("Couldn't read AO3's series form.")
}
