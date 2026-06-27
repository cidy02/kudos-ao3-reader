package io.github.cidy02.kudos.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class AccountViewModel(
    private val authRepository: AO3AuthRepository
) : ViewModel() {
    val uiState: StateFlow<AccountUiState> = authRepository.state
        .map { AccountUiState(authState = it) }
        .stateIn(
            viewModelScope,
            SharingStarted.WhileSubscribed(5_000),
            AccountUiState()
        )

    init {
        viewModelScope.launch { authRepository.restoreSession() }
    }

    fun logout() {
        viewModelScope.launch { authRepository.logout() }
    }

    companion object {
        fun factory(authRepository: AO3AuthRepository): ViewModelProvider.Factory {
            return object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return AccountViewModel(authRepository) as T
                }
            }
        }
    }
}

class AccountListViewModel(
    private val type: AccountListType,
    private val repository: AccountListRepository
) : ViewModel() {
    private val mutableState = kotlinx.coroutines.flow.MutableStateFlow<AccountListUiState>(
        AccountListUiState.Loading
    )
    val uiState: StateFlow<AccountListUiState> = mutableState

    init {
        load(1)
    }

    fun load(page: Int) {
        viewModelScope.launch {
            mutableState.value = AccountListUiState.Loading
            mutableState.value = when (val result = repository.load(type, page)) {
                is AO3Result.Success -> AccountListUiState.Loaded(result.value)
                is AO3Result.Failure -> {
                    if (result.error == AO3Error.AuthenticationRequired) {
                        AccountListUiState.AuthRequired
                    } else {
                        AccountListUiState.Failed(result.error.displayMessage())
                    }
                }
            }
        }
    }

    companion object {
        fun factory(
            type: AccountListType,
            repository: AccountListRepository
        ): ViewModelProvider.Factory {
            return object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return AccountListViewModel(type, repository) as T
                }
            }
        }
    }
}

private fun AO3Error.displayMessage(): String {
    return when (this) {
        AO3Error.BadRequest -> "AO3 rejected the request."
        AO3Error.AuthenticationRequired -> "Log in to AO3 again."
        AO3Error.Forbidden -> "AO3 denied access to this account page."
        AO3Error.NotFound -> "AO3 could not find this account page."
        is AO3Error.Http -> "AO3 returned HTTP $statusCode."
        is AO3Error.Network -> message
        is AO3Error.Overloaded -> "AO3 is busy. Try again shortly."
        is AO3Error.Parse -> message
        is AO3Error.RateLimited -> "AO3 is rate-limiting requests. Try again shortly."
        is AO3Error.Server -> "AO3 had a server problem (HTTP $statusCode)."
        is AO3Error.Validation -> message
    }
}
