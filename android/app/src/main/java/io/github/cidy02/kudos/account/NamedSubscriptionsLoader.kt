package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscriptionsPage
import io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscriptionsScope
import io.github.cidy02.kudos.network.ao3.displayMessage
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal sealed interface NamedSubscriptionsUiState {
    data object Loading : NamedSubscriptionsUiState
    data object AuthRequired : NamedSubscriptionsUiState
    data class Loaded(val page: AO3NamedSubscriptionsPage) : NamedSubscriptionsUiState
    data class Failed(val message: String) : NamedSubscriptionsUiState
}

/** Owned by the visible scope/page/session composition. Construction makes no request. */
internal class NamedSubscriptionsLoader(
    private val repository: AccountListRepository,
    private val scope: AO3NamedSubscriptionsScope,
    private val page: Int
) {
    private val mutableState = MutableStateFlow<NamedSubscriptionsUiState>(NamedSubscriptionsUiState.Loading)
    val uiState = mutableState.asStateFlow()
    private var request = 0

    suspend fun load() {
        val requested = ++request
        val generation = repository.authRepository.generation.value
        mutableState.value = NamedSubscriptionsUiState.Loading
        val result = repository.loadNamedSubscriptions(scope, page)
        currentCoroutineContext().ensureActive()
        if (requested != request || generation != repository.authRepository.generation.value) return
        mutableState.value = when (result) {
            is AO3Result.Success -> NamedSubscriptionsUiState.Loaded(result.value)
            is AO3Result.Failure -> if (result.error == AO3Error.AuthenticationRequired) {
                NamedSubscriptionsUiState.AuthRequired
            } else NamedSubscriptionsUiState.Failed(result.error.displayMessage())
        }
    }
}
