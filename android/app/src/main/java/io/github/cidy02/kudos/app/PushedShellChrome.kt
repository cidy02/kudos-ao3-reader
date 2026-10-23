package io.github.cidy02.kudos.app

import androidx.compose.ui.graphics.Color
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
    var wholeTitleOnly by mutableStateOf(false)
    var pageBackground by mutableStateOf<Color?>(null)
    var onBack by mutableStateOf<(() -> Unit)?>(null)
    var trailingContent by mutableStateOf<(@Composable RowScope.() -> Unit)?>(null)
    /**
     * Which of a route's own pages is showing, where one route holds several (Settings and its
     * pages). The shell keeps "the top row is scrolled away" by route, so without this a page
     * opened from a scrolled one started with its row hidden and no Back.
     */
    var scrollKey by mutableStateOf<String?>(null)

    /**
     * The screens composed now, in order of arrival, each with how to show its values. During a
     * transition two pushed screens are composed at once: the newer one holds the row whatever
     * the older does on its way out, and gets nothing wiped when the older leaves. A single
     * shared slot let the leaving screen clear the newcomer's buttons, and a screen whose
     * arguments never change again (so it never registered twice) stayed without them.
     * Re-putting a key keeps its place, so an update does not make an older screen the newest.
     */
    private val screens = LinkedHashMap<Any, () -> Unit>()

    internal fun register(screen: Any, show: () -> Unit) {
        screens[screen] = show
        showNewest()
    }

    internal fun leave(screen: Any) {
        screens.remove(screen)
        showNewest()
    }

    /**
     * Which screen holds the row now. It changes when a screen takes over, across routes or
     * inside one (an editor opened from a form). The shell watches it to bring back a row the
     * previous holder had scrolled away, with Back and the newcomer's own buttons on it.
     */
    var holder by mutableStateOf<Any?>(null)
        private set

    private fun showNewest() {
        val newest = screens.entries.lastOrNull()
        holder = newest?.key
        newest?.value?.invoke() ?: reset()
    }

    private fun reset() {
        mounted = false
        hideTabBar = false
        hasSubjectHeader = null
        customTitle = null
        wholeTitleOnly = false
        pageBackground = null
        onBack = null
        trailingContent = null
        scrollKey = null
    }
}

val LocalPushedShellChrome = staticCompositionLocalOf { PushedShellChrome() }

@Composable
fun ProvidePushedShellChrome(
    chrome: PushedShellChrome = LocalPushedShellChrome.current,
    hasSubjectHeader: Boolean? = true,
    hideTabBar: Boolean = false,
    customTitle: String? = null,
    wholeTitleOnly: Boolean = false,
    onBack: (() -> Unit)? = null,
    trailingContent: (@Composable RowScope.() -> Unit)? = null,
    scrollKey: String? = null,
    pageBackground: Color? = null
) {
    val screen = remember { Any() }
    SideEffect {
        chrome.register(screen) {
            chrome.mounted = true
            chrome.hideTabBar = hideTabBar
            chrome.hasSubjectHeader = hasSubjectHeader
            chrome.customTitle = customTitle
            chrome.wholeTitleOnly = wholeTitleOnly
            chrome.pageBackground = pageBackground
            chrome.onBack = onBack
            chrome.trailingContent = trailingContent
            chrome.scrollKey = scrollKey
        }
    }
    DisposableEffect(chrome) {
        onDispose { chrome.leave(screen) }
    }
}
