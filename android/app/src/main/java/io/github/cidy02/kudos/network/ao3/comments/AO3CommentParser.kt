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
        target: AO3CommentTarget,
        page: Int = 1
    ): AO3CommentThread {
        if (AO3OverloadDetector.isOverloadPage(html)) throw AO3CommentParseException.Overloaded()

        val document = Jsoup.parse(html, finalUrl)
        if (document.loginRequired()) throw AO3CommentParseException.LoginRequired()

        val currentPage = page.coerceAtLeast(1)
        return AO3CommentThread(
            target = target,
            comments = parseComments(document),
            form = parseCommentForm(document, html, target),
            commentsLocked = commentsLocked(document),
            workAuthors = parseWorkAuthors(document),
            currentPage = currentPage,
            totalPages = parseTotalPages(document, currentPage),
            totalComments = parseTotalComments(document)
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

    /**
     * Work and chapter comment pages retain the canonical work preface above
     * `#comments_placeholder`. Read only that h3 byline so comment-author links
     * (h4) and unrelated blurbs cannot be mistaken for work creators.
     *
     * Selectors copied from iOS `parseCommentsWorkAuthors` (AO3Client+Comments.swift).
     */
    private fun parseWorkAuthors(document: Document): List<AO3CommentWorkAuthor> {
        val selectors = listOf(
            "#workskin > .preface h3.byline",
            "#workskin .preface h3.byline",
            "#main > .preface h3.byline",
            "h3.byline.heading"
        )
        for (selector in selectors) {
            val byline = document.selectFirst(selector) ?: continue
            val authors = byline.select("a[rel=author]").mapNotNull { link ->
                val displayName = link.normalizedText()
                if (displayName.isBlank()) return@mapNotNull null
                val href = link.attr("href")
                AO3CommentWorkAuthor(
                    displayName = displayName,
                    username = AO3CommentAvatar.usernameFromProfilePath(href),
                    profileUrl = link.absUrl("href").ifBlank { null }
                )
            }
            if (authors.isNotEmpty()) return authors
        }
        return emptyList()
    }

    /**
     * Builds a real comment tree from the page's top-level `ol.thread`
     * (iOS `parseThread`). Nested replies hang under [AO3Comment.replies].
     */
    private fun parseComments(document: Document): List<AO3Comment> {
        val root = document.selectFirst(
            "#comments_placeholder ol.thread, #main > ol.thread, main > ol.thread, ol.thread"
        ) ?: return emptyList()
        return parseThread(root, depth = 0, parentId = null)
    }

    /**
     * Walks one `ol.thread`. AO3's structure: a comment `li.comment`, then —
     * when it has replies — either a nested `ol.thread` *inside* that `li`
     * (simpler fixtures) or a *sibling* wrapper `li` (no id) containing
     * `ol.thread` (live otwarchive). Both attach as [AO3Comment.replies] of
     * the preceding comment.
     */
    private fun parseThread(
        thread: Element,
        depth: Int,
        parentId: String?
    ): List<AO3Comment> {
        val comments = mutableListOf<AO3Comment>()
        for (li in thread.children()) {
            if (!li.tagName().equals("li", ignoreCase = true)) continue
            val effectiveParent = comments.lastOrNull()?.id ?: parentId

            val cutoff = parseThreadCutoff(li, effectiveParent, depth)
            if (cutoff != null) {
                comments.add(cutoff)
                continue
            }

            if (li.hasClass("comment") || li.id().startsWith("comment_")) {
                val parsed = parseOneComment(li, depth) ?: continue
                // Nested ol.thread inside this comment li (fixture / some pages).
                val nestedInside = li.children().firstOrNull {
                    it.tagName().equals("ol", ignoreCase = true) && it.hasClass("thread")
                }
                val withReplies = if (nestedInside != null) {
                    parsed.copy(
                        replies = parseThread(nestedInside, depth + 1, parsed.id)
                    )
                } else {
                    parsed
                }
                comments.add(withReplies)
            } else {
                // Sibling wrapper li containing a nested ol.thread (live AO3).
                val nested = li.selectFirst("ol.thread")
                if (nested != null && comments.isNotEmpty()) {
                    val last = comments.removeAt(comments.lastIndex)
                    comments.add(
                        last.copy(
                            replies = last.replies + parseThread(nested, depth + 1, last.id)
                        )
                    )
                }
            }
        }
        return comments
    }

    private fun parseOneComment(element: Element, depth: Int): AO3Comment? {
        val body = element.selectFirst("blockquote.userstuff, .userstuff")?.normalizedText()
            ?: element.selectFirst(".comment-text")?.normalizedText()
            ?: ""
        val deleted = element.hasClass("deleted") ||
            element.hasClass("hidden") ||
            body.contains("deleted comment", ignoreCase = true) ||
            body.contains("hidden comment", ignoreCase = true) ||
            body.contains("Previous comment deleted", ignoreCase = true)
        if (body.isBlank() && !deleted && !element.id().startsWith("comment_")) {
            return null
        }

        val parsedAuthor = parseCommentAuthor(element, deleted)
        val avatarUrl = if (!parsedAuthor.isGuest) parseAvatarUrl(element) else null
        val id = element.id().ifBlank { null }
        val actions = parseActionPaths(element)
        val chapterLink = element.selectFirst(".parent a[href*=/chapters/]")
        val chapterId = chapterLink?.attr("href")?.let { href ->
            Regex("""/chapters/(\d+)""").find(href)?.groupValues?.getOrNull(1)?.toLongOrNull()
        }
        val chapterLabel = element.selectFirst(".parent")?.normalizedText()?.takeIf { it.isNotBlank() }

        return AO3Comment(
            id = id,
            author = AO3CommentAuthor(
                name = parsedAuthor.name,
                profileUrl = parsedAuthor.profileUrl,
                username = parsedAuthor.username
            ),
            date = element.selectFirst(".datetime, p.datetime, .posted")?.normalizedText().orEmpty(),
            body = body.ifBlank { if (deleted) "(Previous comment deleted.)" else "Deleted or hidden comment." },
            depth = depth,
            isDeletedOrHidden = deleted,
            isGuest = parsedAuthor.isGuest,
            isAnonymousCreator = parsedAuthor.isAnonymousCreator,
            avatarUrl = avatarUrl,
            canReply = parseCanReply(element),
            editPath = actions.editPath,
            deletePath = actions.deletePath,
            threadPath = actions.threadPath,
            parentThreadPath = actions.parentThreadPath,
            chapterId = chapterId,
            chapterLabel = chapterLabel
        )
    }

    /**
     * AO3 deep-thread cutoff (CAA-7): id-less `li.comment` with a single
     * "N more comments in this thread" link to `/comments/<id>`.
     */
    private fun parseThreadCutoff(li: Element, parentId: String?, depth: Int): AO3Comment? {
        if (!li.hasClass("comment") || li.id().isNotBlank() || li.hasAttr("role")) return null
        val children = li.children()
        if (children.size != 1) return null
        val paragraph = children.first() ?: return null
        if (!paragraph.tagName().equals("p", ignoreCase = true)) return null
        val anchors = paragraph.select("a")
        if (anchors.size != 1) return null
        val link = anchors.first() ?: return null
        val href = link.attr("href")
        if (!href.contains("/comments/")) return null
        val lastSegment = href.trimEnd('/').substringAfterLast('/')
        if (lastSegment.toLongOrNull() == null) return null
        val digits = link.normalizedText().takeWhile { it.isDigit() }
        val cutoffId = "cutoff_${parentId ?: "root"}_$lastSegment"
        return AO3Comment(
            id = cutoffId,
            author = AO3CommentAuthor(name = ""),
            date = "",
            body = link.normalizedText(),
            depth = depth,
            isDeletedOrHidden = false,
            isThreadCutoff = true,
            cutoffCount = digits.toIntOrNull(),
            cutoffThreadPath = href
        )
    }

    /**
     * True when AO3 rendered a Reply action for this comment in this session.
     * Mirrors iOS `applyAction` on `ul[id^=navigation_for_comment_], ul.actions`:
     * any `<a>` whose label is "reply" or whose href contains `add_comment_reply`.
     */
    private fun parseCanReply(element: Element): Boolean {
        val actions = element.selectFirst("ul[id^=navigation_for_comment_], ul.actions")
            ?: return false
        for (link in actions.select("a")) {
            val label = link.normalizedText().lowercase()
            val href = link.attr("href")
            if (label == "reply" || href.contains("add_comment_reply")) {
                return true
            }
        }
        return false
    }

    private data class ActionPaths(
        val editPath: String? = null,
        val deletePath: String? = null,
        val threadPath: String? = null,
        val parentThreadPath: String? = null
    )

    private fun parseActionPaths(element: Element): ActionPaths {
        // Only look at this comment's own action list — not nested replies.
        val actions = element.selectFirst("ul[id^=navigation_for_comment_], ul.actions")
            ?: return ActionPaths()
        var editPath: String? = null
        var deletePath: String? = null
        var threadPath: String? = null
        var parentThreadPath: String? = null
        for (link in actions.select("a")) {
            val label = link.normalizedText().lowercase()
            val href = link.attr("href").takeIf { it.isNotBlank() } ?: continue
            when {
                label == "edit" -> editPath = href
                label == "delete" || label.contains("delete") -> deletePath = href
                label.contains("thread") && label.contains("parent") -> parentThreadPath = href
                label.contains("thread") || href.matches(Regex(".*/comments/\\d+/?$")) -> {
                    if (threadPath == null) threadPath = href
                }
            }
        }
        return ActionPaths(editPath, deletePath, threadPath, parentThreadPath)
    }

    /**
     * Highest numeric page in `ol.pagination li` text, never less than the
     * requested page. Same idiom as account/inbox/search parsers — non-numeric
     * entries ("Next ›", "…") yield null from `toIntOrNull` and are skipped.
     */
    private fun parseTotalPages(document: Document, currentPage: Int): Int {
        return document.select("ol.pagination li")
            .mapNotNull { it.normalizedText().toIntOrNull() }
            .fold(currentPage) { total, pageNumber -> maxOf(total, pageNumber) }
    }

    /** Work-level comment total from `dl.stats dd.comments`, if present. */
    private fun parseTotalComments(document: Document): Int? {
        val text = document.selectFirst("dl.stats dd.comments")?.normalizedText()
            ?: return null
        val digits = text.filter { it.isDigit() }
        return digits.takeIf { it.isNotEmpty() }?.toIntOrNull()
    }

    /**
     * Registered / guest / anonymous-creator byline detection.
     * Guest + anonymous-creator branches follow iOS `parseComment` (AO3Client+Comments.swift);
     * name fallbacks for malformed bylines keep Android's previous behaviour.
     */
    private fun parseCommentAuthor(element: Element, deleted: Boolean): ParsedCommentAuthor {
        // If the <li> itself has the 'deleted' class, AO3 usually hides the
        // author entirely.
        if (deleted) {
            return ParsedCommentAuthor(
                name = "Deleted comment",
                profileUrl = null,
                username = null,
                isGuest = true,
                isAnonymousCreator = false
            )
        }

        // Prefer a real profile link (iOS: `a[href^=/users/]` on the byline).
        // Keep the broader author-link selectors as a registered-user fallback so
        // existing fixtures and slightly drifted markup still resolve a name.
        val userLink = element.selectFirst(
            "h4.heading.byline a[href^=/users/], " +
                "h4.heading a[href^=/users/], " +
                ".heading a[href^=/users/], " +
                ".byline a[href*=/users/], " +
                ".heading a[rel=author], " +
                "h4.heading a[rel=author]"
        )

        if (userLink != null) {
            val href = userLink.attr("href")
            val profileUrl = userLink.absUrl("href").ifBlank { null }
            val name = userLink.normalizedText()
                .ifBlank {
                    element.selectFirst(".heading, .byline")?.normalizedText().orEmpty()
                }
                .ifBlank { if (deleted) "Deleted comment" else "Anonymous" }
            return ParsedCommentAuthor(
                name = name,
                profileUrl = profileUrl,
                username = AO3CommentAvatar.usernameFromProfilePath(href)
                    ?: AO3CommentAvatar.usernameFromProfilePath(profileUrl),
                isGuest = false,
                isAnonymousCreator = false
            )
        }

        val byline = element.selectFirst(
            "h4.heading.byline, h4.heading, .heading.byline, .byline, .heading"
        )
        val roleText = byline?.selectFirst("span.role")?.normalizedText().orEmpty()
        var isGuest = roleText.contains("guest", ignoreCase = true)
        val fullByline = byline?.normalizedText().orEmpty()

        if (!isGuest && fullByline.contains("anonymous creator", ignoreCase = true)) {
            return ParsedCommentAuthor(
                name = "Anonymous Creator",
                profileUrl = null,
                username = null,
                isGuest = false,
                isAnonymousCreator = true
            )
        }

        // Guest byline (or unknown non-linked byline): treat as guest.
        // iOS: `<span>Name</span><span class="role"> (Guest)</span>`.
        isGuest = true
        val guestNameFromSpan = byline?.children()?.firstOrNull { child ->
            child.tagName() == "span" &&
                !child.hasClass("role") &&
                !child.hasClass("parent") &&
                !child.hasClass("posted")
        }?.normalizedText()

        val name = guestNameFromSpan
            ?.takeIf { it.isNotBlank() }
            ?: byline?.normalizedText()?.takeIf { it.isNotBlank() }
            ?: if (deleted) "Deleted comment" else "Guest"

        return ParsedCommentAuthor(
            name = name,
            profileUrl = null,
            username = null,
            isGuest = true,
            isAnonymousCreator = false
        )
    }

    /**
     * AO3 includes the user icon in the comment itself. Use only that URL —
     * never follow the profile link. Accounts with no uploaded icon get AO3's
     * logo under `/images/skins/`, which [AO3CommentAvatar] rejects.
     *
     * Selector: iOS `div.icon img.icon[src]` on the comment `li`.
     */
    private fun parseAvatarUrl(element: Element): String? {
        val icon = element.selectFirst("div.icon img.icon[src]") ?: return null
        val src = icon.attr("src").takeIf { it.isNotBlank() }
            ?: icon.absUrl("src").takeIf { it.isNotBlank() }
            ?: return null
        // Prefer absUrl when Jsoup resolved it against the page base; fall back
        // to the raw src for relative-path resolution in AO3CommentAvatar.
        val absolute = icon.absUrl("src").takeIf { it.isNotBlank() }
        return AO3CommentAvatar.avatarUrlForIconSource(absolute ?: src)
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
                ?: formParser.parseDefaultPseudId(html),
            availablePseuds = formParser.parsePostingPseuds(form.outerHtml(), "comment[pseud_id]")
                .ifEmpty { formParser.parsePostingPseuds(html, "comment[pseud_id]") }
        )
    }

    private fun commentsLocked(document: Document): Boolean {
        val text = document.body().normalizedText()
        // Do NOT treat "log in to comment" as locked — that is an auth prompt, not a lock.
        return text.contains("comments have been disabled", ignoreCase = true) ||
            text.contains("not accepting comments", ignoreCase = true) ||
            text.contains("comments are disabled", ignoreCase = true)
    }


    private data class ParsedCommentAuthor(
        val name: String,
        val profileUrl: String?,
        val username: String?,
        val isGuest: Boolean,
        val isAnonymousCreator: Boolean
    )
}
