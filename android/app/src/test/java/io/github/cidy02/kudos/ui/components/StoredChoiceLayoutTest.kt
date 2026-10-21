package io.github.cidy02.kudos.ui.components

import android.app.Application
import android.content.Context
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Tests verifying default layout and persistence of stored choices (iOS `@AppStorage` match).
 * Brief 3fu (Q25b): Lists open on Compact.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class StoredChoiceLayoutTest {
    @get:Rule val compose = createComposeRule()

    private enum class TestDisplayMode { Compact, Ledger, Detailed }

    @Test fun freshLaunchDefaultsToCompactForAccountAndQueueLists() {
        val context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("layout-choices", Context.MODE_PRIVATE).edit().clear().commit()

        var accountState: MutableState<TestDisplayMode>? = null
        var queueState: MutableState<TestDisplayMode>? = null
        compose.setContent {
            accountState = rememberStoredChoice("account.displayMode", TestDisplayMode.Compact)
            queueState = rememberStoredChoice("library.readingQueueBrowser.displayMode.test-queue-1", TestDisplayMode.Compact)
        }
        assertEquals(TestDisplayMode.Compact, accountState?.value)
        assertEquals(TestDisplayMode.Compact, queueState?.value)
    }

    @Test fun storedChoiceKeepsReaderSelectionBetweenLaunches() {
        val context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("layout-choices", Context.MODE_PRIVATE).edit().clear().commit()

        var state: MutableState<TestDisplayMode>? = null
        var secondState: MutableState<TestDisplayMode>? = null
        var relaunched by androidx.compose.runtime.mutableStateOf(false)
        compose.setContent {
            // A second key-less mount stands for the next launch: it reads the stored choice afresh.
            if (!relaunched) state = rememberStoredChoice("account.displayMode", TestDisplayMode.Compact)
            else secondState = rememberStoredChoice("account.displayMode", TestDisplayMode.Compact)
        }
        assertEquals(TestDisplayMode.Compact, state?.value)

        compose.runOnIdle {
            state?.value = TestDisplayMode.Detailed
        }

        val prefs = context.getSharedPreferences("layout-choices", Context.MODE_PRIVATE)
        assertEquals("Detailed", prefs.getString("account.displayMode", null))

        // Subsequent read retains the user's stored choice instead of falling back to default Compact
        compose.runOnIdle { relaunched = true }
        compose.waitForIdle()
        assertEquals(TestDisplayMode.Detailed, secondState?.value)
    }
}
