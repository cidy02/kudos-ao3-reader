package io.github.cidy02.kudos.comments

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CommentFormattingTrayScreenTest {
    @get:Rule val compose = createComposeRule()

    private fun checkColumns(scale: Float, columns: Int) {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale)) {
                    CommentFormattingTray(TextFieldValue(""), {}, {})
                }
            }
        }
        compose.waitForIdle()
        val tags = listOf("Bold", "Italic", "Underline", "Strike", "Superscript")
        val bounds = tags.map { compose.onNodeWithText(it, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot }
        for (index in 1 until columns) {
            assertEquals(bounds[0].top, bounds[index].top, 1f)
            assertTrue(bounds[index].left > bounds[index - 1].left)
        }
        assertTrue(bounds[columns].top > bounds[0].top)
        assertEquals(bounds[0].center.x, bounds[columns].center.x, 1f)
    }

    @Test fun formattingLettersUseIosSerifSizes() {
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            CommentFormattingContent(TextFieldValue(""), {}, {})
        } }
        compose.waitForIdle()
        for (letter in listOf("B", "I", "U", "S", "Aa")) {
            val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithText(letter, useUnmergedTree = true)
                .performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertEquals(androidx.compose.ui.text.font.FontFamily.Serif, layouts.single().layoutInput.style.fontFamily)
            assertEquals(if (letter == "Aa") 11.sp else 16.sp, layouts.single().layoutInput.style.fontSize)
        }
    }

    @Test fun restingTrayHasFourEqualColumns() = checkColumns(1f, 4)
    @Test fun firstAccessibilitySizeHasTwoColumns() = checkColumns(1.5f, 2)
    @Test fun secondAccessibilitySizeHasTwoColumns() = checkColumns(1.7f, 2)
    @Test fun thirdAccessibilitySizeHasOneColumn() = checkColumns(1.8f, 1)
}
