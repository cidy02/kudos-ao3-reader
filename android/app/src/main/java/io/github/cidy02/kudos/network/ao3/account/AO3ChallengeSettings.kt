package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.network.ao3.AO3Constants
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.jsoup.Jsoup
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

data class AO3ChallengeSettings(
    val kind: AO3ChallengeKind,
    val dates: List<String>,
    val promptsPerSignup: String,
    val fandoms: String,
    val relationships: String,
    val characters: String,
    val optionalTags: Boolean,
    val allowAnyPrompt: Boolean,
    val requireFandomMatch: Boolean,
    val anonymous: Boolean
)

data class AO3ChallengeTagSet(val id: Int, val title: String)
data class AO3ChallengeSignUpCountPage(val count: Int, val totalPages: Int)
data class AO3ChallengeSettingsPage(
    val settings: AO3ChallengeSettings,
    val tagSets: List<AO3ChallengeTagSet>,
    /** null means an attempted sign-up read failed, never a fabricated zero. */
    val signUpTotal: Int?
)

/** AO3 addresses shared by native challenge readers and browser destinations. */
object ChallengeSettingsDestinations {
    fun challengeSettingsEditView(slug: String, kind: AO3ChallengeKind) =
        "${AO3CollectionFormUrls.show(slug)}/${kind.fieldPrefix}/edit"
    fun promptMemeView(slug: String) = "${AO3CollectionFormUrls.show(slug)}/requests"
    fun tagSetView(id: Int) = "${AO3Constants.BASE_URL}/tag_sets/$id"
    fun challengeSignUpsView(slug: String) = "${AO3CollectionFormUrls.show(slug)}/signups"
    fun challengeAssignmentsView(slug: String) = "${AO3CollectionFormUrls.show(slug)}/assignments"
    // iOS's own OS-browser escape hatch, not a placeholder native destination.
    fun runMatching(slug: String) = "${AO3CollectionFormUrls.show(slug)}/potential_matches"
    fun profile(slug: String) = "${AO3CollectionFormUrls.show(slug)}/profile"
    fun signUpPage(slug: String, page: Int = 1): String = challengeSignUpsView(slug).toHttpUrl()
        .newBuilder().apply { if (page > 1) addQueryParameter("page", page.toString()) }.build().toString()
}

/** Only the fields 1by displays. No form serializer, assignment parser or write path. */
class AO3ChallengeSettingsParser {
    fun parseSettings(html: String, kind: AO3ChallengeKind): AO3ChallengeSettings {
        val doc = Jsoup.parse(html)
        val prefix = kind.fieldPrefix
        val form = doc.selectFirst("form[action*='$prefix']") ?: doc.selectFirst("#main form")
            ?: error("Missing challenge form")
        val csrf = doc.selectFirst("meta[name=csrf-token]")?.attr("content")?.takeIf { it.isNotEmpty() }
            ?: form.selectFirst("input[name=authenticity_token]")?.attr("value").orEmpty()
        require(csrf.isNotEmpty()) { "Missing challenge form token" }
        fun input(name: String) = form.selectFirst("[name=\"$prefix[$name]\"]")?.attr("value").orEmpty()
        fun checked(name: String) = form.selectFirst("input[type=checkbox][name=\"$prefix[$name]\"]")?.hasAttr("checked") == true
        fun range(name: String, fallback: Int) = "${input("${name}_num_required").toIntOrNull() ?: fallback} to " +
            "${input("${name}_num_allowed").toIntOrNull() ?: fallback}"
        fun restriction(name: String) = "request_restriction_attributes][$name"
        return AO3ChallengeSettings(kind,
            listOf("signups_open_at", "signups_close_at", "assignments_due_at", "works_reveal_at", "authors_reveal_at")
                .map { key -> input("${key}_string").ifBlank { input(key) } },
            range("requests", 1), range(restriction("fandom"), 0), range(restriction("relationship"), 0),
            range(restriction("character"), 0), checked(restriction("optional_tags_allowed")),
            listOf("fandom", "relationship", "character", "freeform").any { checked(restriction("allow_any_$it")) },
            !checked(restriction("allow_any_fandom")), checked("anonymous"))
    }

    fun parseTagSets(html: String): List<AO3ChallengeTagSet> {
        val doc = Jsoup.parse(html)
        val seen = mutableSetOf<Int>()
        return doc.select("dt").filter { it.text().trim().lowercase().startsWith("tag set") }.flatMap { heading ->
            heading.nextElementSibling()?.takeIf { it.tagName() == "dd" }?.select("a[href*=/tag_sets/]")
                ?.mapNotNull { link ->
                    val id = Regex("/tag_sets/(\\d+)(?:/|$|[?#])").find(link.attr("href"))?.groupValues?.get(1)?.toIntOrNull()
                    if (id == null || !seen.add(id)) null else AO3ChallengeTagSet(id, link.text().trim().ifEmpty { "Tag set $id" })
                }.orEmpty()
        }
    }

    fun parseSignUpCount(html: String, page: Int = 1): AO3ChallengeSignUpCountPage {
        val doc = Jsoup.parse(html)
        val rows = doc.select("dl.index > dt.participant")
        rows.forEach { row ->
            val link = row.selectFirst("a[href*='/signups/']") ?: error("Missing sign-up link")
            require(Regex("/signups/\\d+(?:/|$|[?#])").containsMatchIn(link.attr("href"))) { "Missing sign-up id" }
            require(row.nextElementSibling()?.tagName() == "dd") { "Missing sign-up details" }
        }
        if (rows.isEmpty()) {
            val heading = doc.selectFirst("h2.heading")?.text().orEmpty().lowercase()
            require(heading.contains("sign") || heading.contains("challenge") || doc.selectFirst("p.note, p.message") != null) {
                "Unrecognized sign-ups page"
            }
        }
        val totalPages = doc.select("ol.pagination li").mapNotNull { it.text().trim().toIntOrNull() }.fold(page, ::maxOf)
        return AO3ChallengeSignUpCountPage(rows.size, totalPages)
    }
}

/** iOS formats wall-clock digits as an abbreviated date; no device-zone conversion. */
internal fun challengeDateText(raw: String, locale: Locale = Locale.getDefault()): String {
    val wire = raw.trim()
    if (wire.isEmpty()) return "Not set"
    val date = runCatching { OffsetDateTime.parse(wire).withOffsetSameInstant(ZoneOffset.UTC).toLocalDate() }.getOrNull()
        ?: runCatching {
            val candidate = wire.removeSuffix(" UTC").removeSuffix(" gmt").removeSuffix("Z").replace('T', ' ')
            require(Regex("\\d{4}-\\d{2}-\\d{2}(?: \\d{2}:\\d{2}(?::\\d{2})?)?").matches(candidate))
            // Validate the time too, before dropping it as iOS does for display.
            if (candidate.length > 10) java.time.LocalDateTime.parse(candidate.replace(' ', 'T'))
            LocalDate.parse(candidate.take(10))
        }.getOrNull()
    return date?.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale)) ?: wire
}
