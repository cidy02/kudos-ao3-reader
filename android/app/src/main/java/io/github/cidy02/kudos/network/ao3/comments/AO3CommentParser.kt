package io.github.cidy02.kudos.network.ao3.comments

import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteUrls
import io.github.cidy02.kudos.network.ao3.writes.loginRequired
import io.github.cidy02.kudos.network.ao3.writes.normalizedText
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

sealed class AO3CommentParseException(message: String) : Exception(message) {
    class LoginRequired : AO3CommentParseException("AO3 requires login for these comments.")
    class Overloaded : AO3CommentParseException("AO3 returned an overload or capacity page.")
}

class AO3CommentParser(
    private val formParser: AO3WriteFormParser = AO3WriteFormParser()
) {
    fun parseThread(
        html: String,
        finalUrl: String,
        target: AO3CommentTarget
    ): AO3CommentThread {
        if (AO3OverloadDetector.isOverloadPage(html)) throw AO3CommentParseException.Overloaded()

        val document = Jsoup.parse(html, finalUrl)
        if (document.loginRequired()) throw AO3CommentParseException.LoginRequired()

        return AO3CommentThread(
            target = target,
            comments = parseComments(document),
            form = parseCommentForm(document, html, target),
            commentsLocked = commentsLocked(document)
        )
    }

    fun parseCommentForm(
        html: String,
        finalUrl: String,
        target: AO3CommentTarget
    ): AO3CommentForm? {
        val document = Jsoup.parse(html, finalUrl)
        return parseCommentForm(document, html, target)
    }

    private fun parseComments(document: Document): List<AO3Comment> {
        return document.select("li.comment, div.comment").mapIndexedNotNull { index, element ->
            val body = element.selectFirst("blockquote.userstuff, .userstuff")?.normalizedText()
                ?: element.selectFirst(".comment-text")?.normalizedText()
                ?: ""
            val deleted = element.hasClass("deleted") ||
                element.hasClass("hidden") ||
                body.contains("deleted comment", ignoreCase = true) ||
                body.contains("hidden comment", ignoreCase = true)
            if (body.isBlank() && !deleted) return@mapIndexedNotNull null

            val authorLink = element.selectFirst(".heading a[rel=author], h4.heading a[rel=author], .byline a[href*=/users/]")
            val authorName = authorLink?.normalizedText()
                ?: element.selectFirst(".heading, .byline")?.normalizedText()
                ?: if (deleted) "Deleted comment" else "Anonymous"
            val id = element.id().ifBlank { null }
            AO3Comment(
                id = id,
                author = AO3CommentAuthor(
                    name = authorName.ifBlank { "Anonymous" },
                    profileUrl = authorLink?.absUrl("href")?.ifBlank { null }
                ),
                date = element.selectFirst(".datetime, p.datetime, .posted")?.normalizedText().orEmpty(),
                body = body.ifBlank { "Deleted or hidden comment." },
                depth = commentDepth(element, index),
                isDeletedOrHidden = deleted
            )
        }
    }

    private fun parseCommentForm(
        document: Document,
        html: String,
        target: AO3CommentTarget
    ): AO3CommentForm? {
        val form = document.selectFirst("form#new_comment, form[action*=comments]") ?: return null
        val token = form.selectFirst("input[name=authenticity_token]")?.attr("value")?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: formParser.parseAuthenticityToken(html)
            ?: return null
        val action = form.absUrl("action").ifBlank {
            AO3WriteUrls.absoluteUrl(form.attr("action")) ?: target.defaultSubmitUrl()
        }
        return AO3CommentForm(
            actionUrl = action,
            authenticityToken = token,
            pseudId = formParser.parseDefaultPseudId(form.outerHtml())
                ?: formParser.parseDefaultPseudId(html)
        )
    }

    private fun commentsLocked(document: Document): Boolean {
        val text = document.body().normalizedText()
        return text.contains("comments have been disabled", ignoreCase = true) ||
            text.contains("not accepting comments", ignoreCase = true) ||
            text.contains("log in to comment", ignoreCase = true)
    }

    private fun commentDepth(element: Element, fallback: Int): Int {
        val explicit = element.classNames().firstNotNullOfOrNull { className ->
            Regex("""depth[-_]?(\d+)""").find(className)?.groupValues?.getOrNull(1)?.toIntOrNull()
        }
        if (explicit != null) return explicit.coerceAtLeast(0)
        return element.parents().count { it.hasClass("thread") || it.hasClass("children") }
            .takeIf { it > 0 }
            ?: fallback.coerceAtMost(0)
    }
}
