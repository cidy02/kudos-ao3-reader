package io.github.cidy02.kudos.network.ao3.inbox

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import io.github.cidy02.kudos.network.ao3.account.AO3UsernameParser
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentAvatar
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

sealed class AO3InboxParseException(message: String) : Exception(message) {
    class LoginRequired : AO3InboxParseException("AO3 account login is required.")
    class Overloaded : AO3InboxParseException("AO3 returned an overload or capacity page.")
    class MissingRequiredStructure(detail: String) : AO3InboxParseException(detail)
}

/**
 * Jsoup port of iOS `AO3Client+Inbox.swift` selectors. Fail closed: incomplete
 * bulk/filter forms become null rather than partially writable/guessable.
 */
class AO3InboxParser(
    private val usernameParser: AO3UsernameParser = AO3UsernameParser()
) {
    fun parseInboxPage(
        html: String,
        page: Int,
        finalUrl: String? = null
    ): AO3InboxPage {
        if (AO3OverloadDetector.isOverloadPage(html)) throw AO3InboxParseException.Overloaded()
        if (usernameParser.isLoginRequiredPage(html, finalUrl)) {
            throw AO3InboxParseException.LoginRequired()
        }

        val document = Jsoup.parse(html, AO3Constants.BASE_URL)
        val itemElements = document.select("li[id^=feedback_comment_]")
        if (itemElements.isEmpty()) {
            val heading = document.selectFirst("h2.heading")?.text().orEmpty()
            val hasFilters = document.selectFirst("form#inbox-filters") != null
            if (!heading.contains("inbox", ignoreCase = true) && !hasFilters) {
                throw AO3InboxParseException.MissingRequiredStructure(
                    "AO3 Inbox markup was not recognized."
                )
            }
        }

        val parsed = itemElements.map { element ->
            runCatching { parseInboxItem(element) }.getOrNull()
        }
        if (itemElements.isNotEmpty() && parsed.all { it == null }) {
            throw AO3InboxParseException.MissingRequiredStructure(
                "AO3 Inbox items could not be parsed."
            )
        }
        val items = itemElements.mapIndexedNotNull { index, element ->
            parsed[index] ?: runCatching {
                parseUnavailableInboxItem(element, id = -(index + 1L))
            }.getOrNull()
        }

        val bulkForm = parseInboxBulkForm(document, items)
        val filterForm = parseInboxFilterForm(document)
        val totalPages = parseTotalPages(document, page.coerceAtLeast(1))

        var totalComments: Int? = null
        var unreadCount: Int? = null
        document.selectFirst("h2.heading")?.text()?.let { heading ->
            val numbers = integersIn(heading)
            if (numbers.size >= 2) {
                totalComments = numbers[0]
                unreadCount = numbers[1]
            }
        }

        return AO3InboxPage(
            items = items,
            currentPage = page.coerceAtLeast(1),
            totalPages = totalPages,
            totalComments = totalComments,
            unreadCount = unreadCount,
            bulkForm = bulkForm,
            filterForm = filterForm,
            pageUrl = finalUrl
        )
    }

    private fun parseInboxItem(li: Element): AO3InboxItem {
        val rawId = li.id().removePrefix("feedback_comment_")
        val id = rawId.toLongOrNull()
            ?: throw AO3InboxParseException.MissingRequiredStructure("Invalid feedback comment id.")

        val byline = li.selectFirst("h4.heading.byline")
            ?: return parseUnavailableInboxItem(li, id)

        var subjectTitle = ""
        var subjectUrl: String? = null
        var workId: Long? = null
        var commenterUsername: String? = null
        var commenterProfileUrl: String? = null
        var commenterName = ""

        for (link in byline.select("a")) {
            val href = link.attr("href")
            when {
                href.contains("/comments/") -> {
                    subjectTitle = link.text().trim()
                    subjectUrl = AO3CommentAvatar.absoluteAo3Url(href)
                    workId = workIdInPath(href)
                }
                href.contains("/users/") && commenterUsername == null && commenterProfileUrl == null -> {
                    val name = link.text().trim()
                    commenterName = name
                    commenterProfileUrl = AO3CommentAvatar.absoluteAo3Url(href)
                    commenterUsername = AO3CommentAvatar.usernameFromProfilePath(href)
                }
            }
        }

        var isGuest = false
        var isAnonymousCreator = false
        if (commenterUsername == null && commenterProfileUrl == null) {
            val role = byline.selectFirst("span.role")?.text().orEmpty()
            isGuest = role.contains("guest", ignoreCase = true)
            for (span in byline.select("span")) {
                val classNames = span.className()
                if (classNames.contains("role") ||
                    classNames.contains("status") ||
                    classNames.contains("datetime")
                ) {
                    continue
                }
                val text = span.text().trim()
                if (text.isNotEmpty()) {
                    commenterName = text
                    break
                }
            }
            if (commenterName.isEmpty()) {
                val full = byline.text()
                if (full.contains("anonymous creator", ignoreCase = true)) {
                    commenterName = "Anonymous Creator"
                    isAnonymousCreator = true
                }
            }
        }
        if (commenterName.isEmpty()) commenterName = "Unknown"

        val postedAgo = li.selectFirst("span.posted.datetime")?.text()?.trim().orEmpty()
        val excerpt = li.selectFirst("blockquote.userstuff")?.text()
            ?.replace(Regex("\\s+"), " ")
            ?.trim()
            .orEmpty()

        val iconSrc = li.selectFirst("div.icon img")?.attr("src")
        val avatarUrl = AO3CommentAvatar.avatarUrlForIconSource(iconSrc)

        val isUnread = li.hasClass("unread")
        val isReplied = li.selectFirst("ul.actions span.replied") != null
        val canReply = li.select("ul.actions a").any { link ->
            link.text().trim().equals("Reply", ignoreCase = true)
        }
        val bulkSelectionField = firstCheckboxField(li)

        return AO3InboxItem(
            id = id,
            commenterName = commenterName,
            isGuest = isGuest,
            isAnonymousCreator = isAnonymousCreator,
            commenterUsername = commenterUsername,
            commenterProfileUrl = commenterProfileUrl,
            avatarUrl = avatarUrl,
            subjectTitle = subjectTitle,
            subjectUrl = subjectUrl,
            workId = workId,
            excerpt = excerpt,
            postedAgo = postedAgo,
            isUnread = isUnread,
            isReplied = isReplied,
            canReply = canReply,
            bulkSelectionField = bulkSelectionField
        )
    }

    private fun parseUnavailableInboxItem(li: Element, id: Long): AO3InboxItem {
        return AO3InboxItem(
            id = id,
            commenterName = "Unavailable",
            subjectTitle = "",
            excerpt = "",
            postedAgo = "",
            isUnread = li.hasClass("unread"),
            isReplied = false,
            canReply = false,
            bulkSelectionField = firstCheckboxField(li),
            isUnavailable = true
        )
    }

    /**
     * Parse mass-edit form exactly as rendered. Partial/malformed → null so the
     * UI stays read-only instead of guessing a write request.
     */
    private fun parseInboxBulkForm(
        document: Document,
        items: List<AO3InboxItem>
    ): AO3InboxBulkForm? {
        val form = document.selectFirst("form#inbox-form") ?: return null
        val action = form.attr("action").trim()
        val actionUrl = AO3CommentAvatar.absoluteAo3Url(action) ?: return null
        val htmlMethod = form.attr("method").trim().lowercase()
        if (htmlMethod != "post") return null

        val hiddenFields = hiddenFields(form)
        val csrfToken = hiddenFields.firstOrNull { it.name == "authenticity_token" }?.value
            ?.takeIf { it.isNotEmpty() }
            ?: return null
        val checkboxFieldName = items.mapNotNull { it.bulkSelectionField?.name }
            .firstOrNull()
            ?.takeIf { it.isNotEmpty() }
            ?: return null

        val actionFields = linkedMapOf<AO3InboxBulkAction, AO3FormField>()
        for (input in form.select("input[type=submit][name][value]")) {
            val name = input.attr("name").trim()
            val value = input.attr("value").trim()
            if (name.isEmpty() || value.isEmpty()) continue
            val actionKind = when (value.lowercase()) {
                "mark read" -> AO3InboxBulkAction.MarkRead
                "mark unread" -> AO3InboxBulkAction.MarkUnread
                "delete from inbox" -> AO3InboxBulkAction.Delete
                else -> null
            }
            if (actionKind != null && actionKind !in actionFields) {
                actionFields[actionKind] = AO3FormField(name, value)
            }
        }
        // All three submit actions required — fewer means treat form as absent.
        if (!AO3InboxBulkAction.entries.all { it in actionFields }) return null

        return AO3InboxBulkForm(
            actionUrl = actionUrl,
            htmlMethod = htmlMethod,
            httpMethodOverride = hiddenFields.firstOrNull { it.name == "_method" }?.value,
            csrfToken = csrfToken,
            hiddenFields = hiddenFields,
            checkboxFieldName = checkboxFieldName,
            actionFields = actionFields
        )
    }

    private fun parseInboxFilterForm(document: Document): AO3InboxFilterForm? {
        val form = document.selectFirst("form#inbox-filters") ?: return null
        val action = form.attr("action").trim()
        val actionUrl = AO3CommentAvatar.absoluteAo3Url(action) ?: return null
        val method = form.attr("method").ifBlank { "get" }.trim().lowercase()
        if (method != "get") return null

        val names = ArrayList<String>()
        val inputsByName = linkedMapOf<String, MutableList<Element>>()
        for (input in form.select("input[type=radio][name][value]")) {
            val name = input.attr("name").trim()
            if (name.isEmpty()) continue
            if (name !in inputsByName) {
                names.add(name)
                inputsByName[name] = ArrayList()
            }
            inputsByName.getValue(name).add(input)
        }

        val fields = names.mapNotNull { name ->
            val inputs = inputsByName[name] ?: return@mapNotNull null
            val options = inputs.mapNotNull { input ->
                val value = input.attr("value").trim()
                if (value.isEmpty()) return@mapNotNull null
                val inputId = input.id()
                val label = if (inputId.isNotEmpty()) {
                    form.selectFirst("label[for=$inputId]")?.text()?.trim()?.takeIf { it.isNotEmpty() }
                        ?: value
                } else {
                    value
                }
                AO3InboxFilterOption(
                    value = value,
                    label = label,
                    isSelected = input.hasAttr("checked")
                )
            }
            if (options.isEmpty()) return@mapNotNull null
            AO3InboxFilterField(
                name = name,
                title = filterTitle(options),
                options = options
            )
        }
        if (fields.isEmpty()) return null

        return AO3InboxFilterForm(
            actionUrl = actionUrl,
            hiddenFields = hiddenFields(form),
            fields = fields
        )
    }

    private fun firstCheckboxField(li: Element): AO3FormField? {
        val checkbox = li.selectFirst("input[type=checkbox][name][value]") ?: return null
        val name = checkbox.attr("name").trim()
        val value = checkbox.attr("value").trim()
        if (name.isEmpty() || value.isEmpty()) return null
        return AO3FormField(name, value)
    }

    private fun hiddenFields(form: Element): List<AO3FormField> {
        return form.select("input[type=hidden][name]").mapNotNull { input ->
            val name = input.attr("name").trim()
            if (name.isEmpty()) return@mapNotNull null
            AO3FormField(name, input.attr("value"))
        }
    }

    private fun filterTitle(options: List<AO3InboxFilterOption>): String {
        val labels = options.map { it.label.lowercase() }
        if (labels.any { it.contains("newest first") || it.contains("oldest first") }) {
            return "Sort by Date"
        }
        if (labels.any { it.contains("without replies") || it.contains("replied") }) {
            return "Replied To"
        }
        if (labels.any { it.contains("unread") || it.contains("show read") }) {
            return "Read"
        }
        return "Filter"
    }

    private fun parseTotalPages(document: Document, currentPage: Int): Int {
        return document.select("ol.pagination li")
            .mapNotNull { it.text().replace(Regex("\\s+"), " ").trim().toIntOrNull() }
            .fold(currentPage) { total, page -> maxOf(total, page) }
    }

    private fun workIdInPath(path: String): Long? {
        val marker = "/works/"
        val start = path.indexOf(marker)
        if (start < 0) return null
        return path.substring(start + marker.length)
            .takeWhile(Char::isDigit)
            .toLongOrNull()
    }

    /** Every integer in the text, commas tolerated ("1,234"). */
    private fun integersIn(text: String): List<Int> {
        val results = ArrayList<Int>()
        val current = StringBuilder()
        for (character in text) {
            when {
                character.isDigit() -> current.append(character)
                character == ',' && current.isNotEmpty() -> Unit
                current.isNotEmpty() -> {
                    current.toString().toIntOrNull()?.let { results.add(it) }
                    current.clear()
                }
            }
        }
        if (current.isNotEmpty()) {
            current.toString().toIntOrNull()?.let { results.add(it) }
        }
        return results
    }

    companion object {
        fun inboxUrl(username: String, page: Int): String? {
            val name = username.trim()
            if (name.isEmpty()) return null
            val builder = AO3Constants.baseHttpUrl.newBuilder()
                .addPathSegment("users")
                .addPathSegment(name)
                .addPathSegment("inbox")
            if (page > 1) builder.addQueryParameter("page", page.toString())
            return builder.build().toString()
        }
    }
}
