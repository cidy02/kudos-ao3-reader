package io.github.cidy02.kudos.account

import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionPeoplePage
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionShow
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/** One navigation entry and session, like iOS AO3CollectionDetailView's kept state. */
internal class AO3CollectionDetailViewModel(
    private val slug: String,
    private val repository: AO3CollectionDetailRepository
) : ViewModel() {
    private val generation = repository.authRepository.generation.value
    val segment = mutableStateOf(AO3CollectionSegment.Works)
    val listState = LazyListState()
    var show by mutableStateOf<AO3CollectionShow?>(null)
        private set
    var worksPage by mutableStateOf<AO3SearchPage?>(null)
        private set
    var bookmarksPage by mutableStateOf<AO3SearchPage?>(null)
        private set
    var peoplePage by mutableStateOf<AO3CollectionPeoplePage?>(null)
        private set
    var phase by mutableStateOf<AO3CollectionDetailPhase>(AO3CollectionDetailPhase.Idle)
        private set
    private var loaded = emptySet<AO3CollectionSegment>()
    private var failures = emptyMap<AO3CollectionSegment, String>()
    private var request = 0
    private var seenChange = repository.collectionRevision(slug)

    fun currentPage(target: AO3CollectionSegment): Int = when (target) {
        AO3CollectionSegment.Works -> worksPage?.currentPage ?: 1
        AO3CollectionSegment.Bookmarks -> bookmarksPage?.currentPage ?: 1
        AO3CollectionSegment.People -> peoplePage?.currentPage ?: 1
    }

    suspend fun loadOnAppear(changedRevision: Int = repository.collectionRevision(slug)) {
        if (seenChange != changedRevision) {
            seenChange = changedRevision
            loaded = emptySet()
            failures = emptyMap()
        }
        val failure = failures[segment.value]
        when {
            failure != null -> phase = AO3CollectionDetailPhase.Failed(failure)
            segment.value in loaded -> phase = AO3CollectionDetailPhase.Loaded
            else -> load(segment.value)
        }
    }

    suspend fun refresh() {
        loaded = loaded - segment.value
        failures = failures - segment.value
        load(segment.value)
    }

    // Called by a visible composition's cancellable effect or refresh, never by a background job.
    suspend fun load(target: AO3CollectionSegment, page: Int = currentPage(target)) {
        if (generation != repository.authRepository.generation.value) return
        val mine = ++request
        fun current(): Boolean = mine == request && generation == repository.authRepository.generation.value
        failures = failures - target
        phase = AO3CollectionDetailPhase.Loading
        if (show == null) {
            val result = repository.getCollectionShow(slug)
            currentCoroutineContext().ensureActive()
            if (!current()) return
            when (result) {
                is AO3Result.Success -> show = result.value
                is AO3Result.Failure -> {
                    failures = failures + (target to result.error.displayMessage())
                    phase = AO3CollectionDetailPhase.Failed(result.error.displayMessage())
                    return
                }
            }
        }
        val result = when (target) {
            AO3CollectionSegment.Works -> repository.getCollectionWorks(slug, page)
            AO3CollectionSegment.Bookmarks -> repository.getCollectionBookmarks(slug, page)
            AO3CollectionSegment.People -> repository.getCollectionPeople(slug, page)
        }
        currentCoroutineContext().ensureActive()
        if (!current()) return
        when (result) {
            is AO3Result.Failure -> {
                failures = failures + (target to result.error.displayMessage())
                phase = AO3CollectionDetailPhase.Failed(result.error.displayMessage())
            }
            is AO3Result.Success -> {
                when (target) {
                    AO3CollectionSegment.Works -> worksPage = result.value as AO3SearchPage
                    AO3CollectionSegment.Bookmarks -> bookmarksPage = result.value as AO3SearchPage
                    AO3CollectionSegment.People -> peoplePage = result.value as AO3CollectionPeoplePage
                }
                loaded = loaded + target
                phase = AO3CollectionDetailPhase.Loaded
            }
        }
    }
}
