package io.github.cidy02.kudos.reader

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import io.github.cidy02.kudos.reader.settings.ReaderSettingsMapper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Drives the reader screen: resolves the work, exposes [ReaderUiState], and
 * debounces/persists progress reported by the Readium navigator host.
 */
class ReaderViewModel(
    private val repository: ReaderRepository,
    private val settingsRepository: SettingsRepository,
    private val annotationRepository: AnnotationRepository,
    private val workId: String,
    private val writeRepository: AO3WriteRepository? = null
) : ViewModel() {

    private val _state = MutableStateFlow<ReaderUiState>(ReaderUiState.Loading)
    val state: StateFlow<ReaderUiState> = _state.asStateFlow()

    private val _writeMessage = MutableStateFlow<String?>(null)
    val writeMessage: StateFlow<String?> = _writeMessage.asStateFlow()

    private val _searchHits = MutableStateFlow<List<ReaderSearchHit>>(emptyList())
    val searchHits: StateFlow<List<ReaderSearchHit>> = _searchHits.asStateFlow()

    private val _searchLoading = MutableStateFlow(false)
    val searchLoading: StateFlow<Boolean> = _searchLoading.asStateFlow()

    private var autoFinishedThisSession = false
    private var spineCountForEof = 0

    private val saver = ReaderProgressSaver(viewModelScope) { progress ->
        repository.saveProgress(workId, progress)
    }

    init {
        load()
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
                    preferences = result.preferences,
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

    /** Called by the navigator host on each meaningful location change. */
    fun onProgress(progress: ReaderProgress) {
        saver.onProgress(progress)
        updateReading { it.copy(liveProgress = progress) }
        maybeAutoFinish(progress)
    }

    private fun maybeAutoFinish(progress: ReaderProgress) {
        if (autoFinishedThisSession) return
        val reading = _state.value as? ReaderUiState.Reading ?: return
        if (reading.finished || !reading.endOfWork.canMarkFinished) return
        if (!EndOfWorkActions.isAtEndOfPublication(progress, spineCountForEof)) return
        autoFinishedThisSession = true
        markFinished()
    }

    fun flushProgress() {
        viewModelScope.launch { saver.flush() }
    }

    fun markFinished() {
        viewModelScope.launch {
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
        viewModelScope.launch {
            annotationRepository.addOrRecolorHighlight(
                workId = workId,
                locatorString = locatorString,
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

    fun deleteAnnotation(id: String) {
        viewModelScope.launch {
            annotationRepository.deleteAnnotation(id)
        }
    }

    fun updateNote(id: String, note: String) {
        viewModelScope.launch {
            annotationRepository.updateNote(id, note)
        }
    }

    fun giveKudos() {
        val ao3Id = (_state.value as? ReaderUiState.Reading)?.endOfWork?.workId ?: return
        val writes = writeRepository ?: return
        viewModelScope.launch {
            when (val result = writes.giveKudos(ao3Id)) {
                is AO3Result.Success -> _writeMessage.value = result.value.message
                is AO3Result.Failure -> _writeMessage.value = when (val err = result.error) {
                    is io.github.cidy02.kudos.network.ao3.AO3Error.Network -> err.message
                    is io.github.cidy02.kudos.network.ao3.AO3Error.Validation -> err.message
                    is io.github.cidy02.kudos.network.ao3.AO3Error.AuthenticationRequired ->
                        "Sign in to give kudos."
                    else -> "Couldn't give kudos."
                }
            }
        }
    }

    fun clearWriteMessage() {
        _writeMessage.value = null
    }

    fun runSearch(publication: org.readium.r2.shared.publication.Publication, query: String) {
        viewModelScope.launch {
            _searchLoading.value = true
            _searchHits.value = ReaderSearch.search(publication, query)
            _searchLoading.value = false
        }
    }

    fun clearSearch() {
        _searchHits.value = emptyList()
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
        val clamped = rate.coerceIn(0.5f, 2.0f)
        updatePreferences { it.copy(speechRate = clamped) }
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
            settingsRepository: SettingsRepository,
            annotationRepository: AnnotationRepository,
            workId: String,
            writeRepository: AO3WriteRepository? = null
        ): ViewModelProvider.Factory =
            viewModelFactory {
                initializer {
                    ReaderViewModel(
                        repository,
                        settingsRepository,
                        annotationRepository,
                        workId,
                        writeRepository
                    )
                }
            }
    }
}
