package io.github.cidy02.kudos.auth

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

private val Context.postingPseudDataStore by preferencesDataStore(name = "ao3_posting_pseud")

/**
 * Persists the user's non-secret "Posting As" preference per AO3 account.
 * Port of iOS `UserDefaultsAO3PostingPseudStore`.
 */
class AO3PostingPseudStore(
    private val context: Context,
    private val json: Json = Json { ignoreUnknownKeys = true }
) {
    private val key = stringPreferencesKey("ao3PostingPseudByUsername")

    val mapFlow: Flow<Map<String, String>> = context.postingPseudDataStore.data.map { prefs ->
        decode(prefs[key])
    }

    suspend fun pseudName(forUsername: String): String? {
        return mapFlow.first()[normalize(forUsername)]
    }

    suspend fun setPseudName(pseudName: String?, forUsername: String) {
        val username = normalize(forUsername)
        if (username.isEmpty()) return
        context.postingPseudDataStore.edit { prefs ->
            val current = decode(prefs[key]).toMutableMap()
            val trimmed = pseudName?.trim().orEmpty()
            if (trimmed.isEmpty()) {
                current.remove(username)
            } else {
                current[username] = trimmed
            }
            prefs[key] = json.encodeToString(
                MapSerializer(String.serializer(), String.serializer()),
                current
            )
        }
    }

    private fun decode(raw: String?): Map<String, String> {
        if (raw.isNullOrBlank()) return emptyMap()
        return runCatching {
            json.decodeFromString(MapSerializer(String.serializer(), String.serializer()), raw)
        }.getOrDefault(emptyMap())
    }

    private fun normalize(username: String): String =
        username.trim().lowercase()
}

/** One option from a write form's `select[name=…pseud_id]`. */
data class AO3PostingPseudOption(
    val id: String,
    val name: String,
    val selected: Boolean = false
)
