package io.github.cidy02.kudos.comments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.comments.AO3Comment
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentTarget
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentThread
import io.github.cidy02.kudos.network.ao3.comments.CommentDraftStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class CommentOrder {
    OldestFirst,
    NewestFirst
}

sealed interface CommentsUiState {
    data object Loading : CommentsUiState
    data class Loaded(val thread: AO3CommentThread) : CommentsUiState
    data class AuthRequired(val message: String) : CommentsUiState
    data class Error(val message: String) : CommentsUiState
}

class CommentsViewModel(
    private val repository: AO3CommentRepository,
    val initialTarget: AO3CommentTarget?,
    private val draftStore: CommentDraftStore? = null,
    private val currentUsername: String? = null
) : ViewModel() {
    private val _state = MutableStateFlow<CommentsUiState>(CommentsUiState.Loading)
    val state: StateFlow<CommentsUiState> = _state.asStateFlow()

    private val _order = MutableStateFlow(CommentOrder.OldestFirst)
    val order: StateFlow<CommentOrder> = _order.asStateFlow()

    private val _draft = MutableStateFlow("")
    val draft: StateFlow<String> = _draft.asStateFlow()

    private val _isDraftRestored = MutableStateFlow(false)
    val isDraftRestored: StateFlow<Boolean> = _isDraftRestored.asStateFlow()

    private val _submitting = MutableStateFlow(false)
    val submitting: StateFlow<Boolean> = _submitting.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private val _currentTarget = MutableStateFlow(initialTarget)
    val currentTarget: StateFlow<AO3CommentTarget?> = _currentTarget.asStateFlow()

    private val _focusedCommentId = MutableStateFlow<Long?>(null)
    val focusedCommentId: StateFlow<Long?> = _focusedCommentId.asStateFlow()

    private val _replyTarget = MutableStateFlow<ReplyTarget?>(null)
    val replyTarget: StateFlow<ReplyTarget?> = _replyTarget.asStateFlow()

    private val _editTarget = MutableStateFlow<AO3Comment?>(null)
    val editTarget: StateFlow<AO3Comment?> = _editTarget.asStateFlow()

    /** Tracks the hash of the last successfully or ambiguously submitted content to prevent double-posts. */
    private var lastSubmittedContentHash: Int? = null

    init {
        load(1)
    }

    data class ReplyTarget(val commentId: Long, val authorName: String)

    fun load(page: Int = 1, focusedId: Long? = null) {
        val target = _currentTarget.value ?: return
        println("Loading comments for target=$target, focusedId=$focusedId")
        _focusedCommentId.value = focusedId
        _replyTarget.value = null
        _editTarget.value = null
        viewModelScope.launch {
            println("Coroutine launched for load")
            _state.value = CommentsUiState.Loading
            val result = repository.loadThread(target, page, focusedId)
            println("Repository returned: $result")
            when (result) {
                is AO3Result.Success -> {
                    val thread = result.value.withSort(_order.value)
                    _state.value = CommentsUiState.Loaded(thread)
                    // Restore a top-level draft on initial load. focusedId is "which
                    // comment to scroll to" (e.g. from a notification deep link), not a
                    // reply target, so it must not be used as parentId here — reply
                    // drafts are restored separately in startReply().
                    println("Fetching draft for workId=${target.workId}, parentId=null")
                    val draftContent = draftStore?.getDraft(
                        workId = target.workId,
                        chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
                        parentId = null,
                        username = currentUsername
                    )
                    if (draftContent != null) _draft.value = draftContent
                    _isDraftRestored.value = true
                }
                is AO3Result.Failure -> {
                    _state.value = if (result.error == AO3Error.AuthenticationRequired) {
                        CommentsUiState.AuthRequired("Log in to AO3 before commenting.")
                    } else {
                        CommentsUiState.Error(result.error.toString())
                    }
                }
            }
        }
    }

    fun updateDraft(content: String) {
        _draft.value = content
        val target = _currentTarget.value ?: return
        val reply = _replyTarget.value
        viewModelScope.launch {
            draftStore?.saveDraft(
                content = content,
                workId = target.workId,
                chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
                parentId = reply?.commentId,
                username = currentUsername
            )
        }
    }

    fun startReply(comment: AO3Comment) {
        val id = comment.numericId ?: return
        val target = _currentTarget.value
        _replyTarget.value = ReplyTarget(commentId = id, authorName = comment.author.name)
        _editTarget.value = null
        _draft.value = ""
        _message.value = null
        if (target != null) {
            viewModelScope.launch {
                val draftContent = draftStore?.getDraft(
                    workId = target.workId,
                    chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
                    parentId = id,
                    username = currentUsername
                )
                // Only apply if the user hasn't already started typing or switched
                // reply targets again while this suspend call was in flight.
                if (draftContent != null && _draft.value.isEmpty() && _replyTarget.value?.commentId == id) {
                    _draft.value = draftContent
                }
            }
        }
    }

    fun cancelReply() {
        _replyTarget.value = null
    }

    fun startEdit(comment: AO3Comment) {
        _editTarget.value = comment
        _replyTarget.value = null
        _draft.value = comment.body
        _message.value = null
    }

    fun cancelEdit() {
        _editTarget.value = null
        _draft.value = ""
    }

    fun deleteComment(comment: AO3Comment) {
        val path = comment.deletePath ?: return
        viewModelScope.launch {
            _submitting.value = true
            when (val result = repository.deleteComment(path)) {
                is AO3Result.Success -> {
                    _message.value = "Comment deleted."
                    load()
                }
                is AO3Result.Failure -> {
                    _message.value = result.error.toString()
                }
            }
            _submitting.value = false
        }
    }

    fun submitComment() {
        val target = _currentTarget.value ?: return
        val content = _draft.value
        if (content.isBlank()) return

        val edit = _editTarget.value
        val reply = _replyTarget.value
        val contentHash = content.hashCode()

        if (contentHash == lastSubmittedContentHash) {
            _message.value = "You just posted this. Reload to see if it appeared."
            return
        }

        viewModelScope.launch {
            _submitting.value = true
            _message.value = null
            
            val result = if (edit != null && edit.editPath != null) {
                repository.editComment(edit.editPath, content)
            } else {
                repository.submitComment(target, content, reply?.commentId)
            }

            when (result) {
                is AO3Result.Success -> {
                    lastSubmittedContentHash = contentHash
                    _draft.value = ""
                    _replyTarget.value = null
                    _editTarget.value = null
                    _message.value = result.value.message
                    draftStore?.clearDraft(
                        workId = target.workId,
                        chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
                        parentId = reply?.commentId,
                        username = currentUsername
                    )
                    load()
                }
                is AO3Result.Failure -> {
                    if (result.error is AO3Error.Network) {
                        // Ambiguous network failure: don't clear draft, block immediate retry of same content.
                        lastSubmittedContentHash = contentHash
                        _message.value = "Couldn't confirm this posted — reloading to check."
                        load()
                    } else {
                        _message.value = result.error.toString()
                    }
                }
            }
            _submitting.value = false
        }
    }

    fun setOrder(next: CommentOrder) {
        _order.value = next
        val current = _state.value
        if (current is CommentsUiState.Loaded) {
            _state.value = current.copy(thread = current.thread.withSort(next))
        }
    }

    private fun AO3CommentThread.withSort(order: CommentOrder): AO3CommentThread {
        val sortedComments = when (order) {
            CommentOrder.OldestFirst -> comments.sortedBy { it.id }
            CommentOrder.NewestFirst -> comments.sortedByDescending { it.id }
        }
        return copy(comments = sortedComments)
    }

    fun clearMessage() {
        _message.value = null
    }

    fun setTarget(target: AO3CommentTarget) {
        if (_currentTarget.value == target) return
        _currentTarget.value = target
        load(1)
    }

    companion object {
        fun factory(
            repository: AO3CommentRepository,
            initialTarget: AO3CommentTarget?,
            draftStore: CommentDraftStore? = null,
            currentUsername: String? = null
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                CommentsViewModel(repository, initialTarget, draftStore, currentUsername)
            }
        }
    }
}
