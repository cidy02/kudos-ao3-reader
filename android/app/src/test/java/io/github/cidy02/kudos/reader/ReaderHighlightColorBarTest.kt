package io.github.cidy02.kudos.reader

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h891dp")
class ReaderHighlightColorBarTest {
    @get:Rule val compose = createComposeRule()

    @Test fun everySwatchIsNamedAndOneTapRefinesThenDismisses() {
        var showing by mutableStateOf(true)
        var picked: String? = null
        compose.setContent {
            CompositionLocalProvider(LocalKudosTokens provides KudosTokens.of(ReaderTheme.Sepia, Color.Red)) {
                if (showing) ReaderHighlightColorBar(ReadingAnnotationColor.YELLOW.raw,
                    onSelect = { picked = it; showing = false }, onDismiss = { showing = false })
            }
        }
        ReadingAnnotationColor.entries.forEach {
            compose.onNodeWithContentDescription(it.displayName)
                .assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp)
        }
        compose.onNodeWithContentDescription("Custom colour").assertExists()
        compose.onNodeWithContentDescription("Underline").performClick()
        compose.onNodeWithContentDescription("Highlight colour").assertDoesNotExist()
        compose.runOnIdle { assertEquals("underline", picked) }
    }
}
