package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.network.ao3.AO3RedirectCookieRelay
import io.github.cidy02.kudos.network.ao3.writing.AO3ServedControl
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkFormParser
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import org.jsoup.Jsoup
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneOffset

/** The opening's browser controls, plus only the moderator's edits. Never persisted. */
data class AO3ChallengeSettingsForm(
    val slug: String, val kind: AO3ChallengeKind, val actionUrl: String, val token: String,
    val controls: List<AO3ServedControl>, val changes: Map<String, String> = emptyMap(),
    val generalErrors: List<String> = emptyList(), val fieldErrors: Map<String, String> = emptyMap()
) {
    fun field(key: String) = "${kind.fieldPrefix}[$key]"
    fun control(name: String) = controls.lastOrNull { it.name == name && it.type != "hidden" }
    operator fun get(name: String): String = changes[name] ?: control(name)?.let {
        if (it.type == "checkbox") if (it.browserChecked) "1" else "0" else it.values.lastOrNull().orEmpty()
    } ?: controls.lastOrNull { it.name == name }?.values?.lastOrNull().orEmpty()
    fun value(key: String) = this[field(key)]
    val scheduleIsEditable get() = value("time_zone").isNotEmpty()
    val isValid get() = generalErrors.isEmpty() && fieldErrors.isEmpty()
    fun dateField(key: String) = listOf(field("${key}_string"), field(key)).firstOrNull { control(it) != null }
    fun editable(name: String): Boolean {
        val control = control(name) ?: return false
        if (control.disabled || "readonly" in control.attributes) return false
        if (challengeDateKeys.any { name == dateField(it) }) {
            return scheduleIsEditable && (this[name].isEmpty() || challengeWallClock(this[name]) != null || name in changes)
        }
        return true
    }
    fun changed(name: String, value: String): AO3ChallengeSettingsForm {
        if (!editable(name)) return this
        val control = control(name) ?: return this
        if (control.tag == "select" && control.options.none { !it.disabled && it.value == value }) return this
        return copy(changes = changes + (name to value), generalErrors = emptyList(), fieldErrors = emptyMap())
    }

    fun accepted() = copy(controls = controls.mapIndexed { index, served ->
        val changed = changes[served.name].takeIf { index == controls.indexOfLast { it.name == served.name && it.type != "hidden" } }
        when {
            served.name == "authenticity_token" -> served.copy(values = listOf(token))
            changed == null || served.type == "hidden" -> served
            served.type == "checkbox" -> served.copy(browserChecked = changed == "1")
            else -> served.copy(values = listOf(changed))
        }
    }, changes = emptyMap(), fieldErrors = emptyMap(), generalErrors = emptyList())

    /** Untouched controls keep whitespace, twins, repeated names, unknowns and disabled state. */
    fun parameters(): List<Pair<String, String>> {
        val submitter = controls.indexOfFirst { !it.disabled && it.type == "submit" && it.tag in setOf("input", "button") }
        return buildList {
            controls.forEachIndexed { index, served ->
                val changed = changes[served.name].takeIf { index == controls.indexOfLast { it.name == served.name && it.type != "hidden" } }
                val control = if (changed == null || served.type == "hidden") served else when (served.type) {
                    "checkbox" -> served.copy(browserChecked = changed == "1")
                    else -> served.copy(values = listOf(changed))
                }
                val submit = if (index == submitter) control.name else null
                if (control.type == "submit" && index != submitter) return@forEachIndexed
                control.successfulValues(submit).forEach { value ->
                    add(control.name to if (control.name == "authenticity_token") token else value)
                }
            }
            if (none { it.first == "authenticity_token" }) add("authenticity_token" to token)
        }
    }

    fun validated(): AO3ChallengeSettingsForm {
        val errors = linkedMapOf<String, String>()
        val dates = challengeDateKeys.map { key -> dateField(key)?.let { challengeWallClock(this[it]) } }
        challengeDateKeys.forEachIndexed { index, key ->
            val name = dateField(key)
            if (name != null && name in changes && this[name].isNotBlank() && dates[index] == null)
                errors[name] = "Enter the date in the format shown on AO3."
            if (index > 0 && dates[index] != null && dates[index - 1] != null && dates[index]!! < dates[index - 1]!!)
                errors[name ?: field("${key}_string")] = "This date is before the previous deadline."
        }
        for (noun in if (kind == AO3ChallengeKind.GiftExchange) listOf("requests", "offers") else listOf("requests")) {
            val required = value("${noun}_num_required").toIntOrNull() ?: 1
            val allowed = value("${noun}_num_allowed").toIntOrNull() ?: 1
            val singular = noun.dropLast(1)
            if (required < 1) errors[field("${noun}_num_required")] = "At least one $singular is required."
            if (required > allowed) errors[field("${noun}_num_allowed")] =
                "Allowed $noun cannot be fewer than required $noun."
        }
        return copy(fieldErrors = errors, generalErrors = emptyList())
    }
}

internal val challengeDateKeys = listOf("signups_open_at", "signups_close_at", "assignments_due_at", "works_reveal_at", "authors_reveal_at")
internal val challengeMatchTypes = listOf("fandoms", "characters", "relationships", "freeforms", "categories", "ratings", "archive_warnings")
internal fun challengeMatchLabel(type: String) = when (type) {
    "freeforms" -> "Additional tags"
    "archive_warnings" -> "Warnings"
    else -> type.replaceFirstChar(Char::uppercase)
}

/** Swift's UTC container represents the served digits, independent of the device zone. */
internal fun challengeWallClock(raw: String): LocalDateTime? = runCatching {
    OffsetDateTime.parse(raw.trim()).withOffsetSameInstant(ZoneOffset.UTC).toLocalDateTime()
}.getOrNull() ?: runCatching {
    val text = raw.trim().removeSuffix(" UTC").removeSuffix(" gmt").removeSuffix("Z").replace(' ', 'T')
    if (text.length == 10) java.time.LocalDate.parse(text).atStartOfDay() else LocalDateTime.parse(text)
}.getOrNull()

data class AO3ChallengeSettingsEditPage(
    val form: AO3ChallengeSettingsForm, val collection: AO3ChallengeSettingsForm?,
    val tagSets: List<AO3ChallengeTagSet>, val signUpTotal: Int?
)

sealed interface AO3ChallengeSettingsSaveOutcome {
    data class Saved(val form: AO3ChallengeSettingsForm, val message: String) : AO3ChallengeSettingsSaveOutcome
    data class Invalid(val form: AO3ChallengeSettingsForm) : AO3ChallengeSettingsSaveOutcome
}

class AO3ChallengeSettingsFormParser {
    fun parse(html: String, slug: String, kind: AO3ChallengeKind, collection: Boolean = false): AO3ChallengeSettingsForm {
        val referer = if (collection) AO3CollectionFormUrls.form(slug) else ChallengeSettingsDestinations.challengeSettingsEditView(slug, kind)
        val doc = Jsoup.parse(html, referer)
        val form = doc.selectFirst(if (collection) "form[action*='/collections']" else "form[action*='/${kind.fieldPrefix}']")
            ?: doc.selectFirst("#main form")?.takeIf { candidate ->
                candidate.select("[name]").any { it.attr("name").startsWith(if (collection) "collection[" else "${kind.fieldPrefix}[") }
            } ?: error("Couldn't read AO3's challenge form.")
        val expected = if (collection) AO3CollectionFormUrls.show(slug) else "${AO3CollectionFormUrls.show(slug)}/${kind.fieldPrefix}"
        val action = form.attr("abs:action").ifEmpty { expected }
        require(AO3RedirectCookieRelay.isTrustedUrl(action) && action.trimEnd('/') == expected && form.attr("method").equals("post", true)) {
            "Couldn't read AO3's challenge form."
        }
        val controls = AO3WorkFormParser().servedControls(doc, form)
        val token = AO3WriteFormParser().parseAuthenticityToken(html, metaOnly = true)
            ?: controls.firstOrNull { it.name == "authenticity_token" }?.values?.firstOrNull()?.takeIf(String::isNotEmpty)
            ?: error("Couldn't read AO3's challenge form.")
        val general = doc.select("#error ul li, .error ul li, #errorExplanation li").map { it.text() }.filter(String::isNotBlank).distinct()
        val errors = doc.select(".field_with_errors [name], .fieldWithErrors [name]").associate {
            it.attr("name") to (general.firstOrNull() ?: "Invalid")
        }
        return AO3ChallengeSettingsForm(slug, kind, action, token, controls, generalErrors = general, fieldErrors = errors)
    }
}
