package io.github.cidy02.kudos.writing

import android.app.Application
import android.window.BackEvent
import android.window.OnBackAnimationCallback
import android.window.OnBackInvokedCallback
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.test.core.app.ApplicationProvider
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WritingPredictiveBackTest {
    @get:Rule val compose = createComposeRule()
    private val chrome = PushedShellChrome()
    private lateinit var activity: ComponentActivity
    private lateinit var model: WritingWorkFormState
    private var leaves = 0
    private var parentBacks = 0

    @Before fun enablePlatformCallbacks() {
        // Robolectric disables the framework feature by default, even on API 34.
        ReflectionHelpers.setStaticField(Class.forName("android.window.WindowOnBackInvokedDispatcher"),
            "ENABLE_PREDICTIVE_BACK", true)
        // Test the callback-enabled runtime even if Robolectric omits this new manifest attribute.
        // PredictiveBackManifestTest independently pins the real application opt-in.
        ReflectionHelpers.callInstanceMethod<Void>(
            ApplicationProvider.getApplicationContext<Application>().applicationInfo,
            "setEnableOnBackInvokedCallback",
            ReflectionHelpers.ClassParameter.from(Boolean::class.javaPrimitiveType!!, true))
    }

    private fun open() {
        val setup = runBlocking { workFormSetup() }
        model = setup.model(995001L)
        runBlocking { model.load() }
        compose.setContent {
            activity = LocalView.current.context as ComponentActivity
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                    BackHandler { parentBacks++ }
                    WritingWorkFormContent(model, model.account, "Edit work", { leaves++ })
                }
            }
        }
        compose.waitForIdle()
    }

    private fun platformCallback(): OnBackInvokedCallback {
        val callback = ReflectionHelpers.callInstanceMethod<OnBackInvokedCallback?>(
            activity.onBackInvokedDispatcher, "getTopCallback")
        assertNotNull("BackHandler must register through the platform callback API", callback)
        return callback!!
    }

    private fun back() {
        compose.runOnIdle { platformCallback().onBackInvoked() }
        compose.waitForIdle()
    }

    @Test fun platformBackAsksBeforeLeavingAndKeepEditingRetainsTheUnsavedForm() {
        open()
        compose.onNodeWithContentDescription("Title, required").performTextReplacement("Unsaved title")
        back()
        compose.onNodeWithText("Discard unsaved changes?").assertExists()
        assertEquals(0, leaves)
        assertEquals(0, parentBacks)
        compose.onNodeWithText("Keep editing").performClick()
        compose.onNodeWithContentDescription("Title, required").assertTextContains("Unsaved title")
        back()
        compose.onNodeWithText("Discard changes").performClick()
        assertEquals(1, leaves)
        assertEquals(0, parentBacks)
    }

    @Test fun cancellingTheGestureDoesNotAskOrLeaveAndTheShellUsesTheSameGuard() {
        open()
        compose.onNodeWithContentDescription("Title, required").performTextReplacement("Unsaved title")
        compose.runOnIdle {
            val callback = platformCallback() as OnBackAnimationCallback
            callback.onBackStarted(BackEvent(0f, 100f, 0f, BackEvent.EDGE_LEFT))
            callback.onBackProgressed(BackEvent(30f, 100f, 0.3f, BackEvent.EDGE_LEFT))
            callback.onBackCancelled()
        }
        compose.onNodeWithText("Discard unsaved changes?").assertDoesNotExist()
        assertEquals(0, leaves)
        compose.runOnIdle { chrome.onBack!!.invoke() }
        compose.onNodeWithText("Discard unsaved changes?").assertExists()
        assertEquals(0, leaves)
    }

    @Test fun anUnchangedOrRevertedFormLeavesWithoutAQuestion() {
        open()
        val original = model.state.value.form!!.title
        compose.onNodeWithContentDescription("Title, required").performTextReplacement("Temporary edit")
        compose.onNodeWithContentDescription("Title, required").performTextReplacement(original)
        back()
        compose.onNodeWithText("Discard unsaved changes?").assertDoesNotExist()
        assertEquals(1, leaves)
        assertEquals(0, parentBacks)
    }
}
