package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterRef
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.LocalDate

internal data class WritingWorkFormUiState(
    val form: AO3WorkForm? = null,
    val loading: Boolean = false,
    val failure: String? = null,
    val saving: Boolean = false,
    val saved: Boolean = false,
    val publicationNeedRefresh: Boolean = false,
    val refreshingPublication: Boolean = false,
    val tagsNeedRefresh: Boolean = false,
    val refreshingTags: Boolean = false,
    val saveError: String? = null
)

internal enum class WorkFormChoice { Rating, Language, Comments, Skin }
internal enum class WorkFormTags { Warnings, Categories }
internal enum class WorkFormSwitch { Backdate, Restricted, Moderation, Complete }
internal enum class WorkFormText(val title: String, val field: String) {
    Summary("Summary", "summary"), Notes("Beginning notes", "notes"), Endnotes("End notes", "endnotes"),
    Content("Work text", "content");

    fun text(form: AO3WorkForm): String = when (this) {
        Summary -> form.summary
        Notes -> form.notes
        Endnotes -> form.endnotes
        Content -> form.chapter?.content.orEmpty()
    }
}

/** Owns one opening, one form read, in-memory edits and a single guarded Save. */
internal class WritingWorkFormState(
    private val workID: Long?,
    private val repository: AO3WorkFormRepository,
    private val auth: AO3AuthRepository,
    private val writes: AO3WriteRepository,
    private val today: () -> LocalDate = { LocalDate.now() },
    private val editTagsOnly: Boolean = false
) {
    private val generation = auth.generation.value
    val account = auth.username().orEmpty()
    private var active = true
    private var attempted = false
    private var collectionsAttempted = false
    private var tagRefreshAttempted = false
    private var publicationRefreshAttempted = false
    private var loadedChapter: AO3WorkChapterDraft? = null
    private val mutable = MutableStateFlow(WritingWorkFormUiState())
    val state = mutable.asStateFlow()
    private fun ownsSession() = active && generation == auth.generation.value

    suspend fun save() {
        val old = state.value
        val form = old.form ?: return
        // EditTagsView keeps fields editable during Save; a refusal keeps even edits made in flight.
        fun retained() = if (editTagsOnly) old.copy(form = state.value.form) else old
        if (!active || old.saving || old.saved || old.tagsNeedRefresh || old.publicationNeedRefresh) return
        if (generation != auth.generation.value) {
            mutable.value = retained().copy(saveError = WORK_FORM_SESSION_CHANGED)
            return
        }
        mutable.value = retained().copy(saving = true, saveError = null)
        try {
            val result = if (editTagsOnly) writes.editWorkTags(form, generation) else writes.saveWork(form, generation)
            currentCoroutineContext().ensureActive()
            if (!active) return
            mutable.value = when {
                generation != auth.generation.value -> retained().copy(saveError = WORK_FORM_SESSION_CHANGED)
                result is AO3Result.Success -> retained().copy(saved = true, saveError = null)
                result is AO3Result.Failure -> retained().copy(saveError = workFormFailure(result.error))
                else -> retained()
            }
        } catch (cancelled: CancellationException) {
            if (active && generation != auth.generation.value) {
                mutable.value = retained().copy(saveError = WORK_FORM_SESSION_CHANGED)
            } else {
                if (active) mutable.value = retained()
                throw cancelled
            }
        } catch (error: Exception) {
            val failure = if (error is java.io.IOException) AO3Error.networkFromTransport(error)
                else AO3Error.Network(error.message.orEmpty(), error)
            if (active) mutable.value = retained().copy(saveError = if (generation != auth.generation.value)
                WORK_FORM_SESSION_CHANGED else workFormFailure(failure))
        }
    }

    fun dismissSaveError() { mutable.value = state.value.copy(saveError = null) }

    suspend fun load(retry: Boolean = false) {
        if (!ownsSession() || state.value.loading || state.value.form != null || (attempted && !retry)) return
        attempted = true
        if (!auth.state.value.isSignedIn) {
            mutable.value = WritingWorkFormUiState(failure = "Log in to AO3 first.")
            return
        }
        mutable.value = WritingWorkFormUiState(loading = true)
        val result = if (editTagsOnly && workID != null) repository.loadEditTagsForm(workID)
            else if (workID == null) repository.loadNewWorkForm() else repository.loadWorkForm(workID)
        currentCoroutineContext().ensureActive()
        if (!ownsSession()) return
        mutable.value = when (result) {
            is AO3Result.Success -> { loadedChapter = result.value.chapter; WritingWorkFormUiState(form = result.value) }
            is AO3Result.Failure -> WritingWorkFormUiState(failure = workFormFailure(result.error))
        }
    }

    fun editTagsModel(): WritingWorkFormState? {
        val old = state.value
        val form = old.form ?: return null
        if (!ownsSession() || !auth.state.value.isSignedIn || old.saving || old.saved ||
            !form.isPosted || form.workID == null) return null
        return WritingWorkFormState(form.workID, repository, auth, writes, today, editTagsOnly = true)
    }

    fun chapterModel(chapterID: Long?, chapterCount: Int?): WritingChapterFormState? {
        val old = state.value
        val form = old.form ?: return null
        if (!ownsSession() || !auth.state.value.isSignedIn || old.saving || old.saved || !form.isPosted) return null
        val id = form.workID ?: return null
        return WritingChapterFormState(id, chapterID, chapterCount, repository, auth, today, writes)
    }

    fun chapterSaved() {
        if (!ownsSession()) return
        publicationRefreshAttempted = false
        mutable.value = state.value.copy(publicationNeedRefresh = true)
    }

    /** Chapter success refreshes only publication and chapter-1 fields, never unsaved metadata. */
    suspend fun refreshPublication(retry: Boolean = false) {
        val old = state.value
        val id = old.form?.workID ?: return
        if (!ownsSession() || !old.publicationNeedRefresh || old.refreshingPublication || (publicationRefreshAttempted && !retry)) return
        publicationRefreshAttempted = true
        mutable.value = old.copy(refreshingPublication = true)
        try {
            when (val result = repository.loadWorkForm(id)) {
                is AO3Result.Success -> {
                    currentCoroutineContext().ensureActive()
                    if (!ownsSession()) return
                    val current = state.value.form ?: return
                    val fresh = result.value
                    val freshChapter = fresh.chapter
                    val currentChapter = current.chapter
                    fun date(value: AO3WorkChapterDraft?) = listOf(value?.publishedYear, value?.publishedMonth, value?.publishedDay)
                    val chapter = if (currentChapter != null && freshChapter != null && date(currentChapter) != date(loadedChapter))
                        freshChapter.copy(publishedYear = currentChapter.publishedYear,
                            publishedMonth = currentChapter.publishedMonth, publishedDay = currentChapter.publishedDay) else freshChapter
                    loadedChapter = fresh.chapter
                    // Remove stale replay of chapter 1 as well: AO3 may have removed its text box after an Add.
                    val controls = current.servedControls.filterNot { it.name.startsWith("work[chapter_attributes]") } +
                        fresh.servedControls.filter { it.name.startsWith("work[chapter_attributes]") }
                    mutable.value = state.value.copy(form = current.copy(chapterTotal = fresh.chapterTotal,
                        chaptersPosted = fresh.chaptersPosted, isChaptered = fresh.isChaptered, chapter = chapter,
                        servedControls = controls), publicationNeedRefresh = false, refreshingPublication = false, saveError = null)
                }
                is AO3Result.Failure -> if (ownsSession()) mutable.value = state.value.copy(refreshingPublication = false,
                    saveError = "Reload chapter totals before saving this work. " + workFormFailure(result.error))
            }
        } catch (cancelled: CancellationException) {
            if (active) mutable.value = state.value.copy(refreshingPublication = false)
            throw cancelled
        } catch (error: Exception) {
            if (ownsSession()) mutable.value = state.value.copy(refreshingPublication = false,
                saveError = "Reload chapter totals before saving this work. " + workFormFailure(
                    if (error is java.io.IOException) AO3Error.networkFromTransport(error) else AO3Error.Network(error.message.orEmpty(), error)))
        }
    }

    fun tagsSaved() {
        if (!ownsSession()) return
        tagRefreshAttempted = false
        mutable.value = state.value.copy(tagsNeedRefresh = true)
    }

    /** One required read after confirmation; a failed attempt blocks Save until explicit Reload tags. */
    suspend fun refreshTags(retry: Boolean = false) {
        val old = state.value
        val id = old.form?.workID ?: return
        if (!ownsSession() || !old.tagsNeedRefresh || old.refreshingTags || (tagRefreshAttempted && !retry)) return
        tagRefreshAttempted = true
        mutable.value = old.copy(refreshingTags = true)
        try {
            val result = repository.loadWorkForm(id)
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            val latest = state.value
            mutable.value = when (result) {
                is AO3Result.Success -> latest.copy(form = latest.form?.withTagsFrom(result.value),
                    tagsNeedRefresh = false, refreshingTags = false, saveError = null)
                is AO3Result.Failure -> latest.copy(refreshingTags = false,
                    saveError = "Reload tags before saving this work. " + workFormFailure(result.error))
            }
        } catch (cancelled: CancellationException) {
            if (active) mutable.value = state.value.copy(refreshingTags = false)
            throw cancelled
        } catch (error: Exception) {
            if (ownsSession()) mutable.value = state.value.copy(refreshingTags = false,
                saveError = "Reload tags before saving this work. " + workFormFailure(
                    if (error is java.io.IOException) AO3Error.networkFromTransport(error)
                    else AO3Error.Network(error.message.orEmpty(), error)))
        }
    }

    private fun change(edit: (AO3WorkForm) -> AO3WorkForm) {
        if (!ownsSession() || !auth.state.value.isSignedIn) return
        val old = state.value
        if ((old.saving && !editTagsOnly) || old.saved) return
        val form = old.form ?: return
        mutable.value = old.copy(form = edit(form))
    }

    /** First opening only: a failed/cancelled best-effort read is still an attempt. */
    /** The Chapters row: the form's work, its own session, one read. */
    suspend fun loadChapters(): AO3Result<List<AO3ChapterRef>> {
        val id = state.value.form?.workID
        if (!ownsSession() || id == null) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        return repository.loadChapters(id)
    }

    suspend fun openCollections() {
        if (!ownsSession() || !auth.state.value.isSignedIn || state.value.form == null || collectionsAttempted) return
        collectionsAttempted = true
        val result = try { repository.loadCollectionOffers() } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            currentCoroutineContext().ensureActive()
            return // Same silent best-effort behavior as iOS, with the attempt retained.
        }
        currentCoroutineContext().ensureActive()
        if (result is AO3Result.Success && result.value.isNotEmpty()) change { form ->
            // Edits made while the page was loading remain authoritative; the served fallback stays exact.
            val selected = form.postedCollectionNames
            val offered = result.value.map { row -> row.copy(isSelected = selected.any { it.equals(row.name, true) }) }
            val held = form.collections.filter { row -> result.value.none { it.name.equals(row.name, true) } }
            form.copy(collections = offered + held)
        }
    }

    fun selectSeries(id: Long) = change { form ->
        val row = form.series.firstOrNull { it.seriesID == id } ?: return@change form
        if (form.currentSeries.any { it.seriesID == id }) return@change form
        val picked = !row.isSelected
        form.copy(series = form.series.map { it.copy(isSelected = picked && it.seriesID == id) },
            newSeriesTitle = if (picked) "" else form.newSeriesTitle)
    }
    fun newSeries(value: String) = change { form -> form.copy(newSeriesTitle = value,
        series = if (trimWritingTag(value).isNotEmpty()) form.series.map { it.copy(isSelected = false) } else form.series) }
    fun toggleCollection(name: String) = change { form -> form.copy(collections = form.collections.map {
        if (it.name == name) it.copy(isSelected = !it.isSelected) else it
    }) }
    fun addCollection(offer: AO3CollectionOffer) = change { form ->
        if (form.collections.any { it.name.equals(offer.name, true) }) form
        else form.copy(collections = form.collections + offer.copy(isSelected = false))
    }
    fun addGift(value: String): Boolean {
        val name = trimWritingTag(value)
        var added = false
        change { form ->
            if (name.isEmpty() || form.gifts.any { it.equals(name, true) }) form else {
                added = true
                form.copy(gifts = form.gifts + name)
            }
        }
        return added
    }
    fun removeGift(name: String) = change { it.copy(gifts = it.gifts.filterNot { gift -> gift == name }) }
    fun togglePseud(id: String) = change { form ->
        val creators = form.creators
        if (creators.availablePseuds.none { it.value == id }) return@change form
        val chosen = creators.selectedPseudIDs
        val next = if (id !in chosen) chosen + id else if (chosen.size > 1) chosen.filterNot { it == id } else chosen
        form.copy(creators = creators.copy(selectedPseudIDs = next))
    }
    fun coauthor(value: String) = change { it.copy(creators = it.creators.copy(coauthorByline = value)) }
    fun parentWork(edit: (AO3ParentWorkDraft) -> AO3ParentWorkDraft) = change { it.copy(parentWork = edit(it.parentWork)) }

    fun title(value: String) = change { it.copy(title = value) }
    fun choice(kind: WorkFormChoice, value: String) = change { form ->
        if (form.choiceOptions(kind).none { it.value == value }) form else when (kind) {
            WorkFormChoice.Rating -> form.copy(rating = value)
            WorkFormChoice.Language -> form.copy(languageID = value)
            WorkFormChoice.Comments -> form.copy(commentPermissions = value)
            WorkFormChoice.Skin -> form.copy(workSkinID = value)
        }
    }

    fun toggleTag(kind: WorkFormTags, value: String) = change { form ->
        if (form.tagOptions(kind).none { it.value == value }) return@change form
        val old = form.tagValues(kind)
        // WritingTagsEditor appends new picks, removes all occurrences on deselection.
        val picked = if (value in old) old.filterNot { it == value } else old + value
        when (kind) {
            WorkFormTags.Warnings -> form.copy(warnings = picked)
            WorkFormTags.Categories -> form.copy(categories = picked)
        }
    }

    fun writingTags(kind: WritingTagKind, values: List<String>) = change { form -> when (kind) {
        WritingTagKind.Fandom -> form.copy(fandoms = values)
        WritingTagKind.Relationship -> form.copy(relationships = values)
        WritingTagKind.Character -> form.copy(characters = values)
        WritingTagKind.Freeform -> form.copy(additionalTags = values)
    } }

    fun checkpoint(field: WorkFormText, text: String) = change { form -> when (field) {
        WorkFormText.Summary -> form.copy(summary = text)
        WorkFormText.Notes -> form.copy(notes = text)
        WorkFormText.Endnotes -> form.copy(endnotes = text)
        WorkFormText.Content -> form.copy(chapter = (form.chapter ?: AO3WorkChapterDraft()).copy(content = text))
    } }

    fun chapterTotal(value: String) = change { if (it.isPosted && !state.value.publicationNeedRefresh) it.copy(chapterTotal = value) else it }
    fun toggle(kind: WorkFormSwitch, value: Boolean) = change { form -> if (state.value.publicationNeedRefresh) form else when (kind) {
        WorkFormSwitch.Restricted -> form.copy(restricted = value)
        WorkFormSwitch.Moderation -> form.copy(moderatedCommenting = value)
        WorkFormSwitch.Complete -> if (form.isPosted) form.copy(chapterTotal = if (value) "${form.chaptersPosted ?: 1}" else "") else form
        WorkFormSwitch.Backdate -> {
            val toggled = form.copy(backdate = value)
            if (value && form.chapter?.publishedYear?.isEmpty() == true) toggled.withPublicationDate(today()) else toggled
        }
    } }
    fun publicationDate(date: LocalDate) = change { form ->
        if (state.value.publicationNeedRefresh || date < LocalDate.of(1950, 1, 1) || date > today()) form else form.withPublicationDate(date)
    }
    fun close() { active = false }
}

internal const val WORK_FORM_SESSION_CHANGED = "Your AO3 session changed. Reopen this form before saving."

private fun AO3WorkForm.withPublicationDate(date: LocalDate) = copy(chapter = chapter?.copy(
    publishedYear = date.year.toString(), publishedMonth = date.monthValue.toString(), publishedDay = date.dayOfMonth.toString()))

internal fun AO3WorkForm.publicationDate(today: LocalDate = LocalDate.now()): LocalDate {
    val draft = chapter ?: return today
    // Gregorian Calendar.date(from:) normalizes overflow in iOS, rather than parsing an ISO string.
    return runCatching {
        LocalDate.of(draft.publishedYear.toInt(), 1, 1)
            .plusMonths(draft.publishedMonth.toLong() - 1).plusDays(draft.publishedDay.toLong() - 1)
    }.getOrDefault(today)
}

internal fun AO3WorkForm.choiceOptions(kind: WorkFormChoice): List<AO3FormOption> = when (kind) {
    WorkFormChoice.Rating -> ratingOptions
    WorkFormChoice.Language -> languageOptions
    WorkFormChoice.Comments -> commentPermissionOptions
    WorkFormChoice.Skin -> {
        if (workSkinOptions.none { it.value.isEmpty() }) listOf(AO3FormOption("", "Default")) + workSkinOptions
        else workSkinOptions.map { if (it.value.isEmpty() && it.title.isBlank()) it.copy(title = "Default") else it }
    }
}
internal fun AO3WorkForm.choiceValue(kind: WorkFormChoice): String = when (kind) {
    WorkFormChoice.Rating -> rating
    WorkFormChoice.Language -> languageID
    WorkFormChoice.Comments -> commentPermissions
    WorkFormChoice.Skin -> workSkinID
}
internal fun AO3WorkForm.tagOptions(kind: WorkFormTags) = when (kind) {
    WorkFormTags.Warnings -> warningOptions
    WorkFormTags.Categories -> categoryOptions
}
internal fun AO3WorkForm.tagValues(kind: WorkFormTags) = when (kind) {
    WorkFormTags.Warnings -> warnings
    WorkFormTags.Categories -> categories
}
internal fun workFormCount(values: List<*>) = if (values.isEmpty()) "None" else values.size.toString()
internal fun AO3WorkForm.screenTitle() = when (kind) {
    AO3WorkFormKind.New -> "New work"
    AO3WorkFormKind.Draft -> "Draft"
    AO3WorkFormKind.Edit, AO3WorkFormKind.EditTags -> "Edit work"
}
internal fun AO3WorkForm.subtitle() = buildList {
    add(title.ifEmpty { "Untitled" })
    if (isDraft) add("never posted")
    if (isPosted) chaptersPosted?.let { add("$it ${if (it == 1) "chapter" else "chapters"}") }
}.joinToString(" · ")
internal fun AO3WorkForm.recoveryTarget() = workID?.let { "work:$it" } ?: "work:new"
internal fun AO3WorkForm.seriesValue(): String {
    val current = currentSeries.joinToString(", ") { it.title }
    val adding = series.firstOrNull { it.isSelected }?.title ?: trimWritingTag(newSeriesTitle).takeIf { it.isNotEmpty() }
    return when {
        current.isEmpty() && adding == null -> "None"
        current.isEmpty() -> "Adding $adding"
        adding == null -> current
        else -> "$current + $adding"
    }
}
internal fun AO3WorkForm.creatorsValue(): String {
    val pseuds = creators.selectedPseudIDs.size
    return when {
        creators.coauthorByline.isNotEmpty() -> "$pseuds + 1 invited"
        pseuds == 0 -> "None"
        else -> "$pseuds"
    }
}

/** iOS UserFacingError/AO3Error copy; Android's extra overload type follows its HTTP server case. */
internal fun workFormFailure(error: AO3Error): String = when (error) {
    AO3Error.AuthenticationRequired -> "Your AO3 session expired. Please log in again."
    AO3Error.Forbidden -> "AO3 refused the request (HTTP 403). Wait a while before trying again."
    AO3Error.NotFound -> "That work or page couldn't be found (it may be restricted)."
    is AO3Error.Parse -> "AO3's page format wasn't what the app expected."
    is AO3Error.Server -> "AO3 had a server problem (HTTP ${error.statusCode}). Try again shortly."
    is AO3Error.Overloaded -> when (error.statusCode) {
        429 -> "AO3 is rate-limiting requests. Wait a moment and try again."
        in 500..599 -> "AO3 had a server problem (HTTP ${error.statusCode}). Try again shortly."
        else -> "AO3's page format wasn't what the app expected."
    }
    is AO3Error.RateLimited -> "AO3 is rate-limiting requests. Wait a moment and try again."
    is AO3Error.Network -> when {
        error.offline -> "You're offline. Connect to the internet and try again."
        error.cause is java.net.SocketTimeoutException -> "AO3 took too long to answer. Try again."
        error.cause is javax.net.ssl.SSLException -> "Couldn't make a secure connection to AO3."
        else -> "Couldn't reach AO3. Check your connection and try again."
    }
    is AO3Error.Http -> "AO3 returned an unexpected response (HTTP ${error.statusCode})."
    is AO3Error.Validation -> error.message
    AO3Error.BadRequest -> "AO3 returned an unexpected response (HTTP 400)."
}
