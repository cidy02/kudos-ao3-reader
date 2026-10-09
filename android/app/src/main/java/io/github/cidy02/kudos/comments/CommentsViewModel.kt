package io.github.cidy02.kudos.comments

import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.Job
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

/** The iOS comments destination's access/failure words, including reader-menu entry. */
internal fun commentsReadErrorMessage(error: AO3Error): String = when (error) {
    AO3Error.AuthenticationRequired -> "Log in to AO3 to do that."
    AO3Error.Forbidden -> "AO3 declined the request. The work may be restricted to logged-in users."
    AO3Error.NotFound -> "AO3 couldn't find these comments — the work may be hidden or deleted."
    is AO3Error.RateLimited -> "AO3 is asking for a pause. Please try again in a moment."
    is AO3Error.Network -> if (error.offline) {
        "You're offline. Comments will load when you're back online."
    } else error.displayMessage()
    else -> error.displayMessage()
}

class CommentsViewModel(
    private val repository: AO3CommentRepository,
    val initialTarget: AO3CommentTarget?,
    private val draftStore: CommentDraftStore? = null,
    /** The comment an Inbox row asked for: the first load is that thread, not the work's page 1. */
    initialFocusedCommentId: Long? = null,
    /**
     * With [initialFocusedCommentId], the Inbox's "Chapter Comments": that comment's chapter, with its
     * thread on the chapter's first page. The number is only the chapter's label until the index is read.
     */
    initialChapterPosition: Int? = null,
    /**
     * Read at each save and load, never kept: the screen's first frame did not yet know who
     * was signed in, the name was captured then, and every signed-in reader's drafts were
     * stored as the guest's, where the next account found them (audit A18-2).
     */
    private val currentUsername: () -> String? = { null }
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

    /** The load that owns the screen. A newer one cancels it, and its answer is not applied. */
    private var loadJob: Job? = null

    /** The Inbox's "Chapter Comments" until it has been shown whole: Try Again repeats it, not page 1. */
    private var pendingChapterComments: Pair<Long, Int>? = null
    private var lastPage = 1

    init {
        if (initialFocusedCommentId != null && initialChapterPosition != null) {
            loadChapterComments(initialFocusedCommentId, initialChapterPosition)
        } else {
            load(1, initialFocusedCommentId)
        }
    }

    /** Try Again: the request that failed, not always the work's first page (audit A28-3). */
    fun retry() {
        val chapterComments = pendingChapterComments
        if (chapterComments != null) loadChapterComments(chapterComments.first, chapterComments.second)
        else load(lastPage, _focusedCommentId.value)
    }

    data class ReplyTarget(val commentId: Long, val authorName: String)

    fun load(page: Int = 1, focusedId: Long? = null, forceRefresh: Boolean = false) {
        val target = _currentTarget.value ?: return
        _focusedCommentId.value = focusedId
        lastPage = page
        pendingChapterComments = null
        // Reading a page again is not closing the composer. While the sheet is open its reply
        // or edit target stays: a reload after a post AO3 did not confirm used to clear it,
        // and the same text then went out as a new comment on the work (audit A22-1).
        if (!_composerPresented.value) {
            _replyTarget.value = null
            _editTarget.value = null
            _composerParent.value = null
        }
        // One load at a time. The Inbox's thread and the work's first page used to race, and
        // whichever answered last was shown (audit A22-3).
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _state.value = CommentsUiState.Loading
            val result = repository.loadThread(target, page, focusedId)
            ensureActive()
            present(target, result)
        }
    }

    private var openedOnChapter = false

    /**
     * The chapter this screen was opened for by the reader's comments button. Once: the screen coming
     * back into view must not undo a scope the reader chose since. The scope and its label follow, as
     * iOS's `scope = .byChapter`: the chapter's comments used to be shown under "All comments".
     */
    fun openOnChapter(chapter: AO3ChapterRef) {
        val workId = _currentTarget.value?.workId ?: return
        if (openedOnChapter) return
        openedOnChapter = true
        _selectedChapter.value = chapter
        _scope.value = CommentScope.ByChapter
        setTarget(AO3CommentTarget.Chapter(workId, chapter.chapterId))
    }

    /**
     * The Inbox's "Chapter Comments" (iOS `CommentsModel.loadFocusedThread` with a chapter focus): the
     * comment's thread, then its chapter's first page with that thread put first when AO3 has it on a
     * later page. **One operation owned by [loadJob]**, so a scope or page the reader chooses meanwhile
     * cancels all of it; the first version joined the thread read as a separate job, which could then
     * overwrite that choice, and took a failed thread read for "nothing to add" (audits A26-4, A28-2,
     * A28-3). The chapter is the one the thread's own page names, as iOS reads it first; iOS then
     * falls back to the chapter index by position, which Android does not (the index is read without
     * the session and a signed-in-only work refuses it: A28-4). Without a named chapter the thread is
     * shown by itself, as the Inbox row's own tap shows it.
     */
    private fun loadChapterComments(commentId: Long, position: Int) {
        val workId = _currentTarget.value?.workId ?: return
        pendingChapterComments = commentId to position
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _state.value = CommentsUiState.Loading
            _focusedCommentId.value = commentId
            val work = AO3CommentTarget.Work(workId)
            val thread = repository.loadThread(work, 1, commentId)
            ensureActive()
            val root = (thread as? AO3Result.Success)?.value?.comments
                ?.firstOrNull { findCommentRecursive(listOf(it), commentId) != null }
            val chapterId = root?.let { findCommentRecursive(listOf(it), commentId)?.chapterId ?: it.chapterId }
            if (root == null || chapterId == null) {
                // A failure is shown as one and Try Again asks again; a thread that names no chapter is the screen.
                if (thread is AO3Result.Success) pendingChapterComments = null
                _currentTarget.value = work
                present(work, thread)
                return@launch
            }
            val chapter = AO3CommentTarget.Chapter(workId, chapterId)
            val page = repository.loadThread(chapter, 1, null)
            ensureActive()
            if (page is AO3Result.Success) {
                // Only now is it the chapter's page: paging and refresh read the chapter, not the one thread.
                pendingChapterComments = null
                openedOnChapter = true
                _currentTarget.value = chapter
                _focusedCommentId.value = null
                _scope.value = CommentScope.ByChapter
                if (_selectedChapter.value?.chapterId != chapterId) {
                    _selectedChapter.value = _chapters.value.firstOrNull { it.chapterId == chapterId }
                        ?: AO3ChapterRef(chapterId, position, "")
                }
            }
            present(chapter, page, first = root.takeIf {
                page is AO3Result.Success && findCommentRecursive(page.value.comments, commentId) == null
            })
        }
    }

    private fun collectIds(comments: List<AO3Comment>, into: MutableSet<String>) {
        for (comment in comments) { comment.id?.let(into::add); collectIds(comment.replies, into) }
    }
    private fun AO3Comment.without(ids: Set<String>): AO3Comment =
        copy(replies = replies.filter { it.id !in ids }.map { it.without(ids) })

    private suspend fun present(target: AO3CommentTarget, result: AO3Result<AO3CommentThread>, first: AO3Comment? = null) {
        when (result) {
            is AO3Result.Success -> {
                val sorted = result.value.withSort(_order.value)
                // The thread put first must not repeat a comment the page already shows: the list keys
                // its rows by comment id, and a second row with the same key crashes it (seen in the
                // demo, whose one comments page serves as both).
                val onPage = mutableSetOf<String>().also { collectIds(sorted.comments, it) }
                val thread = if (first == null) sorted else sorted.copy(comments = listOf(first.without(onPage)) + sorted.comments)
                _state.value = CommentsUiState.Loaded(thread)
                // Restore a top-level draft on initial load.
                val draftContent = draftStore?.getDraft(
                    workId = target.workId,
                    chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
                    parentId = null,
                    username = currentUsername()
                )
                // Only into a field nobody has opened. Reading the store suspends: a load that finished
                // just after Reply was tapped put the work's own draft into the reply, where it was
                // saved, and sent, as that reply (audit A28-1). Each composer reads its own draft when
                // it opens.
                if (draftContent != null && _draft.value.isEmpty() && _editTarget.value == null &&
                    _replyTarget.value == null && !_composerPresented.value && _currentTarget.value == target) {
                    _draft.value = draftContent
                }
                _isDraftRestored.value = true
            }
            is AO3Result.Failure -> {
                _state.value = if (result.error == AO3Error.AuthenticationRequired) {
                    CommentsUiState.AuthRequired(commentsReadErrorMessage(result.error))
                } else {
                    CommentsUiState.Error(commentsReadErrorMessage(result.error))
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
                val target = _currentTarget.value
                // The stored draft, or nothing, before the sheet can be typed in: the field
                // used to keep whatever an edit had left in it, and a draft that arrived
                // late replaced what had been typed meanwhile (audit A18-1).
                viewModelScope.launch {
                    _draft.value = if (target == null) "" else draftStore?.getDraft(
                        workId = target.workId,
                        chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
                        parentId = null,
                        username = currentUsername()
                    ).orEmpty()
                    _composerPresented.value = true
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
        // iOS `saveDraft`: an edit never uses the draft store. It has no slot of its own, so
        // its text went into the new-comment slot and replaced the comment waiting there.
        if (_editTarget.value != null) return
        val target = _currentTarget.value ?: return
        val reply = _replyTarget.value
        val content = _draft.value
        viewModelScope.launch {
            draftStore?.saveDraft(
                content = content,
                workId = target.workId,
                chapterId = (target as? AO3CommentTarget.Chapter)?.chapterId,
                parentId = reply?.commentId,
                username = currentUsername()
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
                    username = currentUsername()
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

    /**
     * The page on screen, to read again after a write that belongs to it. A reply, an edit or
     * a delete used to reload page 1, wherever the comment was (audit A20-5, the same on iOS).
     */
    private fun reloadPageOnScreen() {
        val page = (_state.value as? CommentsUiState.Loaded)?.thread?.currentPage ?: 1
        load(page, _focusedCommentId.value)
    }

    fun deleteComment(comment: AO3Comment) {
        val path = comment.deletePath ?: return
        viewModelScope.launch {
            _submitting.value = true
            when (val result = repository.deleteComment(path)) {
                is AO3Result.Success -> {
                    _message.value = "Comment deleted."
                    reloadPageOnScreen()
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
                        username = currentUsername()
                    )
                    if (reply != null || edit != null) reloadPageOnScreen() else load()
                }
                is AO3Result.Failure -> {
                    val unconfirmed = (result.error as? AO3Error.Validation)?.message ==
                        io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields.UNCONFIRMED
                    // An edit AO3 did not confirm is a failure to read and decide on, as on iOS:
                    // no reload, and the edit stays an edit.
                    if (edit == null && (unconfirmed || (result.error is AO3Error.Network && !result.error.isOffline()))) {
                        // The text stays in the composer. The thread is read again so the reader
                        // can see whether it arrived; the same text is not sent twice by a tap.
                        lastSubmittedContentHash = contentHash
                        _message.value = "Couldn't confirm this posted — reloading to check."
                        if (reply != null) reloadPageOnScreen() else load()
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
            initialFocusedCommentId: Long? = null,
            initialChapterPosition: Int? = null,
            currentUsername: () -> String? = { null }
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                CommentsViewModel(repository, initialTarget, draftStore, initialFocusedCommentId,
                    initialChapterPosition, currentUsername)
            }
        }
    }
}
