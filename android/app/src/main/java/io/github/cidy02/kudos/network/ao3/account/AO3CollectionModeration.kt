package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import org.jsoup.Jsoup

data class AO3CollectionParticipant(val id: Int, val pseud: String, val role: String) {
    val isMembershipRequest get() = role.equals("None", true)
    val isMaintainer get() = role.equals("Owner", true) || role.equals("Moderator", true)
}

data class AO3CollectionModeration(
    val queue: AO3CollectionItemsPage,
    val requests: List<AO3CollectionParticipant>,
    val maintainerCount: Int,
    val unrevealed: Boolean,
    val anonymous: Boolean
)

object AO3CollectionModerationUrls {
    fun participants(slug: String) = AO3CollectionParticipantsUrls.page(slug)
    fun participant(slug: String, id: Int) = AO3CollectionParticipantsUrls.participant(slug, id)
}

/** iOS parseCollectionParticipants/parseParticipant; these are remote values, never Room records. */
class AO3CollectionParticipantsParser {
    fun parse(html: String): List<AO3CollectionParticipant> {
        require(!AO3OverloadDetector.isOverloadPage(html)) { "AO3 is busy. Try again shortly." }
        val doc = Jsoup.parse(html)
        require(doc.selectFirst("form#new_user, form[action='/users/login']") == null) { "Log in to AO3 first." }
        return doc.select("ul.participant.index li, li[id^=participant_]").mapNotNull { li ->
            val id = li.id().takeIf { it.startsWith("participant_") }?.replace("participant_", "")?.toIntOrNull()?.takeIf { it != 0 }
                ?: li.selectFirst("form")?.attr("action")?.let {
                    val parts = it.split('/').filter(String::isNotEmpty)
                    val index = parts.indexOf("participants")
                    if (index < 0) null else parts.getOrNull(index + 1)?.substringBefore('?')?.toIntOrNull()
                }?.takeIf { it != 0 } ?: return@mapNotNull null
            val pseud = li.selectFirst("span.byline a, a[href*='/users/']")?.text()?.trim().orEmpty()
            fun selected(suffix: Boolean): String {
                val field = li.select("select").firstOrNull {
                    if (suffix) it.attr("name").endsWith("[participant_role]")
                    else it.attr("name") == "collection_participant[participant_role]"
                } ?: return ""
                return (field.selectFirst("option[selected]") ?: field.selectFirst("option"))?.attr("value").orEmpty()
            }
            val roleText = selected(false).ifBlank { selected(true) }.trim()
            val role = AO3CollectionParticipantRole.entries.firstOrNull { it.title.equals(roleText, true) }
                ?: AO3CollectionParticipantRole.Member
            AO3CollectionParticipant(id, pseud, role.title)
        }
    }
}
