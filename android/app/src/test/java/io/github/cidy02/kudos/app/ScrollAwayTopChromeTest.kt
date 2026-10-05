package io.github.cidy02.kudos.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** T-349: the top chrome scrolls away going down and returns going up or at the top. */
class ScrollAwayTopChromeTest {
    @Test
    fun hidesGoingDownAndReturnsGoingUpOrAtTheTop() {
        // Near the top it always shows, whichever way you scroll.
        assertFalse(ScrollAwayTopChrome.hides(false, 0f, 30f, 30f))
        // Down past the bar hides; a small jitter up keeps it hidden.
        assertTrue(ScrollAwayTopChrome.hides(false, 200f, 210f, 210f))
        assertTrue(ScrollAwayTopChrome.hides(true, 210f, 207f, 207f))
        // A deliberate upward scroll brings it back.
        assertFalse(ScrollAwayTopChrome.hides(true, 400f, 380f, 380f))
        // No offset change (only the inset moved as the bar toggled) changes nothing.
        assertTrue(ScrollAwayTopChrome.hides(true, 500f, 500f, 450f))
        assertFalse(ScrollAwayTopChrome.hides(false, 500f, 500f, 550f))
    }

    @Test
    fun shellRoutesShareOneFlagAndTheTopBringsItBack() {
        val chrome = ShellChromeState()
        chrome.onContentDelta(Routes.Home, deltaDp = 30f, atTop = false)
        assertFalse(chrome.isHidden(Routes.Home))
        chrome.onContentDelta(Routes.Home, deltaDp = 180f, atTop = false)
        assertTrue(chrome.isHidden(Routes.Home))
        // A small upward jitter keeps Home hidden. Library, still at the top, stays shown.
        chrome.onContentDelta(Routes.Home, deltaDp = -3f, atTop = false)
        assertTrue(chrome.isHidden(Routes.Home))
        assertFalse(chrome.isHidden(Routes.Library))
        chrome.onContentDelta(Routes.Home, deltaDp = -20f, atTop = false)
        assertFalse(chrome.isHidden(Routes.Home))
        chrome.onContentDelta(Routes.Home, deltaDp = 200f, atTop = false)
        assertTrue(chrome.isHidden(Routes.Home))
        chrome.onContentDelta(Routes.Home, deltaDp = 0f, atTop = true)
        assertFalse(chrome.isHidden(Routes.Home))
    }

    @Test
    fun aListThatHasLeftTheTopCountsAsScrolledUntilItReturns() {
        val chrome = ShellChromeState()
        assertFalse(chrome.isScrolled(Routes.AccountList))
        chrome.onContentDelta(Routes.AccountList, deltaDp = 6f, atTop = false)
        assertFalse(chrome.isScrolled(Routes.AccountList))
        chrome.onContentDelta(Routes.AccountList, deltaDp = 6f, atTop = false)
        assertTrue(chrome.isScrolled(Routes.AccountList))
        // Shown again part-way down a list: still scrolled, which is when the buttons need a ground.
        chrome.onContentDelta(Routes.AccountList, deltaDp = 300f, atTop = false)
        chrome.onContentDelta(Routes.AccountList, deltaDp = -20f, atTop = false)
        assertFalse(chrome.isHidden(Routes.AccountList))
        assertTrue(chrome.isScrolled(Routes.AccountList))
        chrome.onContentDelta(Routes.AccountList, deltaDp = 0f, atTop = true)
        assertFalse(chrome.isScrolled(Routes.AccountList))
        assertFalse(chrome.isScrolled(Routes.Home))
    }

    @Test
    fun nestedScrollUsesContentOffsetNotTheInset() {
        val chrome = ShellChromeState()
        // density 2: -20px is 10dp down, still inside the top band.
        chrome.onNestedScroll(Routes.Home, consumedYPx = -20f, availableYPx = 0f, density = 2f)
        assertFalse(chrome.isHidden(Routes.Home))
        chrome.onNestedScroll(Routes.Home, consumedYPx = -400f, availableYPx = 0f, density = 2f)
        assertTrue(chrome.isHidden(Routes.Home))
        // Leftover toward the start is the top, even when the inset would have moved.
        chrome.onNestedScroll(Routes.Home, consumedYPx = 0f, availableYPx = 30f, density = 2f)
        assertFalse(chrome.isHidden(Routes.Home))
    }
}
