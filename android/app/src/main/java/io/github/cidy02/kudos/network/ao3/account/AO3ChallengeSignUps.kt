package io.github.cidy02.kudos.network.ao3.account

import okhttp3.HttpUrl.Companion.toHttpUrl
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

/** Read-only inline prompts; deliberately separate from successful form controls. */
data class AO3SignUpReadPrompt(
    val tags: Map<SignUpTagType, List<String>>, val any: Set<SignUpTagType>,
    val optionalTags: List<String>, val text: String
)
data class AO3ListedSignUp(val id: Int, val pseud: String,
    val requests: List<AO3SignUpReadPrompt>, val offers: List<AO3SignUpReadPrompt>) {
    val requestTagSummary get() = requests.flatMap {
        it.tags[SignUpTagType.Fandom].orEmpty() + if (SignUpTagType.Fandom in it.any) listOf("Any Fandom") else emptyList()
    }.distinct().joinToString(", ")
}
data class AO3SignUpsPage(val rows: List<AO3ListedSignUp>, val currentPage: Int, val totalPages: Int)
/** Only the recipient and giver evidence the list joins; no assignment management. */
data class AO3SignUpAssignment(val requestID: Int?, val recipient: String, val giver: String, val defaulted: Boolean)
enum class SignUpMatch { Matched, Unmatched, Unknown }
enum class SignUpFilter(val label: String) { All("All"), Matched("Matched"), Unmatched("Unmatched") }
enum class SignUpAssignmentList(val query: String?) { Complete("fulfilled"), Open("unfulfilled"), Defaults(null) }

object AO3ChallengeSignUpsUrls {
    fun page(slug: String, page: Int = 1) = ChallengeSettingsDestinations.signUpPage(slug, page)
    fun assignments(slug: String, list: SignUpAssignmentList) =
        ChallengeSettingsDestinations.challengeAssignmentsView(slug).toHttpUrl().newBuilder().apply {
            list.query?.let { addQueryParameter(it, "true") }
        }.build().toString()
}

fun signUpMatch(row: AO3ListedSignUp, assignments: List<AO3SignUpAssignment>?): SignUpMatch {
    if (assignments.isNullOrEmpty()) return SignUpMatch.Unknown
    // Swift's dictionary keeps the last ID match and the first byline match.
    val joined = assignments.lastOrNull { it.requestID == row.id }
        ?: assignments.firstOrNull { it.recipient.equals(row.pseud, true) && it.recipient.isNotEmpty() }
    return if (joined != null && joined.giver.isNotEmpty() && !joined.defaulted) SignUpMatch.Matched else SignUpMatch.Unmatched
}
fun ownListedSignUpID(rows: List<AO3ListedSignUp>, login: String): Int? {
    val name = login.trim()
    if (name.isEmpty()) return null
    return rows.firstOrNull { it.pseud.trim().equals(name, true) || it.pseud.trim().endsWith("($name)", true) }?.id
}
fun signUpCount(size: Int, noun: String) = "$size $noun${if (size == 1) "" else "s"}"
fun signUpPromptCount(row: AO3ListedSignUp) = signUpCount(row.requests.size, "request") + " · " + signUpCount(row.offers.size, "offer")

class AO3ChallengeSignUpsParser {
    private fun resourceID(link: Element?, resource: String) = link?.attr("href")?.let {
        Regex("/$resource/(\\d+)(?:/|$|[?#])").find(it)?.groupValues?.get(1)?.toIntOrNull()
    }
    fun parse(html: String, page: Int = 1): AO3SignUpsPage {
        // Share the existing index validation and pagination with Challenge Settings.
        val count = AO3ChallengeSettingsParser().parseSignUpCount(html, page)
        val doc = Jsoup.parse(html)
        val rows = doc.select("dl.index > dt.participant").map { heading ->
            val link = heading.selectFirst("a[href*='/signups/']") ?: error("Missing sign-up link")
            val id = resourceID(link, "signups") ?: error("Missing sign-up id")
            val details = heading.nextElementSibling() ?: error("Missing sign-up details")
            AO3ListedSignUp(id, link.text().trim(), prompts(details, "requests"), prompts(details, "offers"))
        }
        return AO3SignUpsPage(rows, page, count.totalPages)
    }
    private fun prompts(details: Element, list: String) = details.select("div[id^=${list}_] ol.prompt > li.blurb").map { li ->
        val chosen = "ul.tags:not(.optional)"
        fun tags(selector: String) = li.select(selector).map { it.text() }
        val any = tags("$chosen li.tag").map { it.lowercase() }
        AO3SignUpReadPrompt(mapOf(
            SignUpTagType.Fandom to tags("h5.fandoms a.tag"),
            SignUpTagType.Relationship to tags("$chosen li.relationships a.tag"),
            SignUpTagType.Character to tags("$chosen li.characters a.tag"),
            SignUpTagType.Freeform to tags("$chosen li.freeforms a.tag")),
            SignUpTagType.entries.filter { type -> any.any { label -> when (type) {
                SignUpTagType.Fandom -> label.contains("fandom")
                SignUpTagType.Relationship -> label.contains("relationship")
                SignUpTagType.Character -> label.contains("character")
                SignUpTagType.Freeform -> label.contains("additional") || label.contains("freeform")
            } } }.toSet(), tags("ul.optional.tags a.tag"), li.select("blockquote.userstuff.summary").text())
    }
    fun parseAssignments(html: String): List<AO3SignUpAssignment> {
        val doc = Jsoup.parse(html)
        val rows = doc.select("dl.index > dt").map { heading ->
            val details = heading.nextElementSibling()?.takeIf { it.tagName() == "dd" } ?: error("Missing assignment details")
            val assignment = details.selectFirst("a[href*='/assignments/']")
            val control = details.select("input[name]").firstNotNullOfOrNull { input ->
                listOf("default_", "undefault_", "approve_", "cover_").firstNotNullOfOrNull { prefix ->
                    input.attr("name").takeIf { it.startsWith(prefix) }?.removePrefix(prefix)?.toIntOrNull()
                }
            }
            require(resourceID(assignment, "assignments") != null || control != null) { "Missing assignment id" }
            val signup = heading.selectFirst("a[href*='/signups/']") ?: details.selectFirst("a[href*='/signups/']")
            val defaulted = details.selectFirst("input[name^=undefault_]") != null
            val giver = if (defaulted) details.selectFirst("label[for^=undefault_]")?.ownText().orEmpty().removePrefix("Undefault ")
                else heading.ownText().trim().removeSuffix("* (pinch hitter)")
            AO3SignUpAssignment(resourceID(signup, "signups"), (signup ?: assignment)?.text().orEmpty(), giver.trim(), defaulted)
        }
        if (rows.isEmpty()) require(doc.select("h2.heading").text().contains("assignments", true) &&
            doc.select("p.note").text().contains("No assignments", true)) { "Unrecognized assignments page" }
        return rows
    }
}
