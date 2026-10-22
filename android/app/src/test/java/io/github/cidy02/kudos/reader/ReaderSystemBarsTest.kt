package io.github.cidy02.kudos.reader

import android.app.Activity
import android.app.Application
import android.view.Window
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class ReaderSystemBarsTest {
    @get:Rule val compose = createComposeRule()
    private var chrome by mutableStateOf(false)
    private var overlay by mutableStateOf(false)
    private var reading by mutableStateOf(true)
    private lateinit var window: Window
    private val owner = object : LifecycleOwner {
        override val lifecycle = LifecycleRegistry.createUnsafe(this).apply {
            currentState = Lifecycle.State.RESUMED
        }
    }

    private fun open() {
        compose.setContent {
            window = (LocalView.current.context as Activity).window
            CompositionLocalProvider(LocalLifecycleOwner provides owner) {
                if (reading) ReaderSystemBars(chrome, overlay)
            }
        }
        compose.waitForIdle()
    }

    // Read Android's requested visibility, rather than asserting a duplicate boolean policy.
    private fun assertBarsVisible(visible: Boolean) = compose.runOnIdle {
        val requested = ReflectionHelpers.callInstanceMethod<Int>(window.insetsController, "getRequestedVisibleTypes")
        val bars = WindowInsetsCompat.Type.systemBars()
        assertEquals(if (visible) bars else 0, requested and bars)
    }

    @Test fun bothBarsFollowChromeAndLeavingRestoresThem() {
        open()
        assertBarsVisible(false)
        // The swipe-to-peek behaviour reads back as 0 under Robolectric; it is checked on the emulator.
        compose.runOnIdle { chrome = true }
        assertBarsVisible(true)
        compose.runOnIdle { chrome = false }
        assertBarsVisible(false)
        compose.runOnIdle { reading = false }
        assertBarsVisible(true)
    }

    @Test fun aSheetRestoresBarsEvenWhenChromeIsHiddenAndReturnsToImmersionAfterward() {
        open()
        compose.runOnIdle { overlay = true }
        assertBarsVisible(true)
        compose.runOnIdle { overlay = false }
        assertBarsVisible(false)
    }

    @Test fun aCoveredOrStoppedReaderRestoresBarsAndOnlyAResumedReaderCanHideThem() {
        open()
        compose.runOnIdle { owner.lifecycle.currentState = Lifecycle.State.STARTED }
        assertBarsVisible(true)
        compose.runOnIdle { chrome = true; chrome = false }
        assertBarsVisible(true)
        compose.runOnIdle { owner.lifecycle.currentState = Lifecycle.State.CREATED }
        assertBarsVisible(true)
        compose.runOnIdle { owner.lifecycle.currentState = Lifecycle.State.RESUMED }
        assertBarsVisible(false)
        compose.runOnIdle { reading = false }
        assertBarsVisible(true)
        compose.runOnIdle { owner.lifecycle.currentState = Lifecycle.State.STARTED }
        assertBarsVisible(true)
    }
}
