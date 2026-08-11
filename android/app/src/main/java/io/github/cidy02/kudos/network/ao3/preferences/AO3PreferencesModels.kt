package io.github.cidy02.kudos.network.ao3.preferences

data class AO3PreferenceToggle(
    val name: String,
    val label: String,
    val checked: Boolean,
    val helpUrl: String? = null
)

data class AO3PreferenceSection(
    val title: String,
    val toggles: List<AO3PreferenceToggle>
)

data class AO3PreferenceSelect(
    val name: String,
    val label: String,
    val options: List<Pair<String, String>>,
    val selectedValue: String
)

data class AO3PreferenceTextField(
    val name: String,
    val label: String,
    val value: String
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
