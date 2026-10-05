package io.github.cidy02.kudos.reader

import android.icu.text.BreakIterator
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.search.SearchIterator
import org.readium.r2.shared.publication.services.search.isSearchable
import org.readium.r2.shared.publication.services.search.search

data class ReaderSearchHit(val id: Int, val locator: Locator) {
    val before: String
        get() {
            val full = locator.text.before.orEmpty()
            if (full.length <= 70) return full
            // Swift suffix(70) counts whole characters; don't split a surrogate
            // pair or a joined emoji when clipping the Kotlin string.
            val characters = BreakIterator.getCharacterInstance().apply { setText(full) }
            var boundary = characters.last()
            repeat(70) {
                boundary = characters.previous()
                if (boundary == BreakIterator.DONE) return full
            }
            return if (boundary == 0) full else "…" + full.substring(boundary)
        }
    val match: String get() = locator.text.highlight.orEmpty()
    val after: String get() = locator.text.after.orEmpty()
    val chapterTitle: String get() = locator.title.orEmpty()
    // Copy the real passage, without the display-only leading ellipsis.
    val copyText: String get() = locator.text.before.orEmpty() + match + after
}

enum class ReaderSearchPhase { Idle, Searching, Done, Failed }

data class ReaderSearchState(
    val phase: ReaderSearchPhase = ReaderSearchPhase.Idle,
    val hits: List<ReaderSearchHit> = emptyList(),
    val error: String = "",
    val hasMore: Boolean = false,
    val isLoadingMore: Boolean = false,
    val isSearchingCurrentChapter: Boolean = false
)

@OptIn(ExperimentalReadiumApi::class)
object ReaderSearch {
    fun isAvailable(publication: Publication): Boolean = publication.isSearchable

    suspend fun open(publication: Publication, query: String): SearchIterator? =
        if (query.isBlank() || !publication.isSearchable) null else publication.search(query.trim())
}

/**
 * Sheet-owned search session. One coroutine owns each iterator, including close(),
 * so next() calls cannot overlap. Query changes cancel it immediately, before debounce.
 * Iterator creation/scanning runs off the UI thread; state is published on the owner scope.
 */
@OptIn(ExperimentalReadiumApi::class)
class ReaderSearchModel(
    private val scope: CoroutineScope,
    private val openIterator: suspend (String) -> SearchIterator?,
    private val scanDispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    private val _state = MutableStateFlow(ReaderSearchState())
    val state = _state.asStateFlow()
    private var searchJob: Job? = null
    private var pageRequests: Channel<Unit>? = null

    fun search(query: String, currentChapterHrefKey: String?, debounce: Boolean = true) {
        reset()
        val trimmed = query.trim()
        // iOS accepts one-character queries; only empty/whitespace is excluded.
        if (trimmed.isEmpty()) return
        val requests = Channel<Unit>(Channel.CONFLATED)
        pageRequests = requests
        searchJob = scope.launch {
            if (debounce) delay(350)
            _state.value = ReaderSearchState(phase = ReaderSearchPhase.Searching)
            // Keep acquisition inside the same IO block as finally: if cancellation
            // races with openIterator returning, the newly opened iterator still closes.
            try {
                withContext(scanDispatcher) {
                    val iterator = openIterator(trimmed) ?: return@withContext
                    try {
                        var hits = emptyList<ReaderSearchHit>()
                        var coveredCurrent = currentChapterHrefKey == null
                        var autoPagesFetched = 0
                        while (true) {
                            currentCoroutineContext().ensureActive()
                            val page = iterator.next()
                            currentCoroutineContext().ensureActive()
                            val failure = page.failureOrNull()
                            if (failure != null) {
                                publish(
                                    ReaderSearchState(
                                        phase = if (hits.isEmpty()) ReaderSearchPhase.Failed else ReaderSearchPhase.Done,
                                        hits = hits,
                                        error = failure.message
                                    )
                                )
                                return@withContext
                            }
                            val locators = page.getOrNull()?.locators.orEmpty()
                            if (locators.isEmpty()) {
                                publish(ReaderSearchState(phase = ReaderSearchPhase.Done, hits = hits))
                                return@withContext
                            }
                            val base = hits.size
                            hits = hits + locators.mapIndexed { offset, locator ->
                                ReaderSearchHit(base + offset, locator)
                            }
                            if (!coveredCurrent && locators.any {
                                    ReaderSectionBuilder.hrefKey(it.href.toString()) == currentChapterHrefKey
                                }) {
                                coveredCurrent = true
                            }
                            val autoContinue = !coveredCurrent && autoPagesFetched < 40
                            publish(
                                ReaderSearchState(
                                    phase = ReaderSearchPhase.Done,
                                    hits = hits,
                                    hasMore = true,
                                    isLoadingMore = autoContinue,
                                    isSearchingCurrentChapter = !coveredCurrent
                                )
                            )
                            if (autoContinue) {
                                autoPagesFetched++
                            } else {
                                requests.receive()
                            }
                        }
                    } finally {
                        iterator.close()
                    }
                }
                // Android returns null for an unavailable search service, rather
                // than iOS's failure outcome. The fan pill is disabled for it.
                if (_state.value.phase == ReaderSearchPhase.Searching) {
                    _state.value = ReaderSearchState(phase = ReaderSearchPhase.Failed)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                currentCoroutineContext().ensureActive()
                val previous = _state.value
                _state.value = previous.copy(
                    phase = if (previous.hits.isEmpty()) ReaderSearchPhase.Failed else ReaderSearchPhase.Done,
                    error = error.localizedMessage.orEmpty(),
                    hasMore = false,
                    isLoadingMore = false,
                    isSearchingCurrentChapter = false
                )
            }
        }
    }

    private suspend fun publish(state: ReaderSearchState) = withContext(scope.coroutineContext.minusKey(Job)) {
        currentCoroutineContext().ensureActive()
        _state.value = state
    }

    fun loadMoreIfNeeded(id: Int) {
        val current = _state.value
        if (!current.hasMore || current.isLoadingMore || id < current.hits.size - 5) return
        // Set synchronously, before another visible row can request the same page.
        _state.value = current.copy(isLoadingMore = true)
        pageRequests?.trySend(Unit)
    }

    fun reset() {
        searchJob?.cancel()
        searchJob = null
        pageRequests?.close()
        pageRequests = null
        _state.value = ReaderSearchState()
    }
}
