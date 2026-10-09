package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CancellationException
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writing.*
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.LocalDate

internal enum class ChapterFormText(val title: String, val field: String) {
    Content("Chapter text", "content"), Summary("Summary", "summary"),
    Notes("Beginning notes", "notes"), Endnotes("End notes", "endnotes");
    fun text(form: AO3ChapterForm) = when (this) {
        Content -> form.content; Summary -> form.summary; Notes -> form.notes; Endnotes -> form.endnotes
    }
}

internal data class WritingChapterUiState(
    val form: AO3ChapterForm? = null, val loading: Boolean = false, val failure: String? = null,
    val busy: Boolean = false, val chapterSaved: Boolean = false, val finished: Boolean = false,
    val isLastChapter: Boolean = false, val postWithoutPreview: Boolean = false,
    val preview: AO3ChapterPreview? = null, val saveError: String? = null,
    val savedRevision: Int = 0
)

/** One opening, attempt remembered even on failure, immutable in-memory edits. */
internal class WritingChapterFormState(
    private val workID: Long,
    private val chapterID: Long?,
    val chapterCount: Int?,
    private val repository: AO3WorkFormRepository,
    private val auth: AO3AuthRepository,
    private val today: () -> LocalDate = { LocalDate.now() },
    private val writes: AO3WriteRepository
) {
    private val generation = auth.generation.value
    val account = auth.username().orEmpty()
    private var active = true
    private var attempted = false
    private var savedTotal: Long? = null
    private val mutable = MutableStateFlow(WritingChapterUiState())
    val state = mutable.asStateFlow()
    private fun ownsSession() = active && generation == auth.generation.value

    suspend fun load(retry: Boolean = false) {
        if (!ownsSession() || state.value.loading || state.value.form != null || attempted && !retry) return
        attempted = true
        if (!auth.state.value.isSignedIn) {
            mutable.value = WritingChapterUiState(failure = "Log in to AO3 first.")
            return
        }
        mutable.value = WritingChapterUiState(loading = true)
        try {
            val result = repository.loadChapterForm(workID, chapterID)
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            mutable.value = when (result) {
                is AO3Result.Success -> WritingChapterUiState(form = result.value)
                is AO3Result.Failure -> WritingChapterUiState(failure = workFormFailure(result.error))
            }
        } catch (cancelled: CancellationException) {
            if (active) mutable.value = state.value.copy(loading = false)
            throw cancelled
        } catch (error: Exception) {
            if (ownsSession()) mutable.value = WritingChapterUiState(failure = chapterFailure(error))
        }
    }
    private fun change(edit: (AO3ChapterForm) -> AO3ChapterForm) {
        val old = state.value
        if (!ownsSession() || !auth.state.value.isSignedIn || old.busy || old.chapterSaved || old.finished) return
        val form = old.form ?: return
        mutable.value = old.copy(form = edit(form))
    }
    fun title(value: String) = change { it.copy(title = value) }
    fun total(value: String) = change { it.copy(wipLength = value) }
    fun afterChapter(value: String) = change { it.copy(position = chapterPosition(value)) }
    fun checkpoint(field: ChapterFormText, value: String) = change { when (field) {
        ChapterFormText.Content -> it.copy(content = value)
        ChapterFormText.Summary -> it.copy(summary = value)
        ChapterFormText.Notes -> it.copy(notes = value)
        ChapterFormText.Endnotes -> it.copy(endnotes = value)
    } }
    fun dateEnabled(value: Boolean) = change { if (value) it.withDate(today())
        else it.copy(publishedYear = "", publishedMonth = "", publishedDay = "") }
    fun date(value: LocalDate) = change { it.withDate(value) }
    fun lastChapter(value: Boolean) {
        if (canEdit()) mutable.value = state.value.copy(isLastChapter = value)
    }
    fun withoutPreview(value: Boolean) { if (canEdit()) mutable.value = state.value.copy(postWithoutPreview = value) }
    private fun canEdit() = ownsSession() && auth.state.value.isSignedIn && state.value.form != null &&
        !state.value.busy && !state.value.chapterSaved && !state.value.finished
    /** Starts before its first await: a second queued tap sees busy immediately. */
    suspend fun save(submit: AO3WorkSubmitAction) {
        val old = state.value
        val form = old.form ?: return
        if (!active || old.busy || old.finished) return
        if (!ownsSession()) { mutable.value = old.copy(saveError = WORK_FORM_SESSION_CHANGED); return }
        mutable.value = old.copy(busy = true, saveError = null)
        try {
            if (!old.chapterSaved) {
                savedTotal = if (old.isLastChapter) form.position.toLongOrNull()?.takeIf { it > 0 }
                    ?: throw IllegalArgumentException("Enter this chapter’s position to mark it as the last chapter.") else null
                when (val result = writes.saveChapter(form, submit, generation)) {
                    is AO3Result.Failure -> throw ChapterFailure(result.error)
                    is AO3Result.Success -> {
                        if (!active) return
                        mutable.value = state.value.copy(chapterSaved = true)
                    }
                }
            }
            savedTotal?.let { total ->
                when (val result = writes.updateWorkTotals(form.workID, total, generation)) {
                    is AO3Result.Failure -> throw ChapterFailure(result.error)
                    is AO3Result.Success -> Unit
                }
            }
            if (active) mutable.value = state.value.copy(busy = false, finished = true, preview = null, saveError = null)
        } catch (cancelled: CancellationException) {
            if (active && generation != auth.generation.value) failSave(WORK_FORM_SESSION_CHANGED)
            else { if (active) mutable.value = state.value.copy(busy = false); throw cancelled }
        } catch (error: Exception) {
            if (active) failSave(chapterFailure(error))
        } finally {
            // iOS calls onSaved for every attempt after the chapter has succeeded, including a total-only retry.
            if (active) mutable.value = state.value.copy(busy = false,
                savedRevision = state.value.savedRevision + if (state.value.chapterSaved) 1 else 0)
        }
    }

    suspend fun openPreview() {
        val old = state.value
        val form = old.form ?: return
        if (!active || old.busy || old.chapterSaved || old.finished) return
        if (!ownsSession()) { mutable.value = old.copy(saveError = WORK_FORM_SESSION_CHANGED); return }
        mutable.value = old.copy(busy = true, saveError = null)
        try {
            when (val result = writes.previewChapter(form, generation)) {
                is AO3Result.Failure -> throw ChapterFailure(result.error)
                is AO3Result.Success -> {
                    if (!active) return
                    val adopted = form.adopting(result.value)
                    mutable.value = old.copy(form = adopted, preview = result.value,
                        savedRevision = old.savedRevision + if (form.chapterID == null) 1 else 0)
                }
            }
        } catch (cancelled: CancellationException) {
            if (active && generation != auth.generation.value) mutable.value = old.copy(saveError = WORK_FORM_SESSION_CHANGED)
            else { if (active) mutable.value = old; throw cancelled }
        } catch (error: Exception) {
            if (active) mutable.value = old.copy(saveError = chapterFailure(error))
        } finally {
            if (active) mutable.value = state.value.copy(busy = false)
        }
    }

    suspend fun deleteChapter(confirmed: Boolean = false) {
        val old = state.value
        val form = old.form ?: return
        val id = form.chapterID ?: return
        if (!confirmed || (chapterCount ?: 0) <= 1 || !active || old.busy || old.chapterSaved || old.finished) return
        if (!ownsSession()) { mutable.value = old.copy(saveError = CHAPTER_DELETE_SESSION_CHANGED); return }
        mutable.value = old.copy(busy = true, saveError = null)
        try {
            when (val result = writes.deleteChapter(form.workID, id, generation)) {
                is AO3Result.Failure -> throw ChapterFailure(result.error)
                is AO3Result.Success -> {
                    if (active) mutable.value = old.copy(finished = true, savedRevision = old.savedRevision + 1)
                }
            }
        } catch (cancelled: CancellationException) {
            if (active && generation != auth.generation.value) mutable.value = old.copy(saveError = CHAPTER_DELETE_SESSION_CHANGED)
            else { if (active) mutable.value = old; throw cancelled }
        } catch (error: Exception) {
            val message = chapterFailure(error)
            if (active) mutable.value = old.copy(saveError = if (message == AO3CollectionFields.UNCONFIRMED) message
                else "The chapter was not deleted. " + message)
        } finally {
            if (active) mutable.value = state.value.copy(busy = false)
        }
    }


    private fun failSave(message: String) {
        mutable.value = state.value.copy(busy = false, saveError =
            (if (state.value.chapterSaved && message != AO3CollectionFields.UNCONFIRMED)
                "The chapter was saved, but the work total was not updated. " else "") + message)
    }

    fun dismissError() { mutable.value = state.value.copy(saveError = null) }
    fun closePreview() { if (!state.value.busy) mutable.value = state.value.copy(preview = null) }
    fun close() { active = false }
}

internal fun chapterNumber(position: String): Long? = trimChapterNumber(position).toLongOrNull()?.takeIf { it > 0 }
private fun trimChapterNumber(value: String) = value.trim { char ->
    char == '\t' || char == ' ' || char == '\u00a0' || char == '\u1680' ||
        char in '\u2000'..'\u200b' || char == '\u202f' || char == '\u205f' || char == '\u3000'
}
internal fun chapterAfterText(position: String) = chapterNumber(position)?.let { (it - 1).toString() } ?: position
internal fun chapterPosition(after: String): String = trimChapterNumber(after).toLongOrNull()?.takeIf { it >= 0 && it < Long.MAX_VALUE }
    ?.let { (it + 1).toString() } ?: after
internal fun chapterSubtitle(workTitle: String, form: AO3ChapterForm) = "$workTitle · " +
    (chapterNumber(form.position)?.let { "chapter $it" } ?: form.title.ifEmpty { "chapter" })
internal fun chapterDeleteName(form: AO3ChapterForm): String {
    val title = trimWritingTag(form.title)
    return chapterNumber(form.position)?.let { if (title.isEmpty()) "Chapter $it" else "Chapter $it: $title" }
        ?: title.ifEmpty { "this chapter" }
}
internal fun AO3ChapterForm.publicationDate(today: LocalDate = LocalDate.now()) = runCatching {
    LocalDate.of(publishedYear.toInt(), 1, 1).plusMonths(publishedMonth.toLong() - 1).plusDays(publishedDay.toLong() - 1)
}.getOrDefault(today)
private fun AO3ChapterForm.withDate(date: LocalDate) = copy(publishedYear = "${date.year}", publishedMonth = "${date.monthValue}", publishedDay = "${date.dayOfMonth}")

private class ChapterFailure(val error: AO3Error) : Exception()
private fun chapterFailure(error: Exception): String = when (error) {
    is ChapterFailure -> workFormFailure(error.error)
    is IllegalArgumentException -> error.message ?: AO3CollectionFields.UNCONFIRMED
    is java.io.IOException -> workFormFailure(AO3Error.networkFromTransport(error))
    else -> workFormFailure(AO3Error.Network(error.message.orEmpty(), error))
}

internal const val CHAPTER_DELETE_SESSION_CHANGED = "Your AO3 session changed, so nothing was deleted."
