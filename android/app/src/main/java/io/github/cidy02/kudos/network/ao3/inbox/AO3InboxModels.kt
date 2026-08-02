package io.github.cidy02.kudos.network.ao3.inbox

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentParticipantRole
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** Exact name/value pair scraped from an AO3 form control. Never invent these. */
data class AO3FormField(
    val name: String,
    val value: String
)

/**
 * One AO3 Inbox notification (a comment on the user's work, or a reply to one
 * they posted). Flatter than a full comment thread by design.
 *
 * Port of iOS `AO3InboxItem` (AO3InboxModels.swift).
 */
data class AO3InboxItem(
    /** AO3 feedback-comment id from `li#feedback_comment_<id>`. */
    val id: Long,
    val commenterName: String,
    val isGuest: Boolean = false,
    val isAnonymousCreator: Boolean = false,
    /** Registered commenter's display name + profile path/username when known. */
    val commenterUsername: String? = null,
    val commenterProfileUrl: String? = null,
    val avatarUrl: String? = null,
    /** AO3's own label, e.g. "Work Title" or "Chapter 3 of Work Title". */
    val subjectTitle: String,
    val subjectUrl: String? = null,
    /** Parsed from subject URL's `/works/<id>/` segment when present. */
    val workId: Long? = null,
    val excerpt: String,
    /** AO3's relative-time text as rendered ("3 days ago"). */
    val postedAgo: String,
    val isUnread: Boolean,
    val isReplied: Boolean,
    val canReply: Boolean,
    /**
     * Exact checkbox name+value AO3 rendered for this row. Its value is the
     * InboxComment record id (distinct from [id] on real pages).
     */
    val bulkSelectionField: AO3FormField? = null,
    /**
     * Admin-hidden/unavailable tombstone: real `li` with an id (and often a
     * checkbox) but no byline/subject/excerpt.
     */
    val isUnavailable: Boolean = false
) {
    /**
     * Strictly parsed from AO3's "Chapter N of Work" label. Presentation only —
     * no chapter *id* is available on the Inbox page itself.
     */
    val chapterPosition: Int?
        get() {
            if (!subjectTitle.startsWith("Chapter ")) return null
            val separator = subjectTitle.indexOf(" of ")
            if (separator < 0) return null
            return subjectTitle.substring("Chapter ".length, separator).toIntOrNull()
        }

    val chapterIndicatorTitle: String?
        get() = chapterPosition?.let { "Chapter $it" }

    val workTitle: String
        get() {
            if (chapterPosition == null) return subjectTitle
            val separator = subjectTitle.indexOf(" of ")
            if (separator < 0) return subjectTitle
            return subjectTitle.substring(separator + " of ".length)
        }

    fun participantRole(
        workAuthors: List<String>,
        workAuthorUsernames: List<String> = emptyList(),
        currentUsername: String? = null
    ): AO3CommentParticipantRole {
        return AO3CommentParticipantRole.resolve(
            name = commenterName,
            isGuest = isGuest,
            isAnonymousCreator = isAnonymousCreator,
            commenterUsername = commenterUsername,
            currentUsername = currentUsername,
            workAuthors = workAuthors,
            workAuthorUsernames = workAuthorUsernames
        )
    }
}

/**
 * One of AO3's own inbox mass-edit submit buttons. Field name/value come from
 * the scraped form; this enum only gives the native UI stable intent.
 */
enum class AO3InboxBulkAction(
    val label: String,
    val successMessage: String
) {
    MarkRead("Mark Read", "Marked as read."),
    MarkUnread("Mark Unread", "Marked as unread."),
    Delete("Delete From Inbox", "Removed from your AO3 inbox.")
}

/**
 * AO3's `form#inbox-form`, parsed rather than reconstructed.
 * [parameters] returns null — never a partial body — unless every selected
 * item's checkbox name matches [checkboxFieldName] and the action has a
 * resolved submit field.
 */
data class AO3InboxBulkForm(
    val actionUrl: String,
    val htmlMethod: String,
    val httpMethodOverride: String?,
    val csrfToken: String,
    val hiddenFields: List<AO3FormField>,
    val checkboxFieldName: String,
    val actionFields: Map<AO3InboxBulkAction, AO3FormField>
) {
    fun parameters(
        items: List<AO3InboxItem>,
        action: AO3InboxBulkAction
    ): List<Pair<String, String>>? {
        val actionField = actionFields[action] ?: return null
        if (items.isEmpty()) return null
        val selections = items.mapNotNull { it.bulkSelectionField }
        if (selections.size != items.size) return null
        if (selections.any { it.name != checkboxFieldName }) return null

        val fields = ArrayList<Pair<String, String>>(hiddenFields.size + selections.size + 2)
        if (hiddenFields.none { it.name == "authenticity_token" }) {
            fields.add("authenticity_token" to csrfToken)
        }
        hiddenFields.forEach { fields.add(it.name to it.value) }
        selections.forEach { fields.add(it.name to it.value) }
        fields.add(actionField.name to actionField.value)
        return fields
    }
}

data class AO3InboxFilterOption(
    val value: String,
    val label: String,
    val isSelected: Boolean
)

data class AO3InboxFilterField(
    val name: String,
    val title: String,
    val options: List<AO3InboxFilterOption>
) {
    val selectedValue: String?
        get() = options.firstOrNull { it.isSelected }?.value
            ?: options.firstOrNull()?.value
}

/**
 * AO3's GET filter form. Field names and allowed values are scraped from the
 * page so a markup change fails closed instead of inventing query params.
 */
data class AO3InboxFilterForm(
    val actionUrl: String,
    val hiddenFields: List<AO3FormField>,
    val fields: List<AO3InboxFilterField>
) {
    val selectedValues: Map<String, String>
        get() = fields.mapNotNull { field ->
            field.selectedValue?.let { field.name to it }
        }.toMap()

    /**
     * Builds AO3's own GET URL for the selected filters and requested page.
     * Page 1 omits `page`, matching the archive's paginator URLs.
     */
    fun url(values: Map<String, String>, page: Int): String? {
        val action = actionUrl.toHttpUrlOrNull()
            ?: (AO3Constants.BASE_URL + actionUrl).toHttpUrlOrNull()
            ?: return null
        val fieldNames = fields.map { it.name }.toSet()
        val removedNames = fieldNames + "page"

        val builder = action.newBuilder().query(null)
        for (i in 0 until action.querySize) {
            val name = action.queryParameterName(i)
            if (name !in removedNames) {
                builder.addQueryParameter(name, action.queryParameterValue(i))
            }
        }
        for (hidden in hiddenFields) {
            if (hidden.name == "page") continue
            builder.addQueryParameter(hidden.name, hidden.value)
        }
        for (field in fields) {
            val value = values[field.name] ?: field.selectedValue ?: continue
            builder.addQueryParameter(field.name, value)
        }
        if (page > 1) {
            builder.addQueryParameter("page", page.toString())
        }
        return builder.build().toString()
    }
}

/**
 * One page of the AO3 Inbox, plus the totals AO3 prints in the heading when
 * readable ("My Inbox (12 comments, 3 unread)").
 */
data class AO3InboxPage(
    val items: List<AO3InboxItem>,
    val currentPage: Int,
    val totalPages: Int,
    val totalComments: Int? = null,
    val unreadCount: Int? = null,
    /** null when the bulk form is incomplete — native writes stay unavailable. */
    val bulkForm: AO3InboxBulkForm? = null,
    /** null when the filter form cannot be parsed without guessing. */
    val filterForm: AO3InboxFilterForm? = null,
    /** Absolute page URL this HTML was loaded from (used as bulk-action Referer). */
    val pageUrl: String? = null
)
