package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.network.ao3.writing.AO3CollectionOffer
import io.github.cidy02.kudos.network.ao3.writing.AO3CollectionAccess
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkForm
import io.github.cidy02.kudos.network.ao3.writing.trimWritingTag
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

internal data class WritingCollectionSearch(val query: String = "", val offers: List<AO3CollectionOffer> = emptyList())

/** iOS's query task: clear immediately, one read after 300 ms, silent failures, no prefetch/cache. */
internal class WritingCollectionsSearchState(
    private val repository: AO3TagAutocompleteRepository?, private val scope: CoroutineScope
) {
    private val mutable = MutableStateFlow(WritingCollectionSearch())
    val state = mutable.asStateFlow()
    private var request: Job? = null
    private var active = true

    fun type(query: String) {
        if (!active || query == state.value.query) return
        request?.cancel()
        mutable.value = WritingCollectionSearch(query)
        if (trimWritingTag(query).isEmpty() || repository == null) return
        request = scope.launch {
            try {
                delay(300)
                val result = repository.openCollections(query)
                currentCoroutineContext().ensureActive()
                if (active && state.value.query == query && result is AO3Result.Success)
                    mutable.value = WritingCollectionSearch(query, result.value)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                currentCoroutineContext().ensureActive() // iOS silently ignores search failures.
            }
        }
    }
    fun close() { active = false; request?.cancel() }
}

internal fun collectionStateText(access: AO3CollectionAccess): String {
    var text = when {
        !access.isOpen -> "Closed to new works"
        !access.isDescribed -> "Open to new works (it may be moderated or unrevealed)"
        access.isModerated -> "Moderated (a maintainer approves the work)"
        else -> "Open"
    }
    if (access.isUnrevealed) text += " · Unrevealed until reveal"
    if (access.isAnonymous) text += " · Anonymous"
    return text
}

internal fun seriesPickerSubtitle(form: AO3WorkForm): String {
    form.series.firstOrNull { it.isSelected }?.let { return "Saving adds ${form.title} to ${it.title}" }
    trimWritingTag(form.newSeriesTitle).takeIf { it.isNotEmpty() }?.let {
        return "Saving creates $it with ${form.title} in it"
    }
    return if (form.currentSeries.isNotEmpty()) {
        "${form.title} is part of " + if (form.currentSeries.size == 1) "one series" else "${form.currentSeries.size} series"
    } else "Choose a series to add ${form.title} to"
}
