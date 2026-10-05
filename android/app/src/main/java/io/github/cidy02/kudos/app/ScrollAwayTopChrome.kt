package io.github.cidy02.kudos.app

import androidx.compose.runtime.mutableIntStateOf
import kotlin.math.abs

/**
 * T-349. Scrolling down hides the top chrome; scrolling back up, or returning to
 * the top, shows it. Android's navigation bar stays put (iOS's tab bar shrinks on the same flag).
 *
 * Offsets are in one unit. Callers pass dp so the `44` threshold matches iOS
 * points. Direction uses the raw delta, not a value adjusted for insets: on iOS
 * an inset-based reading treated the bar's own hide as a scroll and toggled
 * forever at the bottom of a list.
 */
object ScrollAwayTopChrome {
    fun hides(hidden: Boolean, from: Float, to: Float, fromTop: Float): Boolean {
        if (fromTop <= 44f) return false
        val delta = to - from
        if (delta > 1f) return true
        if (delta < -6f) return false
        return hidden
    }
}

/**
 * One scroll-direction flag per shell route for the top chrome, and how far the content has
 * moved. [revision] is what Compose observes.
 */
/** Content this far from the top counts as scrolled. Small drift in the running sum stays under it. */
private const val SCROLLED_DP = 8f

class ShellChromeState {
    private val offsetDp = HashMap<String, Float>()
    private val hiddenByRoute = HashMap<String, Boolean>()
    private val revisionState = mutableIntStateOf(0)

    fun isHidden(route: String?): Boolean {
        if (revisionState.intValue < 0) return false
        if (route == null) return false
        return hiddenByRoute[route] == true
    }

    /** True once the content has left the top: a list is running under the top chrome. */
    fun isScrolled(route: String?): Boolean {
        if (revisionState.intValue < 0) return false
        if (route == null) return false
        return (offsetDp[route] ?: 0f) > SCROLLED_DP
    }

    /**
     * [deltaDp] is the change in content offset: positive scrolls down.
     * [atTop] forces the near-top rule, which always shows the chrome.
     */
    fun onContentDelta(route: String, deltaDp: Float, atTop: Boolean) {
        val from = offsetDp[route] ?: 0f
        val to = if (atTop) 0f else (from + deltaDp).coerceAtLeast(0f)
        val fromTop = if (atTop) 0f else to
        offsetDp[route] = to
        val next = ScrollAwayTopChrome.hides(hiddenByRoute[route] == true, from, to, fromTop)
        val scrolledChanged = (from > SCROLLED_DP) != (to > SCROLLED_DP)
        if (hiddenByRoute[route] == next && !scrolledChanged) return
        hiddenByRoute[route] = next
        revisionState.intValue = revisionState.intValue + 1
    }

    /**
     * Compose nested-scroll sign: a negative [consumedYPx] is a downward scroll
     * (content offset grows), the same convention as a collapsing toolbar.
     * Leftover positive [availableYPx] while moving toward the start means the
     * list is at the top.
     */
    fun onNestedScroll(route: String, consumedYPx: Float, availableYPx: Float, density: Float) {
        if (density <= 0f) return
        val towardStart = consumedYPx > 0f || (consumedYPx == 0f && availableYPx > 1f)
        val atTop = towardStart && availableYPx > 1f
        val deltaDp = if (atTop) 0f else -consumedYPx / density
        if (!atTop && abs(deltaDp) < 0.01f) return
        onContentDelta(route, deltaDp, atTop)
    }
}
