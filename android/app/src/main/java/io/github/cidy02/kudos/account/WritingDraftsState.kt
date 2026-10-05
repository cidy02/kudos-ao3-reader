package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writing.AO3DraftsPage
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Replace these two destinations together when Android's native work editor lands. */
object WritingWorkDestination {
    fun url(workId: Long? = null): String = if (workId == null) "${AO3Constants.BASE_URL}/works/new"
        else "${AO3Constants.BASE_URL}/works/$workId/edit"
}

internal data class WritingDraftsUiState(
    val loading: Boolean = false,
    val drafts: AO3DraftsPage? = null,
    val error: String? = null
)

/** Owned by the visible page/session composition; construction makes no request. */
internal class WritingDraftsState(private val repository: WritingDraftsRepository, private val page: Int) {
    private val mutableState = MutableStateFlow(WritingDraftsUiState())
    val state = mutableState.asStateFlow()

    suspend fun load() {
        if (state.value.loading) return
        val generation = repository.authRepository.generation.value
        mutableState.value = WritingDraftsUiState(loading = true)
        try {
            val result = repository.load(page)
            currentCoroutineContext().ensureActive()
            if (generation != repository.authRepository.generation.value) return
            mutableState.value = when (result) {
                is AO3Result.Success -> WritingDraftsUiState(drafts = result.value)
                is AO3Result.Failure -> WritingDraftsUiState(error = if (result.error == AO3Error.AuthenticationRequired)
                    "Log in to AO3 first." else result.error.moderationMessage())
            }
        } finally {
            if (state.value.loading) mutableState.value = WritingDraftsUiState()
        }
    }
}
