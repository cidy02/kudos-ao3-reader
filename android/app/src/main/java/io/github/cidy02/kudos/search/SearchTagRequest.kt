package io.github.cidy02.kudos.search

import androidx.compose.runtime.staticCompositionLocalOf
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class SearchTagRequest(
    val field: SearchSubjectField,
    val value: String,
    val isFreshTabJump: Boolean
)

/** Hands one tapped AO3 tag to the retained Search destination. */
object SearchTagRequests {
    private val tickFlow = MutableStateFlow(0)
    val tick: StateFlow<Int> = tickFlow.asStateFlow()

    private var pending: SearchTagRequest? = null

    fun request(field: SearchSubjectField, value: String, isFreshTabJump: Boolean) {
        pending = SearchTagRequest(field, value, isFreshTabJump)
        tickFlow.value += 1
    }

    fun take(): SearchTagRequest? = pending.also { pending = null }
}

val LocalTagSearch = staticCompositionLocalOf<(SearchSubjectField, String) -> Unit> {
    { _, _ -> }
}
