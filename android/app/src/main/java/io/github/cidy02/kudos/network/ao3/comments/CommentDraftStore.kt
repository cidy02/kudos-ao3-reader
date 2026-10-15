package io.github.cidy02.kudos.network.ao3.comments

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

val Context.commentDraftDataStore by preferencesDataStore(name = "comment_drafts")

/**
 * Persists unsent comment drafts keyed by (work, chapter, parent, identity).
 * Port of iOS `CommentDraftStore`.
 */
object CommentDraftIdentity {
    const val UNNAMED_PREFIX = "unknown-session:"
    private val launch = UUID.randomUUID().toString()
    fun unnamedSession(generation: Int) = "$UNNAMED_PREFIX$launch:$generation"
    fun forViewer(username: String?, generation: Int): String? =
        if (username != null && username.isBlank()) unnamedSession(generation) else username
}

class CommentDraftStore(private val dataStore: DataStore<Preferences>) {
    private fun keyFor(workId: Long, chapterId: Long?, parentId: Long?, username: String?): String {
        return "draft:${workId}:${chapterId ?: 0}:${parentId ?: 0}:${username ?: "guest"}"
    }

    suspend fun getDraft(workId: Long, chapterId: Long? = null, parentId: Long? = null, username: String? = null): String? {
        val key = stringPreferencesKey(keyFor(workId, chapterId, parentId, username))
        return dataStore.data.map { it[key] }.first()
    }

    suspend fun saveDraft(content: String, workId: Long, chapterId: Long? = null, parentId: Long? = null, username: String? = null) {
        val key = stringPreferencesKey(keyFor(workId, chapterId, parentId, username))
        dataStore.edit { prefs ->
            if (content.isBlank()) prefs.remove(key)
            else prefs[key] = content
        }
    }

    /** Keep both drafts on collision, with the just-typed unnamed draft first. */
    suspend fun move(from: String, to: String) {
        if (from == to) return
        dataStore.edit { prefs ->
            prefs.asMap().entries.toList().forEach { (key, value) ->
                if (!key.name.startsWith("draft:") || !key.name.endsWith(":$from") || value !is String) return@forEach
                val destination = stringPreferencesKey(key.name.removeSuffix(from) + to)
                val existing = prefs[destination]
                prefs[destination] = if (existing != null && existing != value) "$value\n\n$existing" else value
                prefs.remove(stringPreferencesKey(key.name))
            }
        }
    }

    /** Only this account's work/parent variants; other replies and works remain drafts. */
    suspend fun clearVariants(workId: Long, parentId: Long?, username: String?) {
        dataStore.edit { prefs ->
            prefs.asMap().keys.filter {
                it.name.startsWith("draft:$workId:") && it.name.endsWith(":${parentId ?: 0}:${username ?: "guest"}")
            }.forEach { prefs.remove(stringPreferencesKey(it.name)) }
        }
    }

    suspend fun clearDraft(workId: Long, chapterId: Long? = null, parentId: Long? = null, username: String? = null) {
        saveDraft("", workId, chapterId, parentId, username)
    }
}
