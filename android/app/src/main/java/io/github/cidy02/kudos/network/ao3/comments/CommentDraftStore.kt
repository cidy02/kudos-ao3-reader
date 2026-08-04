package io.github.cidy02.kudos.network.ao3.comments

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.commentDraftDataStore by preferencesDataStore(name = "comment_drafts")

/**
 * Persists unsent comment drafts keyed by (work, chapter, parent, identity).
 * Port of iOS `CommentDraftStore`.
 */
class CommentDraftStore(private val context: Context) {
    private fun keyFor(workId: Long, chapterId: Long?, parentId: Long?, username: String?): String {
        return "draft:${workId}:${chapterId ?: 0}:${parentId ?: 0}:${username ?: "guest"}"
    }

    suspend fun getDraft(workId: Long, chapterId: Long? = null, parentId: Long? = null, username: String? = null): String? {
        val key = stringPreferencesKey(keyFor(workId, chapterId, parentId, username))
        return context.commentDraftDataStore.data.map { it[key] }.first()
    }

    suspend fun saveDraft(content: String, workId: Long, chapterId: Long? = null, parentId: Long? = null, username: String? = null) {
        val key = stringPreferencesKey(keyFor(workId, chapterId, parentId, username))
        context.commentDraftDataStore.edit { prefs ->
            if (content.isBlank()) prefs.remove(key)
            else prefs[key] = content
        }
    }

    suspend fun clearDraft(workId: Long, chapterId: Long? = null, parentId: Long? = null, username: String? = null) {
        saveDraft("", workId, chapterId, parentId, username)
    }
}
