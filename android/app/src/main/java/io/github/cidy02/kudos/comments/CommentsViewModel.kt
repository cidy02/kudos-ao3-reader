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
import kotlinx.coroutines.launch

sealed interface CommentsUiState {
    data object Loading : CommentsUiState
    data class Loaded(val thread: AO3CommentThread) : CommentsUiState
    data class AuthRequired(val message: String) : CommentsUiState
    data class Error(val message: String) : CommentsUiState
}

class CommentsViewModel(
    private val repository: AO3CommentRepository,
    private val initialTarget: AO3CommentTarget?,
    private val draftStore: CommentDraftStore? = null,
    private val currentUsername: String? = null
) : ViewModel() {
    private val _state = MutableStateFlow<CommentsUiState>(CommentsUiState.Loading)
    val state: StateFlow<CommentsUiState> = _state

    private val _draft = MutableStateFlow("")
    val draft: StateFlow<String> = _draft

    private val _submitting = MutableStateFlow(false)
    val submitting: StateFlow<Boolean> = _submitting

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message

    private val _currentTarget = MutableStateFlow(initialTarget)
    val currentTarget: StateFlow<AO3CommentTarget?> = _currentTarget

    private val _focusedCommentId = MutableStateFlow<Long?>(null)
    val focusedCommentId: StateFlow<Long?> = _focusedCommentId

    private val _replyTarget = MutableStateFlow<ReplyTarget?>(null)
    val replyTarget: StateFlow<ReplyTarget?> = _replyTarget

    private val _editTarget = MutableStateFlow<AO3Comment?>(null)
    val editTarget: StateFlow<AO3Comment?> = _editTarget

    init {
        load(1)
    }

    data class ReplyTarget(val commentId: Long, val authorName: String)

    fun load(page: Int = 1, focusedId: Long? = null) {
        val target = _currentTarget.value ?: return
        _focusedCommentId.value = focusedId
        _replyTarget.value = null
        _editTarget.value = null
        viewModelScope.launch {
            _state.value = CommentsUiState.Loading
            when (val result = repository.loadThread(target, page, focusedId)) {
                is AO3Result.Success -> {
                    _state.value = CommentsUiState.Loaded(result.value)
                    // Load draft if applicable
                    val draftContent = draftStore?.getDraft(
                        workId = target.workId,
                        chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
                        username = currentUsername
                    )
                    if (draftContent != null) _draft.value = draftContent
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
        viewModelScope.launch {
            draftStore?.saveDraft(
                content = content,
                workId = target.workId,
                chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
                username = currentUsername
            )
        }
    }

    fun startReply(comment: AO3Comment) {
        val id = comment.numericId ?: return
        _replyTarget.value = ReplyTarget(commentId = id, authorName = comment.author.name)
        _editTarget.value = null
        _draft.value = ""
        _message.value = null
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
                    _draft.value = ""
                    _replyTarget.value = null
                    _editTarget.value = null
                    _message.value = result.value.message
                    draftStore?.clearDraft(
                        workId = target.workId,
                        chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
                        username = currentUsername
                    )
                    load()
                }
                is AO3Result.Failure -> {
                    _message.value = result.error.toString()
                }
            }
            _submitting.value = false
        }
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
