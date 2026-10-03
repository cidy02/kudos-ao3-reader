package io.github.cidy02.kudos.comments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterIndexRepository
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterRef
import io.github.cidy02.kudos.network.ao3.comments.AO3Comment
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentTarget
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentThread
import io.github.cidy02.kudos.network.ao3.comments.CommentDraftStore
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.isOffline
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class CommentOrder {
    OldestFirst,
    NewestFirst
}

enum class CommentScope {
    All,
    ByChapter
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

    private val _scope = MutableStateFlow(
        if (initialTarget is AO3CommentTarget.Chapter) CommentScope.ByChapter else CommentScope.All
    )
    val scope: StateFlow<CommentScope> = _scope.asStateFlow()

    private val _chapters = MutableStateFlow<List<AO3ChapterRef>>(emptyList())
    val chapters: StateFlow<List<AO3ChapterRef>> = _chapters.asStateFlow()

    private val _selectedChapter = MutableStateFlow<AO3ChapterRef?>(null)
    val selectedChapter: StateFlow<AO3ChapterRef?> = _selectedChapter.asStateFlow()

    private val _chaptersFailed = MutableStateFlow(false)
    val chaptersFailed: StateFlow<Boolean> = _chaptersFailed.asStateFlow()

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

    private val _composerParent = MutableStateFlow<AO3Comment?>(null)
    val composerParent: StateFlow<AO3Comment?> = _composerParent.asStateFlow()

    private val _editTarget = MutableStateFlow<AO3Comment?>(null)
    val editTarget: StateFlow<AO3Comment?> = _editTarget.asStateFlow()

    private val _composerPresented = MutableStateFlow(false)
    val composerPresented: StateFlow<Boolean> = _composerPresented.asStateFlow()

    private val _expandedRootIds = MutableStateFlow<Set<Long>>(emptySet())
    val expandedRootIds: StateFlow<Set<Long>> = _expandedRootIds.asStateFlow()

    private val _visibleReplyCounts = MutableStateFlow<Map<Long, Int>>(emptyMap())
    val visibleReplyCounts: StateFlow<Map<Long, Int>> = _visibleReplyCounts.asStateFlow()

    private val _collapsedRootIds = MutableStateFlow<Set<Long>>(emptySet())
    val collapsedRootIds: StateFlow<Set<Long>> = _collapsedRootIds.asStateFlow()

    /** Tracks the hash of the last successfully or ambiguously submitted content to prevent double-posts. */
    private var lastSubmittedContentHash: Int? = null

    init {
        load(1)
    }

    data class ReplyTarget(val commentId: Long, val authorName: String)

    fun load(page: Int = 1, focusedId: Long? = null, forceRefresh: Boolean = false) {
        val target = _currentTarget.value ?: return
        _focusedCommentId.value = focusedId
        _replyTarget.value = null
        _editTarget.value = null
        _composerParent.value = null
        viewModelScope.launch {
            _state.value = CommentsUiState.Loading
            val result = repository.loadThread(target, page, focusedId)
            when (result) {
                is AO3Result.Success -> {
                    val thread = result.value.withSort(_order.value)
                    _state.value = CommentsUiState.Loaded(thread)
                    // Restore a top-level draft on initial load.
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
                        CommentsUiState.Error(result.error.displayMessage())
                    }
                }
            }
        }
    }

    fun loadChaptersIfNeeded(chapterIndexRepository: AO3ChapterIndexRepository?) {
        val target = _currentTarget.value ?: return
        if (chapterIndexRepository == null || _chapters.value.isNotEmpty()) return
        viewModelScope.launch {
            when (val res = chapterIndexRepository.chapters(target.workId)) {
                is AO3Result.Success -> {
                    _chapters.value = res.value
                    _chaptersFailed.value = false
                    if (_selectedChapter.value == null && res.value.isNotEmpty()) {
                        val initialChapterId = (initialTarget as? AO3CommentTarget.Chapter)?.chapterId
                        val matched = if (initialChapterId != null) {
                            res.value.firstOrNull { it.chapterId == initialChapterId }
                        } else {
                            res.value.first()
                        }
                        _selectedChapter.value = matched
                    }
                }
                is AO3Result.Failure -> {
                    _chaptersFailed.value = true
                }
            }
        }
    }

    fun setScope(next: CommentScope) {
        if (_scope.value == next) return
        _scope.value = next
        val target = _currentTarget.value ?: return
        if (next == CommentScope.All) {
            setTarget(AO3CommentTarget.Work(target.workId))
        } else {
            val chapter = _selectedChapter.value
            if (chapter != null) {
                setTarget(AO3CommentTarget.Chapter(target.workId, chapter.chapterId))
            }
        }
    }

    fun selectChapter(chapter: AO3ChapterRef) {
        _selectedChapter.value = chapter
        _scope.value = CommentScope.ByChapter
        val target = _currentTarget.value ?: return
        setTarget(AO3CommentTarget.Chapter(target.workId, chapter.chapterId))
    }

    fun toggleCollapsed(rootId: Long) {
        _collapsedRootIds.update { set ->
            if (set.contains(rootId)) {
                set - rootId
            } else {
                set + rootId
            }
        }
        // Collapsing drops "show more" progress for that root, matching iOS:
        _visibleReplyCounts.update { map -> map - rootId }
    }

    fun expandReplies(rootId: Long) {
        _expandedRootIds.update { it + rootId }
        val current = _visibleReplyCounts.value[rootId] ?: CommentThreadGeometry.repliesChunkSize
        _visibleReplyCounts.update { it + (rootId to current + CommentThreadGeometry.repliesChunkSize) }
    }

    fun findComment(id: Long): AO3Comment? {
        val current = _state.value as? CommentsUiState.Loaded ?: return null
        return findCommentRecursive(current.thread.comments, id)
    }

    private fun findCommentRecursive(comments: List<AO3Comment>, id: Long): AO3Comment? {
        for (c in comments) {
            if (c.numericId == id) return c
            val found = findCommentRecursive(c.replies, id)
            if (found != null) return found
        }
        return null
    }

    fun openComposer(replyingTo: AO3Comment? = null, editing: AO3Comment? = null) {
        when {
            editing != null -> startEdit(editing)
            replyingTo != null -> startReply(replyingTo)
            else -> {
                _replyTarget.value = null
                _editTarget.value = null
                _composerParent.value = null
                _composerPresented.value = true
                val target = _currentTarget.value
                if (target != null) {
                    viewModelScope.launch {
                        val draftContent = draftStore?.getDraft(
                            workId = target.workId,
                            chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
                            parentId = null,
                            username = currentUsername
                        )
                        if (draftContent != null) _draft.value = draftContent
                    }
                }
            }
        }
    }

    fun closeComposer() {
        saveDraft()
        _composerPresented.value = false
        _replyTarget.value = null
        _editTarget.value = null
        _composerParent.value = null
    }

    fun saveDraft() {
        val target = _currentTarget.value ?: return
        val reply = _replyTarget.value
        val content = _draft.value
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

    fun updateDraft(content: String) {
        _draft.value = content
        saveDraft()
    }

    fun startReply(comment: AO3Comment) {
        val id = comment.numericId ?: return
        val target = _currentTarget.value
        _replyTarget.value = ReplyTarget(commentId = id, authorName = comment.author.name)
        _composerParent.value = comment
        _editTarget.value = null
        _draft.value = ""
        _message.value = null
        _composerPresented.value = true
        if (target != null) {
            viewModelScope.launch {
                val draftContent = draftStore?.getDraft(
                    workId = target.workId,
                    chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
                    parentId = id,
                    username = currentUsername
                )
                if (draftContent != null && _draft.value.isEmpty() && _replyTarget.value?.commentId == id) {
                    _draft.value = draftContent
                }
            }
        }
    }

    fun cancelReply() {
        _replyTarget.value = null
        _composerParent.value = null
        _composerPresented.value = false
    }

    fun startEdit(comment: AO3Comment) {
        _editTarget.value = comment
        _replyTarget.value = null
        _composerParent.value = null
        _draft.value = comment.body
        _message.value = null
        _composerPresented.value = true
    }

    fun cancelEdit() {
        _editTarget.value = null
        _draft.value = ""
        _composerPresented.value = false
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
                    _message.value = result.error.displayMessage()
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
                    _composerParent.value = null
                    _composerPresented.value = false
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
                    if (result.error is AO3Error.Network && !result.error.isOffline()) {
                        lastSubmittedContentHash = contentHash
                        _message.value = "Couldn't confirm this posted — reloading to check."
                        load()
                    } else {
                        _message.value = result.error.displayMessage()
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
            CommentOrder.OldestFirst -> comments.sortedBy { it.numericId ?: 0L }
            CommentOrder.NewestFirst -> comments.sortedByDescending { it.numericId ?: 0L }
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
