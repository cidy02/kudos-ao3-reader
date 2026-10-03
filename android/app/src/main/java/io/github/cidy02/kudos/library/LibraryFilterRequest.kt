package io.github.cidy02.kudos.library

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Search's "Fandoms in Your Library" and "Your Tags" rows switch to Library
 * filtered to that name. Library's filter state lives in its own ViewModel,
 * so the request is handed across the tab here and consumed once.
 */
object LibraryFilterRequest {
    private val tickFlow = MutableStateFlow(0)
    val tick: StateFlow<Int> = tickFlow.asStateFlow()

    var fandom: String? = null
        private set
    var userTagName: String? = null
        private set

    fun requestFandom(name: String) {
        fandom = name
        userTagName = null
        tickFlow.value = tickFlow.value + 1
    }

    fun requestUserTag(name: String) {
        userTagName = name
        fandom = null
        tickFlow.value = tickFlow.value + 1
    }

    fun takeFandom(): String? = fandom.also { fandom = null }

    fun takeUserTag(): String? = userTagName.also { userTagName = null }
}
