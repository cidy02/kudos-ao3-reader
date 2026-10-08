package io.github.cidy02.kudos.app

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * When one pushed screen opens another, the old one leaves after the new one has registered its
 * top buttons. Its farewell reset used to wipe them: the collection moderation screen opened
 * from a collection had no Submit or Discard.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class PushedShellChromeTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun aScreenLeavingAfterTheNextArrivedDoesNotWipeTheNewcomersButtons() {
        val chrome = PushedShellChrome()
        var showOld by mutableStateOf(true)
        var showNew by mutableStateOf(false)
        compose.setContent {
            CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                if (showOld) ProvidePushedShellChrome(customTitle = "Old")
                if (showNew) ProvidePushedShellChrome(customTitle = "New", trailingContent = {})
            }
        }
        compose.runOnIdle { assertEquals("Old", chrome.customTitle) }

        showNew = true
        compose.waitForIdle()
        showOld = false
        compose.waitForIdle()
        compose.runOnIdle {
            assertEquals("New", chrome.customTitle)
            assertNotNull(chrome.trailingContent)
        }

        showNew = false
        compose.waitForIdle()
        compose.runOnIdle {
            assertNull(chrome.customTitle)
            assertFalse(chrome.mounted)
        }
    }

    /** A back gesture that is cancelled composes the screen underneath for a moment, then drops it. */
    @Test
    fun theNewestScreenHoldsTheRowAndHandsItBackWhenItLeaves() {
        val chrome = PushedShellChrome()
        var oldTitle by mutableStateOf("Old")
        var showOld by mutableStateOf(true)
        var showNew by mutableStateOf(false)
        compose.setContent {
            CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                if (showOld) ProvidePushedShellChrome(customTitle = oldTitle)
                if (showNew) ProvidePushedShellChrome(customTitle = "New", trailingContent = {})
            }
        }
        compose.waitForIdle()
        val oldHolder = compose.runOnIdle { chrome.holder }
        showNew = true
        compose.waitForIdle()
        // The shell watches this to bring back a row the older screen had scrolled away.
        val newHolder = compose.runOnIdle { chrome.holder }
        assertTrue(oldHolder != null && newHolder != null && newHolder !== oldHolder)

        // The older screen updates itself while the newer one is up: it must not take the row.
        oldTitle = "Old, loaded"
        compose.waitForIdle()
        compose.runOnIdle {
            assertEquals("New", chrome.customTitle)
            assertNotNull(chrome.trailingContent)
        }

        showNew = false
        compose.waitForIdle()
        compose.runOnIdle {
            assertEquals("Old, loaded", chrome.customTitle)
            assertNull(chrome.trailingContent)
            assertTrue(chrome.mounted)
            assertTrue(chrome.holder === oldHolder)
        }

        showOld = false
        compose.waitForIdle()
        compose.runOnIdle { assertFalse(chrome.mounted) }
    }
}
