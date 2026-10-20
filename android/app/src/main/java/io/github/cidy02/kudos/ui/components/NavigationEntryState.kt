package io.github.cidy02.kudos.ui.components

import androidx.lifecycle.viewmodel.initializer
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.viewModelFactory

/** Small remote-page values live with their navigation entry, not its disposable composition. */
@Composable
internal fun <T> navigationEntryState(key: String, initial: () -> T): MutableState<T> {
    val model: NavigationEntryState<T> = viewModel(
        key = key,
        factory = viewModelFactory { initializer { NavigationEntryState(initial()) } }
    )
    return model.value
}

internal class NavigationEntryState<T>(initial: T) : ViewModel() {
    val value = mutableStateOf(initial)
}
