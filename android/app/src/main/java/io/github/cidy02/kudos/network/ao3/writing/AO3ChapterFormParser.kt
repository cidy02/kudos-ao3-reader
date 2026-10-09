package io.github.cidy02.kudos.network.ao3.writing

import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import io.github.cidy02.kudos.network.ao3.AO3RedirectCookieRelay
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import io.github.cidy02.kudos.network.ao3.account.AO3UsernameParser
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

/** Only the supplied page. Raw controls reuse the work form's browser snapshot. */
class AO3ChapterFormParser {
    fun parse(html: String, pageUrl: String): AO3ChapterForm {
        val doc = document(html, pageUrl)
        val form = doc.selectFirst("#chapter-form form, form.chapter, form[action*=/chapters]")
            ?: invalid("Couldn't read AO3's chapter form.")
        val action = action(form)
        val path = action.toHttpUrlOrNull()!!.pathSegments
        val controls = AO3WorkFormParser().servedControls(doc, form)
        fun input(name: String) = controls.firstOrNull { it.tag == "input" && it.name == name }?.attributes?.get("value").orEmpty()
        fun area(name: String) = controls.firstOrNull { it.tag == "textarea" && it.name == name }?.text.orEmpty()
        fun date(name: String): String {
            input(name).takeIf(String::isNotEmpty)?.let { return it }
            val options = controls.firstOrNull { it.tag == "select" && it.name == name }?.options.orEmpty()
            val option = options.firstOrNull { "selected" in it.attributes } ?: options.firstOrNull()
            return option?.attributes?.get("value")?.takeIf(String::isNotEmpty) ?: option?.text.orEmpty()
        }
        val pseuds = controls.firstOrNull { it.tag == "select" && it.name == AO3ChapterField.authorIDs }?.options.orEmpty()
            .map { AO3FormOption(it.attributes["value"].orEmpty(), it.text.trim(), "selected" in it.attributes) }
        val ids = pseuds.filter { it.isSelected }.map { it.value }.ifEmpty {
            controls.filter { it.tag == "input" && it.type == "hidden" && it.name == AO3ChapterField.authorIDs }
                .map { it.attributes["value"].orEmpty() }.filter(String::isNotEmpty)
        }
        return AO3ChapterForm(workID = path[1].toLong(), chapterID = path.getOrNull(3)?.toLongOrNull(),
            actionUrl = action, methodOverride = input("_method").takeIf(String::isNotEmpty), csrfToken = token(doc, form),
            servedControls = controls, formAttributes = attributes(form), title = input(AO3ChapterField.title),
            position = input(AO3ChapterField.position), includePosition = controls.any { it.tag == "input" && it.name == AO3ChapterField.position },
            wipLength = input(AO3ChapterField.total), summary = area(AO3ChapterField.summary), notes = area(AO3ChapterField.notes),
            endnotes = area(AO3ChapterField.endnotes), content = area(AO3ChapterField.content).ifEmpty {
                controls.firstOrNull { it.tag == "textarea" && it.attributes["id"] == "content" }?.text.orEmpty()
            }, publishedYear = date(AO3ChapterField.year), publishedMonth = date(AO3ChapterField.month), publishedDay = date(AO3ChapterField.day),
            isDraft = controls.any { it.name == AO3WorkSubmitAction.SaveDraft.fieldName && (it.tag == "button" || it.type == "submit") },
            creators = AO3CreatorDraft(ids, pseuds))
    }

    fun preview(html: String, pageUrl: String, workOnly: Boolean = false): AO3ChapterPreview {
        val doc = document(html, pageUrl)
        val pane = doc.selectFirst("#previewpane") ?: invalid(CHAPTER_PREVIEW_UNAVAILABLE)
        val form = doc.select("form").firstOrNull { it.selectFirst("[name=edit_button]") != null }
        val action = form?.let {
            if (!workOnly) action(it) else it.attr("abs:action").also { url ->
                if (!AO3RedirectCookieRelay.isTrustedUrl(url) ||
                    !Regex("^/works/[1-9][0-9]*/?$").matches(url.toHttpUrlOrNull()?.encodedPath.orEmpty()))
                    invalid(CHAPTER_PREVIEW_UNAVAILABLE)
            }
        }
        val path = action?.toHttpUrlOrNull()?.pathSegments.orEmpty()
        val controls = form?.let { AO3WorkFormParser().servedControls(doc, it) }.orEmpty()
        pane.select("form, .landmark, img").remove()
        val blocks = pane.select("h2.title, h3.title, .module > h3.heading, .userstuff").mapNotNull { element ->
            if (element.hasClass("userstuff")) AO3ChapterPreview.Block(AO3ChapterPreview.Kind.Html, element.html())
            else element.text().trim().takeIf(String::isNotEmpty)?.let {
                AO3ChapterPreview.Block(if (element.hasClass("title")) AO3ChapterPreview.Kind.Heading else AO3ChapterPreview.Kind.Label, it)
            }
        }
        return AO3ChapterPreview(path.getOrNull(1)?.toLongOrNull(), path.getOrNull(3)?.toLongOrNull(),
            doc.selectFirst("meta[name=csrf-token]")?.attr("content")?.let(::trimWritingTag)?.takeIf(String::isNotEmpty),
            AO3WriteFormParser().workWriteNotice(html), blocks, controls, form?.let(::attributes).orEmpty())
    }

    fun deleteForm(html: String, pageUrl: String, workID: Long, chapterID: Long): AO3ChapterDeleteForm {
        val doc = document(html, pageUrl)
        val form = doc.selectFirst("form.destroy, form[method=post]") ?: invalid("Couldn't read AO3's chapter form.")
        val url = action(form)
        if (url.toHttpUrlOrNull()?.encodedPath?.trimEnd('/') != "/works/$workID/chapters/$chapterID")
            invalid("Couldn't read AO3's chapter form.")
        return AO3ChapterDeleteForm(url, token(doc, form),
            form.selectFirst("input[name=_method]")?.attr("value")?.takeIf(String::isNotEmpty) ?: "delete")
    }

    private fun document(html: String, pageUrl: String): Document {
        val doc = Jsoup.parse(html, pageUrl)
        val chrome = doc.clone().apply { select("form, #previewpane, #workskin, .userstuff").remove() }
        if (AO3OverloadDetector.isOverloadPage(chrome.text())) throw AO3WorkFormParseException.Overloaded()
        if (doc.selectFirst("form#new_user, form[action='/users/login']") != null || AO3UsernameParser().isLoginRequiredPage(html, pageUrl))
            throw AO3WorkFormParseException.LoginRequired()
        return doc
    }
    private fun action(form: Element): String {
        val url = form.attr("abs:action")
        if (form.attr("action").isEmpty() || !AO3RedirectCookieRelay.isTrustedUrl(url) ||
            !Regex("^/works/[1-9][0-9]*/chapters(?:/[1-9][0-9]*)?/?$").matches(url.toHttpUrlOrNull()?.encodedPath.orEmpty()) ||
            !form.attr("method").equals("post", true)) invalid("Couldn't read AO3's chapter form.")
        return url
    }
    private fun token(doc: Document, form: Element) = doc.selectFirst("meta[name=csrf-token]")?.attr("content")?.trim()?.takeIf(String::isNotEmpty)
        ?: form.selectFirst("input[name=authenticity_token]")?.attr("value")?.takeIf(String::isNotEmpty)
        ?: invalid("Couldn't prepare the request. Try again, or open the form on AO3.")
    private fun attributes(form: Element) = form.attributes().associate { it.key to it.value }
    private fun invalid(message: String): Nothing = throw AO3WorkFormParseException.InvalidForm(message)
}

const val CHAPTER_PREVIEW_UNAVAILABLE = "AO3 didn't return a preview. Try opening the work on AO3."
