package io.github.cidy02.kudos.app

import androidx.compose.foundation.layout.RowScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * Pushed screens' top chrome state, generalized from HomeShellChrome and LibraryShellChrome.
 * Screens hand their trailing buttons to the shell so they can float on the same row as the
 * glass back button and scroll away together.
 */
class PushedShellChrome {
    var mounted by mutableStateOf(false)
    var hideTabBar by mutableStateOf(false)
    var hasSubjectHeader by mutableStateOf<Boolean?>(null)
    var customTitle by mutableStateOf<String?>(null)
    var onBack by mutableStateOf<(() -> Unit)?>(null)
    var trailingContent by mutableStateOf<(@Composable RowScope.() -> Unit)?>(null)

    fun reset() {
        mounted = false
        hideTabBar = false
        hasSubjectHeader = null
        customTitle = null
        onBack = null
        trailingContent = null
    }
}

val LocalPushedShellChrome = staticCompositionLocalOf { PushedShellChrome() }

@Composable
fun ProvidePushedShellChrome(
    chrome: PushedShellChrome = LocalPushedShellChrome.current,
    hasSubjectHeader: Boolean? = true,
    hideTabBar: Boolean = false,
    customTitle: String? = null,
    onBack: (() -> Unit)? = null,
    trailingContent: (@Composable RowScope.() -> Unit)? = null
) {
    SideEffect {
        chrome.mounted = true
        chrome.hideTabBar = hideTabBar
        chrome.hasSubjectHeader = hasSubjectHeader
        chrome.customTitle = customTitle
        chrome.onBack = onBack
        chrome.trailingContent = trailingContent
    }
    DisposableEffect(chrome) {
        onDispose {
            chrome.reset()
        }
    }
}
