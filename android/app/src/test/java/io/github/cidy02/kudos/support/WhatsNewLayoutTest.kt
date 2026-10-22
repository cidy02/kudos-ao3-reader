package io.github.cidy02.kudos.support

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WhatsNewLayoutTest {
    @get:Rule val compose = createComposeRule()

    @Test fun aShortReleaseStillFillsTheSheetWithACentredTitleAndWorkingDone() {
        var done = false
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                Box(Modifier.fillMaxSize().testTag("Host")) {
                    WhatsNewContent(listOf(ChangelogEntry("1.0", "A short note.")),
                        onDone = { done = true }, modifier = Modifier.testTag("What's New content"))
                }
            }
        }
        val host = compose.onNodeWithTag("Host").fetchSemanticsNode().boundsInRoot
        val content = compose.onNodeWithTag("What's New content").fetchSemanticsNode().boundsInRoot
        val title = compose.onNodeWithText("What's New").fetchSemanticsNode().boundsInRoot
        assertEquals(host.height, content.height, 1f)
        assertEquals(host.center.x, title.center.x, 1f)
        compose.onNodeWithContentDescription("Done").performClick()
        assertTrue(done)
    }
}
