package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.network.ao3.account.AO3Collection
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

data class AccountUiState(
    val authState: AO3AuthState = AO3AuthState.Restoring
)

sealed interface AccountListUiState {
    data object Loading : AccountListUiState
    data object AuthRequired : AccountListUiState
    data class Loaded(val page: AO3SearchPage) : AccountListUiState
    data class Failed(val message: String) : AccountListUiState
}

val AccountListUiState.works: List<AO3WorkSummary>
    get() = (this as? AccountListUiState.Loaded)?.page?.works.orEmpty()

sealed interface AO3CollectionsUiState {
    data object Loading : AO3CollectionsUiState
    data object AuthRequired : AO3CollectionsUiState
    data class Loaded(val collections: List<AO3Collection>) : AO3CollectionsUiState
    data class Failed(val message: String) : AO3CollectionsUiState
}
