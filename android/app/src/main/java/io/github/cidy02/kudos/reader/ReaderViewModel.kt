package io.github.cidy02.kudos.reader

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import io.github.cidy02.kudos.data.preferences.SettingsRepository
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
 *
 * Initial preferences come from [ReaderRepository.open] (DataStore snapshot).
 * Display sheet changes update the in-session snapshot and persist via
 * [SettingsRepository] so they survive leaving the reader.
 */
class ReaderViewModel(
    private val repository: ReaderRepository,
    private val settingsRepository: SettingsRepository,
    private val workId: String
) : ViewModel() {

    private val _state = MutableStateFlow<ReaderUiState>(ReaderUiState.Loading)
    val state: StateFlow<ReaderUiState> = _state.asStateFlow()

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
        }
    }

    /** Called by the navigator host on each meaningful location change. */
    fun onProgress(progress: ReaderProgress) {
        saver.onProgress(progress)
        updateReading { it.copy(liveProgress = progress) }
    }

    /** Persist any pending progress immediately (reader close/background). */
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

    /** Mark the backing EPUB missing after a confirmed FileMissing error. */
    fun markEpubMissing() {
        viewModelScope.launch { repository.markEpubMissing(workId) }
    }

    /**
     * Font size (% of publisher base). Clamped to mapper bounds, applied
     * in-session, and persisted as `readerFontPt` (18pt base) + customize on.
     */
    fun setFontSizePercent(percent: Int) {
        val clamped = percent.coerceIn(
            ReaderSettingsMapper.MIN_FONT_PERCENT,
            ReaderSettingsMapper.MAX_FONT_PERCENT
        )
        updatePreferences { prefs ->
            prefs.copy(
                fontSizePercent = clamped,
                // User overrides should win over pure publisher styles.
                publisherStyles = false
            )
        }
        viewModelScope.launch {
            settingsRepository.updateReaderFontPt(
                ReaderSettingsMapper.fontPtFromPercent(clamped)
            )
            settingsRepository.updateReaderCustomize(true)
        }
    }

    /**
     * Reader colour theme (light / sepia / dark). Applied in-session and
     * persisted as `readerTheme` with `matchAppReaderTheme = false` so the
     * choice is not overridden by app theme on reopen.
     */
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
            workId: String
        ): ViewModelProvider.Factory =
            viewModelFactory {
                initializer {
                    ReaderViewModel(repository, settingsRepository, workId)
                }
            }
    }
}
