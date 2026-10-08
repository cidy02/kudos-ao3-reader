package io.github.cidy02.kudos.network.ao3.preferences

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorUrls
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AO3PreferencesRepository(
    private val client: AO3AuthenticatedClient,
    private val parser: AO3PreferencesParser = AO3PreferencesParser()
) {
    suspend fun load(username: String): AO3Result<AO3PreferencesSnapshot> {
        val url = AO3AuthorUrls.preferencesUrl(username)
            ?: return AO3Result.Failure(AO3Error.Validation("Not signed in."))
        return when (val page = client.getAuthenticated(url)) {
            is AO3Result.Failure -> page
            is AO3Result.Success -> {
                try {
                    AO3Result.Success(
                        withContext(Dispatchers.Default) { parser.parse(page.value.body) }
                    )
                } catch (e: AO3PreferencesParseException) {
                    AO3Result.Failure(AO3Error.Parse(e.message ?: "Preferences parse failed."))
                }
            }
        }
    }

    suspend fun save(
        snapshot: AO3PreferencesSnapshot,
        toggles: Map<String, Boolean>,
        selects: Map<String, String>,
        textFields: Map<String, String>
    ): AO3Result<Unit> {
        val fields = buildList {
            add("authenticity_token" to snapshot.csrfToken)
            snapshot.httpMethodOverride?.let { add("_method" to it) }
            snapshot.hiddenFields.forEach { add(it) }
            // Unchecked checkboxes are omitted from browser posts; AO3 expects
            // present=1 for on. Only send checked ones as "1".
            snapshot.sections.flatMap { it.toggles }.forEach { toggle ->
                val on = toggles[toggle.name] ?: toggle.checked
                if (on) add(toggle.name to "1")
            }
            snapshot.selects.forEach { select ->
                val value = selects[select.name] ?: select.selectedValue
                add(select.name to value)
            }
            snapshot.textFields.forEach { field ->
                val value = textFields[field.name] ?: field.value
                add(field.name to value)
            }
        }
        return when (
            val response = client.postAuthenticated(
                url = snapshot.actionUrl,
                formFields = fields,
                headers = mapOf(
                    "Referer" to snapshot.actionUrl,
                    "X-CSRF-Token" to snapshot.csrfToken
                )
            )
        ) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                // iOS `savePreferences`: AO3's reason if it gave one; saved only on AO3's own
                // word (its notice, its sentence, or the redirect away from the form). Any
                // page that came back fine used to count as saved (audit A17-2).
                val body = response.value.body
                val status = response.value.statusCode
                val parser = io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser()
                val error = parser.writeErrorMessage(body)
                when {
                    error != null -> AO3Result.Failure(AO3Error.Validation(error))
                    status !in 200..399 -> AO3Result.Failure(AO3Error.Http(status))
                    parser.writeSuccessMessage(body) != null || status in 300..399 ||
                        body.contains("successfully updated", ignoreCase = true) -> AO3Result.Success(Unit)
                    else -> AO3Result.Failure(AO3Error.Validation(
                        io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields.UNCONFIRMED))
                }
            }
        }
    }
}
