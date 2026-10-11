package io.github.cidy02.kudos.network.ao3.preferences

/** iOS `AO3PreferenceHelpRef`: the "?" beside a preferences heading or field. */
data class AO3PreferenceHelpRef(val title: String, val url: String)

/** One topic of an AO3 help page: a `dt` and its `dd`s. */
data class AO3PreferenceHelpEntry(val heading: String, val body: String)

/** iOS `AO3PreferenceHelpContent`: an AO3 `/help/…` page as the sheet shows it. */
data class AO3PreferenceHelpContent(
    val title: String,
    val entries: List<AO3PreferenceHelpEntry>,
    /** The note under the list (the Preferences FAQ line), when there is one. */
    val footer: String?,
    val sourceUrl: String
)

data class AO3PreferenceToggle(
    val name: String,
    val label: String,
    val checked: Boolean,
    val help: AO3PreferenceHelpRef? = null
) {
    val helpUrl: String? get() = help?.url
}

data class AO3PreferenceSection(
    val title: String,
    val toggles: List<AO3PreferenceToggle>,
    /** The "?" on the section's own heading: where AO3 puts most of its help. */
    val help: AO3PreferenceHelpRef? = null
)

data class AO3PreferenceSelect(
    val name: String,
    val label: String,
    val options: List<Pair<String, String>>,
    val selectedValue: String,
    val help: AO3PreferenceHelpRef? = null
)

data class AO3PreferenceTextField(
    val name: String,
    val label: String,
    val value: String,
    val help: AO3PreferenceHelpRef? = null
)

data class AO3PreferencesSnapshot(
    val actionUrl: String,
    val httpMethodOverride: String?,
    val csrfToken: String,
    val sections: List<AO3PreferenceSection>,
    val selects: List<AO3PreferenceSelect>,
    val textFields: List<AO3PreferenceTextField>,
    val hiddenFields: List<Pair<String, String>>
)
