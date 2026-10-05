package io.github.cidy02.kudos.app

import androidx.compose.foundation.layout.RowScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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

    /**
     * The screen whose values these are. When one pushed screen opens another, the old one
     * leaves the composition after the new one has registered; without this its farewell reset
     * wiped the newcomer's buttons, and a screen whose arguments never change again (so its
     * registration is not repeated) stayed without them.
     */
    internal var owner: Any? = null

    fun reset() {
        owner = null
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
    val owner = remember { Any() }
    SideEffect {
        chrome.owner = owner
        chrome.mounted = true
        chrome.hideTabBar = hideTabBar
        chrome.hasSubjectHeader = hasSubjectHeader
        chrome.customTitle = customTitle
        chrome.onBack = onBack
        chrome.trailingContent = trailingContent
    }
    DisposableEffect(chrome) {
        onDispose {
            if (chrome.owner === owner) chrome.reset()
        }
    }
}
