package io.github.cidy02.kudos.network.ao3.account

import org.jsoup.Jsoup

enum class AO3CollectionParticipantRole(val title: String) {
    None("None"), Owner("Owner"), Moderator("Moderator"), Member("Member"), Invited("Invited")
}

data class AO3CollectionParticipant(
    val id: Int,
    val pseud: String,
    val role: AO3CollectionParticipantRole
)

object AO3CollectionParticipantsUrls {
    fun page(slug: String) = "${AO3CollectionFormUrls.show(slug)}/participants"
    fun add(slug: String) = "${page(slug)}/add"
    fun participant(slug: String, id: Int) = "${page(slug)}/$id"
}

/** iOS parseCollectionParticipants/parseParticipant; these are remote values, never Room records. */
class AO3CollectionParticipantsParser {
    fun parse(html: String): List<AO3CollectionParticipant> {
        val doc = Jsoup.parse(html)
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
            AO3CollectionParticipant(id, pseud, role)
        }
    }
}
