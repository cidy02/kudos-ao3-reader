package io.github.cidy02.kudos.reader

import android.content.Context
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.map
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import io.github.cidy02.kudos.reader.settings.ReaderSettingsMapper
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** iOS reader AO3 alert words; the existing repository still owns dispatch and rejection. */
internal fun readerKudosErrorMessage(error: AO3Error): String = when (error) {
    AO3Error.AuthenticationRequired -> "Log in to AO3 first."
    AO3Error.Forbidden -> "AO3 refused the request (HTTP 403). Wait a while before trying again."
    AO3Error.NotFound -> "That work or page couldn't be found (it may be restricted)."
    is AO3Error.RateLimited -> "AO3 is rate-limiting requests. Wait a moment and try again."
    is AO3Error.Server -> "AO3 had a server problem (HTTP ${error.statusCode}). Try again shortly."
    is AO3Error.Http -> "AO3 returned an unexpected response (HTTP ${error.statusCode})."
    else -> error.displayMessage()
}

/**
 * Drives the reader screen: resolves the work, exposes [ReaderUiState], and
 * debounces/persists progress reported by the Readium navigator host.
 */
class ReaderViewModel(
    private val repository: ReaderRepository,
    private val readingLogService: ReadingLogService,
    private val settingsRepository: SettingsRepository,
    private val annotationRepository: AnnotationRepository,
    private val workId: String,
    private val writeRepository: AO3WriteRepository? = null
) : ViewModel() {

    private val _state = MutableStateFlow<ReaderUiState>(ReaderUiState.Loading)
    val state: StateFlow<ReaderUiState> = _state.asStateFlow()

    private val _writeMessage = MutableStateFlow<String?>(null)
    val writeMessage: StateFlow<String?> = _writeMessage.asStateFlow()

    private val _kudosWorking = MutableStateFlow(false)
    val kudosWorking: StateFlow<Boolean> = _kudosWorking.asStateFlow()

    // Room reads suspend: serialize editor writes so rapid Colour → Done cannot overwrite either field.
    private val annotationEditMutex = Mutex()

    private var autoFinishedThisSession = false
    private var spineCountForEof = 0
    private var isScrubbing = false
    private var sessionLifecycleJob: Job? = null

    /** iOS KeepScreenAwakeModifier: the screen stays lit while a book is open, if asked. */
    val keepScreenAwake: kotlinx.coroutines.flow.StateFlow<Boolean> = settingsRepository.settings
        .map { it.reader.keepScreenAwake }
        .stateIn(viewModelScope, kotlinx.coroutines.flow.SharingStarted.WhileSubscribed(5_000), false)

    private val saver = ReaderProgressSaver(viewModelScope) { progress ->
        repository.persistLocation(workId, progress)
    }

    init {
        load()
        viewModelScope.launch {
            settingsRepository.speechPreferences.collect { speech ->
                updatePreferences { speech.applyTo(it) }
            }
        }
    }

    fun load() {
        _state.value = ReaderUiState.Loading
        viewModelScope.launch {
            _state.value = when (val result = repository.open(workId)) {
                is ReaderOpenResult.Failure -> ReaderUiState.Error(result.error, result.work)
                is ReaderOpenResult.Success -> ReaderUiState.Reading(
                    work = result.work,
                    epubPath = result.epubPath,
                    restoreTarget = result.restoreTarget,
                    preferences = settingsRepository.speechPreferences.first().applyTo(result.preferences),
                    endOfWork = EndOfWorkActions.forWork(result.work),
                    finished = result.work.isFinished
                )
            }
            if (_state.value is ReaderUiState.Reading) {
                observeAnnotations()
            }
        }
    }

    private fun observeAnnotations() {
        viewModelScope.launch {
            annotationRepository.observeForWork(workId).collect { annotations ->
                updateReading { state ->
                    state.copy(
                        editingAnnotationId = state.editingAnnotationId?.takeIf { id ->
                            annotations.any { it.id == id }
                        },
                        bookmarks = annotations.filter {
                            it.kindRaw.equals("bookmark", ignoreCase = true)
                        },
                        highlights = annotations.filter {
                            it.kindRaw.equals("highlight", ignoreCase = true) ||
                                it.kindRaw.equals("note", ignoreCase = true)
                        }
                    )
                }
            }
        }
    }

    fun setSpineCount(count: Int) {
        spineCountForEof = count
    }

    /**
     * Called by the navigator host on each location, including the open landing.
     * The landing is not a read and is not saved (iOS seeds the persistence
     * baseline so the first identical callback stays quiet).
     */
    fun onProgress(progress: ReaderProgress) {
        updateReading { it.copy(
            liveProgress = progress,
            viewport = it.viewport?.takeIf { viewport -> viewport.spineIndex == progress.spineIndex }
        ) }
        if (isScrubbing) return
        if (!repository.observeLocation(workId, progress)) return
        saver.onProgress(progress)
    }

    fun setScrubbing(scrubbing: Boolean) {
        isScrubbing = scrubbing
        if (!scrubbing) (_state.value as? ReaderUiState.Reading)?.liveProgress?.let(::onProgress)
    }

    fun onViewport(viewport: ReaderViewport?) {
        updateReading { it.copy(viewport = viewport) }
        if (autoFinishedThisSession) return
        val reading = _state.value as? ReaderUiState.Reading ?: return
        if (reading.finished || !reading.endOfWork.canMarkFinished) return
        if (!EndOfWorkActions.isAtEndOfPublication(viewport, spineCountForEof)) return
        autoFinishedThisSession = true
        enqueueSessionLifecycle {
            saver.flush()
            (_state.value as? ReaderUiState.Reading)?.liveProgress?.let { repository.persistLocation(workId, it) }
            repository.finishAtPublicationEnd(workId)
            updateReading { it.copy(
                finished = true,
                endOfWork = it.endOfWork.copy(canMarkFinished = false)
            ) }
        }
    }

    fun startReadingSession() {
        enqueueSessionLifecycle {
            repository.currentWork(workId)?.let { readingLogService.startSession(it) }
        }
    }

    fun pauseReadingSession() {
        enqueueSessionLifecycle {
            saver.flush()
            flushScrubPosition()
            repository.finishReading(workId)?.let { readingLogService.pauseSession(it) }
        }
    }

    fun resumeReadingSession() {
        enqueueSessionLifecycle { readingLogService.resumeSession(workId) }
    }

    fun close() {
        enqueueSessionLifecycle {
            saver.flush()
            flushScrubPosition()
            isScrubbing = false
            repository.finishReading(workId)?.let { readingLogService.endSession(it) }
            repository.close(workId)
        }
    }

    private suspend fun flushScrubPosition() {
        if (isScrubbing) {
            (_state.value as? ReaderUiState.Reading)?.liveProgress?.let {
                repository.persistLocation(workId, it)
            }
        }
    }

    private fun enqueueSessionLifecycle(block: suspend () -> Unit) {
        val previous = sessionLifecycleJob
        sessionLifecycleJob = viewModelScope.launch {
            previous?.join()
            block()
        }
    }

    fun markFinished() {
        enqueueSessionLifecycle {
            // The position first: both writes replace the whole row, and a debounced save
            // landing after this one put "not finished" back (audit A5-1).
            saver.flush()
            repository.setFinished(workId, true)
            updateReading { reading ->
                reading.copy(
                    finished = true,
                    endOfWork = reading.endOfWork.copy(canMarkFinished = false)
                )
            }
        }
    }

    fun markEpubMissing() {
        viewModelScope.launch { repository.markEpubMissing(workId) }
    }

    fun addBookmarkAtProgress(progress: ReaderProgress, locatorString: String, chapterTitle: String = "") {
        viewModelScope.launch {
            annotationRepository.addBookmark(
                workId = workId,
                locatorString = locatorString.ifBlank { progress.locatorJson.orEmpty() },
                progression = progress.totalProgression ?: progress.scrollFraction,
                spineIndex = progress.spineIndex,
                chapterTitle = chapterTitle
            )
        }
    }

    fun toggleBookmarkAtProgress(progress: ReaderProgress, locatorString: String, chapterTitle: String = "") {
        viewModelScope.launch {
            val removed = annotationRepository.removeBookmarkNear(
                workId = workId,
                spineIndex = progress.spineIndex,
                progression = progress.totalProgression ?: progress.scrollFraction
            )
            if (!removed) {
                addBookmarkAtProgress(progress, locatorString, chapterTitle)
            }
        }
    }

    fun addHighlight(
        locatorString: String,
        selectedText: String,
        color: String,
        note: String = "",
        progression: Double,
        spineIndex: Int,
        chapterTitle: String = "",
        asNote: Boolean = false
    ) {
        // A selection hands over a bare Readium locator; a bookmark already hands over the
        // envelope. Stored bare, the highlight could not be drawn or gone to.
        val stored = ReaderLocatorCodec.forStorage(locatorString) ?: return
        viewModelScope.launch {
            annotationEditMutex.withLock {
                annotationRepository.addOrRecolorHighlight(
                    workId = workId,
                    locatorString = stored,
                    selectedText = selectedText,
                    color = color,
                    note = note,
                    progression = progression,
                    spineIndex = spineIndex,
                    chapterTitle = chapterTitle,
                    kind = if (asNote) "note" else "highlight"
                )
            }
        }
    }

    /** Page decorations and Contents share the same editor; bookmarks only navigate. */
    fun openHighlight(id: String) {
        updateReading { reading ->
            if (reading.highlights.any { it.id == id }) reading.copy(editingAnnotationId = id)
            else reading
        }
    }

    fun closeNoteEditor() {
        updateReading { it.copy(editingAnnotationId = null) }
    }

    fun recolorHighlight(id: String, color: String) {
        viewModelScope.launch {
            annotationEditMutex.withLock {
                annotationRepository.addOrRecolorHighlight(id = id, color = color)
            }
        }
    }

    fun deleteAnnotation(id: String) {
        updateReading { if (it.editingAnnotationId == id) it.copy(editingAnnotationId = null) else it }
        viewModelScope.launch {
            annotationEditMutex.withLock { annotationRepository.deleteAnnotation(id) }
        }
    }

    fun updateNote(id: String, note: String) {
        viewModelScope.launch {
            annotationEditMutex.withLock { annotationRepository.updateNote(id, note) }
        }
    }

    fun giveKudos() {
        val reading = _state.value as? ReaderUiState.Reading ?: return
        if (_kudosWorking.value || reading.work.hasGivenKudos) return
        val ao3Id = reading.endOfWork.workId ?: return
        val writes = writeRepository ?: return
        // Set before launching so two taps before recomposition cannot start two writes.
        _kudosWorking.value = true
        viewModelScope.launch {
            try {
                when (val result = writes.giveKudos(ao3Id)) {
                    is AO3Result.Success -> {
                        _writeMessage.value = result.value.message
                        val updated = repository.markKudosGiven(workId)
                        updateReading { current ->
                            current.copy(work = updated ?: current.work.copy(hasGivenKudos = true))
                        }
                    }
                    is AO3Result.Failure -> _writeMessage.value = readerKudosErrorMessage(result.error)
                }
            } finally {
                _kudosWorking.value = false
            }
        }
    }

    fun clearWriteMessage() {
        _writeMessage.value = null
    }

    fun shareWork(context: Context) {
        viewModelScope.launch {
            val work = repository.currentWork(workId) ?: return@launch
            if (!work.isDeleted) _writeMessage.value = ReaderWorkActions(context).share(work)
        }
    }

    fun openOriginal(context: Context) {
        viewModelScope.launch {
            val work = repository.currentWork(workId) ?: return@launch
            if (!work.isDeleted) _writeMessage.value = ReaderWorkActions(context).openOriginal(work)
        }
    }

    fun setFontSizePercent(percent: Int) {
        val clamped = percent.coerceIn(
            ReaderSettingsMapper.MIN_FONT_PERCENT,
            ReaderSettingsMapper.MAX_FONT_PERCENT
        )
        updatePreferences { prefs ->
            prefs.copy(fontSizePercent = clamped, publisherStyles = false)
        }
        viewModelScope.launch {
            settingsRepository.updateReaderFontPt(
                ReaderSettingsMapper.fontPtFromPercent(clamped)
            )
            settingsRepository.updateReaderCustomize(true)
        }
    }

    fun setColorTheme(theme: ReaderColorTheme) {
        updatePreferences { prefs ->
            prefs.copy(theme = theme, publisherStyles = false)
        }
        viewModelScope.launch {
            settingsRepository.updateReaderTheme(
                ReaderSettingsMapper.toReaderThemeSetting(theme)
            )
            settingsRepository.updateMatchAppReaderTheme(false)
            settingsRepository.updateReaderCustomize(true)
        }
    }

    fun setKeepScreenAwake(on: Boolean) {
        viewModelScope.launch { settingsRepository.updateKeepScreenAwake(on) }
    }

    fun setScrollMode(scroll: Boolean) {
        updatePreferences { it.copy(scroll = scroll, publisherStyles = false) }
        viewModelScope.launch {
            settingsRepository.updateReaderMode(if (scroll) ReaderMode.Scroll else ReaderMode.Paged)
            settingsRepository.updateReaderCustomize(true)
        }
    }

    fun setTwoPage(twoPage: Boolean) {
        updatePreferences {
            it.copy(columnCount = if (twoPage) 2 else 1, scroll = false, publisherStyles = false)
        }
        viewModelScope.launch {
            settingsRepository.updateReaderMode(ReaderMode.Paged)
            settingsRepository.updateReaderTwoPage(twoPage)
            settingsRepository.updateReaderCustomize(true)
        }
    }

    fun setBold(bold: Boolean) {
        updatePreferences { it.copy(bold = bold, publisherStyles = false) }
        viewModelScope.launch {
            settingsRepository.updateReaderBoldText(bold)
            settingsRepository.updateReaderCustomize(true)
        }
    }

    fun setLetterSpacing(em: Double) {
        val clamped = em.coerceIn(0.0, 0.5)
        updatePreferences { it.copy(letterSpacingEm = clamped, publisherStyles = false) }
        viewModelScope.launch {
            settingsRepository.updateReaderLetterSpacing(clamped)
            settingsRepository.updateReaderCustomize(true)
        }
    }

    fun setWordSpacing(em: Double) {
        val clamped = em.coerceIn(0.0, 1.0)
        updatePreferences { it.copy(wordSpacingEm = clamped, publisherStyles = false) }
        viewModelScope.launch {
            settingsRepository.updateReaderWordSpacing(clamped)
            settingsRepository.updateReaderCustomize(true)
        }
    }

    fun setSpeechRate(rate: Float) {
        viewModelScope.launch { settingsRepository.updateSpeechRate(rate) }
    }

    fun setSpeechVoiceIdentifier(id: String?) {
        viewModelScope.launch { settingsRepository.updateSpeechVoiceIdentifier(id) }
    }

    fun setSpeechPitch(pitch: Float) {
        val clamped = pitch.coerceIn(0.5f, 2.0f)
        updatePreferences { it.copy(speechPitch = clamped) }
    }

    fun setFontFamily(family: String?) {
        updatePreferences { it.copy(fontFamily = family, publisherStyles = false) }
        viewModelScope.launch {
            settingsRepository.updateReaderFontId(family ?: "system")
            settingsRepository.updateReaderCustomize(true)
        }
    }

    private fun updatePreferences(transform: (ReaderPreferences) -> ReaderPreferences) {
        updateReading { reading ->
            reading.copy(preferences = transform(reading.preferences))
        }
    }

    private fun updateReading(transform: (ReaderUiState.Reading) -> ReaderUiState.Reading) {
        val current = _state.value as? ReaderUiState.Reading ?: return
        _state.value = transform(current)
    }

    companion object {
        fun factory(
            repository: ReaderRepository,
            readingLogService: ReadingLogService,
            settingsRepository: SettingsRepository,
            annotationRepository: AnnotationRepository,
            workId: String,
            writeRepository: AO3WriteRepository? = null
        ): ViewModelProvider.Factory =
            viewModelFactory {
                initializer {
                    ReaderViewModel(
                        repository,
                        readingLogService,
                        settingsRepository,
                        annotationRepository,
                        workId,
                        writeRepository
                    )
                }
            }
    }
}
