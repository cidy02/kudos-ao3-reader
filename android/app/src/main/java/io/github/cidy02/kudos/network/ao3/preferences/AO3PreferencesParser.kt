package io.github.cidy02.kudos.network.ao3.preferences

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.writes.normalizedText
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

class AO3PreferencesParseException(message: String) : Exception(message)

/**
 * Parses AO3 `/users/:login/preferences` form HTML.
 * Port of iOS `AO3Client.parsePreferencesForm`.
 */
class AO3PreferencesParser {
    fun parse(html: String): AO3PreferencesSnapshot {
        val doc = Jsoup.parse(html, AO3Constants.BASE_URL)
        val form = doc.selectFirst("form[action*=preference]")
            ?: doc.selectFirst("#main form")
            ?: throw AO3PreferencesParseException("Preferences form not found.")
        val actionRaw = form.attr("action").trim()
        val actionUrl = absoluteUrl(actionRaw)
            ?: throw AO3PreferencesParseException("Preferences form action missing.")
        val csrf = form.selectFirst("input[name=authenticity_token]")?.attr("value")?.trim()
            ?: doc.selectFirst("meta[name=csrf-token]")?.attr("content")?.trim()
            ?: throw AO3PreferencesParseException("CSRF token missing.")
        val methodOverride = form.selectFirst("input[name=_method]")?.attr("value")?.trim()

        val sections = mutableListOf<AO3PreferenceSection>()
        for (fieldset in form.select("fieldset")) {
            val heading = fieldset.selectFirst("h4.heading")?.normalizedText()
                ?: fieldset.selectFirst("legend")?.normalizedText()
                ?: "Preferences"
            val toggles = parseToggles(fieldset)
            if (toggles.isNotEmpty()) {
                val existing = sections.indexOfFirst { it.title.equals(heading, true) }
                if (existing >= 0) {
                    sections[existing] = sections[existing].copy(
                        toggles = sections[existing].toggles + toggles
                    )
                } else {
                    sections += AO3PreferenceSection(title = heading, toggles = toggles)
                }
            }
        }
        if (sections.isEmpty()) {
            val all = parseToggles(form)
            if (all.isNotEmpty()) {
                sections += AO3PreferenceSection(title = "Preferences", toggles = all)
            }
        }

        val selects = form.select("select[name]").mapNotNull { select ->
            val name = select.attr("name")
            if (name.isBlank() || name == "authenticity_token") return@mapNotNull null
            val label = findLabel(form, name) ?: name
            val options = select.select("option").map {
                it.attr("value") to it.normalizedText()
            }
            val selected = select.selectFirst("option[selected]")?.attr("value")
                ?: options.firstOrNull()?.first.orEmpty()
            AO3PreferenceSelect(name, label, options, selected)
        }

        val textFields = form.select("input[type=text][name], input[type=number][name], textarea[name]")
            .mapNotNull { input ->
                val name = input.attr("name")
                if (name.isBlank()) return@mapNotNull null
                val label = findLabel(form, name) ?: name
                val value = if (input.tagName() == "textarea") {
                    input.text()
                } else {
                    input.attr("value")
                }
                AO3PreferenceTextField(name, label, value)
            }

        val hidden = form.select("input[type=hidden][name]").map {
            it.attr("name") to it.attr("value")
        }.filter { it.first != "authenticity_token" && it.first != "_method" }

        if (sections.isEmpty() && selects.isEmpty() && textFields.isEmpty()) {
            throw AO3PreferencesParseException("No preference fields found.")
        }

        return AO3PreferencesSnapshot(
            actionUrl = actionUrl,
            httpMethodOverride = methodOverride,
            csrfToken = csrf,
            sections = sections,
            selects = selects,
            textFields = textFields,
            hiddenFields = hidden
        )
    }

    private fun parseToggles(root: Element): List<AO3PreferenceToggle> {
        return root.select("input[type=checkbox][name]").mapNotNull { input ->
            val name = input.attr("name")
            if (name.isBlank()) return@mapNotNull null
            val label = findLabel(root, name)
                ?: input.parent()?.normalizedText()?.takeIf { it.isNotBlank() }
                ?: name
            AO3PreferenceToggle(
                name = name,
                label = label,
                checked = input.hasAttr("checked")
            )
        }
    }

    private fun findLabel(root: Element, name: String): String? {
        val byFor = root.selectFirst("label[for=$name]")?.normalizedText()
        if (!byFor.isNullOrBlank()) return byFor
        val input = root.selectFirst("input[name=\"$name\"], select[name=\"$name\"], textarea[name=\"$name\"]")
            ?: return null
        val parentLabel = input.parents().firstOrNull { it.tagName() == "label" }
            ?.normalizedText()
        return parentLabel?.takeIf { it.isNotBlank() }
    }

    private fun absoluteUrl(href: String): String? {
        val raw = href.trim()
        if (raw.isEmpty()) return null
        if (raw.startsWith("http")) return raw
        return AO3Constants.baseHttpUrl.resolve(raw)?.toString()
    }
}
