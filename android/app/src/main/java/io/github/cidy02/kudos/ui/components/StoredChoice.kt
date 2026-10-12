package io.github.cidy02.kudos.ui.components

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext

/**
 * A choice of layout kept between launches, as iOS keeps its `@AppStorage` ones, under the
 * name iOS uses ("account.displayMode"). It lives in a small file of its own: it is a habit
 * of this device, not a setting, and is in no backup (iOS's is not either).
 */
@Composable
inline fun <reified T : Enum<T>> rememberStoredChoice(key: String, default: T): MutableState<T> {
    val context = LocalContext.current
    return remember(context, key) {
        val preferences = context.getSharedPreferences("layout-choices", Context.MODE_PRIVATE)
        val state = mutableStateOf(
            runCatching { enumValueOf<T>(preferences.getString(key, null).orEmpty()) }.getOrDefault(default)
        )
        object : MutableState<T> by state {
            override var value: T
                get() = state.value
                set(choice) {
                    state.value = choice
                    preferences.edit().putString(key, choice.name).apply()
                }
        }
    }
}
